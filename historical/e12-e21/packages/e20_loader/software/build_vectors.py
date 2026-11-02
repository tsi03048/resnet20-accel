from pathlib import Path
import json,hashlib,shutil
from validate_package import validate,InvalidPackage
R=Path(__file__).resolve().parent;PINS=json.loads((R/'approved_manifest_digests.json').read_text())
ROLES=['input','weight1','weight2','bias1','bias2','n1','n2','nm','ns','s1','s2','sa']
out=R.parent/'vectors';out.mkdir(exist_ok=True)
reports=[]
for idx,name in enumerate(['small_compat','small_varied','stage12_varied','stage23_varied']):
    v=validate(R/'packages'/name,PINS[name],include_values=True)
    audit=R/'audit_e18'/v['source_case']
    # Audit vector hashes are frozen separately when creating this fixture.
    hashes=json.loads((R/'audit_sha256.json').read_text())
    for p in audit.glob('*.hex'):
        if hashlib.sha256(p.read_bytes()).hexdigest()!=hashes[str(p.relative_to(R/'audit_e18'))]:raise ValueError('audit bytes changed')
    values=v['values'];values['input']=[int(x,16) for x in (audit/'input.hex').read_text().splitlines()]
    target=out/name;target.mkdir(exist_ok=True);lines=[]
    for role,kind in enumerate(ROLES):
        for a,x in enumerate(values[kind]):lines.append(f'{role} {a} {x&((1<<8)-1) if role<=2 else x&0xffffffff:08x}\n')
    (target/'writes.txt').write_text(''.join(lines))
    (target/'digest.hex').write_text(v['manifest_sha256']+'\n')
    for fn in ['input','acc1','acc2','middle','main','skip','output']:
        shutil.copyfile(audit/(fn+'.hex'),target/(fn+'.hex'))
    meta={k:x for k,x in v.items() if k!='values'};meta.update(generation=100+idx,writes=len(lines),role_order=ROLES)
    (target/'metadata.json').write_text(json.dumps(meta,indent=2)+'\n');reports.append(meta)
print(json.dumps(reports,indent=2))
