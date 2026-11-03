import unittest
from tools.hold_report_checks import verify_views

class HoldReportTests(unittest.TestCase):
    def setUp(self):
        self.guard=dict(whs_ns=0.019,wns_ns=0.972)
        self.nominal=dict(whs_ns=0.119,wns_ns=0.972)
        self.a='create_clock -period 10.0 [get_ports clk]\nset_clock_uncertainty -hold 0.100 [get_clocks clk]\n'
        self.b=self.a.replace('-hold 0.100','-hold 0.000')
    def test_consistent_two_budgets(self):
        self.assertTrue(verify_views(self.guard,self.nominal,self.a,self.b))
    def test_comment_dates_are_not_constraints(self):
        self.assertTrue(verify_views(self.guard,self.nominal,'# Date: a\n'+self.a,'# Date: b\n'+self.b))
    def test_vivado_omitted_zero_default(self):
        self.assertTrue(verify_views(self.guard,self.nominal,self.a,self.b.splitlines()[0]+'\n'))
    def test_vivado_records_sequential_zero_override(self):
        self.assertTrue(verify_views(self.guard,self.nominal,self.a,self.a+self.b.splitlines()[1]+'\n'))
    def test_override_on_another_clock_rejected(self):
        with self.assertRaises(ValueError):verify_views(self.guard,self.nominal,self.a,self.b.replace('get_clocks clk','get_clocks other'))
    def test_zero_guard_cannot_be_labelled_as_margin(self):
        with self.assertRaises(ValueError):verify_views(self.guard,self.nominal,self.b,self.b)
    def test_nonzero_nominal_budget_rejected(self):
        with self.assertRaises(ValueError):verify_views(self.guard,self.nominal,self.a,self.b.replace('0.000','0.050'))
    def test_negative_guarded_hold_rejected(self):
        with self.assertRaises(ValueError):verify_views(dict(self.guard,whs_ns=-0.001),dict(self.nominal,whs_ns=0.099),self.a,self.b)
    def test_inconsistent_report_delta_rejected(self):
        with self.assertRaises(ValueError):verify_views(self.guard,dict(self.nominal,whs_ns=0.125),self.a,self.b)
    def test_setup_relaxation_rejected(self):
        with self.assertRaises(ValueError):verify_views(self.guard,dict(self.nominal,wns_ns=1.5),self.a,self.b)
    def test_extra_false_path_rejected(self):
        with self.assertRaises(ValueError):verify_views(self.guard,self.nominal,self.a,self.b+'set_false_path -to [all_registers]\n')
