#!/usr/bin/env python3
from pathlib import Path
import random,json
ROOT=Path(__file__).resolve().parent
def q4(a,relu):
    q,r=divmod(abs(a),4);q+=r>2 or (r==2 and q%2)
    if a<0:q=-q
    if relu:q=max(0,q)
    return max(-128,min(127,q))
def conv(x,wt,b,c,h,relu):
    aout=[];out=[]
    for co in range(c):
        for oy in range(h):
            for ox in range(h):
                a=b[co]
                for ci in range(c):
                    for ky in range(3):
                        for kx in range(3):
                            iy,ix=oy+ky-1,ox+kx-1
                            if 0<=iy<h and 0<=ix<h:a+=x[(ci*h+iy)*h+ix]*wt[((co*c+ci)*3+ky)*3+kx]
                assert -(1<<31)<=a<(1<<31)
                aout.append(a);out.append(q4(a,relu))
    return aout,out
def save(p,a,bits):p.write_text(''.join(f'{v&((1<<bits)-1):0{bits//4}x}\n' for v in a))
def make(name,c,h,nj):
    records=[]
    for j in range(nj):
        r=random.Random(14014+j)
        x=[r.randint(-12,12) for _ in range(c*h*h)]
        b1=[0]*c;b2=[0]*c
        if j==1:
            w1=[r.randint(-2,2) for _ in range(c*c*9)]
            w2=[r.randint(-2,2) for _ in range(c*c*9)]
            b1=[r.randint(-16,16) for _ in range(c)];b2=[r.randint(-16,16) for _ in range(c)]
        else:
            w1=[0]*(c*c*9);w2=[0]*(c*c*9)
            for co in range(c):w1[(co*c+co)*9+4]=4;w2[(co*c+co)*9+4]=-4 if j==0 else 4
            if j==2:x=[127]*(c*h*h)
            if j==3:x=[-128]*(c*h*h);b2=[-1024]*c
        acc1,a=conv(x,w1,b1,c,h,True);acc2,m=conv(a,w2,b2,c,h,False)
        y=[min(127,max(0,s+t)) for s,t in zip(x,m)]
        witnesses=sum(t<0 and s>0 and min(127,s)!=u for s,t,u in zip(x,m,y))
        if j==0:assert not any(y) and witnesses>0
        if j==2:assert all(v==127 for v in y) and x[0]+m[0]==254
        if j==3:assert not any(y) and x[0]+m[0]==-256
        d=ROOT/name/f'job{j}';d.mkdir(parents=True,exist_ok=True)
        for fn,values,bits in [('input',x,8),('weight1',w1,8),('weight2',w2,8),('bias1',b1,32),('bias2',b2,32),('acc1',acc1,32),('acc2',acc2,32),('middle',a,8),('main',m,8),('output',y,8)]:save(d/(fn+'.hex'),values,bits)
        records.append(dict(job=j,c=c,h=h,outputs=len(y),terms_per_conv=c*h*h*c*9,negative_main_witnesses=witnesses,add_min=min(s+t for s,t in zip(x,m)),add_max=max(s+t for s,t in zip(x,m))))
    (ROOT/name/'summary.json').write_text(json.dumps(records,indent=2)+'\n')
    print(f'REFERENCE PASS {name}: jobs={nj} outputs/block={c*h*h} terms/conv={c*h*h*c*9}')
if __name__=='__main__':make('small',2,4,4);make('full',16,32,2)
