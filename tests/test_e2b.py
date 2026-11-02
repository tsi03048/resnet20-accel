"""Independent arithmetic oracles and deliberately invalid packages.

Synthetic fixtures below are test data, never trained-model accuracy evidence.
"""
import copy
from fractions import Fraction
import importlib.util
import tempfile
import unittest

HAS_NUMPY = importlib.util.find_spec("numpy") is not None
HAS_TORCH = importlib.util.find_spec("torch") is not None


def synthetic_package():
    import numpy as np
    from model.resnet20_plan import build_plan
    from quant.e2b_reference import PROFILE, semantic_hash, array_hash
    rng = np.random.default_rng(7)
    scales = {"input": 1.0, "stem": 1.0, "gap": 1.0}
    scales.update({f"L{s}.{b}.{suffix}": 1.0 for s in range(1, 4) for b in range(3) for suffix in ("h", "m", "y")})
    m = dict(profile=PROFILE, zero_point=0, input_scale=1.0, score_scale=2.0 ** -16,
             activation_scales=scales, operations=[], fixture="SYNTHETIC_UNIT_TEST")
    arrays, previous, block_input = {}, "input", None
    for plan in build_plan()["operations"]:
        name, kind = plan["name"], plan["op"]
        out_shape = plan["output_shape"][1:] if "output_shape" in plan else [plan["cout"], *plan["output_hw"]]
        op = dict(id=plan["id"], name=name, op=kind, inputs=[previous], output_shape=out_shape, output_scale=1.0)
        if name.endswith(".conv1"): block_input = previous
        if kind in ("conv", "fc"):
            cout = plan["cout"] if kind == "conv" else 10
            shape = (cout, plan["cin"], 3, 3) if kind == "conv" else (10, 64)
            w = rng.integers(-2, 3, shape, dtype=np.int8)
            b = rng.integers(-10, 11, cout, dtype=np.int32)
            op.update(input_scale=1.0, relu=name == "stem" or name.endswith(".conv1"))
            factor = 65536 if kind == "fc" else 1
            if kind == "fc": op["output_scale"] = m["score_scale"]
            else: op["stride"] = plan["stride"]
            data = dict(weight=w, bias=b, weight_scale=np.ones(cout, dtype="<f8"),
                        multiplier=np.full(cout, factor, dtype="<i4"), shift=np.zeros(cout, dtype="<i4"),
                        acc_bound=(np.abs(b.astype(np.int64)) + 128*np.abs(w.astype(np.int64)).reshape(cout, -1).sum(1)).astype("<i8"))
            for role, value in data.items():
                key = name + "." + role
                arrays[key], op[role] = value, key
        elif kind == "add_relu":
            op.update(inputs=[previous, block_input], shortcut=plan["shortcut"],
                      multiplier_main=1, multiplier_skip=1, shift=0, input_scales=[1.0, 1.0])
        else: op.update(input_scale=1.0, multiplier=1, shift=6)
        m["operations"].append(op)
        previous = name
    m["arrays"] = {k: dict(shape=list(v.shape), dtype=v.dtype.str, sha256=array_hash(v)) for k, v in arrays.items()}
    m["semantic_sha256"] = semantic_hash(m)
    return m, arrays


@unittest.skipUnless(HAS_NUMPY, "NumPy is required for E2-B")
class E2BTests(unittest.TestCase):
    def test_rne_exact_large_signed_ties(self):
        import numpy as np
        from quant.e2b_reference import rne_numpy
        values = [-(1 << 63), -(1 << 62)+1, -7, -5, -3, -1, 0, 1, 3, 5, 7, (1 << 62)-1]
        for shift in (0, 1, 2, 6, 24, 31):
            expected = [round(Fraction(v, 1 << shift)) for v in values]
            np.testing.assert_array_equal(rne_numpy(values, shift), expected)
        with self.assertRaises(ValueError): rne_numpy([1], -1)
        if HAS_TORCH:
            import torch
            from quant.e2b_reference import rne_torch
            for shift in (0, 1, 6, 31):
                np.testing.assert_array_equal(rne_torch(torch.tensor(values), torch.tensor(shift)).numpy(),
                                              rne_numpy(values, shift))

    def test_conv_against_scalar_oracle(self):
        import numpy as np
        from quant.e2b_reference import conv_numpy
        rng = np.random.default_rng(123)
        for stride in (1, 2):
            x = rng.integers(-128, 128, (1, 2, 4, 4), dtype=np.int64)
            w = rng.integers(-127, 128, (3, 2, 3, 3), dtype=np.int64)
            b = np.array([-123, 456, -789], dtype=np.int64)
            expected = np.zeros((1, 3, (4 + stride - 1)//stride, (4 + stride - 1)//stride), dtype=np.int64)
            for o in range(3):
                for h in range(expected.shape[2]):
                    for col in range(expected.shape[3]):
                        acc = int(b[o])
                        for c in range(2):
                            for kh in range(3):
                                for kw in range(3):
                                    ih, iw = h*stride+kh-1, col*stride+kw-1
                                    if 0 <= ih < 4 and 0 <= iw < 4:
                                        acc += int(x[0,c,ih,iw])*int(w[o,c,kh,kw])
                        expected[0,o,h,col] = acc
            np.testing.assert_array_equal(conv_numpy(x, w, b, stride), expected)
            if HAS_TORCH:
                import torch
                import torch.nn.functional as F
                np.testing.assert_array_equal(F.conv2d(torch.from_numpy(x), torch.from_numpy(w), torch.from_numpy(b),stride=stride,padding=1).numpy(), expected)

    def test_coefficient_rounding_and_invalid_ratio(self):
        from quant.e2b_export import coefficient
        for ratio in (0, 0.3, 1.0, 12.5, 65536):
            n, shift = coefficient([ratio])
            self.assertLessEqual(abs(int(n[0]) / (1 << shift) - ratio), 0.5 / (1 << shift))
        for ratio in (-1, float("nan"), float("inf"), 1e40):
            with self.assertRaises(ValueError): coefficient([ratio])

    def test_roundtrip_and_corrupt_file_rejection(self):
        from pathlib import Path
        from quant.e2b_reference import save_package, load_package
        m, arrays = synthetic_package()
        with tempfile.TemporaryDirectory() as d:
            save_package(m, arrays, d)
            m2, a2 = load_package(d)
            self.assertEqual(m["semantic_sha256"], m2["semantic_sha256"])
            path = Path(d) / "constants.npz"
            path.write_bytes(path.read_bytes() + b"corrupt")
            with self.assertRaisesRegex(ValueError, "file hash"): load_package(d)

    def test_invalid_graph_rejected_even_after_rehash(self):
        from quant.e2b_reference import validate_package, semantic_hash, array_hash
        m, arrays = synthetic_package()
        changes = [lambda z: z["operations"][2].update(relu=True),
                   lambda z: z["operations"][3].update(inputs=["L1.0.conv2", "input"]),
                   lambda z: z["operations"][12].update(shortcut="identity"),
                   lambda z: z["operations"][28].update(multiplier=2),
                   lambda z: z["operations"][29].update(output_scale=1.0)]
        for change in changes:
            z = copy.deepcopy(m)
            change(z); z["semantic_sha256"] = semantic_hash(z)
            with self.assertRaises(ValueError): validate_package(z, arrays)
        a2 = {k: v.copy() for k,v in arrays.items()}
        key = m["operations"][0]["bias"]
        a2[key][0] = (1 << 31)-1
        z = copy.deepcopy(m)
        z["arrays"][key]["sha256"] = array_hash(a2[key])
        z["semantic_sha256"] = semantic_hash(z)
        with self.assertRaisesRegex(ValueError, "accumulation proof"): validate_package(z, a2)

    @unittest.skipUnless(HAS_TORCH, "Torch integer backend")
    def test_whole_graph_and_input_boundary(self):
        import torch
        import numpy as np
        from quant.e2b_reference import IntegerReference
        torch.set_num_threads(2)
        m, arrays = synthetic_package()
        one, two = IntegerReference(m, arrays, "torch"), IntegerReference(m, arrays, "numpy")
        x = np.random.default_rng(9).integers(-128,128,(1,3,32,32),dtype=np.int8)
        y, trace = one.forward(x, capture=True)
        other, trace2 = two.forward(x, capture=True)
        self.assertEqual(len(trace),61)
        for name in trace: np.testing.assert_array_equal(trace[name],trace2[name])
        np.testing.assert_array_equal(y,other)
        # V1 code format is integral; silently truncating caller floats is forbidden.
        with self.assertRaises(ValueError): one.forward(x.astype(float)+0.5)
        with self.assertRaises(ValueError): one.forward(np.full((1,3,32,32),128))


if __name__ == "__main__": unittest.main()
