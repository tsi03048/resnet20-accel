"""The public RTL vectors must remain tied to the real E2-B package."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest


@unittest.skipUnless(importlib.util.find_spec("numpy"), "NumPy required")
class StemVectorIntegrity(unittest.TestCase):
    def test_public_vectors_and_canonical_bytes(self):
        from tools.verify_stem_vectors import verify
        root = Path("reference/e2b_v1/stem_vectors")
        self.assertEqual(verify()["status"], "PASS")
        for path in root.glob("*.hex"):
            raw = path.read_bytes()
            self.assertNotIn(b"\r", raw)
            self.assertTrue(raw.endswith(b"\n"))

    def test_semantic_tamper_rejected_even_with_rehashed_file(self):
        from tools.verify_stem_vectors import verify
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "vectors"
            shutil.copytree("reference/e2b_v1/stem_vectors", root)
            path = root / "acc_expected.hex"
            words = path.read_text(encoding="ascii").splitlines()
            words[0] = f"{int(words[0], 16) ^ 1:08x}"
            path.write_bytes(("\n".join(words) + "\n").encode("ascii"))
            manifest_path = root / "manifest.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["vectors"]["acc_expected"]["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "semantic mismatch: acc_expected"):
                verify(root)

    def test_line_ending_change_rejected(self):
        from tools.verify_stem_vectors import verify
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "vectors"
            shutil.copytree("reference/e2b_v1/stem_vectors", root)
            path = root / "input.hex"
            path.write_bytes(path.read_bytes().replace(b"\n", b"\r\n"))
            with self.assertRaisesRegex(ValueError, "hash mismatch: input"):
                verify(root)
