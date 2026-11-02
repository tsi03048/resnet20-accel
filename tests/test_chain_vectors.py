"""Fixed real-frame provenance and an independent changed-frame oracle."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


@unittest.skipUnless(importlib.util.find_spec("numpy"),"NumPy required")
class ChainVectorTests(unittest.TestCase):
    def test_frozen_manifest_reproduces_and_frames_differ(self):
        from tools.chain_vectors import export,verify,ROOT
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(export(directory),json.loads((Path(ROOT)/"manifest.json").read_text()))
            r=verify(directory)
            self.assertEqual(r["status"],"PASS")
            self.assertEqual(r["changed_elements"],dict(input=3029,stem=10755,h=9030,m=14065,y=11948))

    def test_rehashed_bridge_or_final_golden_cannot_hide_wrong_frame(self):
        from tools.chain_vectors import export,verify
        for name,role in (("actual0","stem"),("synthetic_zero","y")):
            with self.subTest(name=name,role=role),tempfile.TemporaryDirectory() as directory:
                root=Path(directory);export(root);p=root/name/(role+".hex")
                words=p.read_text().splitlines();words[0]=f"{int(words[0],16)^1:02x}"
                p.write_bytes(("\n".join(words)+"\n").encode("ascii"))
                mp=root/"manifest.json";m=json.loads(mp.read_text());m["cases"][name][role]["sha256"]=hashlib.sha256(p.read_bytes()).hexdigest();mp.write_text(json.dumps(m))
                with self.assertRaisesRegex(ValueError,"chain semantic mismatch"):verify(root)

    def test_wrong_path_manifest_is_rejected(self):
        from tools.chain_vectors import export,verify
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);export(root);mp=root/"manifest.json";m=json.loads(mp.read_text());m["path"][1]="L1.1.conv1";mp.write_text(json.dumps(m))
            with self.assertRaisesRegex(ValueError,"path mismatch"):verify(root)
            with self.assertRaisesRegex(ValueError,"Frozen chain manifest differs"):export(root)

    @unittest.skipUnless(importlib.util.find_spec("torch"),"PyTorch required for independent backend")
    def test_synthetic_frame_numpy_vs_torch_every_chain_boundary(self):
        import numpy as np
        from tools.chain_vectors import expected
        _,numpy_cases=expected("numpy");_,torch_cases=expected("torch")
        for role,(a,bits) in numpy_cases["synthetic_zero"].items():
            other,other_bits=torch_cases["synthetic_zero"][role]
            self.assertEqual(bits,other_bits)
            np.testing.assert_array_equal(a,other,err_msg=role)
