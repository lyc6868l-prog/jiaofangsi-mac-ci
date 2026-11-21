from __future__ import annotations

import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

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

        def get(self, key: str):
            return None

        def delall(self, key: str) -> None:
            return None

        def add(self, frame) -> None:
            return None

        def save(self, path) -> None:
            return None

    class _FakeTALB:
        def __init__(self, encoding: int, text: str) -> None:
            self.encoding = encoding
            self.text = text

    mutagen_id3.ID3 = _FakeID3
    mutagen_id3.ID3NoHeaderError = _FakeID3NoHeaderError
    mutagen_id3.TALB = _FakeTALB
    sys.modules["mutagen.id3"] = mutagen_id3

from dj_runtime_py.pinyin_generator_service import PinyinGeneratorRuntime


class _FakeStyle:
    FIRST_LETTER = "first_letter"


class PinyinGeneratorRuntimeTest(unittest.TestCase):
    def test_load_targets_reports_wav_and_non_audio_warnings(self) -> None:
        runtime = PinyinGeneratorRuntime()
        with patch("dj_runtime_py.pinyin_generator_service.require_module_access"):
            with tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                (root / "song.mp3").write_bytes(b"demo")
                (root / "skip.wav").write_bytes(b"demo")
                (root / "note.txt").write_text("demo", encoding="utf-8")

                response = runtime.handle_request(
                    {
                        "request_id": "req_001",
                        "module": "pinyin_generator",
                        "action": "load_targets",
                        "payload": {"panel": "generator", "file_paths": [str(root)]},
                    }
                )

                self.assertTrue(response["ok"])
                self.assertEqual(response["data"]["file_count"], 1)
                self.assertEqual(response["data"]["skipped_wav_count"], 1)
                self.assertIn("不支持 WAV 文件", response["data"]["warning_message"])
                self.assertIn("检测到非音频文件", response["data"]["warning_message"])

    def test_generate_initials_and_compose_album_append_deduplicates(self) -> None:
        runtime = PinyinGeneratorRuntime()

        initials = runtime._generate_initials(
            "中文 Remix",
            8,
            lambda title, style, strict: ["z", "w"],
            _FakeStyle,
        )

        self.assertEqual(initials, "ZW")
        self.assertEqual(runtime._compose_album("已有专辑", initials, "append"), "已有专辑 / ZW")
        self.assertEqual(runtime._compose_album("已有专辑 / ZW", initials, "append"), "已有专辑 / ZW")
        self.assertEqual(runtime._compose_album("已有专辑", initials, "overwrite"), "ZW")

    def test_lock_config_rejects_invalid_stopwords(self) -> None:
        runtime = PinyinGeneratorRuntime()
        with patch("dj_runtime_py.pinyin_generator_service.require_module_access"):
            response = runtime.handle_request(
                {
                    "request_id": "req_002",
                    "module": "pinyin_generator",
                    "action": "lock_config",
                    "payload": {
                        "panel": "generator",
                        "config": {
                            "write_mode": "append",
                            "max_initials_length": 12,
                            "stopwords": ["DJ", 1],
                        },
                    },
                }
            )

        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "INVALID_CONFIG")
        self.assertIn("stopwords 项必须是字符串", response["error"]["message"])


if __name__ == "__main__":
    unittest.main()
