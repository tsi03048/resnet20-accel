#!/usr/bin/env python3
"""Independent integer golden: loop over coordinates, explicit zero extension."""
from pathlib import Path
import json, random
ROOT=Path(__file__).resolve().parent
def rne4(a):
    q,r=divmod(abs(a),4)
    q+=r>2 or (r==2 and q%2==1)
    return -q if a<0 else q
def quant(a,relu):
    q=rne4(a)
    return max(-128,min(127,max(0,q) if relu else q))
def hexfile(path,values,bits):
    path.write_text(''.join(f'{v&((1<<bits)-1):0{bits//4}x}\n' for v in values))
def make(name,cin,cout,h,w,pad,jobs):
    oh,ow=h+2*pad-2,w+2*pad-2
    rng=random.Random(13013)
    summary=[]
    for job in range(jobs):
        relu=job%2 if name=='tiny' else int(job==2)
        if name=='tiny':
            x=list(range(1,17))+[2]*16
            wt=[1]*9+[-1]*9+[-1]*9+[2]*9
            bias=[3,-1]
        elif job==0:
            x=[1]*(cin*h*w);wt=[1]*(cout*cin*9);bias=[0]*cout
        elif job in (1,2):
            # Same signed vector in two modes, using a fresh identical RNG.
            r=random.Random(13131)
            x=[r.randint(-8,8) for _ in range(cin*h*w)]
            wt=[r.randint(-4,4) for _ in range(cout*cin*9)]
            bias=[r.randint(-63,63) for _ in range(cout)]
        else:
            x=[-128 if i%2 else 127 for i in range(cin*h*w)]
            wt=[-128 if (i//9)%2 else 127 for i in range(cout*cin*9)]
            bias=[(-31 if i%2 else 17) for i in range(cout)]
        acc=[];out=[];pads=0;valid=0
        for co in range(cout):
            for oy in range(oh):
                for ox in range(ow):
                    a=bias[co]
                    for ci in range(cin):
                        for ky in range(3):
                            for kx in range(3):
                                iy,ix=oy+ky-pad,ox+kx-pad
                                if 0<=iy<h and 0<=ix<w:
                                    a+=x[(ci*h+iy)*w+ix]*wt[((co*cin+ci)*3+ky)*3+kx]
                                    valid+=1
                                else:pads+=1
                    assert -(1<<31)<=a<(1<<31)
                    acc.append(a);out.append(quant(a,relu))
        d=ROOT/name/f'job{job}';d.mkdir(parents=True,exist_ok=True)
        for filename,values,bits in [('input.hex',x,8),('weight.hex',wt,8),('bias.hex',bias,32),('acc.hex',acc,32),('output.hex',out,8)]:
            hexfile(d/filename,values,bits)
        samples={str(i):{'acc':acc[i],'code':out[i]} for i in sorted({0,1,ow+1,oh*ow-1,len(out)-1})}
        summary.append(dict(job=job,relu=relu,outputs=len(out),terms=cout*oh*ow*cin*9,
                            valid_reads=valid,padding_terms=pads,samples=samples))
        if name=='tiny':assert out==([10,12,19,21,0,0,0,0] if relu else [10,12,19,21,-5,-7,-14,-16])
        if name=='stem' and job==0:
            assert (out[0],out[1],out[33])==(3,4,7)
            assert pads==18240 and valid==424128
    (ROOT/name/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'REFERENCE PASS {name}: jobs={jobs} outputs/job={cout*oh*ow} K={cin*9} valid/job={valid} padding/job={pads}')
if __name__=='__main__':
    make('stem',3,16,32,32,1,4)
    make('tiny',2,2,4,4,0,2)
