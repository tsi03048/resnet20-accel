"""Standard-library evidence check. Does not execute hardware or simulators."""
import hashlib,json
from pathlib import Path

def check_hashes(items,prefix=Path('.')):
    for name,digest in items.items():
        if hashlib.sha256((prefix/name).read_bytes()).hexdigest()!=digest:raise ValueError('Changed evidence/source: '+name)
def verify():
    s=json.loads(Path('results/ps_dma_packed_system_actual.json').read_text());f=json.loads(Path('results/ps_dma_packed_rtl_actual.json').read_text())
    e=json.loads(Path('results/ps_dma_packed_rtl_evidence.json').read_text());ip=json.loads(Path('results/ps_dma_packed_ip_actual.json').read_text())
    arm=json.loads(Path('results/ps_dma_packed_arm_emulation.json').read_text());sw=json.loads(Path('results/ps_dma_packed_software_build.json').read_text(encoding='utf-8-sig'))
    board=json.loads(Path('results/ps_dma_packed_board_actual.json').read_text())
    script=json.loads(Path('results/ps_dma_packed_board_script_test.json').read_text())
    assert script['status']=='SCRIPT_MODEL_PASS' and not script['hardware_access']
    assert hashlib.sha256(Path('board/zedboard/ps_dma_packed/run_board.tcl').read_bytes()).hexdigest()==script['run_board_tcl_sha256']
    assert s['verdict'].startswith('ROUTED_SYSTEM_TIMING_PASS') and s['clock_mhz']==100 and s['part']=='xc7z020clg484-1'
    assert s==json.loads(Path('results/ps_dma_packed_system/summary.json').read_text())
    assert s['route']['complete'] and not s['drc_errors'] and s['measurements']['post_route']['all_check_counts_zero']
    check_hashes(s['report_sha256'],Path('results/ps_dma_packed_system'))
    check_hashes(f['source_sha256']);check_hashes(s['source_sha256'])
    for name in e['active_rtl_sources']:assert s['source_sha256'][name]==f['source_sha256'][name]
    assert f['status']=='PASS' and f['normal_order']==[0,1,0] and f['completed_jobs']==5 and len(f['reset_cancellations'])==8
    assert f['mm2s_bus_words_per_job']==69961 and f['mm2s_bytes_per_job']==279844 and f['packed_int8_per_bus_word']==4
    assert hashlib.sha256(Path('results/ps_dma_packed_rtl_actual.json').read_bytes()).hexdigest()==e['summary_sha256']
    assert ip['status']=='PASS' and ip['max_packet_bytes']==268348 and ip['reset_during_transfer']
    check_hashes(ip['report_sha256'],Path('results/ps_dma_packed_ip_sim'));check_hashes(ip['source_sha256'])
    reset=json.loads(Path('results/ps_dma_packed_reset_actual.json').read_text())
    assert reset['status']=='PASS' and reset['hard_reset_lanes']==4 and reset['soft_reset_buffer_collision'] and reset['bad_weight_complete_packet_drain']
    check_hashes(reset['report_sha256'],Path('results/ps_dma_packed_reset'));check_hashes(reset['source_sha256'])
    comparison=json.loads(Path('results/ps_dma_packed_comparison.json').read_text())
    assert comparison['new_mm2s_bytes_per_image']==279844 and comparison['old_mm2s_bytes_per_image']==1094068 and comparison['normal_compute_cycles_identical']
    assert arm['status']=='PASS' and arm['elf_sha256']==sw['elf_sha256'] and len(arm['cases'])==5 and all(x['status']=='PASS' for x in arm['cases'])
    check_hashes(arm['source_sha256']);check_hashes(sw['source_sha256'])
    binaries_checked=[]
    for name,info in s['binary_artifacts'].items():
        p=Path(info['location_in_practice_zip'])
        if p.exists():
            assert hashlib.sha256(p.read_bytes()).hexdigest()==info['sha256'];binaries_checked.append(name)
    app=Path('build/ps_dma_packed_software/app.elf')
    if app.exists():assert hashlib.sha256(app.read_bytes()).hexdigest()==sw['elf_sha256']
    return dict(status='DELIVERED_PACKED_EVIDENCE_VERIFIED',executed_hardware=False,executed_simulation=False,
        rtl_completed_jobs=5,boundaries_per_job=61,reset_cancellations=8,additional_lane_resets=4,soft_reset_buffer_collision=True,
        mm2s_bytes_per_image=279844,mm2s_reduction_percent=round(comparison['reduction_percent'],2),dma_ip_simulation='PASS',arm_software_emulation='PASS',
        system_clock_mhz=100,wns_ns=s['measurements']['post_route']['timing']['wns_ns'],whs_ns=s['measurements']['post_route']['timing']['whs_ns'],
        board_execution=board['status'],included_platform_binaries_checked=binaries_checked)
if __name__=='__main__':print(json.dumps(verify(),indent=2))
