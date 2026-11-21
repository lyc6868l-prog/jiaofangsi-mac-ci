from __future__ import annotations

import base64
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


class TrialSecurityTest(unittest.TestCase):
    def test_local_signature_detects_tampering(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("dj_runtime_py.system_secret_store.user_data_dir", return_value=temp_dir):
                from dj_runtime_py.trial_security import TrialSecurity

                security = TrialSecurity()
                payload = {
                    "machine_hash": "machine-001",
                    "issued_at": 1700000000,
                    "expires_at": 1700003600,
                    "trial_state": "active",
                    "server_time": 1700000005,
                }
                signed_payload = {
                    **payload,
                    "local_signature": security.sign_local_payload(payload),
                }
                self.assertTrue(security.verify_local_payload(signed_payload))

                tampered = dict(signed_payload)
                tampered["expires_at"] = 1700007200
                self.assertFalse(security.verify_local_payload(tampered))

    def test_server_signature_verification_uses_ed25519(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("dj_runtime_py.system_secret_store.user_data_dir", return_value=temp_dir):
                from dj_runtime_py.trial_security import TrialSecurity

                private_key = Ed25519PrivateKey.generate()
                public_key = private_key.public_key().public_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PublicFormat.SubjectPublicKeyInfo,
                )
                with patch.dict(
                    "os.environ",
                    {"DJ_GUEST_PUBLIC_KEY": public_key.decode("utf-8")},
                    clear=False,
                ):
                    security = TrialSecurity()
                    payload = {
                        "machine_hash": "machine-001",
                        "issued_at": 1700000000,
                        "expires_at": 1700003600,
                        "trial_state": "active",
                        "server_time": 1700000005,
                    }
                    signature = private_key.sign(
                        security.serialize_signed_fields(payload).encode("utf-8")
                    )
                    signed_payload = {
                        **payload,
                        "sig": base64.b64encode(signature).decode("utf-8"),
                    }
                    self.assertTrue(security.verify_server_signature(signed_payload))

                    tampered = dict(signed_payload)
                    tampered["trial_state"] = "expired"
                    self.assertFalse(security.verify_server_signature(tampered))


if __name__ == "__main__":
    unittest.main()
