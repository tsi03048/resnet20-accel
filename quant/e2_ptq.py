"""E2 — INT8 을 쓸지 정하기 위한 정확도 하락 측정 (BN Folding + PTQ fake-quant).

목적: INT8 채택 여부를 결정할 근거(정확도 하락 폭)를 만든다. 아직 RTL 용 bit-exact
정수 Reference 는 아니다. INT8 을 채택하면 다음 단계에서 이 설정을 정수 Reference 로 고정한다.

양자화 설정
  * Weight : 출력 Channel 별 대칭 INT8 [-127, 127], scale = max|w| / 127
  * Activation : Tensor 별 1개 scale, Zero-point 0
      - 'signed'   : 모든 경계 signed INT8 [-128, 127]  (HW 가 가장 단순)
      - 'relu_u8'  : ReLU 뒤 경계는 unsigned [0, 255], 나머지 signed
  * Rounding : torch.round (half-to-even, RNE) → 문서 D1/E2 의 RNE 와 같다
  * Bias : FP32 유지 (INT32 bias 의 영향은 무시할 수준이라 이 단계에서는 측정 대상에서 제외)
  * Calibration : 공식 train split 에서 seed 0 으로 뽑은 1,000장 (증강 없음). Test 는 사용하지 않는다.
"""
import os

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader

from model.common import calibration_subset, evaluate, save_json

# ---------------------------------------------------------------- BN Folding
def _fold(conv, bn):
    a = bn.weight / torch.sqrt(bn.running_var + bn.eps)
    w = conv.weight * a.view(-1, 1, 1, 1)
    b = bn.bias - a * bn.running_mean
    if conv.bias is not None:
        b = b + a * conv.bias
    return w.detach().clone(), b.detach().clone()


def folded_params(model):
    P = {"stem": _fold(model.conv1, model.bn1), "blocks": []}
    for li, layer in enumerate((model.layer1, model.layer2, model.layer3), 1):
        for bi, blk in enumerate(layer):
            w1, b1 = _fold(blk.conv1, blk.bn1)
            w2, b2 = _fold(blk.conv2, blk.bn2)
            option_a = not isinstance(blk.shortcut, nn.Sequential)  # 빈 Sequential = identity
            P["blocks"].append({
                "name": f"L{li}.{bi}", "w1": w1, "b1": b1, "w2": w2, "b2": b2,
                "stride": blk.conv1.stride[0],
                "pad": blk.conv2.out_channels // 4 if option_a else 0,
            })
    P["fc"] = (model.linear.weight.detach().clone(), model.linear.bias.detach().clone())
    return P


def activation_points(P):
    pts = ["input", "stem"]
    for b in P["blocks"]:
        pts += [b["name"] + ".h", b["name"] + ".m", b["name"] + ".y"]
    return pts + ["gap"]


def forward_folded(P, x, act=None):
    """참고 BasicBlock 과 같은 순서: relu(bn1(conv1)) → bn2(conv2) → +shortcut → relu.
    act(name, t) 는 Buffer 에 저장되는 경계마다 호출된다 (관측 또는 fake-quant)."""
    A = act or (lambda _n, t: t)
    y = A("input", x)
    w, b = P["stem"]
    y = A("stem", F.relu(F.conv2d(y, w, b, 1, 1)))
    for blk in P["blocks"]:
        n = blk["name"]
        h = A(n + ".h", F.relu(F.conv2d(y, blk["w1"], blk["b1"], blk["stride"], 1)))
        m = A(n + ".m", F.conv2d(h, blk["w2"], blk["b2"], 1, 1))
        if blk["pad"]:
            s = F.pad(y[:, :, ::2, ::2], (0, 0, 0, 0, blk["pad"], blk["pad"]), "constant", 0)
        else:
            s = y
        y = A(n + ".y", F.relu(m + s))
    g = A("gap", F.avg_pool2d(y, y.size(3)).flatten(1))
    return F.linear(g, *P["fc"])


# ---------------------------------------------------------------- Quantizers
def quant_weight_per_channel(w, bits=8):
    qmax = 2 ** (bits - 1) - 1
    dims = tuple(range(1, w.dim()))
    s = w.abs().amax(dim=dims, keepdim=True).clamp_min(1e-12) / qmax
    return torch.clamp(torch.round(w / s), -qmax, qmax) * s


def quantize_params(P, bits=8):
    Q = {"stem": (quant_weight_per_channel(P["stem"][0], bits), P["stem"][1]), "blocks": []}
    for b in P["blocks"]:
        nb = dict(b)
        nb["w1"] = quant_weight_per_channel(b["w1"], bits)
        nb["w2"] = quant_weight_per_channel(b["w2"], bits)
        Q["blocks"].append(nb)
    Q["fc"] = (quant_weight_per_channel(P["fc"][0], bits), P["fc"][1])
    return Q


def is_post_relu(name):
    return name == "stem" or name == "gap" or name.endswith(".h") or name.endswith(".y")


@torch.no_grad()
def calibrate(P, calib_set, device, percentile=None, batch_size=100):
    """경계별 범위 r 을 구한다. percentile=None 이면 abs-max, 아니면 batch 별 |t| 분위수의 평균."""
    loader = DataLoader(calib_set, batch_size=batch_size, shuffle=False, num_workers=2)
    amax, qsum, nb = {}, {}, 0

    def obs(name, t):
        a = t.detach().abs()
        amax[name] = max(amax.get(name, 0.0), float(a.max()))
        if percentile is not None:
            flat = a.flatten()
            if flat.numel() > 16_000_000:  # torch.quantile 입력 크기 제한 대비
                flat = flat[torch.randperm(flat.numel(), device=flat.device)[:16_000_000]]
            qsum[name] = qsum.get(name, 0.0) + float(torch.quantile(flat.float(), percentile / 100.0))
        return t

    for x, _ in loader:
        forward_folded(P, x.to(device), obs)
        nb += 1
    if percentile is None:
        return amax
    return {k: v / nb for k, v in qsum.items()}


def make_act_quant(ranges, mode="signed"):
    def act(name, t):
        r = max(ranges[name], 1e-12)
        if mode == "relu_u8" and is_post_relu(name):
            s, lo, hi = r / 255.0, 0, 255
        else:
            s, lo, hi = r / 127.0, -128, 127
        return torch.clamp(torch.round(t / s), lo, hi) * s
    return act


# ---------------------------------------------------------------- 실험 실행
def run_e2(model, test_set, train_set, device, fp32_preds, fp32_top1,
           accept_drop_pp=1.0, out_root=".", calib_n=1000):
    P = _to(folded_params(model), device)

    # 1) Folding 동치성: 같은 입력에서 원 모델과 비교
    x0 = torch.stack([test_set[i][0] for i in range(64)]).to(device)
    with torch.no_grad():
        diff = float((model(x0) - forward_folded(P, x0)).abs().max())

    calib_set, calib_idx = calibration_subset(train_set, n=calib_n, seed=0)
    ranges = {"minmax": calibrate(P, calib_set, device),
              "p99.99": calibrate(P, calib_set, device, percentile=99.99)}
    Q = quantize_params(P)

    configs = [
        ("FP32 folded", P, None),
        ("W8 only", Q, None),
        ("W8A8 signed · minmax", Q, make_act_quant(ranges["minmax"], "signed")),
        ("W8A8 signed · p99.99", Q, make_act_quant(ranges["p99.99"], "signed")),
        ("W8A8 relu_u8 · minmax", Q, make_act_quant(ranges["minmax"], "relu_u8")),
        ("W8A8 relu_u8 · p99.99", Q, make_act_quant(ranges["p99.99"], "relu_u8")),
    ]
    rows = []
    for name, params, act in configs:
        r = evaluate(lambda x, p=params, a=act: forward_folded(p, x, a), test_set, device)
        agree = 100.0 * float(r["preds"].eq(fp32_preds).float().mean())
        rows.append({"config": name, "top1": round(r["top1"], 2),
                     "drop_pp": round(fp32_top1 - r["top1"], 2),
                     "agreement_with_fp32_pct": round(agree, 2)})

    int8_rows = [r for r in rows if r["config"].startswith("W8A8")]
    best = min(int8_rows, key=lambda r: r["drop_pp"])
    decision = {
        "accept_drop_pp": accept_drop_pp,
        "best_int8_config": best["config"],
        "best_int8_drop_pp": best["drop_pp"],
        "recommend_int8": best["drop_pp"] <= accept_drop_pp,
        "note": "기준값(accept_drop_pp)은 팀이 정한다. 이 결과는 결정 근거이며 결정 자체는 Notion 결정 기록에 남긴다.",
    }
    summary = {
        "step": "E2",
        "fp32_top1_reference": round(fp32_top1, 2),
        "folding_max_abs_logit_diff_64imgs": diff,
        "calibration": {"split": "train", "n": calib_n, "seed": 0, "first_indices": calib_idx[:10],
                        "source": getattr(train_set, "source", "?"),
                        "images_sha256": getattr(train_set, "data_sha256", "?")},
        "activation_ranges": {k: {p: round(v, 6) for p, v in d.items()} for k, d in ranges.items()},
        "results": rows,
        "decision_input": decision,
    }
    save_json(summary, os.path.join(out_root, "results", "e2_ptq.json"))
    return summary


def _to(P, device):
    out = {"stem": tuple(t.to(device) for t in P["stem"]),
           "fc": tuple(t.to(device) for t in P["fc"]), "blocks": []}
    for b in P["blocks"]:
        nb = dict(b)
        for k in ("w1", "b1", "w2", "b2"):
            nb[k] = b[k].to(device)
        out["blocks"].append(nb)
    return out
