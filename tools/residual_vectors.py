"""Export/verify the actual L1.0 Identity block without choosing new scales."""
import argparse
import hashlib
import json
from pathlib import Path
import re

import numpy as np
from quant.e2b_reference import load_package, rne_numpy
from quant.replay_e2b import replay

ROOT = "reference/e2b_v1/residual_l10_vectors"


def expected(package="reference/e2b_v1"):
    package = Path(package)
    replay(package, backend="numpy")
    m, a = load_package(package)
    ops = m["operations"][1:4]
    assert [o["name"] for o in ops] == ["L1.0.conv1", "L1.0.conv2", "L1.0.add_relu"]
    assert ops[2]["shortcut"] == "identity"
    with np.load(package / "sample0/tensors.npz", allow_pickle=False) as z:
        # Widen before multiplication/addition; NumPy INT8 arithmetic can wrap.
        t = {k: z[k].astype(np.int64) for k in z.files}
    add = ops[2]
    wide = t["L1.0.conv2"] * add["multiplier_main"] + t["stem"] * add["multiplier_skip"]
    values = {"input": (t["stem"], 8), "acc1_expected": (t["L1.0.conv1.acc"], 32),
              "h_expected": (t["L1.0.conv1"], 8), "acc2_expected": (t["L1.0.conv2.acc"], 32),
              "m_expected": (t["L1.0.conv2"], 8), "add_wide_expected": (wide, 64),
              "output_expected": (t["L1.0.add_relu"], 8),
              "add_config": (np.array([add["multiplier_main"], add["multiplier_skip"], add["shift"]], dtype=np.int64), 32)}
    for i, op in enumerate(ops[:2], 1):
        for role in ("weight", "bias", "multiplier", "shift"):
            values[f"{role}{i}"] = (a[op[role]], 8 if role == "weight" else 32)
    main, skip = t["L1.0.conv2"], t["stem"]
    y = t["L1.0.add_relu"]
    wrong_relu = np.clip(rne_numpy(np.maximum(main, 0) * add["multiplier_main"] + skip * add["multiplier_skip"], add["shift"]), 0, 127)
    wrong_add = np.clip(main + skip, 0, 127)
    wrong_round = np.clip(rne_numpy(main * add["multiplier_main"], add["shift"]) + rne_numpy(skip * add["multiplier_skip"], add["shift"]), 0, 127)
    facts = dict(negative_main=int((main < 0).sum()),
                 premature_relu_changes=int((wrong_relu != y).sum()),
                 raw_code_add_changes=int((wrong_add != y).sum()),
                 separate_rounding_changes=int((wrong_round != y).sum()))
    return m, values, facts


def export(directory=ROOT):
    m, values, facts = expected()
    root = Path(directory); root.mkdir(parents=True, exist_ok=True)
    records = {}
    for role, (a, bits) in values.items():
        raw = "".join(f"{int(v) & ((1 << bits)-1):0{bits//4}x}\n" for v in a.reshape(-1)).encode("ascii")
        (root / (role + ".hex")).write_bytes(raw)
        records[role] = dict(file=role+".hex", shape=list(a.shape), bits=bits, count=int(a.size), order="C", sha256=hashlib.sha256(raw).hexdigest())
    manifest = dict(package=m["semantic_sha256"], block="L1.0", source="actual checkpoint + CIFAR-10 test sample 0; input is its Stem output",
                    encoding="ASCII LF, one two's-complement word per line; NCHW/OIHW, no byte swap", vectors=records, teaching_checks=facts)
    manifest_path=root / "manifest.json"
    if manifest_path.exists() and json.loads(manifest_path.read_text(encoding="utf-8")) != manifest:
        raise ValueError("Frozen Residual manifest differs; do not silently replace it")
    manifest_path.write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8", newline="\n")
    return manifest


def verify(directory=ROOT):
    m, values, facts = expected()
    root = Path(directory)
    manifest = json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    if manifest["package"] != m["semantic_sha256"] or manifest["block"] != "L1.0" or set(manifest["vectors"]) != set(values):
        raise ValueError("Residual vector package/block/role mismatch")
    for role, (a, bits) in values.items():
        d = manifest["vectors"][role]
        if d["file"] != role+".hex" or d["shape"] != list(a.shape) or d["bits"] != bits or d["count"] != a.size or d["order"] != "C":
            raise ValueError(f"Residual vector layout mismatch: {role}")
        raw = (root/d["file"]).read_bytes()
        if hashlib.sha256(raw).hexdigest() != d["sha256"] or b"\r" in raw or not raw.endswith(b"\n"):
            raise ValueError(f"Residual vector hash/encoding mismatch: {role}")
        words = raw.decode("ascii").splitlines()
        if len(words) != a.size or any(re.fullmatch(r"[0-9a-f]{"+str(bits//4)+"}", w) is None for w in words):
            raise ValueError(f"Residual vector word mismatch: {role}")
        decoded = np.array([int(w,16) - ((1<<bits) if int(w,16)&(1<<(bits-1)) else 0) for w in words], dtype=np.int64)
        if not np.array_equal(decoded, a.reshape(-1)):
            raise ValueError(f"Residual vector semantic mismatch: {role}")
    if manifest["teaching_checks"] != facts: raise ValueError("Residual teaching evidence mismatch")
    return dict(status="PASS", package=m["semantic_sha256"], block="L1.0", vectors={k:int(v[0].size) for k,v in values.items()}, teaching_checks=facts)


if __name__ == "__main__":
    p=argparse.ArgumentParser(); p.add_argument("--export", action="store_true"); p.add_argument("--directory", default=ROOT)
    args=p.parse_args()
    print(json.dumps(export(args.directory) if args.export else verify(args.directory), indent=2))
