"""Independent Fraction oracle: signed RNE plus three output ranges."""
from fractions import Fraction
from pathlib import Path
import random

def make():
    rng=random.Random(20261102)
    edges=[-(1<<63),(1<<63)-1,-4294967297,4294967297,-257,-255,-129,-127,-5,-3,-1,0,1,3,5,255]
    rows=[(v,s,m) for v in edges for s in (0,1,2,16,31) for m in range(3)]
    while len(rows)<2000:rows.append((rng.randrange(-(1<<48),1<<48),rng.randrange(32),rng.randrange(3)))
    out=Path('reference/e2b_v1/full_vectors/post');out.mkdir(exist_ok=True)
    columns={k:[] for k in ('wide','shift','mode','rounded','code')}
    for v,s,m in rows:
        n=round(Fraction(v,1<<s));lo=-(1<<31) if m==2 else (0 if m==1 else -128);hi=(1<<31)-1 if m==2 else 127
        for k,x in zip(columns,(v,s,m,n,min(hi,max(lo,n)))):columns[k].append(x)
    for k,values in columns.items():
        bits=64 if k in ('wide','rounded') else 32
        (out/(k+'.hex')).write_text(''.join(f'{v&((1<<bits)-1):0{bits//4}x}\n' for v in values),encoding='ascii',newline='\n')
    return len(rows)
if __name__=='__main__':print(make())
