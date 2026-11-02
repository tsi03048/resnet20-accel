"""Require complete simulator evidence and recheck normal CSV vs frozen NPZ."""
import csv
import hashlib
import json
from pathlib import Path
import re

import numpy as np
from tools.residual_vectors import expected


def summarize(directory="results/residual_rtl"):
    root=Path(directory)
    validation=json.loads((root/"vector_validation.json").read_text())
    if validation["status"]!="PASS": raise ValueError("vector validation absent")
    if "RNE_PASS vectors=2000" not in (root/"rne.log").read_text(): raise ValueError("RNE oracle not passed")
    total=0;cases=[]
    for mode,count in ((0,2),(1,1),(2,1),(5,1)):
        log=(root/f"mode{mode}.log").read_text()
        jobs=re.findall(r"JOB_PASS mode=(\d+) job=(\d+) h=16384 m=16384 y=16384 mac1=2359296 mac2=2359296 mismatches=0 negative_main=(\d+)",log)
        end=re.search(r"CASE_PASS mode=(\d+) jobs=(\d+) cancelled=(\d+) mac_stalls=(\d+) conv_stalls=(\d+) y_stalls=(\d+) rsp_stalls=(\d+) lifetime_checks=(\d+)",log)
        if len(jobs)!=count or end is None or int(end[1])!=mode or int(end[2])!=count or int(end[8])!=count*3*16384:
            raise ValueError(f"incomplete case {mode}")
        for i,j in enumerate(jobs):
            if int(j[0])!=mode or int(j[1])!=i or int(j[2])!=validation["teaching_checks"]["negative_main"]: raise ValueError("job identity/negative Main count mismatch")
        if mode==1 and (min(map(int,end.group(4,5,6,7)))<=0 or "BUSY_COMMAND_PASS" not in log): raise ValueError("stall/busy coverage absent")
        if mode==2 and (int(end[3])!=3 or any(f"CANCELLED point={p} " not in log for p in range(3))): raise ValueError("reset coverage absent")
        if mode==5 and "LOADER_NEGATIVE_PASS rejected=14" not in log: raise ValueError("loader rejection absent")
        cases.append(dict(mode=mode,jobs=count,cancelled=int(end[3]),mac_stalls=int(end[4]),conv_stalls=int(end[5]),output_stalls=int(end[6]),response_stalls=int(end[7])))
        total+=count
    markers={6:"ACC1_MISMATCH",7:"M_MISMATCH",8:"Y_MISMATCH",9:"ADD_WIDE_MISMATCH",10:"OVERFLOW_PASS rejected=1 outputs=0 response=0"}
    for mode,marker in markers.items():
        if marker not in (root/f"mode{mode}.log").read_text(): raise ValueError(f"negative evidence absent: {mode}")
    _,v,_=expected()
    keys={0:("acc1_expected","h_expected"),1:("acc2_expected","m_expected"),2:("add_wide_expected","output_expected")}
    rows=0
    with (root/"normal_boundaries.csv").open() as f:
        for row in csv.DictReader(f):
            job=rows//49152; stage=(rows%49152)//16384; addr=rows%16384
            if int(row["job"])!=job or int(row["stage"])!=stage or int(row["address"])!=addr: raise ValueError(f"CSV order mismatch row {rows}")
            a,b=keys[stage]
            if int(row["acc" if stage<2 else "wide"])!=int(v[a][0].reshape(-1)[addr]) or int(row["code"])!=int(v[b][0].reshape(-1)[addr]): raise ValueError(f"CSV numerical mismatch row {rows}")
            if stage==2 and (int(row["main"])!=int(v["m_expected"][0].reshape(-1)[addr]) or int(row["skip"])!=int(v["input"][0].reshape(-1)[addr])): raise ValueError("CSV Add pairing mismatch")
            rows+=1
    if rows!=98304: raise ValueError("CSV incomplete")
    source={p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for folder in ("rtl/residual_e2b_v1","tb/residual_e2b_v1") for p in Path(folder).glob("*") if p.is_file()}
    result=dict(status="PASS",block="ResNet-20 L1.0 Identity",package_semantic_sha256=validation["package"],different_real_images=1,
                shape=[1,16,32,32],completed_jobs=total,conv_acc_compared=total*32768,h_m_y_codes_compared=total*49152,
                add_wide_compared=total*16384,mismatches=0,macs_per_job=4718592,cases=cases,
                buffer_lifetime_elements_checked=total*49152,normal_csv_rows_vs_npz=rows,postproc_oracle_vectors=2000,
                negative_goldens_rejected=list(markers.values())[:4],loader_invalid_words_rejected=14,overflow_rejected=True,
                teaching_checks=validation["teaching_checks"],source_sha256=source,
                simulator=(root/"toolchain.txt").read_text().strip(),trace="first 500 cycles only; full jobs verified by scoreboard/CSV",
                scope="one actual Identity block, frozen sample 0; not chained Stem+Block, Transition/full-model RTL, synthesis/timing or board")
    (root/"summary.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8",newline="\n")
    return result


if __name__=="__main__": print(json.dumps(summarize(),indent=2))
