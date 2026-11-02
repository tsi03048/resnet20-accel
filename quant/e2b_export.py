"""Freeze the existing E2-A signed/minmax choice as integer package v1."""
import hashlib
import json
import math
from pathlib import Path

import numpy as np

from quant.integer_math import multiplier_shift
from quant.e2b_reference import PROFILE, I32_MAX, save_package


def coefficient(ratios):
    """Largest common denominator up to 2^31 with nonnegative INT32 N."""
    ratios = [float(r) for r in ratios]
    if not all(math.isfinite(r) and r >= 0 for r in ratios):
        raise ValueError("invalid scale ratio")
    for shift in range(31, -1, -1):
        try:
            values = [multiplier_shift(r, shift)[0] for r in ratios]
        except ValueError:
            continue
        if all(r == 0 or n > 0 for r, n in zip(ratios, values)):
            return np.asarray(values, dtype="<i4"), shift
    raise ValueError("scale ratio cannot be represented by profile v1")


def export_model(model, report, selection, model_info, directory):
    import torch
    from model.common import AKA_COMMIT, CKPT_SHA256, MEAN, STD, CLASSES
    from quant.e2_ptq import folded_params, activation_points
    if selection["selected_config"] != "W8A8 signed · minmax":
        raise ValueError("v1 requires the adopted signed/minmax selection")
    if model_info["checkpoint_sha256"] != CKPT_SHA256:
        raise ValueError("unexpected checkpoint")
    calib, dev = selection["calibration_indices"], selection["development_indices"]
    if len(calib) != 1000 or len(dev) != 1000 or len(set(calib + dev)) != 2000 or not all(0 <= i < 50000 for i in calib + dev):
        raise ValueError("expected disjoint 1000/1000 train indices")
    if report["calibration"]["indices"] != calib or report["development"]["indices"] != dev:
        raise ValueError("selection/report indices mismatch")
    if report["selected_test"]["config"] != selection["selected_config"]:
        raise ValueError("selection/report config mismatch")
    if not report["folding_tolerance"]["passed"]:
        raise ValueError("E2-A folding gate not passed")
    if len(model.layer1) != 3 or len(model.layer2) != 3 or len(model.layer3) != 3:
        raise ValueError("expected ResNet-20")
    P = folded_params(model)
    ranges = report["activation_ranges"]["minmax"]
    if set(ranges) != set(activation_points(P)) or not all(math.isfinite(v) and v >= 0 for v in ranges.values()):
        raise ValueError("activation range set/value mismatch")
    scales = {name: max(value, 1e-12) / 127.0 for name, value in ranges.items()}
    arrays, operations = {}, []
    m = dict(profile=PROFILE, model="ResNet-20 CIFAR Option A", zero_point=0,
             input_scale=scales["input"], score_scale=2.0 ** -16,
             preprocessing=dict(mean=MEAN, std=STD, layout="NCHW", input="FP32 Normalize then binary64 quantization"),
             classes=list(CLASSES), reference_commit=AKA_COMMIT, checkpoint_sha256=CKPT_SHA256,
             activation_scales=scales, calibration_indices=calib,
             development_indices=dev, calibration_dataset_sha256=report["calibration"]["images_sha256"],
             e2a_selection_rule=selection["selection_rule"], operations=operations,
             contract=dict(weight="signed INT8 [-127,127], OIHW/output channel", activation="signed INT8 [-128,127], z=0",
                           bias="INT32 in sx*sw channel domain", accumulator="INT32 with absolute-prefix proof; INT64 software storage",
                           requant="RNE(acc*N/2^shift) once, then ReLU if required, then saturation",
                           residual="requantized Conv2 code and skip code; common denominator, sum then ONE RNE; ReLU+clip",
                           gap="INT64 sum of 64 codes; rescale including /64; ONE RNE; clip",
                           fc="INT32 common output code, scale=2^-16, no ReLU; argmax first index on ties"))
    shapes = {"input": [3, 32, 32]}

    def layer(name, src, dst_scale, weight, bias, stride=1, relu=False, kind="conv"):
        weight = weight.detach().cpu()
        bias = bias.detach().cpu()
        dims = tuple(range(1, weight.ndim))
        sw = weight.abs().amax(dim=dims, keepdim=True).clamp_min(1e-12) / 127
        qw = torch.clamp(torch.round(weight / sw), -127, 127).to(torch.int8).numpy()
        sw = sw.flatten().double().numpy()
        sx = scales[src]
        qb64 = np.rint(bias.double().numpy() / (sx * sw))
        if not np.isfinite(qb64).all() or np.any(qb64 < -(1 << 31)) or np.any(qb64 > I32_MAX):
            raise OverflowError(f"INT32 bias overflow: {name}")
        qb = qb64.astype("<i4")
        bound = np.abs(qb.astype(np.int64)) + 128 * np.abs(qw.astype(np.int64)).reshape(qw.shape[0], -1).sum(1)
        if np.any(bound > I32_MAX):
            raise OverflowError(f"INT32 prefix bound failed: {name}")
        ratio = sx * sw / dst_scale
        # Separate channel shifts allow each channel the best valid denominator.
        coefficients = [coefficient([r]) for r in ratio]
        ns = np.asarray([int(n[0]) for n, _ in coefficients], dtype="<i4")
        shifts = np.asarray([s for _, s in coefficients], dtype="<i4")
        a = {"weight": qw, "bias": qb, "weight_scale": sw.astype("<f8"),
             "multiplier": ns, "shift": shifts, "acc_bound": bound.astype("<i8")}
        op = dict(id=len(operations), name=name, op=kind, inputs=[src], relu=relu,
                  input_scale=sx, output_scale=dst_scale)
        for role, value in a.items():
            key = name + "." + role
            arrays[key], op[role] = np.ascontiguousarray(value), key
        if kind == "conv":
            op["stride"] = stride
            op["output_shape"] = [qw.shape[0], shapes[src][1] // stride, shapes[src][2] // stride]
        else: op["output_shape"] = [10]
        op["max_multiplier_error"] = float(np.max(np.abs(ns.astype(np.float64) / (2.0 ** shifts) - ratio)))
        shapes[name] = op["output_shape"]
        scales[name] = dst_scale
        operations.append(op)

    layer("stem", "input", scales["stem"], *P["stem"], relu=True)
    previous = "stem"
    for block in P["blocks"]:
        name, skip = block["name"], previous
        h, main, out = name + ".h", name + ".m", name + ".y"
        # Package graph names match the static 30-op inventory; Tensor scales retain E2-A names.
        conv1, conv2, add = name + ".conv1", name + ".conv2", name + ".add_relu"
        layer(conv1, previous, scales[h], block["w1"], block["b1"], block["stride"], True)
        layer(conv2, conv1, scales[main], block["w2"], block["b2"])
        values, shift = coefficient([scales[main] / scales[out], scales[previous] / scales[out]])
        operations.append(dict(id=len(operations), name=add, op="add_relu", inputs=[conv2, skip],
                               shortcut="option_a" if block["pad"] else "identity",
                               multiplier_main=int(values[0]), multiplier_skip=int(values[1]), shift=shift,
                               output_shape=shapes[conv2], input_scales=[scales[main], scales[previous]],
                               output_scale=scales[out]))
        shapes[add], scales[add], previous = shapes[conv2], scales[out], add
    n, shift = coefficient([scales[previous] / (64 * scales["gap"])])
    operations.append(dict(id=len(operations), name="gap", op="gap", inputs=[previous],
                           multiplier=int(n[0]), shift=shift, output_shape=[64],
                           input_scale=scales[previous], output_scale=scales["gap"]))
    shapes["gap"] = [64]
    layer("fc", "gap", m["score_scale"], *P["fc"], kind="fc")
    # Keep only the frozen tensor names in the scale map; op-local scales are explicit.
    m["activation_scales"] = {k: scales[k] for k in activation_points(P)}
    save_package(m, arrays, directory)
    return m, arrays
