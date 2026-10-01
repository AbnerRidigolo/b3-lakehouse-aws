import base64
from pathlib import Path
import tempfile
import unittest

from nacl.exceptions import CryptoError
from scripts.plan_crypto import transform


class PlanCryptoTests(unittest.TestCase):
    def test_plan_restored_exactly_and_randomized(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "plan"
            payload = bytes(range(256)) * 10
            source.write_bytes(payload)
            key = base64.b64encode(b"k" * 32).decode()
            for name in ("first", "second"):
                transform("encrypt", source, root / name, key, "run:sha")
            self.assertNotEqual((root / "first").read_bytes(), (root / "second").read_bytes())
            transform("decrypt", root / "first", root / "restored", key, "run:sha")
            self.assertEqual((root / "restored").read_bytes(), payload)

    def test_tampering_wrong_key_and_wrong_run_block_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "plan"
            source.write_bytes(b"private plan")
            key = base64.b64encode(b"k" * 32).decode()
            transform("encrypt", source, root / "encrypted", key, "run:sha")
            original = (root / "encrypted").read_bytes()
            for case in ("tampered", "wrong-key", "wrong-run"):
                with self.subTest(case=case):
                    altered = bytearray(original)
                    if case == "tampered":
                        altered[-1] ^= 1
                    (root / "encrypted").write_bytes(altered)
                    test_key = base64.b64encode(b"x" * 32).decode() if case == "wrong-key" else key
                    context = "other:sha" if case == "wrong-run" else "run:sha"
                    with self.assertRaises(CryptoError):
                        transform("decrypt", root / "encrypted", root / "output", test_key, context)
                    self.assertFalse((root / "output").exists())


if __name__ == "__main__":
    unittest.main()
