"""python -m quant.run_e2b --limit 10000 --audit 4

Reuses the frozen E2-A choice and train ranges. Never selects/tunes on test.
"""
import argparse
import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import time

import numpy as np

from quant.e2b_reference import IntegerReference, array_hash, load_package, save_package


def dump_golden(trace, model_manifest, index=0):
    root = Path(f"golden/e2b_sample{index}")
    root.mkdir(parents=True, exist_ok=True)
    arrays, records = {}, {}
    for name, value in trace.items():
        dtype = "<i4" if name.endswith(".acc") or name == "fc" else ("<i8" if name == "gap.sum" else "i1")
        a = value.astype(dtype)
        arrays[name] = a
        records[name] = dict(shape=list(a.shape), dtype=a.dtype.str, sha256=array_hash(a),
                             preview=a.reshape(-1)[:8].tolist())
    np.savez_compressed(root / "tensors.npz", **arrays)
    m = dict(split="test", sample_index=index, package_semantic_sha256=model_manifest["semantic_sha256"],
             layout="NCHW for feature maps, NC for GAP/FC", tensors=records,
             npz_sha256=hashlib.sha256((root / "tensors.npz").read_bytes()).hexdigest(),
             note="Integer software Golden; RTL comparison not yet run")
    (root / "manifest.json").write_text(json.dumps(m, indent=2), encoding="utf-8")
    return m


def stem_hex(manifest, arrays, trace, directory):
    directory = Path(directory) / "stem_vectors"
    directory.mkdir(parents=True, exist_ok=True)
    op = manifest["operations"][0]
    vectors = {"input": (trace["input"], 8), "weight": (arrays[op["weight"]], 8),
               "bias": (arrays[op["bias"]], 32), "multiplier": (arrays[op["multiplier"]], 32),
               "shift": (arrays[op["shift"]], 32), "acc_expected": (trace["stem.acc"], 32),
               "output_expected": (trace["stem"], 8)}
    records = {}
    for name, (a, bits) in vectors.items():
        path = directory / (name + ".hex")
        path.write_text("".join(f"{int(v) & ((1 << bits) - 1):0{bits // 4}x}\n" for v in a.reshape(-1)), encoding="ascii")
        records[name] = dict(file=path.name, shape=list(a.shape), bits=bits, count=a.size,
                             order="C", sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (directory / "manifest.json").write_text(json.dumps(dict(package=manifest["semantic_sha256"],
        encoding="one two's-complement hex word per line; NCHW/OIHW order; no byte swapping",
        vectors=records), indent=2), encoding="utf-8")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--limit", type=int, default=10000)
    p.add_argument("--audit", type=int, default=4)
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--package-dir", default="artifacts/e2b_v1")
    p.add_argument("--source", choices=["hf", "toronto"], default="hf")
    p.add_argument("--e2a-report", default="reference/e2b_v1/source_e2a_report.json")
    p.add_argument("--e2a-selection", default="reference/e2b_v1/source_e2a_selection.json")
    args = p.parse_args()
    if not 1 <= args.limit <= 10000 or not 1 <= args.audit <= args.limit or args.batch_size <= 0:
        p.error("require 1 <= audit <= limit <= 10000 and positive batch size")
    import torch
    from model.common import fetch_reference, load_resnet20, cifar10, environment, save_json
    from quant.e2_ptq import folded_params, quantize_params, forward_folded, make_act_quant
    from quant.e2b_export import export_model
    torch.set_num_threads(min(8, torch.get_num_threads()))
    torch.manual_seed(0)
    report_path, selection_path = Path(args.e2a_report), Path(args.e2a_selection)
    report = json.loads(report_path.read_text(encoding="utf-8"))
    selection = json.loads(selection_path.read_text(encoding="utf-8"))
    # Capture source digests BEFORE export/evaluation; no old evidence is relabelled.
    sources = sorted([*Path("quant").glob("*.py"), *Path("model").glob("*.py")])
    run = dict(started_at_utc=datetime.now(timezone.utc).isoformat(), arguments=vars(args),
               environment=environment("cpu"),
               source_sha256={s.as_posix(): hashlib.sha256(s.read_bytes()).hexdigest() for s in sources},
               e2a_report_sha256=hashlib.sha256(report_path.read_bytes()).hexdigest(),
               e2a_selection_sha256=hashlib.sha256(selection_path.read_bytes()).hexdigest())
    save_json(run, "results/e2b_run_manifest.json")
    model, info = load_resnet20(fetch_reference(), "cpu")
    m, a = export_model(model, report, selection, info, args.package_dir)
    m["source_reports"] = {k: run[k] for k in ("e2a_report_sha256", "e2a_selection_sha256")}
    save_package(m, a, args.package_dir)
    loaded_m, loaded_a = load_package(args.package_dir)
    if set(a) != set(loaded_a) or any(not np.array_equal(a[k], loaded_a[k]) for k in a):
        raise RuntimeError("package serialization mismatch")
    ref = IntegerReference(loaded_m, loaded_a, "torch")
    independent = IntegerReference(loaded_m, loaded_a, "numpy")
    data = cifar10(train=False, source=args.source)
    old_e1 = json.loads(Path("results/e1_fp32.json").read_text(encoding="utf-8"))
    if data.data_sha256 != old_e1["dataset"]["images_sha256"] or data.label_sha256 != old_e1["dataset"]["labels_sha256"]:
        raise RuntimeError("test dataset differs from frozen E1")
    audit_elements, audit_records = 0, []
    for i in range(args.audit):
        x = data[i][0].unsqueeze(0).numpy()
        codes = ref.quantize_input(x)
        one, trace = ref.forward(codes, capture=True)
        two, other = independent.forward(codes, capture=True)
        if trace.keys() != other.keys():
            raise RuntimeError("audit boundary set mismatch")
        for name in trace:
            if not np.array_equal(trace[name], other[name]):
                bad = np.argwhere(trace[name] != other[name])[0].tolist()
                raise RuntimeError(f"independent integer mismatch sample={i} tensor={name} index={bad}")
            audit_elements += trace[name].size
        audit_records.append(dict(sample_index=i, tensor_count=len(trace), prediction=int(one.argmax())))
        if i == 0:
            dump_golden(trace, loaded_m)
            stem_hex(loaded_m, loaded_a, trace, args.package_dir)
        print(f"Integer audit sample {i}: {len(trace)} boundaries exact", flush=True)
    folded = folded_params(model)
    q = quantize_params(folded)
    act = make_act_quant(report["activation_ranges"]["minmax"], "signed")
    counts = {k: 0 for k in ("fp32", "fake_quant", "integer", "agree_fp32", "agree_fake_quant")}
    per_class_n, per_class_ok = [0] * 10, [0] * 10
    disagreements, score_abs_error = 0, 0.0
    start = time.time()
    with Path("results/e2b_samples.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["sample_index", "label", "fp32_pred", "fake_quant_pred", "integer_pred"])
        with torch.no_grad():
            for begin in range(0, args.limit, args.batch_size):
                end = min(begin + args.batch_size, args.limit)
                xs = torch.stack([data[i][0] for i in range(begin, end)])
                labels = np.asarray([data[i][1] for i in range(begin, end)])
                fp_logits, fake_logits = model(xs), forward_folded(q, xs, act)
                scores, _ = ref.forward(ref.quantize_input(xs.numpy()))
                fp, fake, pred = fp_logits.argmax(1).numpy(), fake_logits.argmax(1).numpy(), scores.argmax(1)
                counts["fp32"] += int((fp == labels).sum())
                counts["fake_quant"] += int((fake == labels).sum())
                counts["integer"] += int((pred == labels).sum())
                counts["agree_fp32"] += int((pred == fp).sum())
                counts["agree_fake_quant"] += int((pred == fake).sum())
                score_abs_error = max(score_abs_error, float(np.abs(scores * loaded_m["score_scale"] - fake_logits.numpy()).max()))
                for i, y, pf, pa, pi in zip(range(begin, end), labels, fp, fake, pred):
                    writer.writerow([i, y, pf, pa, pi])
                    per_class_n[int(y)] += 1
                    per_class_ok[int(y)] += int(y == pi)
                if begin == 0 or end % (args.batch_size * 20) == 0 or end == args.limit:
                    print(f"E2-B {end}/{args.limit}: integer {100 * counts['integer'] / end:.2f}% ({time.time()-start:.1f}s)", flush=True)
    result = dict(step="E2-B", profile=loaded_m["profile"], package_semantic_sha256=loaded_m["semantic_sha256"],
                  test_images=args.limit, full_test=args.limit == 10000, correct=counts,
                  top1={k: 100 * counts[k] / args.limit for k in ("fp32", "fake_quant", "integer")},
                  integer_drop_vs_fp32_pp=100 * (counts["fp32"] - counts["integer"]) / args.limit,
                  integer_drop_vs_fake_quant_pp=100 * (counts["fake_quant"] - counts["integer"]) / args.limit,
                  integer_agreement_fp32_pct=100 * counts["agree_fp32"] / args.limit,
                  integer_agreement_fake_quant_pct=100 * counts["agree_fake_quant"] / args.limit,
                  max_abs_score_error_vs_fake_quant=score_abs_error,
                  per_class={str(i): dict(n=per_class_n[i], correct=per_class_ok[i]) for i in range(10)},
                  audit=dict(backends=["torch int64 Conv2d", "NumPy int64 einsum"], samples=audit_records,
                             compared_elements=audit_elements, mismatches=0),
                  package_roundtrip=True, accumulator_bound_checked=True,
                  dataset=dict(images_sha256=data.data_sha256, labels_sha256=data.label_sha256),
                  frozen_before_test=True, tuned_on_this_test=False,
                  rtl_compared=False, board_tested=False,
                  note="Software integer reference validated; integer-model quality and RTL correctness are separate.")
    save_json(result, "results/e2b_integer.json")
    print(json.dumps(result["top1"]), flush=True)


if __name__ == "__main__":
    main()
