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


class ArrayCIFAR10(torch.utils.data.Dataset):
    """uint8 HWC 이미지 배열 + label. torchvision CIFAR10 과 같은 방식(PIL→transform)으로 꺼낸다."""

    def __init__(self, images, labels, transform, source):
        self.data, self.targets, self.transform, self.source = images, list(labels), transform, source

    def __len__(self):
        return len(self.targets)

    def __getitem__(self, i):
        from PIL import Image
        return self.transform(Image.fromarray(self.data[i])), int(self.targets[i])


def cifar10(root="data", train=False, source="hf"):
    """평가용(증강 없음) CIFAR-10. train=True 는 Calibration 용으로만 쓴다.

    source="hf"      : Hugging Face uoft-cs/cifar10 (원본 변환본, 빠름). 실패하면 toronto 로 넘어간다.
    source="toronto" : torchvision 원본 tar (cs.toronto.edu, 느릴 수 있음)
    어느 경로든 이미지 배열의 sha256 을 `data_sha256` 으로 남겨 팀원 간 같은 데이터인지 확인한다.
    """
    import numpy as np
    if source not in ("hf", "toronto"):
        raise ValueError("source must be hf or toronto")
    split = "train" if train else "test"
    if source == "hf":
        try:
            from datasets import load_dataset
            ds = load_dataset("uoft-cs/cifar10", split=split, cache_dir=os.path.join(root, "hf"))
            images = np.stack([np.asarray(im.convert("RGB"), dtype=np.uint8) for im in ds["img"]])
            labels = np.asarray(ds["label"], dtype=np.int64)
            out = ArrayCIFAR10(images, labels, eval_transform(), "hf:uoft-cs/cifar10")
        except Exception as e:  # 네트워크·라이브러리 문제 시 원본으로
            print("HF 경로 실패, toronto 원본으로 받습니다:", repr(e)[:200])
            source = "toronto"
    if source == "toronto":
        tv = torchvision.datasets.CIFAR10(root, train=train, download=True, transform=None)
        out = ArrayCIFAR10(tv.data, tv.targets, eval_transform(), "torchvision:cs.toronto.edu")
    expected_n = 50000 if train else 10000
    if out.data.shape != (expected_n, 32, 32, 3) or len(out.targets) != expected_n:
        raise ValueError("CIFAR-10 shape/count mismatch")
    if out.data.dtype != np.uint8 or not all(0 <= int(y) < 10 for y in out.targets):
        raise ValueError("CIFAR-10 dtype/label mismatch")
    out.data_sha256 = hashlib.sha256(out.data.tobytes()).hexdigest()
    out.label_sha256 = hashlib.sha256(np.asarray(out.targets, dtype=np.int64).tobytes()).hexdigest()
    print(f"CIFAR-10 {split}: {len(out)}장 · {out.source} · images sha256 {out.data_sha256[:16]}…")
    return out


def calibration_subset(train_set, n=1000, seed=0):
    g = torch.Generator().manual_seed(seed)
    idx = torch.randperm(len(train_set), generator=g)[:n].tolist()
    return Subset(train_set, idx), idx


@torch.no_grad()
def evaluate(forward, dataset, device, batch_size=128):
    """forward(x)->logits. 동점이면 torch.argmax 규칙(첫 index)을 따른다."""
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=False, num_workers=0)
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
        "per_class_top1": {CLASSES[i]: (round(100.0 * int(per_cls_ok[i]) / int(per_cls_n[i]), 2)
                                      if int(per_cls_n[i]) else None)
                           for i in range(10)},
        "preds": torch.cat(preds),
    }


def environment(device=None):
    env = {
        "python": platform.python_version(),
        "torch": torch.__version__,
        "torchvision": torchvision.__version__,
        "device": "cpu",
        "reference_repo": AKA_REPO,
        "reference_commit": AKA_COMMIT,
    }
    if (device is None or str(device).startswith("cuda")) and torch.cuda.is_available():
        env["device"] = torch.cuda.get_device_name(0)
    return env


def save_json(obj, path):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)

