"""Validate a captured board report; this command does not program/run hardware."""
import argparse,hashlib,json,re
from pathlib import Path
from tools.ps_dma_packed_vectors import artifacts

def validate(words):
    _,m=artifacts()
    if len(words)!=72 or words[0]!=0x52325053 or words[1]!=2 or words[2]!=0 or words[3]!=4:raise ValueError('Board firmware report incomplete/failed: '+str(words[:8]))
    jobs=[]
    for i,cid in enumerate((0,1,0,1)):
        row=words[8+16*i:24+16*i];wanted=m['samples'][str(cid)]
        scores=[x-(1<<32) if x&(1<<31) else x for x in row[4:14]]
        if row[:4]!=[0x52323052,0xc9000000+i,0,wanted['prediction']] or scores!=wanted['scores']:raise ValueError('DDR score/header mismatch in job '+str(i))
        cycles=row[14]+(row[15]<<32)
        if cycles<=40551040:raise ValueError('Missing/inconsistent hardware cycle count')
        jobs.append(dict(job=i,sample=cid,prediction=row[3],scores=scores,compute_cycles=cycles))
    return dict(status='REPORT_CONTENT_VALIDATED',executed_board_in_this_command=False,completed_jobs=4,normal_order=[0,1,0],reset_recovery_sample=1,jobs=jobs,
        scope='Captured final score report only; pair with XSDB log/source hashes. Does not observe 61 internal boundaries on physical board.')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--words',required=True);p.add_argument('--output',required=True);a=p.parse_args()
    raw=Path(a.words).read_bytes();lines=raw.decode().splitlines()
    if any(re.fullmatch(r'[0-9a-fA-F]{8}',x.strip()) is None for x in lines):raise ValueError('Expected 72 one-word hex lines')
    r=validate([int(x,16) for x in lines]);r['captured_words_sha256']=hashlib.sha256(raw).hexdigest()
    Path(a.output).write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8',newline='\n');print(json.dumps(r,indent=2))
