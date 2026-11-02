from pathlib import Path
import json,random
ROOT=Path(__file__).resolve().parent
def quant(a,relu,n=1,sh=2):
    a=a*n;den=1<<sh
    q,r=divmod(abs(a),den);q+=r*2>den or (r*2==den and q%2)
    if a<0:q=-q
    return min(127,max(0 if relu else -128,q))
def conv(x,w,b,cin,cout,h,stride,relu,nn,ss):
    o=h//stride;acc=[];out=[]
    for co in range(cout):
        for oy in range(o):
            for ox in range(o):
                a=b[co]
                for ci in range(cin):
                    for ky in range(3):
                        for kx in range(3):
                            iy,ix=oy*stride+ky-1,ox*stride+kx-1
                            if 0<=iy<h and 0<=ix<h:a+=x[(ci*h+iy)*h+ix]*w[((co*cin+ci)*3+ky)*3+kx]
                acc.append(a);out.append(quant(a,relu,nn[co],ss[co]))
    return acc,out
def save(p,a,bits):p.write_text(''.join(f'{v&((1<<bits)-1):0{bits//4}x}\n' for v in a))
def make(name,c,h,nj):
    d=2*c;o=h//2;records=[]
    for j in range(nj):
        varied=(j>=4 if name=='small' else j==1)
        v=1 if j>=4 else j
        n1=[1]*d;n2=[1]*d;nm=[1]*d;ns=[1]*d;s1=[2]*d;s2=[2]*d;sa=[0]*d
        if varied:
            for co in range(d):
                n1[co]=[1,3,77,2][co%4];s1[co]=[2,3,8,2][co%4]
                n2[co]=[3,1,2,77][co%4];s2[co]=[3,2,3,8][co%4]
                nm[co]=[1,2,3,1][co%4];ns[co]=[2,1,1,3][co%4];sa[co]=1

        r=random.Random(16016+v);x=[r.randint(-12,12) for _ in range(c*h*h)]
        b1=[0]*d;b2=[0]*d
        if v==1 or name!='small':
            w1=[r.randint(-2,2) for _ in range(c*d*9)];w2=[r.randint(-2,2) for _ in range(d*d*9)]
            b1=[r.randint(-16,16) for _ in range(d)];b2=[r.randint(-16,16) for _ in range(d)]
        else:
            w1=[0]*(c*d*9);w2=[0]*(d*d*9)
            for co in range(d):
                if c//2<=co<c//2+c:w1[(co*c+co-c//2)*9+4]=4
                w2[(co*d+co)*9+4]=-4 if j==0 else 4
            if j==2:x=[127]*len(x)
            if j==3:x=[-128]*len(x);b2=[-1024]*d
        a1,mid=conv(x,w1,b1,c,d,h,2,True,n1,s1);a2,main=conv(mid,w2,b2,d,d,o,1,False,n2,s2)
        # Materialize by channel concatenation and spatial slicing.
        skip=[0]*(c//2*o*o)+[x[(ci*h+yy)*h+xx] for ci in range(c) for yy in range(0,h,2) for xx in range(0,h,2)]+[0]*(c//2*o*o)
        y=[quant(u*nm[i//(o*o)]+v*ns[i//(o*o)],True,1,sa[i//(o*o)]) for i,(u,v) in enumerate(zip(main,skip))]
        witness=sum(u<0 and v>0 for u,v in zip(main,skip))
        if j==0 and name=='small':assert not any(y) and witness>0
        if j==2:assert max(u+v for u,v in zip(main,skip))==254
        if j==3:assert min(u+v for u,v in zip(main,skip))==-256
        p=ROOT/name/f'job{j}';p.mkdir(parents=True,exist_ok=True)
        for fn,a,bits in [('input',x,8),('weight1',w1,8),('weight2',w2,8),('bias1',b1,32),('bias2',b2,32),('acc1',a1,32),('acc2',a2,32),('middle',mid,8),('main',main,8),('skip',skip,8),('output',y,8)]:save(p/(fn+'.hex'),a,bits)
        for fn,values in [('n1',n1),('n2',n2),('nm',nm),('ns',ns),('s1',s1),('s2',s2),('sa',sa)]:save(p/(fn+'.hex'),values,32)
        if not varied:
            baseline=ROOT.parent/'baseline_e16'/name/f'job{j}'
            for fn in ['acc1','acc2','middle','main','skip','output']:
                assert (p/(fn+'.hex')).read_bytes()==(baseline/(fn+'.hex')).read_bytes(),fn
        records.append(dict(varied=varied,job=j,cin=c,cout=d,h=h,outputs=len(y),conv1_terms=len(y)*c*9,conv2_terms=len(y)*d*9,negative_main_witnesses=witness))
    (ROOT/name/'summary.json').write_text(json.dumps(records,indent=2)+'\n')
    print('REFERENCE PASS',name,records)
make('small',2,4,6);make('stage12',16,32,2);make('stage23',32,16,2)
