import hashlib,json,re
from pathlib import Path
root=Path(__file__).resolve().parent
cases=[]
for i in (0,1):
    line=next(x for x in (root/f'results/simulation_{i}.log').read_text().splitlines() if x.startswith('PASS '))
    cases.append({k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)})
hashes={}
for folder in ('rtl','sim','software','vectors'):
    for p in sorted((root/folder).rglob('*')):
        if p.is_file() and not any(x.startswith('obj_') or x=='__pycache__' for x in p.parts):
            hashes[str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
unchanged={p.name:p.read_bytes()==(root.parent/'e20_loader/rtl'/p.name).read_bytes() for p in (root/'rtl').glob('*.sv') if p.name!='mmio_transition.sv'}
assert all(unchanged.values())
(root/'results/summary.json').write_text(json.dumps({'cases':cases,'inherited_e20_rtl_unchanged':unchanged,'semantic_error_cases_per_small':3,'semantic_error_cases_per_stage12':2,'reset_pending_response_per_configuration':1,'note':'Final Y scoreboard; no real CPU/APB/AXI or FPGA'},indent=2)+'\n')
(root/'results/source_sha256.json').write_text(json.dumps(hashes,indent=2)+'\n')
print(json.dumps(cases))
