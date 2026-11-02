"""Check supplied evidence/hashes; never starts a simulator or hardware."""
import hashlib,json,re
from pathlib import Path
from tools.check_packed_delivery import check_hashes
from tools.pipe_cycle_model import predict
from tools.pipe_probe_vectors import verify as verify_probe

def load(name):return json.loads(Path(name).read_text(encoding='utf-8-sig'))
def verify():
    f=load('results/ps_dma_pipe_rtl_actual.json');s=load('results/ps_dma_pipe_system_actual.json')
    e=load('results/ps_dma_pipe_rtl_evidence.json');p=load('results/pipe_probe_actual.json');c=load('results/ps_dma_pipe_comparison.json')
    assert f['status']=='PASS' and f['completed_jobs']==5 and f['normal_order']==[0,1,0]
    assert f['boundaries_per_job']==61 and f['boundary_elements_total']==2760420 and f['csv_recompared_events']==274506
    assert len(f['reset_cancellations'])==11 and f['pipeline_freeze_checks']==['conv','conv_tail','gap']
    assert f['mm2s_bytes_per_job']==279844 and f['s2mm_words_per_job']==16
    assert s['verdict'].startswith('ROUTED_SYSTEM_TIMING_PASS') and s['clock_mhz']==100
    assert s==load('results/ps_dma_pipe_system/summary.json') and s['route']['complete'] and not s['drc_errors']
    assert s['measurements']['post_route']['all_check_counts_zero']
    assert hashlib.sha256(Path('results/ps_dma_pipe_rtl_actual.json').read_bytes()).hexdigest()==e['summary_sha256']
    check_hashes(f['source_sha256']);check_hashes(s['source_sha256']);check_hashes(s['report_sha256'],Path('results/ps_dma_pipe_system'))
    for name in e['active_rtl_sources']:assert f['source_sha256'][name]==s['source_sha256'][name]
    check_hashes(p['source_sha256']);check_hashes(p['report_sha256'],Path('results/pipe_probe'))
    assert verify_probe('results/pipe_probe/mac.csv')['independent_csv_checked']
    assert p['status']=='PASS' and p['ordered_macs']==108 and p['held_edges']>0
    cycles=list(map(int,re.findall(r'S2MM_PASS job=\d+ words=16 bytes=64 tag=[0-9a-f]+ elapsed=(\d+)',Path('results/ps_dma_pipe_execution.log').read_text())))[:3]
    model=predict();assert cycles==[model['predicted_pipeline_cycles']]*3 and c['normal_measured_cycles']==cycles
    assert c['cycle_prediction_matches'] and c['old_mm2s_bytes_per_image']==c['new_mm2s_bytes_per_image']==279844
    sw=load('results/ps_dma_packed_software_build.json');arm=load('results/ps_dma_packed_arm_emulation.json')
    assert arm['status']=='PASS' and arm['elf_sha256']==sw['elf_sha256'];check_hashes(sw['source_sha256']);check_hashes(arm['source_sha256'])
    binaries=[]
    for name,info in s['binary_artifacts'].items():
        path=Path(info['location_in_practice_zip'])
        if path.exists():assert hashlib.sha256(path.read_bytes()).hexdigest()==info['sha256'];binaries.append(name)
    app=Path('build/ps_dma_packed_software/app.elf')
    if app.exists():assert hashlib.sha256(app.read_bytes()).hexdigest()==sw['elf_sha256']
    return dict(status='DELIVERED_PIPELINE_EVIDENCE_VERIFIED',executed_simulation=False,executed_hardware=False,
        compute_cycles=cycles[0],reduction_percent=round(model['predicted_cycle_reduction_percent'],2),rtl_completed_jobs=5,boundaries_per_job=61,
        reset_cancellations=11,probe_ordered_macs=108,clock_mhz=100,wns_ns=s['measurements']['post_route']['timing']['wns_ns'],
        whs_ns=s['measurements']['post_route']['timing']['whs_ns'],platform_binaries_checked=binaries,board_execution='NOT_RUN')
if __name__=='__main__':print(json.dumps(verify(),indent=2))
