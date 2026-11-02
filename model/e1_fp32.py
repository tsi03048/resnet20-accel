"""E1 — 같은 모델을 같은 숫자로 재현하기 (ResNet-20 FP32 Reference).

산출물
  results/e1_fp32.json            : 전체 Test Accuracy·Class별 정확도·환경·hash
  golden/e1_sample0/*.npy         : Test sample 0 의 경계별 FP32 Tensor (관측 당시 clone)
  golden/e1_sample0/manifest.json : 각 파일의 shape·dtype·layout·의미
"""
import os

import numpy as np
import torch
import torch.nn.functional as F

from model.common import (CLASSES, MEAN, STD, environment, evaluate, save_json)


@torch.no_grad()
def dump_sample(model, dataset, index, out_dir, device):
    """Hook 으로 경계별 Tensor 를 관측 당시 복사해 저장한다."""
    os.makedirs(out_dir, exist_ok=True)
    x, label = dataset[index]
    x = x.unsqueeze(0).to(device)
    cap = {}

    def keep(name, inp=False):
        def hook(_m, i, o):
            t = i[0] if inp else o
            cap[name] = t.detach().clone().cpu()
        return hook

    hs = [
        model.conv1.register_forward_hook(keep("conv1_preBN")),
        model.bn1.register_forward_hook(keep("stem_bn_preReLU")),
        model.layer1.register_forward_hook(keep("stage1")),
        model.layer2.register_forward_hook(keep("stage2")),
        model.layer3.register_forward_hook(keep("stage3")),
        model.linear.register_forward_hook(keep("fc_input_gap", inp=True)),
        model.linear.register_forward_hook(keep("logits")),
    ]
    logits = model(x)
    for h in hs:
        h.remove()
    cap["input"] = x.detach().clone().cpu()
    cap["stem"] = F.relu(cap["stem_bn_preReLU"])

    meaning = {
        "input": "Normalize 후 입력",
        "conv1_preBN": "Stem Conv 출력, BN·ReLU 전",
        "stem_bn_preReLU": "Stem BN 출력, ReLU 전",
        "stem": "Stem BN·ReLU 후",
        "stage1": "Stage 1 (Block 3개) 출력",
        "stage2": "Stage 2 (Transition 포함) 출력",
        "stage3": "Stage 3 (Transition 포함) 출력",
        "fc_input_gap": "GAP·Flatten 후 FC 입력",
        "logits": "Softmax 전 10개 점수",
    }
    files = {}
    for name, t in cap.items():
        arr = t.numpy().astype("<f4")  # IEEE754 FP32 little-endian, C-order
        np.save(os.path.join(out_dir, f"{name}.npy"), arr)
        files[name] = {"file": f"{name}.npy", "shape": list(arr.shape), "dtype": "float32",
                       "layout": "NCHW" if arr.ndim == 4 else "NC",
                       "meaning": meaning[name]}
    pred = int(logits.argmax(1))
    manifest = {
        "split": "test", "sample_index": index, "label": int(label),
        "label_name": CLASSES[int(label)], "pred": pred, "pred_name": CLASSES[pred],
        "preprocess": {"to_tensor": "/255", "mean": MEAN, "std": STD},
        "max_abs_diff_logits_hook_vs_forward": float((cap["logits"] - logits.cpu()).abs().max()),
        "tensors": files,
    }
    save_json(manifest, os.path.join(out_dir, "manifest.json"))
    return manifest


def run_e1(model, info, test_set, device, out_root="."):
    res = evaluate(model, test_set, device)
    summary = {
        "step": "E1",
        "model": "ResNet-20 (CIFAR-10, Option A)",
        "test_images": res["n"],
        "correct": res["correct"],
        "fp32_top1": round(res["top1"], 2),
        "per_class_top1": res["per_class_top1"],
        "stored_best_prec1_in_checkpoint": info["stored_best_prec1"],
        "note": "stored_best_prec1 는 checkpoint 에 저장된 값이며, fp32_top1 이 이번 직접 평가 결과다.",
        "dataset": {"source": getattr(test_set, "source", "?"),
                    "images_sha256": getattr(test_set, "data_sha256", "?"),
                    "labels_sha256": getattr(test_set, "label_sha256", "?")},
        "model_info": info,
        "environment": environment(),
    }
    save_json(summary, os.path.join(out_root, "results", "e1_fp32.json"))
    manifest = dump_sample(model, test_set, 0, os.path.join(out_root, "golden", "e1_sample0"), device)
    return summary, manifest, res["preds"]
