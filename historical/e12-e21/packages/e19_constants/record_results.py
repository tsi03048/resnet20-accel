from pathlib import Path
import hashlib,json,platform
R=Path(__file__).resolve().parent
v=json.loads((R/'results/validation.json').read_text())
assert len(v['positive'])==4 and len(v['rejections'])==30
summary=dict(packages=4,constant_files=44,elements=sum(x['elements'] for x in v['positive']),negative_rejections=30,software_preloads=4,rtl_simulation_this_chapter=False,known_limitation=v['known_limitations'],python=platform.python_version())
(R/'results/summary.json').write_text(json.dumps(summary,indent=2)+'\n')
files=[p for p in R.rglob('*') if p.is_file() and not any(x.startswith('.') or x=='__pycache__' or x=='results' for x in p.relative_to(R).parts)]
(R/'results/source_sha256.json').write_text(json.dumps({str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)},indent=2)+'\n')
print(json.dumps(summary,indent=2))
