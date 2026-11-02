"""Predict the MAC-loop cycle saving from graph sizes, then verify against RTL.

Baseline is a measured public R202 run. Postprocessing and other control states
are retained. This model is a cycle-count expectation, not a board FPS claim.
"""
import json,re
from pathlib import Path

def predict():
    graph=json.loads(Path('reference/e2b_v1/full_vectors/manifest.json').read_text())['operations']
    baseline=list(map(int,re.findall(r'S2MM_PASS job=\d+ words=16 bytes=64 tag=[0-9a-f]+ elapsed=(\d+)',Path('results/ps_dma_packed_execution.log').read_text())))[:3]
    assert len(baseline)==3 and len(set(baseline))==1
    rows=[]
    for row in graph:
        if row['kind']==1:continue
        k=row['ci']*9 if row['kind']==0 else (row['ih']**2 if row['kind']==2 else row['ci'])
        outputs=row['nout'];saving=outputs*(6*k-(k+4))
        rows.append(dict(id=row['id'],name=row['name'],outputs=outputs,terms=k,old_loop_cycles_per_output=6*k,new_loop_cycles_per_output=k+4,saved_cycles=saving))
    saved=sum(r['saved_cycles'] for r in rows);expected=baseline[0]-saved
    return dict(baseline_measured_cycles=baseline[0],predicted_pipeline_cycles=expected,saved_cycles=saved,
        mac_and_gap_terms=sum(r['terms']*r['outputs'] for r in rows),pipelined_outputs=sum(r['outputs'] for r in rows),
        predicted_cycle_reduction_percent=saved/baseline[0]*100,predicted_cycle_ratio=baseline[0]/expected,operations=rows,
        assumptions='Same graph, ordered INT32 accumulation and unchanged coefficient/RNE/Add/trace control; unstalled normal runs only; no physical board measurement.')
if __name__=='__main__':print(json.dumps(predict(),indent=2))
