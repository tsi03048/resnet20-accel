"""Check delivered evidence bytes; this does not run Vivado or RTL simulation."""
import hashlib,json
from pathlib import Path

ACTIVE=['rtl/full_e2b_v1/argmax10.sv']+['rtl/full_e2b_fpga_v2/'+x for x in (
    'full_model.sv','full_model_timed.sv','control_rom.svh','feature_ram.sv','sync_bram.sv','weight_bram.sv','mul_serial.sv','rne_serial.sv','input_hold.sv')]

def verify():
    v=json.loads(Path('results/vivado_v2_actual.json').read_text());f=json.loads(Path('results/full_fpga_v2_rtl_actual.json').read_text())
    p=Path('results/vivado_v2/final');archived=json.loads((p/'summary.json').read_text())
    if v!=archived:raise ValueError('Vivado summary copy differs')
    if v['verdict']!='ROUTED_CORE_PASS' or v['clock_period_ns']!=10.0 or v['part']!='xc7z020clg484-1':raise ValueError('Vivado target/verdict differs')
    for name,digest in v['report_sha256'].items():
        if hashlib.sha256((p/name).read_bytes()).hexdigest()!=digest:raise ValueError('Report/source snapshot changed: '+name)
    for name,digest in f['source_sha256'].items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest()!=digest:raise ValueError('Regression source changed: '+name)
    for name in ACTIVE:
        if v['source_sha256'][name]!=f['source_sha256'][name]:raise ValueError('Vivado and RTL regression used different source: '+name)
    if f['status']!='PASS' or f['normal_order']!=[0,1,0] or f['completed_jobs']!=5 or len(f['reset_cancellations'])!=7:raise ValueError('Incomplete RTL regression')
    t=v['measurements']['post_route']['timing']
    if not t['numeric_constraints_met'] or not v['route_checks']['complete'] or v['drc_error_rules'] or not v['measurements']['post_route']['all_check_counts_zero']:raise ValueError('Implementation checks did not pass')
    return dict(status='DELIVERED_EVIDENCE_VERIFIED',executed_vivado=False,executed_simulation=False,normal_order=f['normal_order'],completed_jobs=5,
        boundaries=61,reset_cancellations=7,clock_mhz=100,wns_ns=t['wns_ns'],whs_ns=t['whs_ns'],scope='OOC core; real board/system integration NOT_RUN')

if __name__=='__main__':print(json.dumps(verify(),indent=2))
