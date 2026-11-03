"""Validate an actual re-open of the delivered routed checkpoint."""
import argparse,hashlib,json,re,shutil
from pathlib import Path
from tools.summarize_vivado import read,timing

def summarize(run):
    run=Path(run);out=Path('results/ps_dma_hold_checkpoint');out.mkdir(parents=True,exist_ok=True)
    m=json.loads(read(run/'launch_manifest.json'));s=json.loads(read('results/ps_dma_hold_system_actual.json'))
    assert m['input_dcp_sha256']==s['binary_artifacts']['system_post_route.dcp']['sha256']
    for name,digest in m['source_sha256'].items():assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,name
    clocks=read(run/'clocks.rpt');t=timing(read(run/'timing.rpt'))
    assert re.search(r'clk_fpga_0\s+10\.000',clocks) and re.search(r'clk_fpga_0\s+clk_fpga_0\s+0\.100\s+rf -> rf',clocks)
    assert t==s['measurements']['post_route']['timing']
    checks={k:int(v) for k,v in re.findall(r'checking\s+(\w+)\s*\((\d+)\)',read(run/'check_timing.rpt'),re.I)}
    assert len(checks)==12 and not any(checks.values())
    assert 'HOLD_CHECKPOINT_REOPEN_COMPLETE' in read(run/'vivado.log')
    shutil.copytree(run,out,dirs_exist_ok=True)
    r=dict(status='PASS',input_dcp_sha256=m['input_dcp_sha256'],clock_mhz=100,saved_user_hold_uncertainty_ns=0.100,timing=t,all_check_counts_zero=True,
        source_sha256=m['source_sha256'],report_sha256={p.relative_to(out).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.rglob('*')) if p.is_file()},
        scope='Vivado actually re-opened final routed DCP without changing constraints. No hardware execution or post-route functional/timing simulation.')
    Path('results/ps_dma_hold_checkpoint_actual.json').write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8',newline='\n')
    return r
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);a=p.parse_args();r=summarize(a.run);print(json.dumps({k:r[k] for k in ('status','clock_mhz','saved_user_hold_uncertainty_ns')},indent=2))
