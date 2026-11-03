"""Compare the hold-guard implementation to E8-H under both explicit budgets."""
import hashlib,json
from pathlib import Path
from tools.compare_timing_system import path_summary

def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def compare(write=False):
    old=load('results/ps_dma_timing_system_actual.json');new=load('results/ps_dma_hold_system_actual.json')
    assert old['clock_mhz']==new['clock_mhz']==100 and old['part']==new['part'] and old['board_definition']==new['board_definition']
    assert Path('results/ps_dma_timing_system/reports/system_config.txt').read_bytes()==Path('results/ps_dma_hold_system/reports/system_config.txt').read_bytes()
    rtl=[k for k in old['source_sha256'] if k.startswith('rtl/')]
    assert len(rtl)==10 and all(old['source_sha256'][k]==new['source_sha256'][k] for k in rtl)
    script=Path('board/zedboard/ps_dma_hold/build_system.tcl').read_text().replace('ps_dma_hold','ps_dma_timing').replace('zedboard_ps_hold','zedboard_ps_timing')
    kept=[];skip=False
    for line in script.splitlines():
        if '# Keep the implementation' in line:skip=True
        if skip:
            if 'set_clock_uncertainty -hold 0.100' in line:skip=False
            continue
        if 'STEPS.PLACE_DESIGN.TCL.PRE' in line or 'STEPS.POST_ROUTE_PHYS_OPT_DESIGN' in line:continue
        if line.strip():kept.append(line)
    assert '\n'.join(kept)=='\n'.join(x for x in Path('board/zedboard/ps_dma_timing/build_system.tcl').read_text().splitlines() if x.strip()),'Unexpected implementation/constraint change'
    baseline=old['measurements']['post_route'];guard=new['measurements']['post_route'];nominal=new['measurements']['post_route_nominal']
    assert new['verdict'].startswith('ROUTED_SYSTEM_TIMING_PASS') and new['route']['complete'] and not new['drc_errors']
    assert guard['all_check_counts_zero'] and nominal['all_check_counts_zero']
    assert guard['timing']['numeric_constraints_met'] and nominal['timing']['whs_ns']>=0.100
    assert nominal['timing']['whs_ns']>baseline['timing']['whs_ns']
    paths={}
    for label,folder,prefix in (('previous','ps_dma_timing_system','post_route'),('guarded','ps_dma_hold_system','post_route'),('nominal','ps_dma_hold_system','post_route_nominal')):
        paths[label]={}
        for kind in ('setup','hold'):
            p=Path('results')/folder/'reports'/(prefix+'_worst_'+kind+'.rpt')
            paths[label][kind]=dict(path_summary(p.read_text()),report_sha256=hashlib.sha256(p.read_bytes()).hexdigest())
    r=dict(status='HOLD_MARGIN_IMPROVED',clock_mhz=100,rtl_sources_unchanged=rtl,guarded_user_hold_uncertainty_ns=0.100,nominal_user_hold_uncertainty_ns=0.0,
        previous_nominal_hold_whs_ns=baseline['timing']['whs_ns'],new_guarded_hold_whs_ns=guard['timing']['whs_ns'],new_nominal_hold_whs_ns=nominal['timing']['whs_ns'],
        nominal_hold_gain_ns=round(nominal['timing']['whs_ns']-baseline['timing']['whs_ns'],3),previous_setup_wns_ns=baseline['timing']['wns_ns'],new_setup_wns_ns=guard['timing']['wns_ns'],
        previous_resources=baseline['resources'],new_resources=guard['resources'],worst_paths=paths,
        same_board_clock_and_function=True,implementation_changed='Additional 0.100 ns hold uncertainty before placement; enabled post-route ExploreWithAggressiveHoldFix; no setup relaxation',
        limits='Guard is an implementation margin target, not measured jitter. Original-budget report is a separate comparison view; guard remains in delivered checkpoint. No physical board, multi-seed or higher-frequency guarantee.')
    if write:Path('results/ps_dma_hold_route_comparison.json').write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8',newline='\n')
    return r
if __name__=='__main__':print(json.dumps(compare(write=True),indent=2))
