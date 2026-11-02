"""Actual block vector provenance and intentionally incorrect references."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


@unittest.skipUnless(importlib.util.find_spec("numpy"), "NumPy required")
class ResidualVectorTests(unittest.TestCase):
    def test_reproducible_manifest_and_actual_negative_main(self):
        from tools.residual_vectors import export,verify,ROOT
        with tempfile.TemporaryDirectory() as directory:
            m=export(directory)
            self.assertEqual(m,json.loads((Path(ROOT)/"manifest.json").read_text()))
            r=verify(directory)
            self.assertEqual(r["status"],"PASS")
            self.assertEqual(r["teaching_checks"],dict(negative_main=7423,premature_relu_changes=3692,raw_code_add_changes=9345,separate_rounding_changes=2051))

    def test_rehashed_wrong_constants_and_goldens_rejected(self):
        from tools.residual_vectors import export,verify
        for role in ("add_config","m_expected","acc2_expected","add_wide_expected"):
            with self.subTest(role=role), tempfile.TemporaryDirectory() as directory:
                root=Path(directory);export(root)
                path=root/(role+".hex");words=path.read_text().splitlines()
                words[0]=f"{int(words[0],16)^1:0{len(words[0])}x}"
                path.write_bytes(("\n".join(words)+"\n").encode("ascii"))
                mp=root/"manifest.json";m=json.loads(mp.read_text())
                m["vectors"][role]["sha256"]=hashlib.sha256(path.read_bytes()).hexdigest()
                mp.write_text(json.dumps(m),encoding="utf-8")
                with self.assertRaisesRegex(ValueError,"semantic mismatch: "+role): verify(root)

    def test_frozen_manifest_cannot_be_silently_replaced(self):
        from tools.residual_vectors import export
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);export(root)
            mp=root/"manifest.json";m=json.loads(mp.read_text());m["block"]="L1.1"
            mp.write_text(json.dumps(m),encoding="utf-8")
            with self.assertRaisesRegex(ValueError,"Frozen Residual manifest differs"): export(root)
            self.assertEqual(json.loads(mp.read_text())["block"],"L1.1")

    def test_missing_vector_stops_validation(self):
        from tools.residual_vectors import export,verify
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);export(root);(root/"weight2.hex").unlink()
            with self.assertRaises(FileNotFoundError): verify(root)
