import copy,unittest
from tools.ps_dma_board_report import validate
from tools.ps_dma_vectors import artifacts

class BoardReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _,m=artifacts();cls.words=[0x52325053,2,0,4,0,0,0,0]
        for i,cid in enumerate((0,1,0,1)):
            row=m['samples'][str(cid)]
            cls.words += [0x52323052,0xc9000000+i,0,row['prediction']]+[s&0xffffffff for s in row['scores']]+[265000000,0]
    def test_signed_scores(self):
        r=validate(self.words);self.assertEqual(r['completed_jobs'],4);self.assertEqual(r['jobs'][0]['scores'][0],-381997)
    def assert_rejects(self,index,value):
        words=copy.copy(self.words);words[index]=value
        with self.assertRaises(ValueError):validate(words)
    def test_stale_tag(self):self.assert_rejects(9,0xc9000001)
    def test_corrupt_score(self):self.assert_rejects(12,self.words[12]^1)
    def test_wrong_prediction(self):self.assert_rejects(11,8)
    def test_incomplete_jobs(self):self.assert_rejects(3,3)
    def test_failed_firmware(self):self.assert_rejects(1,0x80000051)
    def test_missing_cycle_count(self):self.assert_rejects(22,0)
    def test_truncated_capture(self):
        with self.assertRaises(ValueError):validate(self.words[:-1])
