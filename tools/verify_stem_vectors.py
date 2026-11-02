"""Validate exact Stem hex files against the E2-B constants and sample Golden."""
import argparse
import hashlib
import json
from pathlib import Path
import re

import numpy as np
from quant.e2b_reference import load_package
from quant.replay_e2b import replay


def verify(vectors="reference/e2b_v1/stem_vectors", package="reference/e2b_v1", golden=None):
    root, package = Path(vectors), Path(package)
    golden = Path(golden) if golden else package / "sample0"
    # Independently recompute all 61 sample boundaries before using its Stem Golden.
    replay(package, golden, "numpy")
    m, arrays = load_package(package)
    with np.load(golden / "tensors.npz", allow_pickle=False) as z:
        t = {k:z[k] for k in z.files}
    expected = dict(input=(t["input"],8), weight=(arrays["stem.weight"],8),
                    bias=(arrays["stem.bias"],32), multiplier=(arrays["stem.multiplier"],32),
                    shift=(arrays["stem.shift"],32), acc_expected=(t["stem.acc"],32),
                    output_expected=(t["stem"],8))
    manifest=json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    if manifest["package"] != m["semantic_sha256"] or set(manifest["vectors"]) != set(expected):
        raise ValueError("Stem vector/package identity or role mismatch")
    for role,(a,bits) in expected.items():
        d=manifest["vectors"][role]
        if d["file"] != role+".hex" or d["bits"]!=bits or d["shape"]!=list(a.shape) or d["count"]!=a.size or d["order"]!="C":
            raise ValueError(f"Stem vector layout mismatch: {role}")
        path=root/d["file"]
        if hashlib.sha256(path.read_bytes()).hexdigest()!=d["sha256"]:
            raise ValueError(f"Stem vector hash mismatch: {role}")
        words=path.read_text(encoding="ascii").splitlines()
        if len(words)!=a.size or any(re.fullmatch(r"[0-9a-fA-F]{"+str(bits//4)+"}",w) is None for w in words):
            raise ValueError(f"Stem hex width/count mismatch: {role}")
        values=np.array([int(w,16) - ((1<<bits) if int(w,16)&(1<<(bits-1)) else 0) for w in words],dtype=np.int64)
        if not np.array_equal(values,a.reshape(-1)):
            raise ValueError(f"Stem hex semantic mismatch: {role}")
    return dict(status="PASS", package=m["semantic_sha256"], vectors={k:v[0].size for k,v in expected.items()},
                source="real checkpoint + CIFAR-10 test sample 0", rtl_ran=False)


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--vectors",default="reference/e2b_v1/stem_vectors")
    p.add_argument("--package",default="reference/e2b_v1")
    a=p.parse_args()
    print(json.dumps(verify(a.vectors,a.package),indent=2))


if __name__=="__main__": main()
