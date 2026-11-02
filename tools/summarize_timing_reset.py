"""Collect new loader endpoint/reset RTL evidence; no hardware execution."""
import argparse,hashlib,json,re,shutil
from pathlib import Path

def summarize(run):
    run=Path(run);out=Path('results/ps_dma_timing_reset');out.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((run/'launch_manifest.json').read_text(encoding='utf-8-sig'))
    for name,digest in manifest['source_sha256'].items():
        assert hashlib.sha256((run/'source_snapshot'/name).read_bytes()).hexdigest()==digest,name
        assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,name
    log=(run/'vivado.log').read_text(encoding='utf-8')
    assert 'Fatal:' not in log and re.findall(r'^PACKED_LANE_RESET_PASS lane=(\d)',log,re.M)==['0','1','2','3']
    assert 'PACKED_SOFT_RESET_PASS payload_capture_collision=1 native_scalars=0' in log
    assert 'PACKED_BAD_WEIGHT_PASS code=16 complete_packet_drain=1 packet_words=67087' in log
    assert 'PACKED_RESET_PASS hard_reset_lanes=4 soft_reset_collision=1 recovered_input_bytes=3072' in log
    count=int(re.search(r'^TIMING_ENDPOINT_PASS payload_cycles=(\d+)',log,re.M)[1]);assert count>0
    shutil.copytree(run,out,dirs_exist_ok=True)
    result=dict(status='PASS',simulator='Vivado Xsim 2025.1',hard_reset_lanes=4,soft_reset_buffer_collision=True,bad_weight_numeric_error=16,
        bad_weight_complete_packet_drain=True,bad_weight_packet_words=67087,recovered_input_bytes=3072,endpoint_payload_cycles_checked=count,
        source_sha256=manifest['source_sha256'],report_sha256={p.relative_to(out).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.rglob('*')) if p.is_file()},
        scope='Synthetic input and malformed Weight packet. Checks endpoint metadata throughout observed payload stalls. Not actual-image classification, PS or physical board execution.')
    Path('results/ps_dma_timing_reset_actual.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);a=p.parse_args();r=summarize(a.run);print(json.dumps({k:r[k] for k in ('status','endpoint_payload_cycles_checked','hard_reset_lanes','bad_weight_complete_packet_drain')},indent=2))
