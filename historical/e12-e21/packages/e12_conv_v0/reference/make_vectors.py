"""Generate the E3/E11 diagnostic fixture; standard Python only."""
import json
from pathlib import Path

def rne4(n):
    sign=-1 if n<0 else 1
    q,r=divmod(abs(n),4)
    return sign*(q+int(r>2 or (r==2 and q%2!=0)))

root=Path(__file__).resolve().parent
x=list(range(1,17))+[2]*16
w=[1]*9+[-1]*9+[-1]*9+[2]*9
b=[3,-1]
acc=[]
for co in range(2):
    for oy in range(2):
        for ox in range(2):
            value=b[co]
            for ci in range(2):
                for ky in range(3):
                    for kx in range(3):
                        value+=x[(ci*4+oy+ky)*4+ox+kx]*w[co*18+ci*9+ky*3+kx]
            acc.append(value)
assert acc==[39,48,75,84,-19,-28,-55,-64]
qy=[max(-128,min(127,rne4(v))) for v in acc]
assert qy==[10,12,19,21,-5,-7,-14,-16]
for name,values in [('input.hex',x),('weight.hex',w)]:
    (root/name).write_text(''.join(f'{v&255:02x}\n' for v in values))
(root/'expected.json').write_text(json.dumps({'contract':'DIAG_2X4X4_VALID_V0_PROPOSAL',
    'x_chw':[2,4,4],'weight_oihw':[2,2,3,3],'output_chw':[2,2,2],
    'terms':144,'bias':b,'acc':acc,'relu_off':qy,'relu_on':[max(0,v) for v in qy]},indent=2)+'\n')
print('REFERENCE PASS: 144 terms, 8 outputs')
