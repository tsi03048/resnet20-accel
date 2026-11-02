"""Collect the synthetic Xsim MAC probe with independent integer CSV checks."""
import argparse,hashlib,json,re,shutil
from pathlib import Path
from tools.pipe_probe_vectors import verify

def summarize(run):
    run=Path(run);out=Path('results/pipe_probe');out.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((run/'launch_manifest.json').read_text(encoding='utf-8-sig'))
    for name,digest in manifest['source_sha256'].items():
        assert hashlib.sha256((run/'source_snapshot'/name).read_bytes()).hexdigest()==digest,name
        assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest,name
    log=(run/'vivado.log').read_text(encoding='utf-8')
    marker=re.search(r'^PIPE_PROBE_PASS pixels=4 macs=108 signed_products=1 ordered_prefix=1 compute_stalls=(\d+) trace_stalls=(\d+) held_edges=(\d+)',log,re.M)
    assert marker and all(int(x)>0 for x in marker.groups()) and 'Fatal:' not in log
    result=verify(run/'mac.csv')
    shutil.copytree(run,out,dirs_exist_ok=True)
    result.update(simulator='Vivado Xsim 2025.1',compute_stalls=int(marker[1]),trace_stalls=int(marker[2]),held_edges=int(marker[3]),
        source_sha256=manifest['source_sha256'],report_sha256={p.relative_to(out).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.rglob('*')) if p.is_file()})
    Path('results/pipe_probe_actual.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);a=p.parse_args();r=summarize(a.run);print(json.dumps({k:r[k] for k in ('status','ordered_macs','codes','compute_stalls','trace_stalls','held_edges')},indent=2))
