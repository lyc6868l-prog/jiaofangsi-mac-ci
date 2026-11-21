from __future__ import annotations

import unittest
from unittest.mock import Mock, patch

from dj_runtime_py.access_control import AccessControlError, RuntimeAccessController
from dj_runtime_py.trial_security import TrialSecurity


class RuntimeAccessControllerTest(unittest.TestCase):
    def _build_guest_payload(self, **overrides: object) -> dict[str, object]:
        security = TrialSecurity()
        payload: dict[str, object] = {
            "trial_state": "active",
            "issued_at": 1700000000,
            "expires_at": 4102444800,
            "machine_hash": "guest-machine",
            "entitlements": ["guest_workbench"],
            "sig": "mock-sig",
            "valid": True,
            "need_network_validation": False,
            "server_confirmed_expired": False,
            "server_signature_valid": True,
            "server_time": 1700000000,
            "last_server_time": 1700000000,
            "last_local_time_when_synced": 1700000000,
            "trusted_server_time": 1700000000,
            "trusted_local_time": 1700000000,
        }
        payload.update(overrides)
        payload["local_signature"] = security.sign_local_payload(payload)
        return payload

    @patch("dj_runtime_py.access_control.MachineFingerprint")
    @patch("dj_runtime_py.access_control.SecureStorage")
    @patch("dj_runtime_py.access_control.AuthService")
    def test_workbench_module_rejects_non_vip_user(
        self,
        auth_service_cls,
        storage_cls,
        fingerprint_cls,
    ) -> None:
        storage = storage_cls.return_value
        storage.load_user_session.return_value = {
            "token": "user-token",
            "expires_at": "2099-01-01T00:00:00+00:00",
        }
        storage.load_guest_session.return_value = None
        auth_service_cls.return_value.check_entitlement.return_value = {
            "data": {
                "entitlements": [
                    {"status": "inactive", "entitlement_type": "vip"},
                ],
            },
        }
        fingerprint_cls.return_value = Mock()

        controller = RuntimeAccessController()

        with self.assertRaises(AccessControlError) as context:
            controller.require_module_access("audio_transcode", "start_audio_transcode_task")

        self.assertEqual(context.exception.code, "ENTITLEMENT_REQUIRED")

    @patch("dj_runtime_py.access_control.MachineFingerprint")
    @patch("dj_runtime_py.access_control.SecureStorage")
    @patch("dj_runtime_py.access_control.AuthService")
    def test_workbench_module_allows_guest_session(
        self,
        auth_service_cls,
        storage_cls,
        fingerprint_cls,
    ) -> None:
        storage = storage_cls.return_value
        storage.load_user_session.return_value = None
        storage.load_guest_session.return_value = self._build_guest_payload()
        storage.load_guest_trust_anchor.return_value = {
            "trusted_server_time": 1700000000,
            "trusted_local_time": 1700000000,
            "last_server_time": 1700000000,
            "last_local_time": 1700000000,
        }
        fingerprint_cls.return_value.load_or_create.return_value = "guest-machine"
        auth_service_cls.return_value = Mock()

        with patch("dj_runtime_py.access_control.time.time", return_value=1700000100):
            controller = RuntimeAccessController()
            controller.require_module_access("cleanup_dup", "start_duplicate_check_task")

    @patch("dj_runtime_py.access_control.MachineFingerprint")
    @patch("dj_runtime_py.access_control.SecureStorage")
    @patch("dj_runtime_py.access_control.AuthService")
    def test_authenticated_module_requires_login_or_guest(
        self,
        auth_service_cls,
        storage_cls,
        fingerprint_cls,
    ) -> None:
        storage = storage_cls.return_value
        storage.load_user_session.return_value = None
        storage.load_guest_session.return_value = None
        auth_service_cls.return_value = Mock()
        fingerprint_cls.return_value = Mock()

        controller = RuntimeAccessController()

        with self.assertRaises(AccessControlError) as context:
            controller.require_module_access("unlock_music", "start_unlock_task")

        self.assertEqual(context.exception.code, "AUTH_REQUIRED")

    @patch("dj_runtime_py.access_control.MachineFingerprint")
    @patch("dj_runtime_py.access_control.SecureStorage")
    @patch("dj_runtime_py.access_control.AuthService")
    def test_guest_network_failure_requires_revalidation(
        self,
        auth_service_cls,
        storage_cls,
        fingerprint_cls,
    ) -> None:
        storage = storage_cls.return_value
        storage.load_user_session.return_value = None
        storage.load_guest_session.return_value = self._build_guest_payload(
            need_network_validation=True,
        )
        storage.load_guest_trust_anchor.return_value = {
            "trusted_server_time": 1700000000,
            "trusted_local_time": 1700000000,
            "last_server_time": 1700000000,
            "last_local_time": 1700000000,
        }
        fingerprint_cls.return_value.load_or_create.return_value = "guest-machine"
        auth_service_cls.return_value = Mock()

        controller = RuntimeAccessController()

        with self.assertRaises(AccessControlError) as context:
            controller.require_module_access("cleanup_dup", "start_duplicate_check_task")

        self.assertEqual(context.exception.code, "NETWORK_VALIDATION_REQUIRED")

    @patch("dj_runtime_py.access_control.MachineFingerprint")
    @patch("dj_runtime_py.access_control.SecureStorage")
    @patch("dj_runtime_py.access_control.AuthService")
    def test_user_network_failure_requires_revalidation(
        self,
        auth_service_cls,
        storage_cls,
        fingerprint_cls,
    ) -> None:
        storage = storage_cls.return_value
        storage.load_user_session.return_value = {
            "token": "user-token",
            "expires_at": "2099-01-01T00:00:00+00:00",
        }
        storage.load_guest_session.return_value = None
        auth_service_cls.return_value.check_entitlement.side_effect = RuntimeError("offline")
        fingerprint_cls.return_value = Mock()

        controller = RuntimeAccessController()

        with self.assertRaises(AccessControlError) as context:
            controller.require_module_access("unlock_music", "start_unlock_task")

        self.assertEqual(context.exception.code, "NETWORK_VALIDATION_REQUIRED")

    @patch("dj_runtime_py.access_control.MachineFingerprint")
    @patch("dj_runtime_py.access_control.SecureStorage")
    @patch("dj_runtime_py.access_control.AuthService")
    def test_guest_tampered_local_signature_requires_revalidation(
        self,
        auth_service_cls,
        storage_cls,
        fingerprint_cls,
    ) -> None:
        payload = self._build_guest_payload()
        payload["expires_at"] = 1700003600

        storage = storage_cls.return_value
        storage.load_user_session.return_value = None
        storage.load_guest_session.return_value = payload
        storage.load_guest_trust_anchor.return_value = {
            "trusted_server_time": 1700000000,
            "trusted_local_time": 1700000000,
            "last_server_time": 1700000000,
            "last_local_time": 1700000000,
        }
        fingerprint_cls.return_value.load_or_create.return_value = "guest-machine"
        auth_service_cls.return_value = Mock()

        controller = RuntimeAccessController()

        with self.assertRaises(AccessControlError) as context:
            controller.require_module_access("cleanup_dup", "start_duplicate_check_task")

        self.assertEqual(context.exception.code, "NETWORK_VALIDATION_REQUIRED")


if __name__ == "__main__":
    unittest.main()
