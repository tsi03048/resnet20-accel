"""E2 — INT8 을 쓸지 정하기 위한 정확도 하락 측정 (BN Folding + PTQ fake-quant).

목적: INT8 채택 여부를 결정할 근거(정확도 하락 폭)를 만든다. 아직 RTL 용 bit-exact
정수 Reference 는 아니다. INT8 을 채택하면 다음 단계에서 이 설정을 정수 Reference 로 고정한다.

양자화 설정
  * Weight : 출력 Channel 별 대칭 INT8 [-127, 127], scale = max|w| / 127
  * Activation : Tensor 별 1개 scale, Zero-point 0
      - 'signed'   : 모든 경계 signed INT8 [-128, 127]  (HW 가 가장 단순)
      - 'relu_u8'  : ReLU 뒤 경계는 unsigned [0, 255], 나머지 signed
  * Rounding : torch.round (half-to-even, RNE) → 문서 D1/E2 의 RNE 와 같다
  * Bias : FP32 유지. INT32 bias·정수 계수 오차는 E2-B에서 별도 평가해야 한다.
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
    loader = DataLoader(calib_set, batch_size=batch_size, shuffle=False, num_workers=0)
    amax, qsum, nb = {}, {}, 0

    def obs(name, t):
        a = t.detach().abs()
        amax[name] = max(amax.get(name, 0.0), float(a.max()))
        if percentile is not None:
            flat = a.flatten()
            if flat.numel() > 16_000_000:  # torch.quantile 입력 크기 제한 대비
                step = (flat.numel() + 15_999_999) // 16_000_000
                flat = flat[::step]
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
@torch.no_grad()
def run_e2(model, test_set, train_set, device, fp32_preds, fp32_top1,
           accept_drop_pp=None, out_root=".", calib_n=1000, dev_n=1000,
           fold_atol=1e-4, fold_rtol=1e-4):
    """E2-A: train 개발집합에서 선택한 설정 하나만 최종 test에서 평가한다.

    공개 checkpoint가 train 전체를 학습했으므로 dev는 독립 일반화 검증이 아니다.
    Test 결과를 보고 다시 설정을 선택하면 새 결과는 탐색 결과로 표시해야 한다.
    """
    from torch.utils.data import Subset
    if min(calib_n, dev_n) <= 0 or calib_n + dev_n > len(train_set):
        raise ValueError("calibration/dev size must be positive and disjoint")
    if accept_drop_pp is not None and accept_drop_pp < 0:
        raise ValueError("accept_drop_pp must be nonnegative or None")
    idx = torch.randperm(len(train_set), generator=torch.Generator().manual_seed(0)).tolist()
    calib_idx, dev_idx = idx[:calib_n], idx[calib_n:calib_n + dev_n]
    calib_set, dev_set = Subset(train_set, calib_idx), Subset(train_set, dev_idx)
    P = _to(folded_params(model), device)

    # 1) Folding 동치성: 같은 입력에서 원 모델과 비교
    x0 = torch.stack([dev_set[i][0] for i in range(min(64, dev_n))]).to(device)
    original, folded = model(x0), forward_folded(P, x0)
    diff = float((original - folded).abs().max())
    if not torch.allclose(original, folded, atol=fold_atol, rtol=fold_rtol):
        raise RuntimeError(f"BN folding mismatch: max_abs={diff}; stop before PTQ")
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
    dev_fp32 = evaluate(model, dev_set, device)
    rows = []
    for name, params, act in configs:
        r = evaluate(lambda x, p=params, a=act: forward_folded(p, x, a), dev_set, device)
        agree = 100.0 * float(r["preds"].eq(dev_fp32["preds"]).float().mean())
        rows.append({"config": name, "top1": round(r["top1"], 2),
                     "drop_pp": round(dev_fp32["top1"] - r["top1"], 2),
                     "agreement_with_fp32_pct": round(agree, 2)})

    int8_rows = [r for r in rows if r["config"].startswith("W8A8")]
    best = min(int8_rows, key=lambda r: r["drop_pp"])
    # Selection is persisted BEFORE accessing test labels/results.
    selected_name = best["config"]
    selected = next(c for c in configs if c[0] == selected_name)
    selection = {"selected_config": selected_name, "selected_on": "train_development",
                 "calibration_indices": calib_idx, "development_indices": dev_idx,
                 "selection_rule": "maximum development Top-1; ties use config order",
                 "accept_drop_pp": accept_drop_pp,
                 "independent_validation": False}
    save_json(selection, os.path.join(out_root, "results", "e2_selection.json"))
    _, params, act = selected
    test = evaluate(lambda x: forward_folded(params, x, act), test_set, device)
    test_drop = round(fp32_top1 - test["top1"], 2)
    decision = {
        "accept_drop_pp": accept_drop_pp,
        "selected_int8_config": selected_name,
        "selected_test_drop_pp": test_drop,
        "recommend_int8": None if accept_drop_pp is None else test_drop <= accept_drop_pp,
        "note": "fake-quant 후보 평가다. 최종 채택에는 E2-B 실제 정수 기준 평가가 필요하다. 허용치는 팀이 실행 전에 정한다.",
    }
    summary = {
        "step": "E2-A",
        "deployable_integer_reference": False,
        "fp32_top1_reference": round(fp32_top1, 2),
        "folding_max_abs_logit_diff_64imgs": diff,
        "folding_tolerance": {"atol": fold_atol, "rtol": fold_rtol, "passed": True},
        "calibration": {"split": "train", "n": calib_n, "seed": 0, "indices": calib_idx,
                        "source": getattr(train_set, "source", "?"),
                        "images_sha256": getattr(train_set, "data_sha256", "?"),
                        "labels_sha256": getattr(train_set, "label_sha256", "?")},
        "development": {"split": "train", "n": dev_n, "indices": dev_idx,
                        "independent_validation": False,
                        "note": "공개 checkpoint 학습 데이터와 겹칠 수 있는 개발용 집합"},
        "percentile_method": "mean of per-batch absolute quantiles; deterministic strided cap, approximate",
        "activation_ranges": ranges,
        "results": rows,
        "results_scope": "train development only",
        "selected_test": {"config": selected_name, "n": test["n"], "correct": test["correct"],
                          "top1": test["top1"], "drop_pp": test_drop,
                          "agreement_with_fp32_pct": 100.0 * float(test["preds"].eq(fp32_preds).float().mean())},
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

