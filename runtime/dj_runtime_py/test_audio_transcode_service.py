from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from unittest.mock import patch

from dj_runtime_py.audio_transcode_service import AudioTranscodeRuntime


class AudioTranscodeRuntimeTest(unittest.TestCase):
    def test_resolve_output_dir_supports_custom_and_source_subdir(self) -> None:
        runtime = AudioTranscodeRuntime()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "music" / "Demo.wav"
            source.parent.mkdir(parents=True)
            source.write_bytes(b"demo")

            custom_dir = runtime._resolve_output_dir(
                raw_path=str(source),
                input_path=source,
                output_mode="custom",
                configured_output_dir=str(root / "out"),
                output_format="mp3",
            )
            subdir = runtime._resolve_output_dir(
                raw_path=str(source),
                input_path=source,
                output_mode="source_subdir",
                configured_output_dir=None,
                output_format="flac",
            )

            self.assertEqual(custom_dir, str((root / "out").resolve()))
            self.assertIn("music_FLAC_", Path(subdir).name)
            self.assertEqual(Path(subdir).parent.resolve(), source.parent.resolve())

    def test_resolve_task_output_dir_creates_single_shared_source_subdir(self) -> None:
        runtime = AudioTranscodeRuntime()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            first = root / "music" / "set_a" / "Demo A.wav"
            second = root / "music" / "set_b" / "Demo B.wav"
            first.parent.mkdir(parents=True)
            second.parent.mkdir(parents=True)
            first.write_bytes(b"demo")
            second.write_bytes(b"demo")

            output_dir = runtime._resolve_task_output_dir(
                file_paths=[str(first), str(second)],
                output_mode="source_subdir",
                configured_output_dir=None,
                output_format="mp3",
            )

            self.assertIn("music_MP3_", Path(output_dir).name)
            self.assertEqual(Path(output_dir).parent.resolve(), (root / "music").resolve())

    def test_humanize_runtime_error_maps_common_messages(self) -> None:
        runtime = AudioTranscodeRuntime()
        self.assertEqual(
            runtime._humanize_runtime_error("probe failed: no such file or directory"),
            "文件读取失败，请确认源文件仍然存在。",
        )
        self.assertEqual(
            runtime._humanize_runtime_error("spawn failed: ffmpeg missing"),
            "转码器启动失败，请检查 ffmpeg 和 ffprobe 是否可用。",
        )
        self.assertEqual(
            runtime._humanize_runtime_error("permission denied"),
            "文件写入失败，请检查输出目录权限。",
        )

    def test_start_task_uses_resume_queue_when_present(self) -> None:
        runtime = AudioTranscodeRuntime()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            first = root / "A.wav"
            second = root / "B.wav"
            first.write_bytes(b"demo")
            second.write_bytes(b"demo")

            runtime._panels["transcode"].file_paths = [str(first)]
            runtime._panels["transcode"].resume_queue = [str(second)]
            runtime._panels["transcode"].config = {
                "output_mode": "custom",
                "output_dir": str(root / "out"),
                "output_format": "mp3",
                "channels": "stereo",
            }

            with patch.object(runtime, "_start_worker") as mock_start_worker:
                task = runtime._start_task()

            mock_start_worker.assert_called_once_with(task)
            self.assertEqual(task.file_paths, [str(second)])
            self.assertEqual(task.status, "running")


if __name__ == "__main__":
    unittest.main()
