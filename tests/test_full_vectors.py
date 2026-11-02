"""Full graph bank lifetimes, real input provenance and independent oracle."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

@unittest.skipUnless(importlib.util.find_spec('numpy'),'NumPy required')
class FullVectorsTests(unittest.TestCase):
    def test_graph_banks_and_totals(self):
        from tools.full_vectors import expected,graph_text,ROM
        m,rows,constants,cases,cm=expected()
        owners={0:'input'}
        for op,row in zip(m['operations'],rows):
            self.assertEqual(owners[row['src']],op['inputs'][0])
            if row['kind']==1:self.assertEqual(owners[row['skip']],op['inputs'][1])
            self.assertNotEqual(row['src'],row['dst'])
            if row['kind']==1:self.assertNotEqual(row['skip'],row['dst'])
            owners[row['dst']]=row['name']
        self.assertEqual([sum(r['kind']==k for r in rows) for k in range(4)],[19,9,1,1])
        self.assertEqual(sum(r['nout'] for r in rows),274506)
        self.assertEqual(constants['weight'][0].size,268336)
        self.assertEqual([cm[str(i)]['prediction'] for i in (0,1)],[3,8])
        self.assertEqual(cm['1']['tensor_count'],61)
        self.assertEqual(Path(ROM).read_text(),graph_text(rows))

    def test_rehashed_corrupt_fc_score_rejected(self):
        from tools.full_vectors import export,verify
        with tempfile.TemporaryDirectory() as directory:
            export(directory);root=Path(directory);p=root/'sample1/code.hex'
            words=p.read_text().splitlines();words[-1]=f'{int(words[-1],16)^1:08x}';p.write_bytes(('\n'.join(words)+'\n').encode())
            mp=root/'manifest.json';m=json.loads(mp.read_text());m['vectors']['sample1/code']['sha256']=hashlib.sha256(p.read_bytes()).hexdigest();mp.write_text(json.dumps(m))
            with self.assertRaisesRegex(ValueError,'semantic mismatch'):verify(directory)
            with self.assertRaisesRegex(ValueError,'Frozen full-model manifest differs'):export(directory)

    def test_sample1_input_frozen_hash_and_label(self):
        from tools.full_vectors import ROOT
        p=Path(ROOT);m=json.loads((p/'sample1_source.json').read_text())
        self.assertEqual(m['test_index'],1);self.assertEqual(m['label'],8)
        self.assertTrue(m['sample0_preprocessing_match'])
        self.assertEqual(hashlib.sha256((p/'sample1_input.hex').read_bytes()).hexdigest(),m['input_sha256'])

    @unittest.skipUnless(importlib.util.find_spec('torch'),'PyTorch required for independent integer replay')
    def test_two_actual_samples_numpy_vs_torch_all_boundaries(self):
        import numpy as np
        from tools.full_vectors import expected
        *_,numpy_cases,nm=expected('numpy')
        *_,torch_cases,tm=expected('torch')
        self.assertEqual(nm,tm)
        for cid in ('0','1'):
            for role,(values,bits) in numpy_cases[cid].items():
                self.assertEqual(bits,torch_cases[cid][role][1]);np.testing.assert_array_equal(values,torch_cases[cid][role][0])
