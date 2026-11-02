"""Actual L2.0/L3.0 constants, Golden and independent Option A addresses."""
import argparse
import hashlib
import json
from pathlib import Path
import re

import numpy as np
from quant.e2b_reference import load_package,rne_numpy
from quant.replay_e2b import replay

ROOT="reference/e2b_v1/transition_vectors"


def option_a_direct(x):
    """Destination-to-source scalar addressing, independent of pad/slicing."""
    _,cin,height,width=x.shape
    cout,oh,ow=2*cin,height//2,width//2
    skip=np.zeros((1,cout,oh,ow),dtype=np.int64)
    addresses=np.full(skip.shape,-1,dtype=np.int64)
    for co in range(cout):
        for oy in range(oh):
            for ox in range(ow):
                if cin//2<=co<cin//2+cin:
                    ci=co-cin//2;iy=2*oy;ix=2*ox
                    skip[0,co,oy,ox]=int(x[0,ci,iy,ix])
                    addresses[0,co,oy,ox]=(ci*height+iy)*width+ix
    return skip,addresses


def expected():
    replay(backend="numpy")
    m,a=load_package("reference/e2b_v1")
    with np.load("reference/e2b_v1/sample0/tensors.npz",allow_pickle=False) as z:
        t={k:z[k].astype(np.int64) for k in z.files}
    cases={};facts={}
    for stage in (2,3):
        prefix=f"L{stage}.0";ops=[o for o in m["operations"] if o["name"].startswith(prefix+".")]
        c1,c2,add=ops
        assert c1["stride"]==2 and c2["stride"]==1 and add["shortcut"]=="option_a"
        x=t[c1["inputs"][0]];main=t[c2["name"]];y=t[add["name"]]
        skip,addr=option_a_direct(x)
        if not np.array_equal(skip,t[add["name"]+".skip"]): raise ValueError("Option A scalar addresses disagree with frozen Golden")
        wide=main*add["multiplier_main"]+skip*add["multiplier_skip"]
        values=dict(input=(x,8),acc1_expected=(t[c1["name"]+".acc"],32),h_expected=(t[c1["name"]],8),
            acc2_expected=(t[c2["name"]+".acc"],32),m_expected=(main,8),skip_expected=(skip,8),
            skip_addr_expected=(addr,32),add_wide_expected=(wide,64),output_expected=(y,8),
            add_config=(np.array([add["multiplier_main"],add["multiplier_skip"],add["shift"]],dtype=np.int64),32))
        for i,op in enumerate((c1,c2),1):
            for role in ("weight","bias","multiplier","shift"):values[f"{role}{i}"]=(a[op[role]],8 if role=="weight" else 32)
        wrong_skip=np.pad(x[:,:,1::2,1::2],((0,0),(x.shape[1]//2,x.shape[1]//2),(0,0),(0,0)))
        wrong_y=np.clip(rne_numpy(main*add["multiplier_main"]+wrong_skip*add["multiplier_skip"],add["shift"]),0,127)
        cases[str(stage)]=values
        facts[str(stage)]=dict(input_shape=list(x.shape),output_shape=list(y.shape),
            skip_read_count=int((addr>=0).sum()),zero_skip_count=int((addr<0).sum()),negative_main=int((main<0).sum()),
            zero_skip_but_positive_y=int(((addr<0)&(y>0)).sum()),wrong_odd_coordinate_y_changes=int((wrong_y!=y).sum()))
    return m,cases,facts


def export(directory=ROOT):
    m,cases,facts=expected();root=Path(directory);root.mkdir(parents=True,exist_ok=True)
    records={};payloads={}
    for stage,values in cases.items():
        records[stage]={}
        for role,(a,bits) in values.items():
            file=f"stage{stage}/{role}.hex"
            raw="".join(f"{int(v)&((1<<bits)-1):0{bits//4}x}\n" for v in a.reshape(-1)).encode("ascii")
            payloads[file]=raw
            records[stage][role]=dict(file=file,bits=bits,shape=list(a.shape),count=int(a.size),order="C",sha256=hashlib.sha256(raw).hexdigest())
    manifest=dict(package=m["semantic_sha256"],blocks=["L2.0","L3.0"],source="actual CIFAR-10 test sample 0; frozen upstream outputs; not a full RTL chain",
                  vectors=records,geometry=facts,encoding="ASCII LF two's complement, NCHW/OIHW, one word per line; -1 means no skip read")
    mp=root/"manifest.json"
    if mp.exists() and json.loads(mp.read_text())!=manifest: raise ValueError("Frozen Transition manifest differs")
    for file,raw in payloads.items():
        p=root/file;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
    mp.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8",newline="\n")
    return manifest


def verify(directory=ROOT):
    m,cases,facts=expected();root=Path(directory);manifest=json.loads((root/"manifest.json").read_text())
    if manifest["package"]!=m["semantic_sha256"] or manifest["blocks"]!=["L2.0","L3.0"] or set(manifest["vectors"])!=set(cases): raise ValueError("Transition package/block mismatch")
    if manifest["geometry"]!=facts: raise ValueError("Transition geometry facts mismatch")
    for stage,values in cases.items():
        if set(manifest["vectors"][stage])!=set(values): raise ValueError("Transition vector role mismatch")
        for role,(a,bits) in values.items():
            d=manifest["vectors"][stage][role]
            if d["file"]!=f"stage{stage}/{role}.hex" or d["bits"]!=bits or d["shape"]!=list(a.shape) or d["count"]!=a.size or d["order"]!="C": raise ValueError("Transition vector layout mismatch")
            raw=(root/d["file"]).read_bytes()
            if hashlib.sha256(raw).hexdigest()!=d["sha256"] or b"\r" in raw or not raw.endswith(b"\n"): raise ValueError("Transition hash/encoding mismatch")
            words=raw.decode("ascii").splitlines()
            if len(words)!=a.size or any(re.fullmatch(r"[0-9a-f]{"+str(bits//4)+"}",w) is None for w in words): raise ValueError("Transition word width/count mismatch")
            decoded=np.array([int(w,16)-((1<<bits) if int(w,16)&(1<<(bits-1)) else 0) for w in words],dtype=np.int64)
            if not np.array_equal(decoded,a.reshape(-1)): raise ValueError(f"Transition semantic mismatch: stage{stage}/{role}")
    return dict(status="PASS",package=m["semantic_sha256"],blocks=manifest["blocks"],different_real_images=1,geometry=facts)


if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--export",action="store_true");args=p.parse_args()
    print(json.dumps(export() if args.export else verify(),indent=2))
