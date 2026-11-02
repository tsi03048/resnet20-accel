from pathlib import Path
import json,re,hashlib,subprocess,os,platform
R=Path(__file__).resolve().parent;s=(R/'results/simulation.log').read_text()
assert not re.search(r'%Warning|%Error|%Fatal',s)
rows=re.findall(r'^PASS (.+)$',s,re.M);assert len(rows)==1
counts={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',rows[0])}
assert counts['vectors']==7508 and counts['cancelled']==1 and counts['outputs']==7509
(R/'results/summary.json').write_text(json.dumps(counts,indent=2)+'\n')
paths=[p for p in R.rglob('*') if p.is_file() and not any(x.startswith('.') or x.startswith('obj_') or x=='__pycache__' or x=='results' for x in p.relative_to(R).parts)]
(R/'results/source_sha256.json').write_text(json.dumps({str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)},indent=2)+'\n')
v=subprocess.check_output([os.environ.get('VERILATOR','verilator'),'--version'],text=True).strip()
(R/'results/toolchain.json').write_text(json.dumps({'verilator_version':v,'used_distribution':'PyPI5.48.0','simulation_banner':'Verilator5.49','python':platform.python_version(),'compiler':subprocess.check_output(['c++','--version'],text=True).splitlines()[0]},indent=2)+'\n')
print(counts)
