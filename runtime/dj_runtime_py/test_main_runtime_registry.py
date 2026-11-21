from __future__ import annotations

import sys
import types
import unittest
from unittest.mock import patch

if "platformdirs" not in sys.modules:
    platformdirs_module = types.ModuleType("platformdirs")
    platformdirs_module.user_data_dir = lambda *args, **kwargs: "/tmp/dj_runtime_py"
    sys.modules["platformdirs"] = platformdirs_module
if "mutagen" not in sys.modules:
    mutagen_module = types.ModuleType("mutagen")
    mutagen_module.File = lambda *args, **kwargs: None
    sys.modules["mutagen"] = mutagen_module
if "mutagen.id3" not in sys.modules:
    mutagen_id3 = types.ModuleType("mutagen.id3")

    class _FakeID3NoHeaderError(Exception):
        pass

    class _FakeID3:
        def __init__(self, *args, **kwargs) -> None:
            pass

    class _FakeTALB:
        def __init__(self, encoding: int, text: str) -> None:
            self.encoding = encoding
            self.text = text

    mutagen_id3.ID3 = _FakeID3
    mutagen_id3.ID3NoHeaderError = _FakeID3NoHeaderError
    mutagen_id3.TALB = _FakeTALB
    sys.modules["mutagen.id3"] = mutagen_id3

from dj_runtime_py import __main__
from dj_runtime_py.auth_runtime import AuthRuntime
from dj_runtime_py.guest_runtime import GuestRuntime
from dj_runtime_py.service import CleanupDupRuntime


class MainRuntimeRegistryTest(unittest.TestCase):
    @patch("dj_runtime_py.__main__._resolve_unlock_worker_root")
    @patch(
        "dj_runtime_py.secure_storage.SystemSecretStore.load_or_create",
        return_value="MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=",
    )
    def test_build_runtime_factories_register_expected_modules(
        self,
        _mock_load_or_create,
        mock_resolve_unlock_worker_root,
    ) -> None:
        mock_resolve_unlock_worker_root.return_value = __main__.Path("/tmp/unlock_music_node")

        factories = __main__._build_runtime_factories()

        self.assertEqual(
            set(factories.keys()),
            {
                "audio_transcode",
                "auth",
                "cleanup_dup",
                "guest",
                "metadata_edit",
                "pinyin_generator",
                "usb_backup",
                "unlock_music",
                "search_download",
            },
        )
        self.assertIsInstance(factories["auth"](), AuthRuntime)
        self.assertIsInstance(factories["cleanup_dup"](), CleanupDupRuntime)
        self.assertIsInstance(factories["guest"](), GuestRuntime)


if __name__ == "__main__":
    unittest.main()
