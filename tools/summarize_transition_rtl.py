"""Require both real Transition shapes, scalar geometry and every boundary."""
import csv
import hashlib
import json
from pathlib import Path
import re

from tools.transition_vectors import expected


def summarize(directory="results/transition_rtl"):
    root=Path(directory);validation=json.loads((root/"vector_validation.json").read_text())
    if validation["status"]!="PASS": raise ValueError("Transition vectors not verified")
    _,oracle,_=expected();reports=[];total_outputs=0;csv_rows=0
    for stage,ny,nx in ((2,8192,16384),(3,4096,8192)):
        folder=root/f"stage{stage}";facts=validation["geometry"][str(stage)];cases=[];completed=0
        read_counts=(1131008,2166784) if stage==2 else (1083392,1982464)
        for mode,count in ((0,2),(1,1),(2,1),(5,1)):
            log=(folder/f"mode{mode}.log").read_text()
            jobs=re.findall(r"JOB_PASS stage=(\d+) mode=(\d+) job=(\d+) outputs=(\d+) mac1=(\d+) mac2=(\d+) read1=(\d+) read2=(\d+) skip_reads=(\d+) zero_tokens=(\d+) positive_zero_y=(\d+) negative_main=(\d+) mismatches=0",log)
            end=re.search(r"CASE_PASS stage=(\d+) mode=(\d+) jobs=(\d+) cancelled=(\d+) mac_stalls=(\d+) conv_stalls=(\d+) y_stalls=(\d+) rsp_stalls=(\d+) lifetime_checks=(\d+)",log)
            if len(jobs)!=count or end is None or tuple(map(int,end.group(1,2,3)))!=(stage,mode,count) or int(end[9])!=count*(nx+2*ny): raise ValueError(f"incomplete stage {stage} mode {mode}")
            for i,j in enumerate(jobs):
                wanted=(stage,mode,i,ny,1179648,2359296,*read_counts,ny//2,ny//2,facts["zero_skip_but_positive_y"],facts["negative_main"])
                if tuple(map(int,j))!=wanted: raise ValueError(f"Transition geometry/job counts differ: {j}")
            if mode==1 and (min(map(int,end.group(5,6,7,8)))<=0 or "BUSY_COMMAND_PASS" not in log): raise ValueError("Transition stall coverage absent")
            if mode==2 and (int(end[4])!=4 or any(f"CANCELLED point={p} " not in log for p in range(4))): raise ValueError("Transition reset coverage absent")
            if mode==5 and "LOADER_NEGATIVE_PASS rejected=14" not in log: raise ValueError("Transition loader negative absent")
            if stage==3 and "HIGH_WEIGHT_ADDRESS_PASS addr=36863" not in log: raise ValueError("Stage3 high address unverified")
            cases.append(dict(mode=mode,jobs=count,cancelled=int(end[4]),mac_stalls=int(end[5]),conv_stalls=int(end[6]),output_stalls=int(end[7]),response_stalls=int(end[8])))
            completed+=count
        markers={6:"ACC1_MISMATCH",7:"M_MISMATCH",8:"SKIP_PAIR_MISMATCH",9:"Y_MISMATCH",10:"ADD_WIDE_MISMATCH",12:"SKIP_PAIR_MISMATCH",13:"OPTION_A_READ_ADDRESS"}
        for mode,marker in markers.items():
            if marker not in (folder/f"mode{mode}.log").read_text(): raise ValueError(f"missing Transition negative {mode}")
        if "OVERFLOW_PASS rejected=1 outputs=0 response=0" not in (folder/"mode11.log").read_text(): raise ValueError("Transition overflow not checked")
        for kind in (1,2):
            if f"TRACE_WINDOW_ONLY kind={kind} cycles=500 completed_jobs=0" not in (folder/f"trace{kind}.log").read_text(): raise ValueError("Transition short trace absent")
        rows=0;v=oracle[str(stage)]
        keys={0:("acc1_expected","h_expected"),1:("acc2_expected","m_expected"),2:("add_wide_expected","output_expected")}
        with (folder/"normal_boundaries.csv").open() as f:
            for row in csv.DictReader(f):
                job=rows//(3*ny);phase=(rows%(3*ny))//ny;addr=rows%ny
                if int(row["job"])!=job or int(row["stage"])!=phase or int(row["address"])!=addr: raise ValueError("Transition CSV order mismatch")
                a,b=keys[phase]
                if int(row["acc" if phase<2 else "wide"])!=int(v[a][0].reshape(-1)[addr]) or int(row["code"])!=int(v[b][0].reshape(-1)[addr]): raise ValueError("Transition CSV numerical mismatch")
                if phase==2 and (int(row["main"])!=int(v["m_expected"][0].reshape(-1)[addr]) or int(row["skip"])!=int(v["skip_expected"][0].reshape(-1)[addr])): raise ValueError("Transition CSV Skip mismatch")
                rows+=1
        if rows!=6*ny: raise ValueError("Transition CSV incomplete")
        reports.append(dict(stage=stage,block=f"L{stage}.0",completed_jobs=completed,input_shape=facts["input_shape"],output_shape=facts["output_shape"],
            acc_compared=2*ny*completed,h_m_y_codes_compared=3*ny*completed,skip_codes_compared=ny*completed,add_wide_compared=ny*completed,
            option_a_reads=ny//2*completed,zero_tokens=ny//2*completed,cases=cases,normal_csv_rows=rows,teaching_checks=facts))
        total_outputs+=ny*completed;csv_rows+=rows
    source={}
    for folder in ("rtl/transition_e2b_v1","tb/transition_e2b_v1"):
        for p in Path(folder).glob("*"):
            if p.is_file():source[p.as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
    p=Path("rtl/residual_e2b_v1/rne_clip.sv");source[p.as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
    result=dict(status="PASS",package_semantic_sha256=validation["package"],different_real_images=1,completed_jobs=10,
        blocks=reports,conv_acc_compared=2*total_outputs,h_m_y_codes_compared=3*total_outputs,skip_codes_compared=total_outputs,add_wide_compared=total_outputs,
        mismatches=0,normal_csv_rows_vs_npz=csv_rows,macs_per_job=3538944,completed_job_macs=35389440,
        reset_cancellations=8,loader_invalid_words_rejected=28,expected_mismatch_tests=14,overflow_tests=2,
        source_sha256=source,simulator=(root/"toolchain.txt").read_text().strip(),
        trace="two separate 500-cycle runs per stage: first Conv and Option A boundary; not complete jobs",
        scope="actual L2.0 and L3.0 Transition unit RTL with frozen upstream sample0 inputs; not a full-model chain, synthesis/timing or board")
    (root/"summary.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8",newline="\n")
    return result


if __name__=="__main__":print(json.dumps(summarize(),indent=2))
