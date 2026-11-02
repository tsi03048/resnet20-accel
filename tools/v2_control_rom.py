"""Static bit widths and precomputed geometry; never contains Golden values."""
import json
import math
from pathlib import Path

def generate():
    m=json.loads(Path('reference/e2b_v1/full_vectors/manifest.json').read_text())
    fields={'kind':2,'src':2,'dst':2,'skip':2,'relu':1,'stride2':1,'option_a':1,'ilog':3,'olog':3,'ih':6,'ci':7,'terms':10,'mask':10,'pbase':10,'last':14,'wbase':19,'main_n':31,'skip_n':31,'r':5}
    lines=['// Fixed E2-B descriptors. Precomputed geometry, no tensor outputs.','always_comb begin',"    decoded='0;decoded_pbase=0;decoded_wbase=0;",'    case(op_id)']
    for r in m['operations']:
        values={k:r[k] for k in ('kind','src','skip','relu','option_a','pbase','wbase','main_n','skip_n','r','ci','ih')}
        values.update(dst=r['dst'] if r['dst']<3 else 0,stride2=int(r['stride']==2),ilog=int(math.log2(r['ih'])),olog=int(math.log2(r['oh'])),terms=64 if r['kind'] in (2,3) else (r['ci']*9 if r['kind']==0 else 0),mask=r['oh']**2-1,last=r['nout']-1)
        lines.append(f"        5'd{r['id']}:begin // {r['name']}")
        for k,bits in fields.items():
            assert 0<=values[k]<1<<bits,(k,values[k])
            target="decoded_"+k if k in ("pbase","wbase") else "decoded."+k
            lines.append(f"            {target}={bits}'d{values[k]};")
        lines.append('        end')
    lines+=['        default:begin end','    endcase','end','']
    return '\n'.join(lines)
if __name__=='__main__':Path('rtl/full_e2b_fpga_v2/control_rom.svh').write_text(generate(),encoding='ascii',newline='\n')
