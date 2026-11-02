#!/usr/bin/env python3
"""Exercise a real failure path; restore the vector even when simulation fails."""
from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parent
exe=(ROOT/sys.argv[1]).resolve();p=ROOT/sys.argv[2]
temporary=p.with_suffix('.negative_test_hidden')
assert p.is_file() and not temporary.exists()
p.rename(temporary)
try:
    r=subprocess.run([str(exe)],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
finally:
    temporary.rename(p)
assert r.returncode!=0 and 'missing reference file' in r.stdout,r.stdout
(ROOT/'results/missing_reference_negative.log').write_text(
    'NEGATIVE TEST PASS: missing reference aborts before simulation comparison\n'+r.stdout)
print('NEGATIVE TEST PASS: missing reference guard')
