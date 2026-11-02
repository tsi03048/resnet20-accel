"""Python unbounded integer oracle for signed products and their sum."""
from pathlib import Path
import random

def make():
    rng=random.Random(20261103);rows=[]
    for a in (-(1<<31),-127,-1,0,1,127,(1<<31)-1):
        for n in (0,1,1<<30,(1<<31)-1):
            for add in (0,1):rows.append((a,n,-a if a!=-(1<<31) else (1<<31)-1,n,add))
    while len(rows)<512:rows.append((rng.randrange(-(1<<31),1<<31),rng.randrange(1<<31),rng.randrange(-(1<<31),1<<31),rng.randrange(1<<31),rng.randrange(2)))
    root=Path('reference/e2b_v1/v2_mul');root.mkdir(exist_ok=True)
    columns={k:[] for k in ('a','n','b','m','add','result')}
    for a,n,b,m,add in rows:
        result=a*n+(b*m if add else 0);assert -(1<<63)<=result<1<<63
        for k,v in zip(columns,(a,n,b,m,add,result)):columns[k].append(v)
    for k,values in columns.items():
        bits=64 if k=='result' else 32
        (root/(k+'.hex')).write_text(''.join(f'{v&((1<<bits)-1):0{bits//4}x}\n' for v in values),encoding='ascii',newline='\n')
if __name__=='__main__':make()
