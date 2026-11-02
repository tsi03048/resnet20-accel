"""Reject incomplete logs and recompare the full RTL CSV to integer Golden."""
import csv
import hashlib
import json
from pathlib import Path
import re
import numpy as np
from tools.full_vectors import expected

def summarize(directory='results/ps_dma_packed_rtl'):
    root=Path(directory);m,rows,_,cases,cm=expected()
    jobs=[]
    pattern=r'JOB_PASS job=(\d+) sample=(\d+) boundaries=(\d+) elements=(\d+) events=(\d+) macs=(\d+) gaps=(\d+) prediction=(\d+) compute_stalls=(\d+) trace_stalls=(\d+) rsp_stalls=(\d+)'
    for mode,wanted in ((0,[0,1,0]),(1,[0]),(2,[1])):
        log=(root/f'mode{mode}.log').read_text()
        assert f'CASE_PASS mode={mode} jobs={len(wanted)}' in log
        found=[list(map(int,x)) for x in re.findall(pattern,log)]
        assert [x[1] for x in found]==wanted,(mode,found)
        for x in found:
            job,cid,bounds,elements,events,macs,gaps,pred,cs,ts,rs=x
            assert (bounds,elements,events,macs,gaps,pred)==(61,552084,274506,40551040,4096,cm[str(cid)]['prediction'])
            scores=re.findall(rf'SCORE job={job} sample={cid} class=(\d+) value=(-?\d+)',log)
            assert [(int(i),int(v)) for i,v in scores]==list(enumerate(cm[str(cid)]['scores']))
            if mode==1:assert cs>0 and ts>0 and rs>0 and 'BUSY_STALE_GUARD_PASS' in log
            jobs.append(dict(mode=mode,job=job,sample=cid,boundaries=bounds,elements=elements,events=events,macs=macs,gap_steps=gaps,prediction=pred,scores=cm[str(cid)]['scores'],compute_stalls=cs,trace_stalls=ts,response_stalls=rs))
        if mode==2:
            assert re.findall(r'RESET_CANCEL location=(\d+)',log)==['0','1','2','3','4','5','6','7']
            assert 'RESET_PASS cancelled=8 recovered_sample=1' in log
    for mode,marker in ((6,'CODE_MISMATCH op=0 addr=0'),(7,'SKIP_MISMATCH op=12 addr=2048'),(8,'ACC_MISMATCH op=28 addr=0'),(9,'CODE_MISMATCH op=29 addr=0')):
        assert marker in (root/f'mode{mode}.log').read_text(),mode
    assert 'PACKED_LOADER_PASS input_bytes=3072 weight_bytes=268336 coefficients=2094 bus_words=69961 bytes=279844 bram_boundary=262144' in (root/'mode4.log').read_text()
    assert 'PROTOCOL_PASS malformed=8' in (root/'mode3.log').read_text()
    assert 'aw_w_orders=3 byte_strobes=1 response_hold=1 reset_pending=1' in (root/'mode3.log').read_text()
    assert 'OVERFLOW_PASS code=1 reset_clean=1' in (root/'mode11.log').read_text()
    assert 'MUL_PASS vectors=512 oracle=Python_integer' in (root/'mul.log').read_text()
    assert 'POST_PASS vectors=2000 oracle=Fraction' in (root/'post.log').read_text()
    assert 'ARGMAX_PASS sequences=2 scores=20 signed_extremes=1 lowest_tie=1 hold=1 reset=1' in (root/'argmax.log').read_text()
    # A separate Python pass over recorded RTL output, not just PASS markers.
    data=np.array(list(csv.reader((root/'normal_boundaries.csv').open())),dtype=np.int64)
    assert data.shape==(274506,7),data.shape
    e=cases['0'];ops=np.concatenate([np.full(r['nout'],r['id']) for r in rows]);addr=np.concatenate([np.arange(r['nout']) for r in rows])
    want=np.column_stack([ops,addr,e['acc'][0],e['code'][0],e['skip'][0],e['wide'][0],e['skip_addr'][0]])
    assert np.array_equal(data,want),'Independent CSV comparison failed'
    sources=[p for folder in ('rtl/full_e2b_fpga_v2','rtl/ps_dma_v2','tb/ps_dma_v2') for p in Path(folder).glob('*') if p.is_file()]
    sources += [Path(x) for x in ('tools/full_vectors.py','tools/make_full_post_vectors.py','tools/summarize_ps_dma_packed.py','tools/v2_control_rom.py','tools/v2_mul_vectors.py','rtl/full_e2b_v1/argmax10.sv','rtl/full_e2b_v1/full_graph.svh','reference/e2b_v1/full_vectors/manifest.json','reference/e2b_v1/full_vectors/sample1_input.hex','reference/e2b_v1/full_vectors/sample1_source.json')]
    for mode in (0,1,2):
        text=(root/f'mode{mode}.log').read_text()
        transfers=[list(map(int,row)) for row in re.findall(r'MM2S_PASS job=(\d+) kind=(\d+) payload_words=(\d+) bus_words=(\d+) bytes=(\d+)',text)]
        expected_transfers=[[0,3072,768,3084],[1,268336,67084,268348],[2,698,698,2804],[3,698,698,2804],[4,698,698,2804]]
        if mode==2:transfers=transfers[-5:]
        for i in range(3 if mode==0 else 1):
            assert [row[1:] for row in transfers[5*i:5*i+5]]==expected_transfers
            assert sum(row[-1] for row in transfers[5*i:5*i+5])==279844
        assert len(transfers)==(15 if mode==0 else 5)
        responses=re.findall(r'S2MM_PASS job=(\d+) words=16 bytes=64 tag=([0-9a-f]+) elapsed=(\d+)',text)
        wanted=3 if mode==0 else 1
        assert len(responses)==wanted
        for job,tag,cycles in responses:
            assert int(tag,16)==0xa5000000+int(job) and int(cycles)>40551040
    result=dict(status='PASS' ,package=m['semantic_sha256'],architecture='AXI-Lite PS master BFM; DDR-backed MM2S/S2MM stream BFMs; full 30-op native core; no intermediate preload',
        distinct_actual_images=2,normal_order=[0,1,0],jobs=jobs,completed_jobs=5,boundaries_per_job=61,boundary_elements_total=2760420,trace_events_total=1372530,
        csv_recompared_events=274506,csv_sha256=hashlib.sha256((root/'normal_boundaries.csv').read_bytes()).hexdigest(),
        reset_cancellations=['partial header','partial weight packet','coefficient read','serial multiply','serial RNE','Stem active','Transition active','partial S2MM response'],recovery_sample=1,
        negative_oracle_mutations=4,malformed_packets_rejected=8,axi_aw_w_orders=3,axi_byte_strobes=True,axi_response_holds=True,axi_pending_reset=True,s2mm_words_per_job=16,mm2s_payload_words_per_job=273502,mm2s_bus_words_per_job=69961,mm2s_bytes_per_job=279844,packed_int8_per_bus_word=4,overflow_guard='INT32 fault=1 then clean reset',post_fraction_vectors=2000,mul_integer_vectors=512,argmax_sequences=2,
        source_sha256={p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sources)},
        limits='Actual Test 0/1 RTL plus AXI-Lite/DDR-backed DMA stream BFMs. Not PS CPU execution, DDR PHY training, vendor DMA IP simulation, physical board or full-Test RTL accuracy. Vivado system implementation is separate evidence.')
    Path('results/ps_dma_packed_rtl_actual.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    return result

if __name__=='__main__':print(json.dumps(summarize(),indent=2))
