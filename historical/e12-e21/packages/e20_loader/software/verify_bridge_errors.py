from pathlib import Path
import shutil,tempfile,subprocess,sys,json
R=Path(__file__).resolve().parent;reports=[]
for mode in ['changed_manifest','changed_input_audit']:
    with tempfile.TemporaryDirectory(prefix='e20-bridge-') as td:
        root=Path(td);p=root/'software';shutil.copytree(R,p,ignore=shutil.ignore_patterns('__pycache__'))
        if mode=='changed_manifest':
            f=p/'packages/small_compat/manifest.json';m=json.loads(f.read_text());m['schema_version']=2;f.write_text(json.dumps(m))
        else:
            f=p/'audit_e18/small/job1/input.hex';f.write_text('00\n'+f.read_text()[3:])
        r=subprocess.run([sys.executable,str(p/'build_vectors.py')],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        assert r.returncode!=0 and not list((root/'vectors').rglob('writes.txt')),(mode,r.stdout)
        reports.append({'case':mode,'status':'REJECT_BEFORE_WRITE_STREAM','returncode':r.returncode})
(R.parent/'results/bridge_errors.json').write_text(json.dumps(reports,indent=2)+'\n')
print('PASS bridge rejections=2 no write stream emitted')
