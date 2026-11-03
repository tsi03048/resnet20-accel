"""Reject mismatched guarded/nominal timing views and relaxed constraints."""
import re

def verify_views(guard,nominal,guarded_xdc,nominal_xdc):
    if abs(nominal['whs_ns']-guard['whs_ns']-0.100)>=0.002:
        raise ValueError('Hold budgets do not differ by 0.100 ns')
    if abs(nominal['wns_ns']-guard['wns_ns'])>=0.002:
        raise ValueError('Setup changed between views')
    if guard['whs_ns']<0 or guard['wns_ns']<0 or nominal['whs_ns']<0.100:
        raise ValueError('Timing or implementation margin failed')
    pattern=r'set_clock_uncertainty\s+-hold\s+([0-9.]+)'
    if [float(v) for v in re.findall(pattern,guarded_xdc)]!=[0.100]:
        raise ValueError('Expected exactly one 0.100 ns hold constraint')
    nominal_values=[float(v) for v in re.findall(pattern,nominal_xdc)]
    # write_xdc may retain the earlier 0.100 assignment followed by its zero
    # override. SDC executes them in order; the final assignment is effective.
    if nominal_values not in ([],[0.0],[0.100,0.0]):
        raise ValueError('Expected effective original-budget hold constraint')
    targets=lambda t:re.findall(pattern+r'\s+(\[get_clocks[^\n]+)',t)
    guarded_targets=targets(guarded_xdc)
    if len(guarded_targets)!=1 or any(t[1]!=guarded_targets[0][1] for t in targets(nominal_xdc)):
        raise ValueError('Hold constraints target different clocks')
    def canonical(text):
        return '\n'.join(x.strip() for x in text.splitlines() if x.strip() and not x.lstrip().startswith('#') and not re.match(pattern,x.strip()))
    if canonical(guarded_xdc)!=canonical(nominal_xdc):
        raise ValueError('Other constraints changed between views')
    return True
