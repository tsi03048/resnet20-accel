"""Verify supplied hold-margin evidence/hashes; does not run hardware or RTL."""
import hashlib,json,re,zipfile
from pathlib import Path
from tools.check_packed_delivery import check_hashes
from tools.compare_hold_system import compare
from tools.hold_report_checks import verify_views

def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def verify():
    f=load('results/ps_dma_hold_rtl_actual.json');s=load('results/ps_dma_hold_system_actual.json');e=load('results/ps_dma_hold_rtl_evidence.json')
    r=load('results/ps_dma_hold_reset_actual.json');c=load('results/ps_dma_hold_comparison.json');v=load('results/ps_dma_hold_local_validation.json')
    assert f['status']=='PASS' and f['normal_order']==[0,1,0] and f['completed_jobs']==5 and f['boundaries_per_job']==61
    assert f['boundary_elements_total']==2760420 and f['csv_recompared_events']==274506 and len(f['reset_cancellations'])==11
    assert f['pipeline_freeze_checks']==['conv','conv_tail','gap'] and f['mm2s_bytes_per_job']==279844 and f['s2mm_words_per_job']==16
    assert s==load('results/ps_dma_hold_system/summary.json') and s['verdict'].startswith('ROUTED_SYSTEM_TIMING_PASS')
    assert s['route']['complete'] and not s['drc_errors'] and s['xsa_bit_matches']
    assert s['measurements']['post_route']['all_check_counts_zero'] and s['measurements']['post_route_nominal']['all_check_counts_zero']
    checkpoint=load('results/ps_dma_hold_checkpoint_actual.json')
    assert checkpoint['status']=='PASS' and checkpoint['saved_user_hold_uncertainty_ns']==0.100 and checkpoint['all_check_counts_zero']
    assert checkpoint['input_dcp_sha256']==s['binary_artifacts']['system_post_route.dcp']['sha256'] and checkpoint['timing']==s['measurements']['post_route']['timing']
    check_hashes(checkpoint['source_sha256']);check_hashes(checkpoint['report_sha256'],Path('results/ps_dma_hold_checkpoint'))
    check_hashes(f['source_sha256']);check_hashes(s['source_sha256']);check_hashes(s['report_sha256'],Path('results/ps_dma_hold_system'))
    for name in e['active_rtl_sources']:assert f['source_sha256'][name]==s['source_sha256'][name]
    assert hashlib.sha256(Path('results/ps_dma_hold_rtl_actual.json').read_bytes()).hexdigest()==e['summary_sha256']
    assert r['status']=='PASS' and r['hard_reset_lanes']==4 and r['endpoint_payload_cycles_checked']>0 and r['soft_reset_buffer_collision'] and r['bad_weight_complete_packet_drain']
    check_hashes(r['source_sha256']);check_hashes(r['report_sha256'],Path('results/ps_dma_hold_reset'))
    for name in e['active_rtl_sources']:
        if name in r['source_sha256']:assert r['source_sha256'][name]==s['source_sha256'][name]
    report=Path('results/ps_dma_hold_system/reports')
    verify_views(s['measurements']['post_route']['timing'],s['measurements']['post_route_nominal']['timing'],
        (report/'guarded_constraints.xdc').read_text(),(report/'nominal_constraints.xdc').read_text())
    assert compare()==load('results/ps_dma_hold_route_comparison.json')
    cycles=list(map(int,re.findall(r'S2MM_PASS job=\d+ words=16 bytes=64 tag=[0-9a-f]+ elapsed=(\d+)',Path('results/ps_dma_hold_execution.log').read_text())))[:3]
    assert cycles==c['normal_measured_cycles']==[64063653]*3 and c['normal_compute_cycles_identical']
    sw=load('results/ps_dma_packed_software_build.json');check_hashes(sw['source_sha256'])
    assert v['status']=='PASS' and v['python_unittests']==60
    assert hashlib.sha256(Path('results/ps_dma_hold_python_tests.log').read_bytes()).hexdigest()==v['python_log_sha256']
    check_hashes(v['source_sha256'])
    binaries=[]
    for name,info in s['binary_artifacts'].items():
        p=Path(info['location_in_practice_zip'])
        if p.exists():assert hashlib.sha256(p.read_bytes()).hexdigest()==info['sha256'];binaries.append(name)
    bit=Path('platform_hold/output/system.bit');xsa=Path('platform_hold/output/system.xsa')
    if bit.exists() and xsa.exists():
        with zipfile.ZipFile(xsa) as z:
            names=[n for n in z.namelist() if n.endswith('.bit')];assert len(names)==1 and z.read(names[0])==bit.read_bytes()
    app=Path('build/ps_dma_packed_software/app.elf')
    if app.exists():assert hashlib.sha256(app.read_bytes()).hexdigest()==sw['elf_sha256']
    return dict(status='DELIVERED_HOLD_EVIDENCE_VERIFIED',executed_simulation=False,executed_hardware=False,
        rtl_completed_jobs=5,boundaries_per_job=61,reset_cancellations=11,lane_resets=4,compute_cycles=cycles[0],clock_mhz=100,
        setup_wns_ns=s['measurements']['post_route']['timing']['wns_ns'],guarded_hold_whs_ns=s['measurements']['post_route']['timing']['whs_ns'],
        nominal_hold_whs_ns=s['measurements']['post_route_nominal']['timing']['whs_ns'],user_hold_guard_ns=0.100,
        platform_binaries_checked=binaries,board_execution='NOT_RUN')
if __name__=='__main__':print(json.dumps(verify(),indent=2))
