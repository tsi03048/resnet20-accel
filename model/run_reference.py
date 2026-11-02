"""E1 -> E2-A 실행. python -m model.run_reference --help"""
import argparse
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--device", choices=["auto", "cpu", "cuda"], default="auto")
    p.add_argument("--source", choices=["hf", "toronto"], default="hf")
    p.add_argument("--e1-only", action="store_true")
    p.add_argument("--calib-n", type=int, default=1000)
    p.add_argument("--dev-n", type=int, default=1000)
    p.add_argument("--accept-drop-pp", type=float, default=None)
    args = p.parse_args()
    import torch
    from model.common import fetch_reference, load_resnet20, cifar10, save_json
    from model.e1_fp32 import run_e1
    from quant.e2_ptq import run_e2
    torch.manual_seed(0)
    torch.set_num_threads(min(8, torch.get_num_threads()))
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False
    device = ("cuda" if torch.cuda.is_available() else "cpu") if args.device == "auto" else args.device
    import hashlib
    import subprocess
    from datetime import datetime, timezone
    files = sorted([*Path("model").glob("*.py"), *Path("quant").glob("*.py")])
    git = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True)
    save_json({"started_at_utc": datetime.now(timezone.utc).isoformat(),
               "device": device, "arguments": vars(args),
               "code_commit": git.stdout.strip() if git.returncode == 0 else None,
               "source_sha256": {str(f).replace(chr(92), "/"): hashlib.sha256(f.read_bytes()).hexdigest() for f in files}},
              "results/run_manifest.json")
    model, info = load_resnet20(fetch_reference(), device)
    test_set = cifar10(train=False, source=args.source)
    # 먼저 한 장을 확인한 뒤 전체 평가로 진행한다.
    with torch.no_grad():
        x, label = test_set[0]
        logits = model(x.unsqueeze(0).to(device))
    print("First image:", tuple(x.shape), "label", label, "prediction", int(logits.argmax()), flush=True)
    e1, manifest, preds = run_e1(model, info, test_set, device)
    print("E1 FP32:", e1["fp32_top1"], "%", flush=True)
    if not args.e1_only:
        train = cifar10(train=True, source=args.source)
        e2 = run_e2(model, test_set, train, device, preds, e1["fp32_top1"],
                    accept_drop_pp=args.accept_drop_pp, calib_n=args.calib_n, dev_n=args.dev_n)
        print("E2-A:", e2["selected_test"], flush=True)
    import importlib.metadata as md
    packages = {n: md.version(n) for n in ("torch", "torchvision", "numpy")}
    save_json(packages, "results/environment.json")


if __name__ == "__main__":
    main()
