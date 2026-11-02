#!/usr/bin/env python3
"""Record final logs, tool identity and source/vector hashes. Never infer PASS."""
from pathlib import Path
import hashlib,json,os,platform,re,subprocess
ROOT=Path(__file__).resolve().parent
def version(argv):
    r=subprocess.run(argv,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=True)
    return r.stdout.strip()
def main():
    results=[]
    for i in range(2):
        p=ROOT/f'results/simulation_{i}.log';s=p.read_text()
        assert not re.search(r'%Warning|%Error|%Fatal|Assertion failed',s),p
        rows=re.findall(r'^PASS (.+)$',s,re.M)
        assert len(rows)==1,p
        counts={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',rows[0])}
        results.append({'log':str(p.relative_to(ROOT)),**counts})
    summary={'scope':ROOT.name,'results':results,
             'trace':'separate partial-window run, not full regression evidence',
             'negative_reference_guard':'PASS' if 'NEGATIVE TEST PASS' in (ROOT/'results/missing_reference_negative.log').read_text() else 'FAIL'}
    (ROOT/'results/summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    paths=sorted(p for p in ROOT.rglob('*') if p.is_file() and
                 ('rtl' in p.relative_to(ROOT).parts or 'reference' in p.relative_to(ROOT).parts or
                  p.parent==ROOT or p.parent==ROOT/'sim') and '__pycache__' not in p.parts)
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    (ROOT/'results/source_sha256.json').write_text(json.dumps(hashes,indent=2)+'\n')
    tool={'verilator_distribution':'5.48.0 (used environment PyPI metadata)',
          'verilator_version':version([os.environ.get('VERILATOR','verilator'),'--version']),
          'simulation_banner':'Verilator 5.49 (see full simulation logs)',
          'python':platform.python_version(),'cxx':version(['c++','--version']).splitlines()[0]}
    (ROOT/'results/toolchain.json').write_text(json.dumps(tool,indent=2)+'\n')
    print(json.dumps(summary,indent=2))
if __name__=='__main__':main()
