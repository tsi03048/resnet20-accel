import json,random

def addresses(cin,cout,h,stride):
 o=(h-1)//stride+1;total=valid=pad=0
 for co in range(cout):
  for oy in range(o):
   for ox in range(o):
    for ci in range(cin):
     for ky in range(3):
      for kx in range(3):
       iy,ix=oy*stride+ky-1,ox*stride+kx-1
       index=total//(cin*9);k=total%(cin*9)
       assert index==(co*o+oy)*o+ox
       assert k==ci*9+ky*3+kx
       if 0<=iy<h and 0<=ix<h:
        a=(ci*h+iy)*h+ix;assert 0<=a<cin*h*h;valid+=1
       else:pad+=1
       total+=1
 return dict(outputs=cout*o*o,K=cin*9,terms=total,valid_reads=valid,padding=pad)

def skip(cin,h):
 cout=cin*2;o=h//2;offset=cin//2
 # Independent materialized reference: spatial slicing then zero channel concatenation.
 x=list(range(cin*h*h));s=[0]*(offset*o*o)
 for ci in range(cin):
  for yy in range(0,h,2):
   for xx in range(0,h,2):s.append(x[(ci*h+yy)*h+xx]+1)
 s += [0]*(offset*o*o)
 reads=zeros=0
 for i,v in enumerate(s):
  co=i//(o*o);oy=(i//o)%o;ox=i%o
  if offset<=co<offset+cin:
   a=((co-offset)*h+2*oy)*h+2*ox
   assert v==x[a]+1;reads+=1
  else:assert v==0;zeros+=1
 return dict(outputs=len(s),reads=reads,zero_tokens=zeros)

def q(a,relu):
 v,r=divmod(abs(a),4);v+=r>2 or (r==2 and v%2)
 if a<0:v=-v
 if relu:v=max(0,v)
 return min(127,max(-128,v))
def conv(x,w,b,ci,co,h,stride,relu,materialized=False):
 o=(h-1)//stride+1;y=[]
 if materialized:
  p=[0]*(ci*(h+2)*(h+2))
  for c in range(ci):
   for yy in range(h):
    for xx in range(h):p[(c*(h+2)+yy+1)*(h+2)+xx+1]=x[(c*h+yy)*h+xx]
 for c in range(co):
  for yy in range(o):
   for xx in range(o):
    a=b[c]
    for k in range(ci*9):
     ic=k//9;ky=(k%9)//3;kx=k%3;iy=yy*stride+ky-1;ix=xx*stride+kx-1
     if materialized:v=p[(ic*(h+2)+yy*stride+ky)*(h+2)+xx*stride+kx]
     else:v=x[(ic*h+iy)*h+ix] if 0<=iy<h and 0<=ix<h else 0
     a+=v*w[c*ci*9+k]
    y.append(q(a,relu))
 return y
rng=random.Random(15015)
for case in range(100):
 x=[rng.randint(-12,12) for _ in range(32)];w1=[rng.randint(-3,3) for _ in range(72)];w2=[rng.randint(-3,3) for _ in range(144)];b1=[rng.randint(-16,16) for _ in range(4)];b2=[rng.randint(-16,16) for _ in range(4)]
 a=conv(x,w1,b1,2,4,4,2,True);aa=conv(x,w1,b1,2,4,4,2,True,True);assert a==aa
 m=conv(a,w2,b2,4,4,2,1,False);mm=conv(aa,w2,b2,4,4,2,1,False,True);assert m==mm
 s=[0]*4+[x[(c*4+yy)*4+xx] for c in range(2) for yy in (0,2) for xx in (0,2)]+[0]*4
 y=[min(127,max(0,u+v)) for u,v in zip(m,s)];assert len(y)==16
 # Address-driven skip compared with spatially sliced construction.
 for i in range(16):
  c=i//4;yy=(i//2)%2;xx=i%2
  sk=x[((c-1)*4+yy*2)*4+xx*2] if 1<=c<3 else 0
  assert y[i]==min(127,max(0,mm[i]+sk))
records=[]
for cin,h in [(2,4),(16,32),(32,16)]:
 co=2*cin;o=h//2
 records.append(dict(cin=cin,cout=co,h=h,conv1=addresses(cin,co,h,2),conv2=addresses(co,co,o,1),shortcut=skip(cin,h)))
assert ((8-8)*32+2*1)*32+2*2==68
print(json.dumps(dict(status='PASS',small_random_blocks=100,small_outputs_compared=1600,full_scope='address/tag/range/padding/shortcut enumeration only; not full numeric RTL',shapes=records),indent=2))

