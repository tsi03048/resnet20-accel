"""Replay frozen actual-model sample 0 without a dataset or PyTorch download.

python -m quant.replay_e2b --backend numpy
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

from quant.e2b_reference import IntegerReference, array_hash, load_package


def replay(package_dir="reference/e2b_v1", golden_dir=None, backend="numpy"):
    package_dir = Path(package_dir)
    golden_dir = Path(golden_dir) if golden_dir else package_dir / "sample0"
    m, arrays = load_package(package_dir)
    g = json.loads((golden_dir / "manifest.json").read_text(encoding="utf-8"))
    if g["package_semantic_sha256"] != m["semantic_sha256"]:
        raise ValueError("Golden/package identity mismatch")
    file = golden_dir / "tensors.npz"
    if hashlib.sha256(file.read_bytes()).hexdigest() != g["npz_sha256"]:
        raise ValueError("Golden file hash mismatch")
    with np.load(file, allow_pickle=False) as z:
        expected = {k: z[k].copy() for k in z.files}
    if set(expected) != set(g["tensors"]):
        raise ValueError("Golden tensor set mismatch")
    for key, value in expected.items():
        desc = g["tensors"][key]
        if list(value.shape) != desc["shape"] or value.dtype.str != desc["dtype"] or array_hash(value) != desc["sha256"]:
            raise ValueError(f"Golden tensor hash/shape/dtype mismatch: {key}")
    scores, trace = IntegerReference(m, arrays, backend).forward(expected["input"], capture=True)
    if set(trace) != set(expected): raise ValueError("runtime Golden boundary set mismatch")
    total = 0
    for key in trace:
        if not np.array_equal(trace[key], expected[key]):
            raise RuntimeError(f"first mismatch: {key}")
        total += expected[key].size
    return dict(status="PASS", backend=backend, tensor_count=len(trace), compared_elements=total,
                prediction=int(scores.argmax(1)[0]), class_name=m["classes"][int(scores.argmax(1)[0])],
                package_semantic_sha256=m["semantic_sha256"], rtl_compared=False)


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--package", default="reference/e2b_v1")
    p.add_argument("--golden", default=None)
    p.add_argument("--backend", choices=["numpy","torch"], default="numpy")
    a=p.parse_args()
    print(json.dumps(replay(a.package,a.golden,a.backend),indent=2))


if __name__ == "__main__": main()
