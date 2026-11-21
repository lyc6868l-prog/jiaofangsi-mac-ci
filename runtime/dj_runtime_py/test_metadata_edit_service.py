from __future__ import annotations

import shutil
import tempfile
import time
import unittest
from pathlib import Path

from dj_runtime_py.metadata_edit_service import MetadataEditRuntime


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent


class MetadataEditRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        repo_root = _repo_root()
        self.ffmpeg_path = repo_root / "ff" / "ffmpeg"
        self.ffprobe_path = repo_root / "ff" / "ffprobe"
        self.audio_fixture = (
            repo_root
            / "功能实现参考"
            / "czkawka-master"
            / "czkawka_core"
            / "test_resources"
            / "audio"
            / "base.mp3"
        )
        self.cover_fixture = repo_root / "3b4395f61065f41122fef145212506e6.png"

    def test_filename_task_uses_ffprobe_path_and_completes(self) -> None:
        runtime = MetadataEditRuntime()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "demo.mp3"
            shutil.copy2(self.audio_fixture, source)

            loaded = runtime.handle_request(
                {
                    "request_id": "req_001",
                    "module": "metadata_edit",
                    "action": "load_targets",
                    "payload": {"panel": "metadata_edit", "file_paths": [str(root)]},
                }
            )
            self.assertTrue(loaded["ok"])
            self.assertEqual(loaded["data"]["file_count"], 1)

            locked = runtime.handle_request(
                {
                    "request_id": "req_002",
                    "module": "metadata_edit",
                    "action": "lock_config",
                    "payload": {
                        "panel": "metadata_edit",
                        "config": {
                            "operation": "filename_injection",
                            "append_text": "remix版",
                            "ffmpeg_path": str(self.ffmpeg_path),
                            "ffprobe_path": str(self.ffprobe_path),
                        },
                    },
                }
            )
            self.assertTrue(locked["ok"])

            started = runtime.handle_request(
                {
                    "request_id": "req_003",
                    "module": "metadata_edit",
                    "action": "start_filename_injection_task",
                    "payload": {"panel": "metadata_edit"},
                }
            )
            self.assertTrue(started["ok"])
            task_id = started["data"]["task_id"]

            final_result = None
            for _ in range(120):
                result = runtime.handle_request(
                    {
                        "request_id": "req_004",
                        "module": "metadata_edit",
                        "action": "fetch_metadata_edit_result",
                        "payload": {"task_id": task_id},
                    }
                )
                if result["ok"]:
                    final_result = result
                    break
                time.sleep(0.05)

            self.assertIsNotNone(final_result)
            assert final_result is not None
            self.assertEqual(final_result["data"]["success_count"], 1)
            renamed = root / "demoremix版.mp3"
            self.assertTrue(renamed.exists())

    def test_cover_task_uses_ffmpeg_and_ffprobe_paths(self) -> None:
        runtime = MetadataEditRuntime()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "demo.mp3"
            shutil.copy2(self.audio_fixture, source)

            loaded = runtime.handle_request(
                {
                    "request_id": "req_011",
                    "module": "metadata_edit",
                    "action": "load_targets",
                    "payload": {"panel": "metadata_edit", "file_paths": [str(root)]},
                }
            )
            self.assertTrue(loaded["ok"])

            locked = runtime.handle_request(
                {
                    "request_id": "req_012",
                    "module": "metadata_edit",
                    "action": "lock_config",
                    "payload": {
                        "panel": "metadata_edit",
                        "config": {
                            "operation": "cover_injection",
                            "cover_image_path": str(self.cover_fixture),
                            "ffmpeg_path": str(self.ffmpeg_path),
                            "ffprobe_path": str(self.ffprobe_path),
                        },
                    },
                }
            )
            self.assertTrue(locked["ok"])

            started = runtime.handle_request(
                {
                    "request_id": "req_013",
                    "module": "metadata_edit",
                    "action": "start_cover_injection_task",
                    "payload": {"panel": "metadata_edit"},
                }
            )
            self.assertTrue(started["ok"])
            task_id = started["data"]["task_id"]

            final_result = None
            for _ in range(120):
                result = runtime.handle_request(
                    {
                        "request_id": "req_014",
                        "module": "metadata_edit",
                        "action": "fetch_metadata_edit_result",
                        "payload": {"task_id": task_id},
                    }
                )
                if result["ok"]:
                    final_result = result
                    break
                time.sleep(0.05)

            self.assertIsNotNone(final_result)
            assert final_result is not None
            self.assertEqual(final_result["data"]["success_count"], 1)
            self.assertEqual(final_result["data"]["results"][0]["status"], "ok")


if __name__ == "__main__":
    unittest.main()
