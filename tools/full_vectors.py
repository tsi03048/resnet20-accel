"""Fixed 30-op integer graph, actual test samples 0/1, and full trace oracle.

Only inputs/constants enter the DUT. Golden layout belongs to the testbench.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

import numpy as np
from quant.e2b_reference import IntegerReference,load_package,array_hash
from quant.replay_e2b import replay

ROOT="reference/e2b_v1/full_vectors"
ROM="rtl/full_e2b_v1/full_graph.svh"


def plan(m,a):
    slots={"input":0};shapes={"input":[3,32,32]};offsets={};rows=[];weights=[];bias=[];ns=[];shifts=[];offset=0;wb=0;pb=0;block_x=0
    for op in m["operations"]:
        name=op["name"];kind=op["op"];source=op["inputs"][0];shape=shapes[source]
        if name=="stem":dest=1
        elif name.endswith(".conv1"):block_x=slots[source];dest=(block_x+1)%3
        elif name.endswith(".conv2"):dest=(block_x+2)%3
        elif kind=="add_relu":dest=(block_x+1)%3
        elif kind=="gap":dest=(slots[source]+1)%3
        else:dest=3
        row=dict(id=op["id"],name=name,kind={"conv":0,"add_relu":1,"gap":2,"fc":3}[kind],ci=shape[0],ih=shape[1] if len(shape)>1 else 1,
                 co=op["output_shape"][0],oh=op["output_shape"][1] if len(op["output_shape"])>1 else 1,
                 stride=op.get("stride",1),relu=int(op.get("relu",kind in ("add_relu","gap"))),src=slots[source],dst=dest,skip=0,option_a=0,
                 wbase=wb,pbase=pb,main_n=0,skip_n=0,r=0,nout=int(np.prod(op["output_shape"])),source=source,
                 source_offset=offsets.get(source,-1),source_len=int(np.prod(shape)),skip_offset=-1,skip_len=0,trace_offset=offset)
        if kind in ("conv","fc"):
            weights.append(a[op["weight"]].reshape(-1));bias.append(a[op["bias"]]);ns.append(a[op["multiplier"]]);shifts.append(a[op["shift"]])
            wb+=a[op["weight"]].size;pb+=a[op["bias"]].size
        elif kind=="add_relu":
            skip=op["inputs"][1];ss=shapes[skip]
            row.update(ci=ss[0],ih=ss[1],skip=slots[skip],option_a=int(op["shortcut"]=="option_a"),main_n=op["multiplier_main"],skip_n=op["multiplier_skip"],r=op["shift"],skip_offset=offsets[skip],skip_len=int(np.prod(ss)))
        elif kind=="gap":row.update(main_n=op["multiplier"],r=op["shift"])
        rows.append(row);slots[name]=dest;shapes[name]=op["output_shape"];offsets[name]=offset;offset+=row["nout"]
    constants=dict(weight=(np.concatenate(weights),8),bias=(np.concatenate(bias),32),multiplier=(np.concatenate(ns),32),shift=(np.concatenate(shifts),32))
    assert wb==268336 and pb==698 and offset==274506
    return rows,constants


def graph_text(rows):
    fields=["kind","ci","ih","co","oh","stride","relu","src","dst","skip","option_a","wbase","pbase","main_n","skip_n","r"]
    lines=["// Generated from the frozen E2-B graph. Contains no Golden values.","always_comb begin"]
    lines += [f"    d_{k}=0;" for k in fields]
    lines += ["    case(op_id)"]
    for row in rows:
        lines.append(f"        5'd{row['id']}: begin // {row['name']}")
        lines += [f"            d_{k}={row[k]};" for k in fields]
        lines.append("        end")
    lines += ["        default:begin end","    endcase","end",""]
    return "\n".join(lines)


def expected(backend="numpy"):
    replay(backend=backend);m,a=load_package("reference/e2b_v1");rows,constants=plan(m,a)
    with np.load("reference/e2b_v1/sample0/tensors.npz",allow_pickle=False) as z:t0={k:z[k].astype(np.int64) for k in z.files}
    root=Path(ROOT);meta=json.loads((root/"sample1_source.json").read_text());raw=(root/"sample1_input.hex").read_bytes()
    if hashlib.sha256(raw).hexdigest()!=meta["input_sha256"] or meta["package"]!=m["semantic_sha256"] or meta["preprocessing"]!=m["preprocessing"] or meta["input_scale"]!=m["input_scale"]: raise ValueError("sample1 input provenance mismatch")
    words=raw.decode("ascii").splitlines()
    if len(words)!=3072 or any(re.fullmatch("[0-9a-f]{2}",w) is None for w in words): raise ValueError("sample1 word layout")
    q=np.array([int(w,16)-(256 if int(w,16)>=128 else 0) for w in words],dtype=np.int8).reshape(1,3,32,32)
    if array_hash(q)!=meta["input_array_sha256"]:raise ValueError("sample1 input array hash mismatch")
    _,t1=IntegerReference(m,a,backend).forward(q,capture=True)
    cases={};case_meta={}
    for cid,t in ((0,t0),(1,t1)):
        t={k:v.astype(np.int64) for k,v in t.items()};accs=[];codes=[];skips=[];wides=[];addresses=[]
        for op,row in zip(m["operations"],rows):
            n=row["nout"];kind=op["op"];name=op["name"];code=t[name].reshape(-1)
            acc=np.zeros(n,dtype=np.int64);skip=np.zeros(n,dtype=np.int64);addr=np.full(n,-1,dtype=np.int64)
            if kind in ("conv","fc"):
                acc=t[name+".acc"].reshape(-1);repeat=n//row["co"];wide=acc*np.repeat(a[op["multiplier"]].astype(np.int64),repeat)
            elif kind=="gap":acc=t["gap.sum"].reshape(-1);wide=acc*op["multiplier"]
            else:
                skip=t[name+".skip"].reshape(-1);main=t[op["inputs"][0]].reshape(-1);wide=main*op["multiplier_main"]+skip*op["multiplier_skip"]
                for i in range(n):
                    co=i//(row["oh"]**2);oy=(i%(row["oh"]**2))//row["oh"];ox=i%row["oh"]
                    if not row["option_a"]:addr[i]=i
                    elif row["ci"]//2<=co<row["ci"]//2+row["ci"]:addr[i]=((co-row["ci"]//2)*row["ih"]+2*oy)*row["ih"]+2*ox
                src=t[op["inputs"][1]].reshape(-1)
                direct=np.array([0 if i<0 else src[i] for i in addr],dtype=np.int64)
                if not np.array_equal(direct,skip):raise ValueError("full Option A source mapping mismatch")
            accs.append(acc);codes.append(code);skips.append(skip);wides.append(wide);addresses.append(addr)
        cases[str(cid)]={"input":(t["input"],8),"acc":(np.concatenate(accs),32),"code":(np.concatenate(codes),32),"skip":(np.concatenate(skips),8),"wide":(np.concatenate(wides),64),"skip_addr":(np.concatenate(addresses),32)}
        case_meta[str(cid)]=dict(test_index=cid,prediction=int(t["fc"].argmax()),scores=t["fc"].reshape(-1).tolist(),tensor_count=len(t),boundary_elements=sum(v.size for v in t.values()))
    return m,rows,constants,cases,case_meta


def export(directory=ROOT):
    m,rows,constants,cases,cm=expected();root=Path(directory);root.mkdir(parents=True,exist_ok=True)
    rom=graph_text(rows);rp=Path(ROM);rp.parent.mkdir(parents=True,exist_ok=True)
    if rp.exists() and rp.read_text()!=rom:raise ValueError("Frozen RTL graph differs")
    rp.write_text(rom,encoding="ascii",newline="\n")
    values={f"constants/{k}":v for k,v in constants.items()}
    for cid,items in cases.items():values.update({f"sample{cid}/{k}":v for k,v in items.items()})
    for key in ("kind","nout","src","dst","skip","source_offset","source_len","skip_offset","skip_len","trace_offset"):
        values[f"layout/{key}"]=(np.array([r[key] for r in rows],dtype=np.int64),32)
    records={};payload={}
    for name,(a,bits) in values.items():
        raw="".join(f"{int(v)&((1<<bits)-1):0{bits//4}x}\n" for v in a.reshape(-1)).encode("ascii");payload[name+".hex"]=raw
        records[name]=dict(file=name+".hex",shape=list(a.shape),bits=bits,count=int(a.size),sha256=hashlib.sha256(raw).hexdigest())
    manifest=dict(package=m["semantic_sha256"],graph_sha256=hashlib.sha256(rom.encode()).hexdigest(),operations=rows,cases=cm,vectors=records,
        source="actual Test samples 0 and 1; fixed E2-B integer constants; no retraining/calibration",encoding="ASCII LF two's complement; NCHW/OIHW; testbench Golden is not a DUT input")
    mp=root/"manifest.json"
    if mp.exists() and json.loads(mp.read_text())!=manifest:raise ValueError("Frozen full-model manifest differs")
    for name,raw in payload.items():p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
    mp.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8",newline="\n")
    return manifest


def verify(directory=ROOT):
    m,rows,constants,cases,cm=expected();root=Path(directory);manifest=json.loads((root/"manifest.json").read_text())
    if manifest["package"]!=m["semantic_sha256"] or manifest["operations"]!=rows or manifest["cases"]!=cm:raise ValueError("full model package/graph/case mismatch")
    rom=Path(ROM).read_bytes()
    if rom!=graph_text(rows).encode() or hashlib.sha256(rom).hexdigest()!=manifest["graph_sha256"]:raise ValueError("full model RTL graph mismatch")
    wanted={f"constants/{k}":v for k,v in constants.items()}
    for cid,items in cases.items():wanted.update({f"sample{cid}/{k}":v for k,v in items.items()})
    for key in ("kind","nout","src","dst","skip","source_offset","source_len","skip_offset","skip_len","trace_offset"):wanted[f"layout/{key}"]=(np.array([r[key] for r in rows],dtype=np.int64),32)
    if set(wanted)!=set(manifest["vectors"]):raise ValueError("full vector role mismatch")
    for name,(a,bits) in wanted.items():
        d=manifest["vectors"][name]
        if d["file"]!=name+".hex" or d["shape"]!=list(a.shape) or d["bits"]!=bits or d["count"]!=a.size:raise ValueError("full vector layout mismatch")
        raw=(root/d["file"]).read_bytes()
        if hashlib.sha256(raw).hexdigest()!=d["sha256"] or b"\r" in raw or not raw.endswith(b"\n"):raise ValueError("full vector hash/encoding mismatch")
        words=raw.decode("ascii").splitlines()
        if len(words)!=a.size or any(re.fullmatch(r"[0-9a-f]{"+str(bits//4)+"}",w) is None for w in words):raise ValueError("full vector word layout mismatch")
        got=np.array([int(w,16)-((1<<bits) if int(w,16)&(1<<(bits-1)) else 0) for w in words],dtype=np.int64)
        if not np.array_equal(got,a.reshape(-1)):raise ValueError("full vector semantic mismatch: "+name)
    return dict(status="PASS",package=m["semantic_sha256"],cases=cm,operations=30,weights=268336,coefficients=698,trace_events_per_image=274506,boundaries=61,boundary_elements_per_image=552084)


if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--export",action="store_true");args=p.parse_args()
    result=export() if args.export else verify()
    if args.export:result={"status":"EXPORTED","cases":result["cases"],"graph_sha256":result["graph_sha256"]}
    print(json.dumps(result,indent=2))
