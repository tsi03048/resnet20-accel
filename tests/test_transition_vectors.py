"""Option A's direct addresses and actual Transition Golden provenance."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


@unittest.skipUnless(importlib.util.find_spec("numpy"),"NumPy required")
class TransitionVectorTests(unittest.TestCase):
    def test_small_option_a_addresses_and_center_mapping(self):
        import numpy as np
        from tools.transition_vectors import option_a_direct
        x=np.concatenate([np.arange(1,17),np.arange(101,117)]).reshape(1,2,4,4)
        skip,addr=option_a_direct(x)
        np.testing.assert_array_equal(skip.reshape(4,4),[[0,0,0,0],[1,3,9,11],[101,103,109,111],[0,0,0,0]])
        np.testing.assert_array_equal(addr.reshape(4,4),[[-1,-1,-1,-1],[0,2,8,10],[16,18,24,26],[-1,-1,-1,-1]])
        _,large_addr=option_a_direct(np.zeros((1,16,32,32),dtype=np.int64))
        self.assertEqual(int(large_addr[0,8,1,2]),68)

    def test_frozen_both_shapes_and_high_weight_address(self):
        from tools.transition_vectors import export,verify,ROOT
        with tempfile.TemporaryDirectory() as directory:
            m=export(directory)
            self.assertEqual(m,json.loads((Path(ROOT)/"manifest.json").read_text()))
            r=verify(directory)
            self.assertEqual(r["status"],"PASS")
            self.assertEqual(r["geometry"]["2"]["skip_read_count"],4096)
            self.assertEqual(r["geometry"]["3"]["skip_read_count"],2048)
            self.assertEqual(m["vectors"]["3"]["weight2"]["count"],36864)
            self.assertEqual(len((Path(directory)/"stage3/weight2.hex").read_text().splitlines()),36864)

    def test_rehashed_wrong_skip_address_and_weight_rejected(self):
        from tools.transition_vectors import export,verify
        for stage,role,index in ((2,"skip_addr_expected",2048),(3,"weight2",36863)):
            with self.subTest(stage=stage,role=role),tempfile.TemporaryDirectory() as directory:
                root=Path(directory);export(root);path=root/f"stage{stage}/{role}.hex"
                words=path.read_text().splitlines();words[index]=f"{int(words[index],16)^1:0{len(words[index])}x}";path.write_bytes(("\n".join(words)+"\n").encode("ascii"))
                mp=root/"manifest.json";m=json.loads(mp.read_text());m["vectors"][str(stage)][role]["sha256"]=hashlib.sha256(path.read_bytes()).hexdigest();mp.write_text(json.dumps(m))
                with self.assertRaisesRegex(ValueError,"Transition semantic mismatch"):verify(root)
                with self.assertRaisesRegex(ValueError,"Frozen Transition manifest differs"):export(root)

    @unittest.skipUnless(importlib.util.find_spec("torch"),"PyTorch required for independent replay")
    def test_both_actual_transitions_in_independent_torch_replay(self):
        from quant.replay_e2b import replay
        result=replay(backend="torch")
        self.assertEqual(result["status"],"PASS")
        self.assertEqual(result["tensor_count"],61)
