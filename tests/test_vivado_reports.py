"""Parser safety tests use small invented strings, never hardware result fixtures."""
import unittest
from tools.summarize_vivado import utilization,timing,route_status

class VivadoReportTests(unittest.TestCase):
    def test_unrouted_or_error_nets_never_pass(self):
        for full,errors,want in ((100,0,True),(99,0,False),(100,1,False)):
            text=f'# of routable nets.......... : 100 :\n# of fully routed nets.......... : {full} :\n# of nets with routing errors.......... : {errors} :'
            self.assertEqual(route_status(text)['complete'],want)
        with self.assertRaises(ValueError):route_status('')
    def test_resource_overflow_is_preserved(self):
        text='\n'.join(['| Slice LUTs* | 60000 | 0 | 53200 | 112.78 |','| Slice Registers | 100 | 0 | 106400 | 0.09 |','| Block RAM Tile | 140.5 | 0 | 140 | 100.36 |','| DSPs | 20 | 0 | 220 | 9.09 |'])
        result=utilization(text)
        self.assertFalse(result['lut']['fits']);self.assertFalse(result['bram36_equivalent']['fits'])
        self.assertTrue(result['ff']['fits'])

    def test_missing_resource_rejected(self):
        with self.assertRaisesRegex(ValueError,'Incomplete utilization'):utilization('| DSPs | 0 | 0 | 220 | 0 |')

    def test_prohibited_column_not_mistaken_for_capacity(self):
        text='\n'.join(['| Slice LUTs* | 100 | 0 | 0 | 53200 | 0.19 |','| Slice Registers | 100 | 0 | 0 | 106400 | 0.09 |','| Block RAM Tile | 16 | 0 | 0 | 140 | 11.43 |','| DSPs | 18 | 0 | 0 | 220 | 8.18 |'])
        result=utilization(text);self.assertEqual(result['lut']['available'],53200);self.assertEqual(result['dsp']['used'],18)

    def test_negative_slack_fails(self):
        text='WNS(ns) TNS(ns) TNS Failing Endpoints TNS Total Endpoints WHS(ns) THS(ns) THS Failing Endpoints THS Total Endpoints WPWS(ns) TPWS(ns) TPWS Failing Endpoints TPWS Total Endpoints\n---\n-2.345 -12.0 3 100 0.001 0 0 100 4.5 0 0 10'
        result=timing(text);self.assertFalse(result['numeric_constraints_met']);self.assertEqual(result['wns_ns'],-2.345)

    def test_empty_or_no_endpoints_never_pass(self):
        for text in ('','WNS(ns) TNS(ns) WHS(ns)\n0 0 0 0 0 0 0 0 0 0 0 0'):
            with self.assertRaises(ValueError):timing(text)
