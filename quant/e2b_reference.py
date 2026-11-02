"""E2-B v1: exported integer constants -> integer Conv/Add/GAP/FC.

The core accepts integer NCHW codes. Float preprocessing/input quantization is
an explicit host boundary. Torch and NumPy implementations use int64 arithmetic
to check a signed INT32 accumulator contract without silently overflowing.
"""
import hashlib
import json
from pathlib import Path

import numpy as np

PROFILE = "RESNET20_SIGNED_MINMAX_RNE_V1"
I32_MAX = (1 << 31) - 1


def array_hash(a):
    a = np.ascontiguousarray(a)
    header = json.dumps({"shape": list(a.shape), "dtype": a.dtype.str}, sort_keys=True).encode()
    return hashlib.sha256(header + b"\0" + a.tobytes()).hexdigest()


def semantic_hash(manifest):
    payload = {k: v for k, v in manifest.items() if k not in ("semantic_sha256", "npz_sha256")}
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"),
                                     allow_nan=False).encode()).hexdigest()


def rne_numpy(value, shift):
    """Integer floor quotient/remainder avoids abs(INT64_MIN)."""
    if np.any((np.asarray(shift) < 0) | (np.asarray(shift) > 31)):
        raise ValueError("shift must be 0..31")
    value = np.asarray(value, dtype=np.int64)
    divisor = np.left_shift(np.int64(1), np.asarray(shift, dtype=np.int64))
    q, r = np.floor_divide(value, divisor), np.remainder(value, divisor)
    return q + ((2 * r > divisor) | ((2 * r == divisor) & (q % 2 != 0)))


def rne_torch(value, shift):
    import torch
    if bool(((shift < 0) | (shift > 31)).any()):
        raise ValueError("shift must be 0..31")
    divisor = torch.bitwise_left_shift(torch.ones_like(shift, dtype=torch.int64), shift)
    q = torch.div(value, divisor, rounding_mode="floor")
    r = torch.remainder(value, divisor)
    return q + ((2 * r > divisor) | ((2 * r == divisor) & (q % 2 != 0))).to(torch.int64)


def conv_numpy(x, w, bias, stride=1):
    """Independent exact integer contraction. x=NCHW, w=OIHW, padding=1."""
    x = np.pad(x, ((0, 0), (0, 0), (1, 1), (1, 1)))
    windows = np.lib.stride_tricks.sliding_window_view(x, (3, 3), axis=(2, 3))
    windows = windows[:, :, ::stride, ::stride, :, :]
    return np.einsum("nchwkl,ockl->nohw", windows, w.astype(np.int64), optimize=True) + bias[None, :, None, None]


def validate_package(m, arrays):
    """Reject missing/reordered constants, illegal widths, unsupported graph."""
    from model.resnet20_plan import build_plan
    from quant.integer_math import multiplier_shift
    expected = build_plan()["operations"]
    if m.get("profile") != PROFILE or m.get("zero_point") != 0 or len(m["operations"]) != 30:
        raise ValueError("unsupported quantization profile/graph")
    if m["score_scale"] != 2.0 ** -16:
        raise ValueError("score scale must be the fixed common 2^-16")
    scales = m["activation_scales"]
    expected_scale_names = {"input", "stem", "gap"} | {f"L{s}.{b}.{suffix}" for s in range(1, 4) for b in range(3) for suffix in ("h", "m", "y")}
    if set(scales) != expected_scale_names or not all(np.isfinite(v) and v > 0 for v in scales.values()):
        raise ValueError("invalid frozen activation scales")
    if m["input_scale"] != scales["input"]:
        raise ValueError("input scale mismatch")
    if m.get("semantic_sha256") != semantic_hash(m):
        raise ValueError("package semantic hash mismatch")
    if set(arrays) != set(m["arrays"]):
        raise ValueError("constant array set mismatch")
    for key, desc in m["arrays"].items():
        a = arrays[key]
        if list(a.shape) != desc["shape"] or a.dtype.str != desc["dtype"] or array_hash(a) != desc["sha256"]:
            raise ValueError(f"constant hash/shape/dtype mismatch: {key}")
    shapes = {"input": [3, 32, 32]}
    previous = "input"
    block_input = None
    tensor_scale = {"input": m["input_scale"]}
    for op, plan in zip(m["operations"], expected):
        if op["id"] != plan["id"] or op["name"] != plan["name"] or op["op"] != plan["op"]:
            raise ValueError("operation order mismatch")
        if any(name not in shapes for name in op["inputs"]):
            raise ValueError("unresolved tensor dependency")
        if op["name"].endswith(".conv1"):
            block_input = previous
        expected_inputs = [previous, block_input] if op["op"] == "add_relu" else [previous]
        if op["inputs"] != expected_inputs:
            raise ValueError("tensor/skip graph dependency mismatch")
        name = op["name"]
        scale_name = name.replace(".conv1", ".h").replace(".conv2", ".m").replace(".add_relu", ".y")
        expected_scale = m["score_scale"] if name == "fc" else scales[scale_name]
        if op["output_scale"] != expected_scale:
            raise ValueError("output scale/axis mismatch")
        if op["op"] in ("conv", "fc"):
            w, b = arrays[op["weight"]], arrays[op["bias"]]
            cout = plan["cout"] if op["op"] == "conv" else 10
            expected_w = [cout, plan["cin"], 3, 3] if op["op"] == "conv" else [10, 64]
            if list(w.shape) != expected_w or w.dtype != np.int8 or w.min() < -127:
                raise ValueError("weight axis/range mismatch")
            if b.shape != (cout,) or b.dtype != np.int32:
                raise ValueError("bias axis/dtype mismatch")
            sw = arrays[op["weight_scale"]]
            if sw.shape != (cout,) or sw.dtype != np.dtype("<f8") or not np.isfinite(sw).all() or np.any(sw <= 0):
                raise ValueError("weight scale axis/dtype/value mismatch")
            if op["input_scale"] != tensor_scale[previous]:
                raise ValueError("input scale/graph mismatch")
            if op["relu"] != (name == "stem" or name.endswith(".conv1")):
                raise ValueError("ReLU location mismatch")
            bound = np.abs(b.astype(np.int64)) + 128 * np.abs(w.astype(np.int64)).reshape(cout, -1).sum(1)
            if np.any(bound > I32_MAX) or not np.array_equal(bound, arrays[op["acc_bound"]]):
                raise ValueError("INT32 accumulation proof failed")
            n, s = arrays[op["multiplier"]], arrays[op["shift"]]
            if n.shape != (cout,) or s.shape != (cout,) or n.dtype != np.int32 or s.dtype != np.int32:
                raise ValueError("coefficient axis/dtype mismatch")
            if np.any(n < 0) or np.any((s < 0) | (s > 31)):
                raise ValueError("invalid coefficient")
            ratios = op["input_scale"] * sw / op["output_scale"]
            if any(int(nn) != multiplier_shift(float(rr), int(ss))[0] for nn, rr, ss in zip(n, ratios, s)):
                raise ValueError("coefficient does not match scale ratio")
            if np.any(bound.astype(object) * n.astype(object) >= 2 ** 63):
                raise ValueError("INT64 postmultiply proof failed")
            if op["op"] == "conv" and op["stride"] != plan["stride"]:
                raise ValueError("stride mismatch")
            if op["op"] == "fc" and (not np.all(op["output_scale"] == m["score_scale"]) or op["relu"]):
                raise ValueError("invalid common logit scale/activation")
        if op["op"] == "add_relu":
            if op["shortcut"] != plan["shortcut"] or op["shift"] not in range(32):
                raise ValueError("shortcut/shift mismatch")
            if min(op["multiplier_main"], op["multiplier_skip"]) < 0 or max(op["multiplier_main"], op["multiplier_skip"]) > I32_MAX:
                raise ValueError("invalid Add coefficients")
            incoming = [tensor_scale[t] for t in op["inputs"]]
            if op["input_scales"] != incoming:
                raise ValueError("Add scale dependency mismatch")
            expected_n = [multiplier_shift(sx / op["output_scale"], op["shift"])[0] for sx in incoming]
            if expected_n != [op["multiplier_main"], op["multiplier_skip"]]:
                raise ValueError("Add coefficient/unit mismatch")
        if op["op"] == "gap" and (op["shift"] not in range(32) or not 0 <= op["multiplier"] <= I32_MAX):
            raise ValueError("invalid GAP coefficient")
        if op["op"] == "gap":
            if op["input_scale"] != tensor_scale[previous] or op["multiplier"] != multiplier_shift(op["input_scale"] / (64 * op["output_scale"]), op["shift"])[0]:
                raise ValueError("GAP sum/average scale mismatch")
        if op["output_shape"] != (plan.get("output_shape", [1, plan.get("cout"), *plan.get("output_hw", [])])[1:]):
            raise ValueError("output shape mismatch")
        shapes[op["name"]] = op["output_shape"]
        tensor_scale[op["name"]] = op["output_scale"]
        previous = op["name"]
    return True


def save_package(m, arrays, directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    m["arrays"] = {k: {"shape": list(v.shape), "dtype": v.dtype.str, "sha256": array_hash(v)} for k, v in arrays.items()}
    m["semantic_sha256"] = semantic_hash(m)
    validate_package(m, arrays)
    np.savez_compressed(directory / "constants.npz", **arrays)
    m["npz_sha256"] = hashlib.sha256((directory / "constants.npz").read_bytes()).hexdigest()
    (directory / "manifest.json").write_text(json.dumps(m, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8")


def load_package(directory):
    directory = Path(directory)
    m = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    if hashlib.sha256((directory / "constants.npz").read_bytes()).hexdigest() != m["npz_sha256"]:
        raise ValueError("constant file hash mismatch")
    with np.load(directory / "constants.npz", allow_pickle=False) as z:
        arrays = {k: z[k].copy() for k in z.files}
    validate_package(m, arrays)
    return m, arrays


class IntegerReference:
    def __init__(self, manifest, arrays, backend="torch"):
        validate_package(manifest, arrays)
        if backend not in ("torch", "numpy"):
            raise ValueError("backend must be torch or numpy")
        self.m, self.a, self.backend = manifest, arrays, backend
        if backend == "torch":
            import torch
            self.a = {k: torch.from_numpy(v.astype(np.int64)) for k, v in arrays.items()}

    def quantize_input(self, preprocessed):
        # Host boundary: binary64 division, RNE, saturation; core then uses codes only.
        x = np.asarray(preprocessed, dtype=np.float64)
        if x.ndim != 4 or tuple(x.shape[1:]) != (3, 32, 32) or not np.isfinite(x).all():
            raise ValueError("expected finite NCHW preprocessed CIFAR input")
        return np.clip(np.rint(x / self.m["input_scale"]), -128, 127).astype(np.int8)

    def forward(self, codes, capture=False):
        raw = codes.detach().cpu().numpy() if hasattr(codes, "detach") else np.asarray(codes)
        if raw.dtype.kind not in "iu" or raw.ndim != 4 or tuple(raw.shape[1:]) != (3, 32, 32) or raw.shape[0] < 1 or int(raw.min()) < -128 or int(raw.max()) > 127:
            raise ValueError("core requires integer NCHW input codes in [-128,127]")
        if self.backend == "torch":
            import torch
            x = torch.as_tensor(codes).to(dtype=torch.int64, device="cpu")
            clip = lambda a, lo, hi: a.clamp(lo, hi)
            rne = rne_torch
        else:
            x = np.asarray(codes, dtype=np.int64)
            clip, rne = np.clip, rne_numpy
        if x.ndim != 4 or tuple(x.shape[1:]) != (3, 32, 32) or int(x.min()) < -128 or int(x.max()) > 127:
            raise ValueError("invalid input code shape/range")
        tensors, trace = {"input": x}, {}
        def observe(name, value):
            if capture:
                trace[name] = value.detach().cpu().numpy().copy() if self.backend == "torch" else value.copy()
        observe("input", x)
        for op in self.m["operations"]:
            source = tensors[op["inputs"][0]]
            kind = op["op"]
            if kind in ("conv", "fc"):
                w, b = self.a[op["weight"]], self.a[op["bias"]]
                if kind == "conv":
                    if self.backend == "torch":
                        import torch.nn.functional as F
                        acc = F.conv2d(source, w, b, stride=op["stride"], padding=1)
                    else:
                        acc = conv_numpy(source, w, b, op["stride"])
                    coeff_shape = (1, -1, 1, 1)
                else:
                    acc = source @ w.T + b
                    coeff_shape = (1, -1)
                if int(acc.min()) < -(1 << 31) or int(acc.max()) > I32_MAX:
                    raise OverflowError(f"INT32 accumulator overflow: {op['name']}")
                observe(op["name"] + ".acc", acc)
                n = self.a[op["multiplier"]].reshape(coeff_shape)
                shift = self.a[op["shift"]].reshape(coeff_shape)
                y = clip(rne(acc * n, shift), 0 if op["relu"] else (-(1 << 31) if kind == "fc" else -128),
                         I32_MAX if kind == "fc" else 127)
            elif kind == "add_relu":
                skip = tensors[op["inputs"][1]]
                if op["shortcut"] == "option_a":
                    pad = skip.shape[1] // 2
                    if self.backend == "torch":
                        import torch.nn.functional as F
                        skip = F.pad(skip[:, :, ::2, ::2], (0, 0, 0, 0, pad, pad))
                    else:
                        skip = np.pad(skip[:, :, ::2, ::2], ((0, 0), (pad, pad), (0, 0), (0, 0)))
                observe(op["name"] + ".skip", skip)
                wide = source * op["multiplier_main"] + skip * op["multiplier_skip"]
                if self.backend == "torch":
                    import torch
                    shift = torch.tensor(op["shift"], dtype=torch.int64)
                else: shift = op["shift"]
                y = clip(rne(wide, shift), 0, 127)
            else:  # GAP: sum all 64 positions, then rescale/round ONCE.
                total = source.sum(axis=(2, 3))
                observe("gap.sum", total)
                if self.backend == "torch":
                    import torch
                    shift = torch.tensor(op["shift"], dtype=torch.int64)
                else: shift = op["shift"]
                y = clip(rne(total * op["multiplier"], shift), 0, 127)
            if list(y.shape[1:]) != op["output_shape"]:
                raise ValueError(f"runtime shape mismatch: {op['name']}")
            tensors[op["name"]] = y
            observe(op["name"], y)
        result = tensors["fc"]
        if self.backend == "torch": result = result.numpy()
        return result, trace
