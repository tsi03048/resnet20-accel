"""Generate/verify little-endian DDR packets from the frozen E2-B package."""
import argparse,hashlib,json,struct
from pathlib import Path
import numpy as np
from tools.full_vectors import expected

ROOT=Path('reference/ps_dma_v1')
ADDRESSES={'input0':0x02000000,'input1':0x02004000,'weight':0x02010000,'bias':0x02120000,'multiplier':0x02124000,'shift':0x02128000}
RX=0x02200000;REPORT=0x03000000
def artifacts():
    m,_,constants,cases,cm=expected()
    values={'input0':(0,cases['0']['input'][0]),'input1':(0,cases['1']['input'][0])}
    values.update({name:(kind,constants[name][0]) for kind,name in enumerate(('weight','bias','multiplier','shift'),1)})
    data={};rows=[]
    for name,(kind,array) in values.items():
        # Native INT8 loader wants an unsigned byte in the low lane, not sign extension.
        a=array.reshape(-1).astype(np.int64)
        if kind<=1:a=a &255
        body=(a&0xffffffff).astype('<u4').tobytes()
        packet=struct.pack('<III',0x52323031,kind,a.size)+body
        data[name+'.bin']=packet
        rows.append(dict(name=name,file=name+'.bin',kind=kind,payload_words=int(a.size),bytes=len(packet),ddr_address=ADDRESSES[name],sha256=hashlib.sha256(packet).hexdigest()))
    intervals=sorted((r['ddr_address'],r['ddr_address']+r['bytes']) for r in rows)+[(RX,RX+64),(REPORT,REPORT+512)]
    intervals.sort();assert all(b<=c for (_,b),(c,_) in zip(intervals,intervals[1:]))
    manifest=dict(package=m['semantic_sha256'],format='little-endian uint32; [0x52323031,kind,count,payload...]; one DMA TLAST per packet',packets=rows,
        accelerator_base=0x43c00000,dma_base=0x40400000,rx_address=RX,rx_bytes=64,report_address=REPORT,report_words=72,
        samples=cm,normal_order=[0,1,0],board_recovery_order=[0,1,0,1],payload_words_per_job=273502,mm2s_bytes_per_job=1094068)
    return data,manifest

def header(m):
    lines=['/* Generated from frozen E2-B; Golden scores are PS-side checks only. */','#ifndef PS_DMA_VECTORS_H','#define PS_DMA_VECTORS_H','#include <stdint.h>',
        '#define ACCEL_BASE 0x43c00000u','#define DMA_BASE 0x40400000u',f'#define RX_BASE 0x{RX:08x}u',f'#define REPORT_BASE 0x{REPORT:08x}u',
        'struct packet { uint32_t address, bytes; };','static const struct packet input_packets[2] = {']
    for r in m['packets'][:2]:lines.append(f'    {{0x{r["ddr_address"]:08x}u,{r["bytes"]}u}},')
    lines+=['};','static const struct packet constants[4] = {']
    for r in m['packets'][2:]:lines.append(f'    {{0x{r["ddr_address"]:08x}u,{r["bytes"]}u}},')
    lines+=['};','static const int32_t expected_scores[2][10] = {']
    for cid in ('0','1'):lines.append('    {'+','.join(str(v) for v in m['samples'][cid]['scores'])+'},')
    lines+=['};','static const uint32_t expected_prediction[2]={3u,8u};','#endif','']
    return '\n'.join(lines)

def export():
    data,m=artifacts();ROOT.mkdir(parents=True,exist_ok=True)
    for name,raw in data.items():(ROOT/name).write_bytes(raw)
    (ROOT/'manifest.json').write_text(json.dumps(m,indent=2)+'\n',encoding='utf-8',newline='\n')
    Path('board/zedboard/ps_dma/software/vectors.h').write_text(header(m),encoding='ascii',newline='\n')
    script='set packet_downloads {\n'+''.join('    {'+r['file']+' '+hex(r['ddr_address'])+'}\n' for r in m['packets'])+'}\n'
    (ROOT/'load_packets.tcl').write_text(script,encoding='ascii',newline='\n')
    return m

def verify():
    data,m=artifacts()
    assert json.loads((ROOT/'manifest.json').read_text())==m
    for name,raw in data.items():assert (ROOT/name).read_bytes()==raw,name
    assert Path('board/zedboard/ps_dma/software/vectors.h').read_text()==header(m)
    return dict(status='PASS',packets=len(data),payload_words_per_job=273502,mm2s_bytes_per_job=1094068,rx_bytes=64,package=m['package'])
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--export',action='store_true');args=p.parse_args()
    if args.export:export()
    print(json.dumps(verify(),indent=2))
