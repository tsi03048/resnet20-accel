from pathlib import Path
import json,re,hashlib,subprocess,os,platform
R=Path(__file__).resolve().parent
rows=[]
for i in range(3):
    s=(R/f'results/simulation_{i}.log').read_text()
    assert not re.search(r'%Warning|%Fatal|%Error',s)
    matches=re.findall(r'^PASS (.+)$',s,re.M);assert len(matches)==1
    rows.append({k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',matches[0])})
assert [x['jobs'] for x in rows]==[7,1,1]
assert [x['cancelled'] for x in rows]==[5,0,0]
(R/'results/summary.json').write_text(json.dumps(rows,indent=2)+'\n')
files=[p for p in R.rglob('*') if p.is_file() and not any(x.startswith('obj_') or x=='__pycache__' or x.startswith('.') for x in p.relative_to(R).parts) and 'results' not in p.relative_to(R).parts]
(R/'results/source_sha256.json').write_text(json.dumps({str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)},indent=2)+'\n')
tool={'python':platform.python_version(),'verilator_version':subprocess.check_output([os.environ.get('VERILATOR','verilator'),'--version'],text=True).strip(),'cxx':subprocess.check_output(['c++','--version'],text=True).splitlines()[0],'used_distribution':'PyPI verilator5.48.0','simulation_banner':'Verilator5.49'}
(R/'results/toolchain.json').write_text(json.dumps(tool,indent=2)+'\n')
print(json.dumps(rows,indent=2))
