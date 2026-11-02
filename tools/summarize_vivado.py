"""Preserve raw Vivado evidence and distinguish synthesis estimates from routed STA."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

def read(path):
    return Path(path).read_text(encoding='utf-8-sig',errors='replace')

def utilization(text):
    aliases={'lut':('Slice LUTs','CLB LUTs'),'ff':('Slice Registers','CLB Registers'),'bram36_equivalent':('Block RAM Tile',),'dsp':('DSPs',)}
    result={}
    for role,names in aliases.items():
        for line in text.splitlines():
            cols=[s.strip() for s in line.split('|')]
            if len(cols)<6 or cols[1].rstrip('* ').strip() not in names:continue
            try:
                numbers=[float(x.replace(',','')) for x in cols[2:] if x]
                used,fixed,available,percent=numbers[0],numbers[1],numbers[-2],numbers[-1]
            except ValueError:continue
            if available<=0 or abs(used/available*100-percent)>0.03:raise ValueError('Inconsistent utilization columns: '+line)
            result[role]=dict(used=used,available=available,percent=percent,fits=used<=available)
            break
    if set(result)!=set(aliases):raise ValueError('Incomplete utilization report: '+','.join(sorted(set(aliases)-set(result))))
    for line in text.splitlines():
        cols=[s.strip() for s in line.split('|')]
        if len(cols)>6 and cols[1]=='LUT as Memory':
            nums=[float(x.replace(',','')) for x in cols[2:] if x]
            result['lut_as_memory']=dict(used=nums[0],available=nums[-2],percent=nums[-1],fits=nums[0]<=nums[-2]);break
    return result

def timing(text):
    lines=text.splitlines();values=None
    for i,line in enumerate(lines):
        if 'WNS(ns)' in line and 'TNS(ns)' in line and 'WHS(ns)' in line:
            for candidate in lines[i+1:i+7]:
                words=candidate.split()
                if len(words)>=12 and re.fullmatch(r'-?\d+(?:\.\d+)?',words[0]):
                    values=words;break
            break
    if values is None:raise ValueError('No complete timing summary numbers')
    nums=[float(x) for x in values[:12]]
    # An empty design/no timed endpoints must never count as a timing pass.
    if nums[3]<=0:raise ValueError('No setup endpoints analyzed')
    return dict(wns_ns=nums[0],tns_ns=nums[1],setup_failing_endpoints=int(nums[2]),setup_endpoints=int(nums[3]),
        whs_ns=nums[4],ths_ns=nums[5],hold_failing_endpoints=int(nums[6]),hold_endpoints=int(nums[7]),
        wpws_ns=nums[8],tpws_ns=nums[9],pulse_failing_endpoints=int(nums[10]),pulse_endpoints=int(nums[11]),
        numeric_constraints_met=all(nums[i]>=0 for i in (0,1,4,5,8,9)) and all(nums[i]==0 for i in (2,6,10)))

def summarize(run,output='results/vivado_full'):
    run=Path(run);output=Path(output);reports=run/'output/reports'
    manifest=json.loads(read(run/'launch_manifest.json'))
    if manifest['part']!='xc7z020clg484-1' or manifest['top']!='full_model' or manifest['mode']!='out_of_context':raise ValueError('Unexpected synthesis target')
    current_matches={}
    for name,digest in manifest['source_sha256'].items():
        archived=run/'source_snapshot'/name
        source=archived if archived.exists() else Path(name)
        if hashlib.sha256(source.read_bytes()).hexdigest()!=digest:raise ValueError('Measured source differs from run manifest: '+name)
        current_matches[name]=Path(name).exists() and hashlib.sha256(Path(name).read_bytes()).hexdigest()==digest
    status=dict(line.split('=',1) for line in read(reports/'status.txt').splitlines() if '=' in line)
    cancellation=run/'agent_cancellation.json'
    if cancellation.exists():status=dict(status='CANCELLED_BY_AGENT',phase=status.get('phase'),detail=json.loads(read(cancellation))['reason'])
    log=read(run/'vivado.log')
    if not re.search(r'Got license for feature.*Synthesis',log):raise ValueError('No evidence synthesis was licensed and started')
    output.mkdir(parents=True,exist_ok=True)
    shutil.copytree(reports,output/'reports',dirs_exist_ok=True)
    shutil.copy2(run/'vivado.log',output/'vivado.log');shutil.copy2(run/'launch_manifest.json',output/'launch_manifest.json')
    if cancellation.exists():shutil.copy2(cancellation,output/'agent_cancellation.json')
    if (run/'source_snapshot').exists():shutil.copytree(run/'source_snapshot',output/'source_snapshot',dirs_exist_ok=True)
    data={}
    for phase in ('post_synth','post_route'):
        up=reports/(phase+'_utilization.rpt');tp=reports/(phase+'_timing_summary.rpt')
        if up.exists() and tp.exists():
            data[phase]=dict(resources=utilization(read(up)),timing=timing(read(tp)))
            data[phase]['all_reported_resources_fit']=all(v['fits'] for v in data[phase]['resources'].values())
    errors=re.findall(r'^ERROR:.*$',log,re.M)
    critical=re.findall(r'^CRITICAL WARNING:.*$',log,re.M)
    warnings=re.findall(r'^WARNING:.*$',log,re.M)
    unconstrained=[]
    # Keep detailed raw check_timing evidence; do not infer completeness from WNS alone.
    for phase in data:
        cp=reports/(phase+'_check_timing.rpt')
        checks=read(cp) if cp.exists() else ''
        counts={k:int(v) for k,v in re.findall(r'checking\s+(\w+)\s*\((\d+)\)',checks,re.I)}
        data[phase]['check_timing_counts']=counts
        data[phase]['constraint_checks_clean']=bool(counts) and all(v==0 for k,v in counts.items() if k not in ('partial_input_delay','partial_output_delay'))
        # partial I/O-delay diagnostics must also be reviewed, never silently ignored.
        data[phase]['all_check_counts_zero']=bool(counts) and all(v==0 for v in counts.values())
    routed='post_route' in data and status.get('status')=='COMPLETE' and manifest['action']=='route'
    final='post_route' if routed else ('post_synth' if 'post_synth' in data else None)
    verdict='NOT_MEASURED'
    if final:
        x=data[final]
        if not x['all_reported_resources_fit']:verdict='RESOURCE_OVERFLOW'
        elif not x['timing']['numeric_constraints_met']:verdict='TIMING_FAILED'
        elif not x['all_check_counts_zero']:verdict='CONSTRAINT_REVIEW_REQUIRED'
        else:verdict='ROUTED_CORE_PASS' if routed else 'SYNTHESIS_ESTIMATE_ONLY'
    result=dict(scope='full_model core OOC only; no board pins, PS/DDR/DMA, bitstream or physical board test',variant=manifest.get('variant','baseline'),
        tool=read(reports/'environment.txt').strip(),part=manifest['part'],top=manifest['top'],clock_period_ns=10.0,
        interface_assumptions=dict(input_max_ns=2.0,input_min_ns=0.0,output_max_ns=2.0,output_min_ns=0.0),
        run_name=run.name,status=status,verdict=verdict,synthesis_reports_present='post_synth' in data,routed_reports_present=routed,
        synthesis_status='COMPLETE' if 'post_synth' in data else 'NOT_COMPLETED',
        placement_status='FAILED' if status.get('phase')=='placement' and status.get('status')=='FAILED' else ('COMPLETE' if routed else 'NOT_COMPLETED'),
        routing_status='COMPLETE' if routed else 'NOT_RUN',
        measurements=data,errors=errors,critical_warnings=critical,warnings=warnings,source_sha256=manifest['source_sha256'],current_source_matches=current_matches,
        report_sha256={p.relative_to(output).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.rglob('*')) if p.is_file() and p.name!='summary.json'},
        limitations='Post-synthesis timing is an estimate; passing simulation is not resource fit. No Fmax/FPS or board timing claim.')
    (output/'summary.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--output',default='results/vivado_full');args=p.parse_args()
    print(json.dumps(summarize(args.run,args.output),indent=2))
