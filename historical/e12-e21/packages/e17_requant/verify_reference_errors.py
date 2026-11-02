from pathlib import Path
import subprocess
R=Path(__file__).resolve().parent;p=R/'reference/vectors.txt';backup=p.read_bytes();reports=[]
try:
    p.unlink()
    r=subprocess.run([str(R/'sim/obj_dir/Vtb_requant')],cwd=R,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    assert r.returncode!=0 and 'missing reference' in r.stdout
    reports.append('NEGATIVE PASS missing reference\n'+r.stdout)
    p.write_text('malformed\n')
    r=subprocess.run([str(R/'sim/obj_dir/Vtb_requant')],cwd=R,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    assert r.returncode!=0 and 'malformed vector' in r.stdout
    reports.append('NEGATIVE PASS malformed vector\n'+r.stdout)
finally:p.write_bytes(backup)
(R/'results/reference_errors.log').write_text('\n'.join(reports))
print('NEGATIVE PASS missing/malformed reference (restored)')
