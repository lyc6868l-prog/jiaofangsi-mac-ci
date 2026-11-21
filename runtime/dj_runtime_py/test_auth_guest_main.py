from __future__ import annotations

import sys
import types
import unittest
from unittest.mock import patch

if "platformdirs" not in sys.modules:
    platformdirs_module = types.ModuleType("platformdirs")
    platformdirs_module.user_data_dir = lambda *args, **kwargs: "/tmp/dj_runtime_py"
    sys.modules["platformdirs"] = platformdirs_module

from dj_runtime_py import auth_guest_main


class AuthGuestMainTest(unittest.TestCase):
    @patch(
        "dj_runtime_py.secure_storage.SystemSecretStore.load_or_create",
        return_value="MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=",
    )
    def test_auth_guest_factories_do_not_import_heavy_modules(
        self,
        _mock_load_or_create,
    ) -> None:
        heavy_modules = [
            "dj_runtime_py.audio_transcode_service",
            "dj_runtime_py.metadata_edit_service",
            "dj_runtime_py.pinyin_generator_service",
            "dj_runtime_py.search_download_service",
            "dj_runtime_py.usb_backup_service",
            "dj_runtime_py.unlock_music_service",
            "dj_runtime_py.unlock_node_bridge",
            "dj_runtime_py.rust_bridge",
            "dj_runtime_py.transcode_rust_bridge",
            "dj_runtime_py.usb_backup_rust_bridge",
        ]

        for module_name in heavy_modules:
            self.assertNotIn(module_name, sys.modules)

        factories = auth_guest_main._build_runtime_factories()
        self.assertEqual(set(factories.keys()), {"auth", "guest"})

        auth_runtime = factories["auth"]()
        guest_runtime = factories["guest"]()

        self.assertEqual(auth_runtime.MODULE, "auth")
        self.assertEqual(guest_runtime.MODULE, "guest")

        for module_name in heavy_modules:
            self.assertNotIn(module_name, sys.modules)


if __name__ == "__main__":
    unittest.main()
