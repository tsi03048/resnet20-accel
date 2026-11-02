"""Independent exact-rational oracle for the RTL postprocessor."""
from fractions import Fraction
from pathlib import Path
import random


def generate(path="results/stem_rtl/rne_vectors.txt"):
    rng=random.Random(20261102)
    vectors=[(a,n,s) for a in (-2147483648,-129,-7,-5,-3,-1,0,1,3,5,7,127,129,2147483647)
             for n in (0,1,77,2147483647) for s in (0,1,2,8,31)]
    vectors += [(rng.randint(-2147483648,2147483647),rng.randint(0,2147483647),rng.randint(0,31)) for _ in range(1000)]
    target=Path(path); target.parent.mkdir(parents=True,exist_ok=True)
    with target.open("w",encoding="ascii") as f:
        for a,n,s in vectors:
            rounded=round(Fraction(a*n,1<<s))
            f.write(f"{a} {n} {s} {rounded} {min(127,max(0,rounded))}\n")
    return len(vectors)


if __name__=="__main__": print("RNE vectors:",generate())
