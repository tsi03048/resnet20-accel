"""Execute the real ARM ELF with explicit behavioral DMA/accelerator MMIO models.

This checks firmware/control ordering and error handling, not hardware timing,
vendor DMA RTL, DDR PHY or the CNN RTL (which has a separate Verilator test).
Optional dependencies: unicorn and pyelftools.
"""
import argparse,hashlib,json,struct
from pathlib import Path
from elftools.elf.elffile import ELFFile
from unicorn import Uc,UC_ARCH_ARM,UC_MODE_ARM,UC_HOOK_MEM_READ,UC_HOOK_MEM_WRITE
from unicorn.arm_const import UC_ARM_REG_CPSR,UC_CPU_ARM_CORTEX_A9
from tools.ps_dma_vectors import artifacts,ADDRESSES,RX,REPORT,verify

DMA=0x40400000;ACC=0x43c00000
def run(elf='build/ps_dma_software/app.elf',scenario='normal'):
    verify();packets,manifest=artifacts()
    uc=Uc(UC_ARCH_ARM,UC_MODE_ARM);uc.ctl_set_cpu_model(UC_CPU_ARM_CORTEX_A9)
    for address,size in ((0x00100000,0x00200000),(0x02000000,0x00300000),(REPORT,0x1000),(DMA,0x1000),(ACC,0x1000),(0xf8f00000,0x1000)):
        uc.mem_map(address,size)
    with open(elf,'rb') as f:
        parsed=ELFFile(f);entry=parsed.header.e_entry
        for s in parsed.iter_segments():
            if s.header.p_type=='PT_LOAD':uc.mem_write(s.header.p_paddr,s.data())
    for name,address in ADDRESSES.items():uc.mem_write(address,packets[name+'.bin'])
    uc.reg_write(UC_ARM_REG_CPSR,0x1d3)
    model=dict(stage=0,tag=0,prepared=False,busy=False,done=False,error=0,rx_words=0,tx_words=0,
        sample=0,rx_armed=False,polls=0,elapsed=0,mm2s=0,s2mm=0,aborts=0,terminal=None,
        dma_regs={0:0,4:1,0x30:0,0x34:1},starts=[],transfers=[],timer=0,timer_hi_reads=0)
    def set32(addr,value):uc.mem_write(addr,struct.pack('<I',value&0xffffffff))
    def reset_acc():
        model.update(stage=0,prepared=False,busy=False,done=False,error=0,rx_words=0,tx_words=0,polls=0)
    def complete():
        assert model['rx_armed'] and model['prepared'] is False
        scores=manifest['samples'][str(model['sample'])]['scores']
        words=[0x52323052,model['tag'],0,3 if model['sample']==0 else 8]+[v&0xffffffff for v in scores]+[265000000,0]
        if scenario=='bad_score':words[4]^=1
        if scenario=='stale_tag':words[1]^=1
        assert model['dma_regs'][0x48]==RX and model['dma_regs'][0x58]==64
        uc.mem_write(RX,struct.pack('<16I',*words))
        model.update(busy=False,done=True,tx_words=16,rx_armed=False)
        model['dma_regs'][0x34]=0x1002;model['s2mm']+=1
    def read(_uc,access,address,size,value,user):
        if DMA<=address<DMA+0x1000:
            reg=address-DMA
            if reg==0x34 and model['busy']:
                model['polls']+=1
                if model['polls']>=6:complete()
            set32(address,model['dma_regs'].get(reg,0))
        elif ACC<=address<ACC+0x1000:
            reg=address-ACC
            status=(int(model['done'])<<5)|(int(model['busy'])<<3)|(int(model['prepared'])<<2)|int(model['stage']==5)
            set32(address,{0:0x52323031,8:status,0x10:model['error'],0x14:model['rx_words'],0x18:model['tx_words']}.get(reg,0))
        elif address in (0xf8f00200,0xf8f00204):
            set32(address,model['timer']>>(32 if address==0xf8f00204 else 0))
            if address==0xf8f00204:
                model['timer_hi_reads']+=1
                if model['timer_hi_reads']%2==0:model['timer']+=20000000000 if scenario=='timeout' else 100
    def write(_uc,access,address,size,value,user):
        if address==REPORT+4 and (value==2 or value&0x80000000):model['terminal']=value;uc.emu_stop()
        if DMA<=address<DMA+0x1000:
            reg=address-DMA
            if reg in (0,0x30) and value&4:
                if model['busy']:model['aborts']+=1
                model.update(rx_armed=False,polls=0)
                model['dma_regs']={0:0,4:1,0x30:0,0x34:1}
            elif reg in (4,0x34):model['dma_regs'][reg]=model['dma_regs'].get(reg,0)&~(value&0x7000)
            else:
                model['dma_regs'][reg]=value
                if reg in (0,0x30):model['dma_regs'][reg+4]=2
                if reg==0x58:
                    assert value==64 and model['dma_regs'][0x48]==RX
                    model['rx_armed']=True;model['dma_regs'][0x34]=0
                if reg==0x28:
                    model['mm2s']+=1
                    if scenario=='dma_decode':model['dma_regs'][4]=0x40;return
                    if scenario=='timeout':model['dma_regs'][4]=0;return
                    assert value<(1<<23) and model['dma_regs'][0x18]%4==0
                    raw=bytes(uc.mem_read(model['dma_regs'][0x18],value));magic,kind,count=struct.unpack('<III',raw[:12])
                    assert magic==0x52323031 and kind==model['stage'] and len(raw)==(count+3)*4
                    names=[name for name,data in packets.items() if data==raw]
                    assert len(names)==1,'DMA delivered bytes outside frozen package'
                    if kind==0:model['sample']=int(names[0][5])
                    model['transfers'].append(dict(kind=kind,bytes=value,address=model['dma_regs'][0x18]))
                    model['stage']+=1;model['rx_words']+=count;model['prepared']=model['stage']==5
                    model['dma_regs'][4]=0x1002
        elif ACC<=address<ACC+0x1000:
            reg=address-ACC
            if reg==0x0c:model['tag']=value
            if reg==4:
                if value==4:reset_acc()
                elif value==1:assert not model['busy'];reset_acc()
                elif value==2:
                    assert model['prepared'] and model['rx_armed'] and model['rx_words']==273502
                    model['starts'].append(model['sample']);model.update(prepared=False,busy=True,polls=0)
                else:raise AssertionError('Invalid control command')
    uc.hook_add(UC_HOOK_MEM_READ,read);uc.hook_add(UC_HOOK_MEM_WRITE,write)
    uc.emu_start(entry,0xffffffff,count=2000000)
    state=model['terminal'];raw=bytes(uc.mem_read(REPORT,72*4));words=struct.unpack('<72I',raw)
    if scenario=='normal':
        assert state==2 and words[3]==4,(state,words[:8])
        assert model['starts']==[0,1,0,0,1] and model['mm2s']==25 and model['s2mm']==4 and model['aborts']==1
        for i,cid in enumerate((0,1,0,1)):
            row=words[8+16*i:24+16*i]
            assert row[0]==0x52323052 and row[1]==0xc9000000+i and row[2]==0
            assert row[3]==manifest['samples'][str(cid)]['prediction']
            assert list(row[4:14])==[x&0xffffffff for x in manifest['samples'][str(cid)]['scores']]
    else:
        expected={'dma_decode':0x20,'timeout':0x30,'bad_score':0x51,'stale_tag':0x50}[scenario]
        assert state==0x80000000|expected,(scenario,state,words[:8])
    return dict(scenario=scenario,status='PASS',reported_state=state,completed_jobs=words[3],mm2s_transfers=model['mm2s'],s2mm_transfers=model['s2mm'],aborted_jobs=model['aborts'])

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--elf',default='build/ps_dma_software/app.elf');args=p.parse_args()
    results=[run(args.elf,s) for s in ('normal','dma_decode','timeout','bad_score','stale_tag')]
    sources=['board/zedboard/ps_dma/software/'+x for x in ('start.S','link.ld','main.c','vectors.h')]+['tools/ps_dma_vectors.py','tools/ps_dma_arm_emulate.py']
    record=dict(status='PASS',scope='Real ARM ELF execution in Unicorn Cortex-A9; behavioral DMA/core MMIO models, not RTL or board execution',
        elf_sha256=hashlib.sha256(Path(args.elf).read_bytes()).hexdigest(),cases=results,source_sha256={x:hashlib.sha256(Path(x).read_bytes()).hexdigest() for x in sources})
    Path('results/ps_dma_arm_emulation.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps(record,indent=2))
