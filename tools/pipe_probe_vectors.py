"""Independent Python integer/Fraction oracle for four synthetic Stem pixels."""
import argparse,csv,hashlib,json
from fractions import Fraction
from pathlib import Path

ROOT=Path('reference/pipe_probe')
def expected():
    inputs=[i%8-4 for i in range(3072)];weights=[i%7-3 for i in range(27)]
    products=[];prefix=[];accs=[];codes=[];wides=[];rows=[]
    for x in range(4):
        acc=7
        for term in range(27):
            ic=term//9;ky=(term%9)//3;kx=term%3;iy=ky-1;ix=x+kx-1
            value=inputs[(ic*32+iy)*32+ix] if 0<=iy<32 and 0<=ix<32 else 0
            product=value*weights[term];before=acc;acc+=product
            products.append(product);prefix.append(acc);rows.append([x,term,product,before,acc])
        accs.append(acc);wides.append(acc*3);codes.append(max(0,min(127,round(Fraction(acc*3,4)))))
    values={'input.hex':(inputs,8),'weight.hex':(weights,8),'product.hex':(products,16),'prefix.hex':(prefix,32),'acc.hex':(accs,32),'code.hex':(codes,32),'wide.hex':(wides,64)}
    data={name:''.join(format(v&((1<<bits)-1),'0'+str(bits//4)+'x')+'\n' for v in vals).encode('ascii') for name,(vals,bits) in values.items()}
    return data,rows,accs,codes
def export():
    data,rows,accs,codes=expected();ROOT.mkdir(parents=True,exist_ok=True)
    for name,raw in data.items():(ROOT/name).write_bytes(raw)
    m=dict(scope='Synthetic initial Stem only; 4 pixels, 108 ordered MACs; not an actual CIFAR classification job',bias=7,N=3,shift=2,accs=accs,codes=codes,
        files={k:hashlib.sha256(v).hexdigest() for k,v in data.items()})
    (ROOT/'manifest.json').write_text(json.dumps(m,indent=2)+'\n',encoding='utf-8',newline='\n')
def verify(trace=None):
    data,rows,accs,codes=expected();m=json.loads((ROOT/'manifest.json').read_text())
    for name,raw in data.items():assert (ROOT/name).read_bytes()==raw and m['files'][name]==hashlib.sha256(raw).hexdigest(),name
    if trace:
        with open(trace,newline='') as f:
            reader=csv.reader(f);assert next(reader)==['pixel','term','product','acc_before','acc_after']
            got=[[int(x) for x in row] for row in reader]
        assert got==rows,'Independent ordered MAC/prefix CSV comparison failed'
    return dict(status='PASS',pixels=4,ordered_macs=108,accs=accs,codes=codes,independent_csv_checked=bool(trace),scope=m['scope'])
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--export',action='store_true');p.add_argument('--trace');p.add_argument('--output');a=p.parse_args()
    if a.export:export()
    r=verify(a.trace)
    if a.output:Path(a.output).write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps(r,indent=2))
