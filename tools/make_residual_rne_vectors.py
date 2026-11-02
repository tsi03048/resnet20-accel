"""Exact Fraction oracle covers signed Conv2 and wide scale-aligned Add."""
from fractions import Fraction
from pathlib import Path
import random


def generate(path="results/residual_rtl/rne_vectors.txt"):
    rng=random.Random(20261102)
    edges=[-(1<<63),-(1<<63)+1,-(1<<40),-259,-257,-7,-5,-3,-1,0,1,3,5,7,255,(1<<63)-1]
    vectors=[(v,s,r) for v in edges for s in (0,1,2,8,31) for r in (0,1)]
    vectors += [(rng.randint(-(1<<63),(1<<63)-1),rng.randrange(32),rng.randrange(2)) for _ in range(1840)]
    target=Path(path);target.parent.mkdir(parents=True,exist_ok=True)
    with target.open("w",encoding="ascii",newline="\n") as f:
        for wide,shift,relu in vectors:
            rounded=round(Fraction(wide,1<<shift))
            code=min(127,max(0 if relu else -128,rounded))
            f.write(f"{wide} {shift} {relu} {rounded} {code}\n")
    return len(vectors)


if __name__=="__main__": print("Residual RNE vectors:",generate())
