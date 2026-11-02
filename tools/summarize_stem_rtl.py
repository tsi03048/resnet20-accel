"""Parse simulator evidence and independently check every normal-job dump word."""
import csv
import hashlib
import json
from pathlib import Path
import re

import numpy as np


def summarize(root="results/stem_rtl"):
    root=Path(root)
    vectors=json.loads((root/"vector_validation.json").read_text())
    if vectors["status"]!="PASS": raise ValueError("vector validation failed")
    if "RNE_PASS vectors=1280" not in (root/"rne.log").read_text(): raise ValueError("RNE unit not passed")
    cases=[]; total_jobs=0
    for mode,expected_jobs in ((0,2),(1,1),(2,1),(5,1)):
        log=(root/f"mode{mode}.log").read_text()
        jobs=re.findall(r"JOB_PASS mode=(\d+) job=(\d+) outputs=(\d+) macs=(\d+) acc_mismatches=0 output_mismatches=0",log)
        end=re.search(r"CASE_PASS mode=(\d+) jobs=(\d+) mac_stalls=(\d+) output_stalls=(\d+)",log)
        if len(jobs)!=expected_jobs or end is None or int(end[1])!=mode or int(end[2])!=expected_jobs:
            raise ValueError(f"incomplete simulation case {mode}")
        if any(int(j[0])!=mode or int(j[1])!=i or int(j[2])!=16384 or int(j[3])!=442368 for i,j in enumerate(jobs)):
            raise ValueError(f"simulation counts case {mode}")
        if mode==1 and (int(end[3])==0 or int(end[4])==0 or "BUSY_COMMAND_PASS" not in log):
            raise ValueError("stall/busy tests not exercised")
        if mode==2 and "CANCELLED outputs=" not in log: raise ValueError("reset cancellation absent")
        if mode==5 and "LOADER_NEGATIVE_PASS rejected=8" not in log: raise ValueError("loader rejection absent")
        cases.append(dict(mode=mode,jobs=expected_jobs,outputs_per_job=16384,macs_per_job=442368,
                          mac_stall_edges=int(end[3]),output_stall_edges=int(end[4])))
        total_jobs+=expected_jobs
    for mode,marker in ((3,"EXPECTED_OUTPUT_MISMATCH"),(4,"EXPECTED_ACC_MISMATCH"),(6,"OVERFLOW_PASS rejected=1 outputs=0 done=0")):
        if marker not in (root/f"mode{mode}.log").read_text(): raise ValueError(f"negative evidence absent {mode}")
    with np.load("reference/e2b_v1/sample0/tensors.npz",allow_pickle=False) as z:
        acc=z["stem.acc"].reshape(-1); code=z["stem"].reshape(-1)
    rows=list(csv.DictReader((root/"normal_outputs.csv").open()))
    if len(rows)!=32768: raise ValueError("normal output dump length mismatch")
    for i,row in enumerate(rows):
        addr=i%16384
        if int(row["job"])!=i//16384 or int(row["address"])!=addr or int(row["acc"])!=int(acc[addr]) or int(row["code"])!=int(code[addr]):
            raise ValueError(f"dump vs NPZ Golden mismatch row {i}")
    source={}
    for folder in ("rtl/stem_e2b_v1","tb/stem_e2b_v1"):
        for p in Path(folder).glob("*"):
            if p.is_file(): source[p.as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
    result=dict(status="PASS",package_semantic_sha256=vectors["package"],
                source="real ResNet-20 checkpoint + CIFAR-10 test sample 0",shape=dict(input=[1,3,32,32],output=[1,16,32,32]),
                completed_jobs=total_jobs,compared_accumulators=total_jobs*16384,compared_output_codes=total_jobs*16384,
                acc_mismatches=0,output_mismatches=0,cases=cases,
                normal_csv_vs_npz_compared=32768,postproc_oracle_vectors=1280,
                expected_output_mismatch_rejected=True,expected_acc_mismatch_rejected=True,
                loader_invalid_words_rejected=8,overflow_rejected=True,
                trace="first 300 runtime cycles only; complete jobs verified by scoreboard and dump",
                source_sha256=source,simulator=(root/"toolchain.txt").read_text().splitlines()[0],
                scope="actual Stem only; not Residual/full model/FPGA synthesis or board")
    (root/"summary.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    return result


if __name__=="__main__": summarize()
