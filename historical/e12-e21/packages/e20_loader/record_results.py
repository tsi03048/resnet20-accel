from pathlib import Path
import json,re,hashlib,platform,subprocess,os
R=Path(__file__).resolve().parent;rows=[]
for i in range(3):
    s=(R/f'results/simulation_{i}.log').read_text();assert not re.search(r'%Warning|%Error|%Fatal',s)
    m=re.findall(r'^PASS (.+)$',s,re.M);assert len(m)==1
    rows.append({k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',m[0])})
assert [x['jobs'] for x in rows]==[4,1,1] and [x['cancelled'] for x in rows]==[2,0,0]
assert rows[0]['rejected_transactions']==10 and rows[0]['reset_during_load']==1
assert len(json.loads((R/'results/bridge_errors.json').read_text()))==2
(R/'results/summary.json').write_text(json.dumps(rows,indent=2)+'\n')
files=[p for p in R.rglob('*') if p.is_file() and not any(x.startswith('.') or x.startswith('obj_') or x=='__pycache__' or x=='results' for x in p.relative_to(R).parts)]
(R/'results/source_sha256.json').write_text(json.dumps({str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)},indent=2)+'\n')
(R/'results/toolchain.json').write_text(json.dumps({'python':platform.python_version(),'verilator_version':subprocess.check_output([os.environ.get('VERILATOR','verilator'),'--version'],text=True).strip(),'used_distribution':'PyPI5.48.0','simulation_banner':'Verilator5.49','compiler':subprocess.check_output(['c++','--version'],text=True).splitlines()[0]},indent=2)+'\n')
print(json.dumps(rows,indent=2))
