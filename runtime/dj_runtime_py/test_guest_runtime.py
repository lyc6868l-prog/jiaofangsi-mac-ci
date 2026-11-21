from __future__ import annotations

import tempfile
import unittest
from unittest.mock import patch


class GuestRuntimeTest(unittest.TestCase):
    def test_restore_active_session_offline_marks_need_network_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("dj_runtime_py.system_secret_store.user_data_dir", return_value=temp_dir):
                from dj_runtime_py.guest_runtime import GuestRuntime

                runtime = GuestRuntime()
                machine_hash = "machine-001"
                local_now = 1700000000
                payload = runtime._with_local_signature(
                    {
                        "trial_state": "active",
                        "issued_at": 1700000000,
                        "expires_at": 1700003600,
                        "remaining_hours": 1.0,
                        "machine_hash": machine_hash,
                        "entitlements": ["guest_workbench"],
                        "sig": "invalid-base64",
                        "valid": True,
                        "need_network_validation": False,
                        "server_confirmed_expired": False,
                        "server_signature_valid": True,
                        "server_time": 1700000000,
                        "last_server_time": 1700000000,
                        "last_local_time_when_synced": local_now,
                        "trusted_server_time": 1700000000,
                        "trusted_local_time": local_now,
                    }
                )
                runtime._storage.save_guest_session(payload)
                runtime._storage.save_guest_trust_anchor(
                    {
                        "trusted_server_time": 1700000000,
                        "trusted_local_time": local_now,
                        "last_server_time": 1700000000,
                        "last_local_time": local_now,
                    }
                )

                with patch.object(runtime._fingerprint, "load_or_create", return_value=machine_hash), patch.object(
                    runtime, "_current_timestamp", return_value=1700000100
                ), patch.object(
                    runtime._service,
                    "check_guest_status",
                    side_effect=RuntimeError("offline"),
                ):
                    result = runtime._handle_restore_guest_session({})

                self.assertEqual(result["trial_state"], "active")
                self.assertTrue(result["need_network_validation"])
                self.assertTrue(result["valid"])

    def test_check_never_started_keeps_server_state_without_forced_revalidation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("dj_runtime_py.system_secret_store.user_data_dir", return_value=temp_dir):
                from dj_runtime_py.guest_runtime import GuestRuntime

                runtime = GuestRuntime()
                machine_hash = "a" * 64

                with patch.object(runtime._fingerprint, "load_or_create", return_value=machine_hash), patch.object(
                    runtime,
                    "_current_timestamp",
                    return_value=1700000100,
                ), patch.object(
                    runtime._service,
                    "check_guest_status",
                    return_value={
                        "trial_state": "never_started",
                        "machine_hash": machine_hash,
                        "issued_at": None,
                        "expires_at": None,
                        "remaining_hours": None,
                        "server_time": 1700000000,
                        "sig": None,
                        "reason": "not_registered",
                        "error_message": None,
                        "need_network_validation": False,
                        "valid": False,
                    },
                ):
                    result = runtime._handle_check_guest_status({})

                self.assertEqual(result["trial_state"], "never_started")
                self.assertFalse(result["need_network_validation"])
                self.assertFalse(result["valid"])
                self.assertFalse(result["server_signature_valid"])

    def test_check_never_started_clears_stale_local_session(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("dj_runtime_py.system_secret_store.user_data_dir", return_value=temp_dir):
                from dj_runtime_py.guest_runtime import GuestRuntime

                runtime = GuestRuntime()
                machine_hash = "b" * 64
                stale = runtime._with_local_signature(
                    {
                        "trial_state": "active",
                        "issued_at": 1700000000,
                        "expires_at": 1700003600,
                        "remaining_hours": 1.0,
                        "machine_hash": machine_hash,
                        "entitlements": ["guest_workbench"],
                        "sig": "stale-sig",
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
                )
                runtime._storage.save_guest_session(stale)
                runtime._storage.save_guest_trust_anchor(
                    {
                        "trusted_server_time": 1700000000,
                        "trusted_local_time": 1700000000,
                        "last_server_time": 1700000000,
                        "last_local_time": 1700000000,
                    }
                )

                with patch.object(runtime._fingerprint, "load_or_create", return_value=machine_hash), patch.object(
                    runtime,
                    "_current_timestamp",
                    return_value=1700000100,
                ), patch.object(
                    runtime._service,
                    "check_guest_status",
                    return_value={
                        "trial_state": "never_started",
                        "machine_hash": machine_hash,
                        "issued_at": None,
                        "expires_at": None,
                        "remaining_hours": None,
                        "server_time": 1700000000,
                        "sig": None,
                        "reason": "not_registered",
                        "error_message": None,
                        "need_network_validation": False,
                        "valid": False,
                    },
                ):
                    result = runtime._handle_check_guest_status({})

                self.assertEqual(result["trial_state"], "never_started")
                self.assertIsNone(runtime._storage.load_guest_session())
                self.assertIsNone(runtime._storage.load_guest_trust_anchor())

    def test_restore_without_local_session_offline_returns_never_started(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("dj_runtime_py.system_secret_store.user_data_dir", return_value=temp_dir):
                from dj_runtime_py.guest_runtime import GuestRuntime

                runtime = GuestRuntime()
                machine_hash = "c" * 64

                with patch.object(runtime._fingerprint, "load_or_create", return_value=machine_hash), patch.object(
                    runtime,
                    "_current_timestamp",
                    return_value=1700007200,
                ), patch.object(
                    runtime._service,
                    "check_guest_status",
                    side_effect=RuntimeError("offline"),
                ):
                    result = runtime._handle_restore_guest_session({})

                self.assertEqual(result["trial_state"], "never_started")
                self.assertTrue(result["success"])
                self.assertFalse(result["valid"])
                self.assertFalse(result["need_network_validation"])
                self.assertIsNone(runtime._storage.load_guest_session())
                self.assertIsNone(runtime._storage.load_guest_trust_anchor())

    def test_restore_expired_session_returns_expired_and_blocks_trial(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("dj_runtime_py.system_secret_store.user_data_dir", return_value=temp_dir):
                from dj_runtime_py.guest_runtime import GuestRuntime

                runtime = GuestRuntime()
                machine_hash = "c" * 64
                payload = runtime._with_local_signature(
                    {
                        "trial_state": "active",
                        "issued_at": 1700000000,
                        "expires_at": 1700003600,
                        "remaining_hours": 1.0,
                        "machine_hash": machine_hash,
                        "entitlements": ["guest_workbench"],
                        "sig": "signed",
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
                )
                runtime._storage.save_guest_session(payload)
                runtime._storage.save_guest_trust_anchor(
                    {
                        "trusted_server_time": 1700000000,
                        "trusted_local_time": 1700000000,
                        "last_server_time": 1700000000,
                        "last_local_time": 1700000000,
                    }
                )

                with patch.object(runtime._fingerprint, "load_or_create", return_value=machine_hash), patch.object(
                    runtime,
                    "_current_timestamp",
                    return_value=1700007200,
                ):
                    result = runtime._handle_restore_guest_session({})

                self.assertEqual(result["trial_state"], "expired")
                self.assertTrue(result["server_confirmed_expired"])
                self.assertFalse(result["valid"])
                self.assertFalse(result["need_network_validation"])

    def test_restore_tampered_local_session_returns_unknown(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("dj_runtime_py.system_secret_store.user_data_dir", return_value=temp_dir):
                from dj_runtime_py.guest_runtime import GuestRuntime

                runtime = GuestRuntime()
                machine_hash = "d" * 64
                payload = runtime._with_local_signature(
                    {
                        "trial_state": "active",
                        "issued_at": 1700000000,
                        "expires_at": 1700003600,
                        "remaining_hours": 1.0,
                        "machine_hash": machine_hash,
                        "entitlements": ["guest_workbench"],
                        "sig": "signed",
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
                )
                payload["expires_at"] = 1700007200
                runtime._storage.save_guest_session(payload)

                with patch.object(runtime._fingerprint, "load_or_create", return_value=machine_hash), patch.object(
                    runtime,
                    "_current_timestamp",
                    return_value=1700000100,
                ):
                    result = runtime._handle_restore_guest_session({})

                self.assertEqual(result["trial_state"], "unknown")
                self.assertTrue(result["need_network_validation"])
                self.assertFalse(result["valid"])

    def test_restore_clock_rollback_returns_unknown_and_revalidation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("dj_runtime_py.system_secret_store.user_data_dir", return_value=temp_dir):
                from dj_runtime_py.guest_runtime import GuestRuntime

                runtime = GuestRuntime()
                machine_hash = "e" * 64
                payload = runtime._with_local_signature(
                    {
                        "trial_state": "active",
                        "issued_at": 1700000000,
                        "expires_at": 1700007200,
                        "remaining_hours": 2.0,
                        "machine_hash": machine_hash,
                        "entitlements": ["guest_workbench"],
                        "sig": "signed",
                        "valid": True,
                        "need_network_validation": False,
                        "server_confirmed_expired": False,
                        "server_signature_valid": True,
                        "server_time": 1700000000,
                        "last_server_time": 1700000000,
                        "last_local_time_when_synced": 1700001000,
                        "trusted_server_time": 1700000000,
                        "trusted_local_time": 1700001000,
                    }
                )
                runtime._storage.save_guest_session(payload)
                runtime._storage.save_guest_trust_anchor(
                    {
                        "trusted_server_time": 1700000000,
                        "trusted_local_time": 1700001000,
                        "last_server_time": 1700000000,
                        "last_local_time": 1700001000,
                    }
                )

                with patch.object(runtime._fingerprint, "load_or_create", return_value=machine_hash), patch.object(
                    runtime,
                    "_current_timestamp",
                    return_value=1700000000,
                ):
                    result = runtime._handle_restore_guest_session({})

                self.assertEqual(result["trial_state"], "unknown")
                self.assertTrue(result["need_network_validation"])
                self.assertFalse(result["valid"])


if __name__ == "__main__":
    unittest.main()
