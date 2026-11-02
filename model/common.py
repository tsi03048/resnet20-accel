"""E1 공통 유틸 — 고정된 공개 ResNet-20 checkpoint와 CIFAR-10 평가.

기준(2026-11-02 결정):
  * 모델: akamaster/pytorch_resnet_cifar10 의 ResNet-20 (Option A shortcut)
  * Checkpoint: 공개 pretrained_models/resnet20-12fca82f.th  (학습은 하지 않는다)
  * 전처리: ToTensor(/255) → Normalize(mean, std)  — 참고 trainer.py 와 동일
"""
import hashlib
import json
import os
import platform
import subprocess
import sys

import torch
import torchvision
import torchvision.transforms as T
from torch.utils.data import DataLoader, Subset

AKA_REPO = "https://github.com/akamaster/pytorch_resnet_cifar10.git"
AKA_COMMIT = "d5489e8995e81e91ce6b1d69dcc98ad579b0b153"
CKPT_NAME = "resnet20-12fca82f.th"
CKPT_SHA256 = "12fca82f0bebc4135bf1f32f6e3710e61d5108578464b84fd6d7f5c1b04036c8"
MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)
CLASSES = ("airplane", "automobile", "bird", "cat", "deer",
           "dog", "frog", "horse", "ship", "truck")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_reference(root="third_party"):
    """참고 구현을 고정 commit 으로 받아 import 경로에 추가한다."""
    path = os.path.join(root, "pytorch_resnet_cifar10")
    if not os.path.isdir(path):
        os.makedirs(root, exist_ok=True)
        subprocess.run(["git", "clone", "-q", AKA_REPO, path], check=True)
    subprocess.run(["git", "-C", path, "checkout", "-q", AKA_COMMIT], check=True)
    head = subprocess.run(["git", "-C", path, "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()
    if head != AKA_COMMIT:
        raise RuntimeError(f"참고 구현 commit 불일치: {head}")
    if path not in sys.path:
        sys.path.insert(0, path)
    return path


def load_resnet20(ref_path, device):
    """Strict load. 누락·초과 key 가 있으면 즉시 실패한다."""
    import resnet  # 참고 구현의 resnet.py

    ckpt_path = os.path.join(ref_path, "pretrained_models", CKPT_NAME)
    digest = sha256_file(ckpt_path)
    if digest != CKPT_SHA256:
        raise RuntimeError(f"checkpoint hash 불일치: {digest}")
    try:
        ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=True)
    except Exception:  # 오래된 저장 형식 대비 (고정 hash 를 확인한 파일만)
        ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    state = ckpt["state_dict"]
    state = {k[len("module."):] if k.startswith("module.") else k: v
             for k, v in state.items()}
    model = resnet.resnet20()
    model.load_state_dict(state, strict=True)
    model.eval().to(device)
    info = {
        "checkpoint": CKPT_NAME,
        "checkpoint_sha256": digest,
        "stored_best_prec1": float(ckpt.get("best_prec1", float("nan"))),
        "num_state_keys": len(state),
        "num_params": sum(p.numel() for p in model.parameters()),
    }
    return model, info


def eval_transform():
    return T.Compose([T.ToTensor(), T.Normalize(MEAN, STD)])


def cifar10(root="data", train=False):
    """평가용(증강 없음) CIFAR-10. train=True 는 Calibration 용으로만 쓴다."""
    return torchvision.datasets.CIFAR10(root, train=train, download=True,
                                        transform=eval_transform())


def calibration_subset(train_set, n=1000, seed=0):
    g = torch.Generator().manual_seed(seed)
    idx = torch.randperm(len(train_set), generator=g)[:n].tolist()
    return Subset(train_set, idx), idx


@torch.no_grad()
def evaluate(forward, dataset, device, batch_size=500):
    """forward(x)->logits. 동점이면 torch.argmax 규칙(첫 index)을 따른다."""
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=False, num_workers=2)
    correct = 0
    n = 0
    per_cls_ok = torch.zeros(10, dtype=torch.long)
    per_cls_n = torch.zeros(10, dtype=torch.long)
    preds = []
    for x, y in loader:
        logits = forward(x.to(device))
        p = logits.argmax(1).cpu()
        preds.append(p)
        ok = p.eq(y)
        correct += int(ok.sum())
        n += y.numel()
        per_cls_n += torch.bincount(y, minlength=10)
        per_cls_ok += torch.bincount(y[ok], minlength=10)
    return {
        "n": n,
        "correct": correct,
        "top1": 100.0 * correct / n,
        "per_class_top1": {CLASSES[i]: round(100.0 * int(per_cls_ok[i]) / int(per_cls_n[i]), 2)
                           for i in range(10)},
        "preds": torch.cat(preds),
    }


def environment():
    env = {
        "python": platform.python_version(),
        "torch": torch.__version__,
        "torchvision": torchvision.__version__,
        "device": "cpu",
        "reference_repo": AKA_REPO,
        "reference_commit": AKA_COMMIT,
    }
    if torch.cuda.is_available():
        env["device"] = torch.cuda.get_device_name(0)
    return env


def save_json(obj, path):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
