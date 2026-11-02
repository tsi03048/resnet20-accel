"""Require computed interstage transfers, all boundaries and changed-frame CSV."""
import csv
import hashlib
import json
from pathlib import Path
import re

from tools.chain_vectors import expected


def summarize(directory="results/stem_residual_rtl"):
    root=Path(directory);v=json.loads((root/"vector_validation.json").read_text())
    if v["status"]!="PASS": raise ValueError("chain vector validation absent")
    cases=[];actual=0;synthetic=0
    for mode,expected_cases in ((0,[0,1,0]),(1,[0]),(2,[0]),(5,[0])):
        log=(root/f"mode{mode}.log").read_text()
        jobs=re.findall(r"JOB_PASS mode=(\d+) job=(\d+) case=(\d+) bridges=16384 h=16384 m=16384 y=16384 stem_macs=442368 block_macs=4718592 mismatches=0",log)
        end=re.search(r"CASE_PASS mode=(\d+) jobs=(\d+) cancelled=(\d+) bridge_stalls=(\d+) conv_stalls=(\d+) y_stalls=(\d+) rsp_stalls=(\d+) stem_mac_stalls=(\d+) block_mac_stalls=(\d+) lifetime_checks=(\d+)",log)
        if len(jobs)!=len(expected_cases) or end is None or int(end[1])!=mode or int(end[2])!=len(jobs) or int(end[10])!=len(jobs)*49152:
            raise ValueError(f"incomplete chain case {mode}")
        if any(int(j[0])!=mode or int(j[1])!=i or int(j[2])!=c for i,(j,c) in enumerate(zip(jobs,expected_cases))): raise ValueError("chain frame order mismatch")
        if mode==1 and (min(map(int,end.group(4,5,6,7,8,9)))<=0 or "BUSY_COMMAND_PASS" not in log): raise ValueError("chain stalls not exercised")
        if mode==2 and (int(end[3])!=3 or any(f"CANCELLED point={p} " not in log for p in range(3))): raise ValueError("chain reset coverage absent")
        if mode==5 and "LOADER_NEGATIVE_PASS rejected=8 host_block_x_rejected=1" not in log: raise ValueError("host Block-X route not rejected")
        if log.count("host_block_x_writes=0 block_input_count=0 constants_ready=1")<len(jobs): raise ValueError("Block X was not empty before execution")
        cases.append(dict(mode=mode,case_ids=expected_cases,cancelled=int(end[3]),bridge_stalls=int(end[4]),conv_stalls=int(end[5]),output_stalls=int(end[6]),response_stalls=int(end[7]),stem_mac_stalls=int(end[8]),block_mac_stalls=int(end[9])))
        actual+=expected_cases.count(0);synthetic+=expected_cases.count(1)
    markers={6:"BRIDGE_CODE_MISMATCH",7:"M_CODE_MISMATCH",8:"Y_CODE_MISMATCH",9:"ADD_WIDE_MISMATCH"}
    for mode,marker in markers.items():
        if marker not in (root/f"mode{mode}.log").read_text(): raise ValueError("negative Golden not rejected")
    for mode,source in ((10,1),(11,2)):
        log=(root/f"mode{mode}.log").read_text()
        if f"FAULT_PASS source={source} outputs=0 response=0" not in log or "FAULT_CLEAR_PASS prepared=1 compute_rerun=0" not in log: raise ValueError("fault propagation/clear coverage absent")
    if "TRACE_WINDOW_ONLY cycles=500 completed_jobs=0" not in (root/"trace.log").read_text(): raise ValueError("short trace absent")
    _,oracle=expected()
    keys={0:("stem_acc","stem"),1:("acc1","h"),2:("acc2","m"),3:("add_wide","y")}
    rows=0
    with (root/"normal_boundaries.csv").open() as f:
        for row in csv.DictReader(f):
            job=rows//65536;stage=(rows%65536)//16384;addr=rows%16384;cid=[0,1,0][job] if job<3 else -1
            if int(row["job"])!=job or int(row["case"])!=cid or int(row["stage"])!=stage or int(row["address"])!=addr: raise ValueError("CSV frame/stage/order mismatch")
            values=oracle["actual0" if cid==0 else "synthetic_zero"]
            a,b=keys[stage]
            if int(row["acc" if stage<3 else "wide"])!=int(values[a][0].reshape(-1)[addr]) or int(row["code"])!=int(values[b][0].reshape(-1)[addr]): raise ValueError(f"CSV numeric mismatch row {rows}")
            if stage==3 and (int(row["main"])!=int(values["m"][0].reshape(-1)[addr]) or int(row["skip"])!=int(values["stem"][0].reshape(-1)[addr])): raise ValueError("CSV shortcut mismatch")
            rows+=1
    if rows!=196608: raise ValueError("incomplete CSV")
    total=actual+synthetic
    source={}
    for folder in ("rtl/stem_e2b_v1","rtl/residual_e2b_v1","rtl/stem_residual_e2b_v1","tb/stem_residual_e2b_v1"):
        for p in Path(folder).glob("*"):
            if p.is_file():source[p.as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
    result=dict(status="PASS",path=["Stem","L1.0 Conv1","L1.0 Conv2","L1.0 Add"],package_semantic_sha256=v["package"],
        completed_jobs=total,actual_sample0_jobs=actual,synthetic_zero_jobs=synthetic,different_real_images=1,
        bridge_words_compared=total*16384,conv_acc_compared=total*49152,stem_h_m_y_codes_compared=total*65536,add_wide_compared=total*16384,mismatches=0,
        actual_only_counts=dict(bridge=actual*16384,conv_acc=actual*49152,codes=actual*65536,add_wide=actual*16384),
        macs_per_chain=5160960,cases=cases,normal_csv_rows_vs_reference=rows,buffer_lifetime_checks=total*49152,
        host_block_x_writes=0,host_block_x_load_rejected=True,negative_goldens_rejected=list(markers.values()),
        stem_and_block_faults_propagated=True,fault_clear_to_prepared=True,fault_compute_rerun_tested=False,
        changed_frame_elements=v["changed_elements"],source_sha256=source,simulator=(root/"toolchain.txt").read_text().strip(),
        trace="separate 500-cycle window near first interstage transfers; not a complete job",
        scope="same-clock direct RTL Stem -> first Identity block; one real sample plus synthetic zero; not Transition/full-model RTL, AXI/DMA, synthesis/timing or board")
    (root/"summary.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8",newline="\n")
    return result


if __name__=="__main__": print(json.dumps(summarize(),indent=2))
