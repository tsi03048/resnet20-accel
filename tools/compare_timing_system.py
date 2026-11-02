"""Compare measured system routes with identical clock/board constraints."""
import hashlib,json,re
from pathlib import Path

def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def path_summary(text):
    return dict(slack_ns=float(re.search(r'Slack \(MET\)\s*:\s*([\d.]+)ns',text)[1]),
        source=re.search(r'  Source:\s+(\S+)',text)[1],destination=re.search(r'  Destination:\s+(\S+)',text)[1],
        data_delay_ns=float(re.search(r'Data Path Delay:\s*([\d.]+)ns',text)[1]),logic_levels=int(re.search(r'Logic Levels:\s*(\d+)',text)[1]))
def compare(write=False):
    old=load('results/ps_dma_pipe_system_actual.json');new=load('results/ps_dma_timing_system_actual.json')
    assert old['clock_mhz']==new['clock_mhz']==100 and old['part']==new['part'] and old['board_definition']==new['board_definition']
    assert Path('results/ps_dma_pipe_system/reports/system_config.txt').read_bytes()==Path('results/ps_dma_timing_system/reports/system_config.txt').read_bytes()
    script=Path('board/zedboard/ps_dma_timing/build_system.tcl').read_text().replace('ps_dma_timing','ps_dma_pipe').replace('zedboard_ps_timing','zedboard_ps_pipe').replace('rtl/ps_dma_v3','rtl/ps_dma_v2')
    assert script==Path('board/zedboard/ps_dma_pipe/build_system.tcl').read_text(),'Build/constraints changed beyond source and output paths'
    native=[k for k in old['source_sha256'] if k.startswith('rtl/full_')]
    assert len(native)==8 and all(old['source_sha256'][k]==new['source_sha256'][k] for k in native)
    a=old['measurements']['post_route'];b=new['measurements']['post_route']
    assert new['verdict'].startswith('ROUTED_SYSTEM_TIMING_PASS') and b['timing']['wns_ns']>a['timing']['wns_ns']
    assert b['timing']['whs_ns']>=0 and b['all_check_counts_zero'] and new['route']['complete'] and not new['drc_errors']
    paths={};hold_paths={}
    for label,folder in (('previous','ps_dma_pipe_system'),('current','ps_dma_timing_system')):
        p=Path('results')/folder/'reports/post_route_worst_setup.rpt';paths[label]=dict(path_summary(p.read_text()),report_sha256=hashlib.sha256(p.read_bytes()).hexdigest())
        p=Path('results')/folder/'reports/post_route_worst_hold.rpt';hold_paths[label]=dict(path_summary(p.read_text()),report_sha256=hashlib.sha256(p.read_bytes()).hexdigest())
    r=dict(status='TIMING_MARGIN_IMPROVED',clock_mhz=100,same_board_and_clock_configuration=True,same_implementation_constraints_and_strategy=True,
        unchanged_native_rtl=native,previous_wns_ns=a['timing']['wns_ns'],new_wns_ns=b['timing']['wns_ns'],
        wns_improvement_ns=round(b['timing']['wns_ns']-a['timing']['wns_ns'],3),previous_whs_ns=a['timing']['whs_ns'],new_whs_ns=b['timing']['whs_ns'],
        previous_resources=a['resources'],new_resources=b['resources'],worst_setup_paths=paths,worst_hold_paths=hold_paths,
        limits='Two actual Vivado routes at 100 MHz. Placement/routing may change unrelated path delays. No increased frequency, multi-seed stability, physical board FPS, DDR training or electrical measurement claimed.')
    if write:Path('results/ps_dma_timing_route_comparison.json').write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8',newline='\n')
    return r
if __name__=='__main__':print(json.dumps(compare(write=True),indent=2))
