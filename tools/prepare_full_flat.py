"""Mechanical 3-bank array flattening; numeric logic and FSM remain unchanged.

Generates a separately named source set and testbench. Never edits the tested v1.
"""
from pathlib import Path
import hashlib
import json

BASE='rtl/full_e2b_v1/full_model.sv'
BASE_SHA='530d6a9d42a0e5263afd4b28223c67a95e5af28607b84756cee64cc4859dccdc'

def generate():
    p=Path(BASE);raw=p.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=BASE_SHA:raise ValueError('Baseline RTL differs; review flattening before regeneration')
    text=raw.decode('ascii')
    replacements={
        'act_mem[0:2][0:16383]':'act_mem_flat[0:49151]',
        'act_mem[0][cfg_addr[13:0]]':"act_mem_flat[{2'd0,cfg_addr[13:0]}]",
        'act_mem[d_src][x_address]':'act_mem_flat[(d_src<<14)+x_address]',
        'act_mem[d_skip][skip_address]':"act_mem_flat[(int'(d_skip)<<14)+skip_address]",
        'act_mem[d_src][out_idx]':"act_mem_flat[(d_src<<14)+int'(out_idx)]",
        'act_mem[d_dst][out_idx]':"act_mem_flat[(d_dst<<14)+int'(out_idx)]",
    }
    for old,new in replacements.items():
        if old not in text:raise ValueError('Missing substitution: '+old)
        text=text.replace(old,new)
    if 'act_mem[' in text:raise ValueError('Unconverted feature memory access')
    tb=Path('tb/full_e2b_v1/tb_full.sv').read_text()
    for old,new in {
        'dut.act_mem[src[op]][i]':'dut.act_mem_flat[src[op]*16384+i]',
        'dut.act_mem[skip[op]][i]':'dut.act_mem_flat[skip[op]*16384+i]',
        'dut.act_mem[0][i]':'dut.act_mem_flat[i]',
    }.items():
        if old not in tb:raise ValueError('Missing TB substitution')
        tb=tb.replace(old,new)
    if 'dut.act_mem[' in tb:raise ValueError('Unconverted TB probe')
    outputs={'rtl/full_e2b_flat_v1/full_model.sv':text,'tb/full_e2b_flat_v1/tb_full.sv':tb}
    for name,value in outputs.items():
        out=Path(name);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(value,encoding='ascii',newline='\n')
    meta=dict(baseline=BASE,baseline_sha256=BASE_SHA,transformation='flat address = bank*16384 + offset; all numeric/FSM logic unchanged',generated_sha256={k:hashlib.sha256(v.encode()).hexdigest() for k,v in outputs.items()})
    Path('rtl/full_e2b_flat_v1/manifest.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='ascii',newline='\n')
    return meta
if __name__=='__main__':print(json.dumps(generate(),indent=2))
