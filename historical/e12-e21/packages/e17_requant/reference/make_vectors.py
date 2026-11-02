from pathlib import Path
import random,json
R=Path(__file__).resolve().parent
def rne(v,s):
    q,r=divmod(abs(v),1<<s)
    q+=r*2>(1<<s) or (r*2==(1<<s) and q%2)
    return -q if v<0 else q
def code(a,b,n,m,s,add,relu,z):
    q=rne(a*n+(b*m if add else 0),s)+z
    if relu:q=max(z,q)
    return max(-128,min(127,q))
rows=[]
def add(a,b,n,m,s,mode=0,relu=0,z=0,ch=0):
    expected=code(a,b,n,m,s,mode,relu,z)
    rows.append([a,b,n,m,s,mode,relu,z,ch,len(rows)%17==16,expected])
for a in range(-1024,1025):add(a,0,1,0,2)
for s in [0,1,2,3,8,15,31]:
    for a in [-2147483648,2147483647,-15,-14,-10,-5,-2,-1,0,1,2,5,10,14,15]:
        for n in [0,1,77,65535]:add(a,-a if a!=-2147483648 else 2147483647,n,65535,s,1,0,-3)
for z in [-128,-5,0,7,127]:
    for a in [-516,-14,-10,0,10,14,512]:add(a,0,1,0,2,0,1,z)
# Scale-aligned Add and a single-round witness: 0.5+0.5 ->1.
add(8,4,1,2,0,1);add(1,1,1,1,1,1);add(15,0,77,0,8);add(5,0,1,0,3)
r=random.Random(17017)
table=[(1,2),(77,8),(3,1),(65535,31)]
for i in range(5000):
    ch=i%4;n,s=table[ch]
    add(r.randint(-2147483648,2147483647),r.randint(-2147483648,2147483647),n,r.randint(0,65535),s,i%2,(i//2)%2,r.randint(-128,127),ch)
assert code(8,4,1,2,0,1,0,0)==16
assert code(1,1,1,1,1,1,0,0)==1 and rne(1,1)+rne(1,1)==0
assert code(15,0,77,0,8,0,0,0)==5
assert code(5,0,1,0,3,0,0,0)==1 and rne(rne(5,1),2)==0
(R/'vectors.txt').write_text(''.join(' '.join(str(int(x)) for x in row)+'\n' for row in rows))
(R/'summary.json').write_text(json.dumps({'vectors':len(rows),'divide4_regression':2049,'channel_table':table,'seed':17017},indent=2)+'\n')
print('REFERENCE PASS vectors=',len(rows),'divide4_regression=2049 seed=17017')
