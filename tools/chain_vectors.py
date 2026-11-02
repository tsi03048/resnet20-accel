"""Freeze actual sample 0 plus a different synthetic frame to expose stale X."""
import argparse
import hashlib
import json
from pathlib import Path
import re

import numpy as np
from quant.e2b_reference import IntegerReference,load_package
from quant.replay_e2b import replay
from tools.verify_stem_vectors import verify as verify_stem
from tools.residual_vectors import export as export_block,verify as verify_block

ROOT="reference/e2b_v1/chain_vectors"


def expected(backend="numpy"):
    replay(backend=backend)
    m,a=load_package("reference/e2b_v1")
    with np.load("reference/e2b_v1/sample0/tensors.npz",allow_pickle=False) as z:
        actual={k:z[k].astype(np.int64) for k in z.files}
    zero=np.zeros((1,3,32,32),dtype=np.int8)
    _,synthetic=IntegerReference(m,a,backend).forward(zero,capture=True)
    add=m["operations"][3]
    cases={}
    for name,t in (("actual0",actual),("synthetic_zero",synthetic)):
        t={k:v.astype(np.int64) for k,v in t.items()}
        cases[name]={"input":(t["input"],8),"stem_acc":(t["stem.acc"],32),"stem":(t["stem"],8),
            "acc1":(t["L1.0.conv1.acc"],32),"h":(t["L1.0.conv1"],8),"acc2":(t["L1.0.conv2.acc"],32),"m":(t["L1.0.conv2"],8),
            "add_wide":(t["L1.0.conv2"]*add["multiplier_main"]+t["stem"]*add["multiplier_skip"],64),"y":(t["L1.0.add_relu"],8)}
    return m,cases


def export(directory=ROOT):
    m,cases=expected()
    root=Path(directory);root.mkdir(parents=True,exist_ok=True)
    records={}
    payloads={}
    for name,values in cases.items():
        records[name]={}
        for role,(a,bits) in values.items():
            file=f"{name}/{role}.hex"
            raw="".join(f"{int(v)&((1<<bits)-1):0{bits//4}x}\n" for v in a.reshape(-1)).encode("ascii")
            payloads[file]=raw
            records[name][role]=dict(file=file,bits=bits,shape=list(a.shape),count=int(a.size),sha256=hashlib.sha256(raw).hexdigest())
    manifest=dict(package=m["semantic_sha256"],path=["stem","L1.0.conv1","L1.0.conv2","L1.0.add_relu"],
        cases=records,source=dict(actual0="actual CIFAR-10 Test sample 0; frozen NPZ Golden",synthetic_zero="synthetic integer zero image; same actual constants; stale-frame control, not accuracy evidence"),encoding="ASCII LF NCHW/OIHW two's complement, one word per line")
    mp=root/"manifest.json"
    if mp.exists() and json.loads(mp.read_text())!=manifest: raise ValueError("Frozen chain manifest differs")
    for file,raw in payloads.items():
        p=root/file;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
    mp.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8",newline="\n")
    return manifest


def verify(directory=ROOT):
    stem=verify_stem();export_block();block=verify_block()
    m,cases=expected();root=Path(directory);manifest=json.loads((root/"manifest.json").read_text())
    if manifest["package"]!=m["semantic_sha256"] or set(manifest["cases"])!=set(cases) or manifest["path"]!=["stem","L1.0.conv1","L1.0.conv2","L1.0.add_relu"]: raise ValueError("chain package/case/path mismatch")
    for name,values in cases.items():
        if set(manifest["cases"][name])!=set(values): raise ValueError("chain role mismatch")
        for role,(a,bits) in values.items():
            d=manifest["cases"][name][role]
            if d["file"]!=f"{name}/{role}.hex" or d["bits"]!=bits or d["shape"]!=list(a.shape) or d["count"]!=a.size: raise ValueError("chain layout mismatch")
            raw=(root/d["file"]).read_bytes()
            if hashlib.sha256(raw).hexdigest()!=d["sha256"] or b"\r" in raw or not raw.endswith(b"\n"): raise ValueError("chain hash/encoding mismatch")
            words=raw.decode("ascii").splitlines()
            if len(words)!=a.size or any(re.fullmatch(r"[0-9a-f]{"+str(bits//4)+"}",w) is None for w in words): raise ValueError("chain width/count mismatch")
            decoded=np.array([int(w,16)-((1<<bits) if int(w,16)&(1<<(bits-1)) else 0) for w in words],dtype=np.int64)
            if not np.array_equal(decoded,a.reshape(-1)): raise ValueError(f"chain semantic mismatch: {name}/{role}")
    if not np.array_equal(cases["actual0"]["stem"][0].reshape(-1),np.array([int(w,16) for w in Path("reference/e2b_v1/residual_l10_vectors/input.hex").read_text().splitlines()])):
        raise ValueError("Stem/Block Golden boundary mismatch")
    changes={k:int(np.count_nonzero(cases["actual0"][k][0]!=cases["synthetic_zero"][k][0])) for k in ("input","stem","h","m","y")}
    if min(changes.values())==0: raise ValueError("synthetic frame does not expose stale data")
    return dict(status="PASS",package=m["semantic_sha256"],cases=list(cases),different_real_images=1,synthetic_frames=1,changed_elements=changes,stem_verified=stem["status"],block_verified=block["status"])


if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--export",action="store_true");args=p.parse_args()
    print(json.dumps(export() if args.export else verify(),indent=2))
