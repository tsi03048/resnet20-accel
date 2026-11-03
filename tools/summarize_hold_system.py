"""Collect complete-system Vivado evidence without treating it as a board test."""
import argparse,hashlib,json,re,shutil,zipfile
from pathlib import Path
from tools.summarize_vivado import read,utilization,timing,route_status
from tools.hold_report_checks import verify_views

def summarize(run,output='results/ps_dma_hold_system'):
    run=Path(run);out=Path(output);manifest=json.loads(read(run/'launch_manifest.json'))
    assert manifest['mode']=='complete_system' and manifest['top']=='system_wrapper' and manifest['part']=='xc7z020clg484-1'
    for name,digest in manifest['source_sha256'].items():assert hashlib.sha256((run/'source_snapshot'/name).read_bytes()).hexdigest()==digest,name
    implementation_log=Path(manifest['stage'])/'build/zedboard_ps_hold/project/zedboard_ps_hold.runs/impl_1/runme.log'
    assert implementation_log.exists(),'Keep the stage directory until evidence collection'
    impl=read(implementation_log)
    assert 'HOLD_MARGIN_APPLIED clock=clk_fpga_0 period_ns=10.000 user_hold_uncertainty_ns=0.100' in impl
    reports=run/'output/reports';status=dict(line.split('=',1) for line in read(reports/'status.txt').splitlines() if '=' in line)
    config=read(reports/'system_config.txt');clocks=read(reports/'clocks.rpt')
    for expected in ('PCW_FPGA0_PERIPHERAL_FREQMHZ=100.000000','PCW_USE_M_AXI_GP0=1','PCW_USE_S_AXI_HP0=1','c_include_sg=0','c_sg_length_width=23',
                     '/ps7/Data/SEG_accel_reg0 0x43C00000 0x00001000','/ps7/Data/SEG_dma_Reg 0x40400000 0x00010000','HP0_DDR_LOWOCM 0x00000000 0x20000000'):
        assert expected in config,expected
    assert re.search(r'clk_fpga_0\s+10\.000',clocks)
    measurements={}
    for phase in ('post_synth','post_route','post_route_nominal'):
        checks={k:int(v) for k,v in re.findall(r'checking\s+(\w+)\s*\((\d+)\)',read(reports/(phase+'_check_timing.rpt')),re.I)}
        assert len(checks)==12
        measurements[phase]=dict(resources=utilization(read(reports/(phase+'_utilization.rpt'))),timing=timing(read(reports/(phase+'_timing_summary.rpt'))),check_counts=checks,all_check_counts_zero=not any(checks.values()))
    drc=read(reports/'post_route_drc.rpt')
    rules=[dict(rule=m[0],severity=m[1],count=int(m[2])) for m in re.findall(r'\|\s*(\S+)\s*\|\s*(Error|Critical Warning|Warning|Advisory)\s*\|[^\n]*?\|\s*(\d+)\s*\|',drc)]
    errors=[r for r in rules if r['severity'] in ('Error','Critical Warning')]
    route=route_status(read(reports/'post_route_status.rpt'))
    final=measurements['post_route']
    passed=status['status']=='COMPLETE' and final['timing']['numeric_constraints_met'] and final['all_check_counts_zero'] and all(x['fits'] for x in final['resources'].values()) and route['complete'] and not errors
    guard=measurements['post_route']['timing'];nominal=measurements['post_route_nominal']['timing']
    guarded_xdc=read(reports/'guarded_constraints.xdc');nominal_xdc=read(reports/'nominal_constraints.xdc')
    verify_views(guard,nominal,guarded_xdc,nominal_xdc)
    passed=passed and guard['whs_ns']>=0 and nominal['whs_ns']>=0.100 and nominal['numeric_constraints_met']
    artifacts={} 
    for name in ('system.bit','system.xsa','system_post_route.dcp','ps7_init.tcl','system_export.tcl'):
        p=run/'output'/name;assert p.is_file() and p.stat().st_size>0
        artifacts[name]=dict(bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),location_in_practice_zip='platform_hold/output/'+name)
    with zipfile.ZipFile(run/'output/system.xsa') as archive:
        bits=[n for n in archive.namelist() if n.endswith('.bit')];assert len(bits)==1
        assert archive.read(bits[0])==(run/'output/system.bit').read_bytes(),'XSA/bit mismatch'
    out.mkdir(parents=True,exist_ok=True)
    for folder in ('reports','source_snapshot'):
        source=reports if folder=='reports' else run/folder
        shutil.copytree(source,out/folder,dirs_exist_ok=True)
    shutil.copy2(implementation_log,out/'reports/implementation.log')
    for name in ('launch_manifest.json','vivado.log'):shutil.copy2(run/name,out/name)
    result=dict(status='COMPLETE',verdict='ROUTED_SYSTEM_TIMING_PASS_WITH_IP_WARNINGS' if passed and rules else ('ROUTED_SYSTEM_TIMING_PASS' if passed else 'SYSTEM_IMPLEMENTATION_FAILED'),
        scope='Complete PS7/DDR interfaces/GP0 control/HP0 AXI DMA system implementation; physical DDR training and board execution NOT_RUN',
        run_name=run.name,part=manifest['part'],top=manifest['top'],vivado='2025.1',clock_mhz=100,board_definition='Avnet ZedBoard 1.5, hardware revision D',
        hold_margin_policy=dict(user_hold_uncertainty_ns=0.100,nominal_user_hold_uncertainty_ns=0.0,setup_user_uncertainty_changed=False,post_route_phys_opt='ExploreWithAggressiveHoldFix'),
        xsa_bit_matches=True,measurements=measurements,route=route,drc_rules=rules,drc_errors=errors,binary_artifacts=artifacts,
        source_sha256=manifest['source_sha256'],current_source_matches={name:Path(name).exists() and hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest for name,digest in manifest['source_sha256'].items()},
        report_sha256={p.relative_to(out).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.rglob('*')) if p.is_file() and p.name!='summary.json'},
        limitations='Passing static timing/bitstream generation is not a physical PS/DDR/DMA execution. Vendor IP warnings are retained, not waived or downgraded; timing margin remains small.')
    (out/'summary.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    Path('results/ps_dma_hold_system_actual.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--output',default='results/ps_dma_hold_system');a=p.parse_args()
    r=summarize(a.run,a.output);print(json.dumps(dict(verdict=r['verdict'],route=r['route'],guarded_timing=r['measurements']['post_route']['timing'],nominal_timing=r['measurements']['post_route_nominal']['timing'],drc_rules=r['drc_rules']),indent=2))
