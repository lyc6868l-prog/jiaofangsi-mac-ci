from __future__ import annotations

import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

from dj_runtime_py.transcode_rust_bridge import (
    TranscodeRustBridgeError,
    build_ffmpeg_plan,
    health_check,
    poll_metadata_edit_task,
    poll_transcode_task,
    probe_audio_file,
    scan_audio_targets,
    start_cover_injection_task,
    start_filename_injection_task,
    start_transcode_task,
    stop_metadata_edit_task,
    stop_transcode_task,
)


class TranscodeRustBridgeTest(unittest.TestCase):
    @patch("dj_runtime_py.transcode_rust_bridge._load_module")
    def test_health_check_returns_capabilities(self, mock_load_module) -> None:
        mock_load_module.return_value = types.SimpleNamespace(
            health_check=lambda: '{"ok":true,"capabilities":["build_ffmpeg_plan"]}'
        )

        result = health_check()

        self.assertTrue(result["ok"])
        self.assertIn("build_ffmpeg_plan", result["capabilities"])

    @patch("dj_runtime_py.transcode_rust_bridge._load_module")
    def test_scan_audio_targets_uses_module_wrapper(self, mock_load_module) -> None:
        mock_load_module.return_value = types.SimpleNamespace(
            scan_audio_targets_py=lambda input_paths: '{"ok":true,"targets":%d}' % len(input_paths)
        )

        result = scan_audio_targets(["a.mp3", "b.wav"])

        self.assertTrue(result["ok"])
        self.assertEqual(result["targets"], 2)

    @patch("dj_runtime_py.transcode_rust_bridge._load_module")
    def test_build_mp3_plan_returns_structured_command(self, mock_load_module) -> None:
        mock_load_module.return_value = types.SimpleNamespace(
            build_ffmpeg_plan=lambda *args: '{"ok":true,"args":["-c:a","libmp3lame","-b:a","320k","-ar","44100"],"output_path":"/tmp/out/demo.mp3"}'
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "Demo.wav"
            source.write_bytes(b"RIFFdemo")
            result = build_ffmpeg_plan(
                input_path=str(source),
                output_dir=str(root / "out"),
                output_format="mp3",
                bitrate_kbps=320,
                sample_rate_hz=44100,
                channels="stereo",
            )
            self.assertTrue(result["ok"])
            self.assertIn("libmp3lame", result["args"])
            self.assertIn("320k", result["args"])
            self.assertIn("44100", result["args"])
            self.assertTrue(result["output_path"].endswith(".mp3"))

    @patch("dj_runtime_py.transcode_rust_bridge._load_module")
    def test_probe_audio_file_reports_clean_error_for_invalid_audio(self, mock_load_module) -> None:
        def _raise(_input_path: str, _ffprobe_path=None):
            raise RuntimeError("probe failed")

        mock_load_module.return_value = types.SimpleNamespace(probe_audio_file=_raise)

        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "broken.mp3"
            source.write_bytes(b"not-real-audio")
            with self.assertRaises(TranscodeRustBridgeError):
                probe_audio_file(str(source))

    @patch("dj_runtime_py.transcode_rust_bridge._load_module")
    def test_transcode_task_lifecycle_reports_terminal_status(self, mock_load_module) -> None:
        mock_load_module.return_value = types.SimpleNamespace(
            start_transcode_task=lambda *args: '{"ok":true,"task_id":"task_001"}',
            poll_transcode_task=lambda task_id: '{"ok":true,"task_id":"%s","status":"error"}' % task_id,
            stop_transcode_task=lambda task_id: '{"ok":true,"accepted":true,"task_id":"%s"}' % task_id,
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "missing.wav"
            output_dir = root / "out"

            started = start_transcode_task(
                input_path=str(source),
                output_dir=str(output_dir),
                output_format="mp3",
                bitrate_kbps=320,
                channels="stereo",
            )
            self.assertTrue(started["ok"])
            task_id = started["task_id"]

            final_status = None
            for _ in range(80):
                polled = poll_transcode_task(task_id)
                self.assertTrue(polled["ok"])
                final_status = polled["status"]
                if final_status != "running":
                    break
            self.assertEqual(final_status, "error")

            stopped = stop_transcode_task(task_id)
            self.assertTrue(stopped["ok"])

    @patch("dj_runtime_py.transcode_rust_bridge._load_module")
    def test_metadata_edit_wrappers_call_expected_module_functions(self, mock_load_module) -> None:
        mock_load_module.return_value = types.SimpleNamespace(
            start_filename_injection_task=lambda *args: '{"ok":true,"task_id":"meta_001"}',
            start_cover_injection_task=lambda *args: '{"ok":true,"task_id":"meta_002"}',
            poll_metadata_edit_task=lambda task_id: '{"ok":true,"task_id":"%s","status":"success"}' % task_id,
            stop_metadata_edit_task=lambda task_id: '{"ok":true,"accepted":true,"task_id":"%s"}' % task_id,
        )

        started_filename = start_filename_injection_task("a.mp3", "Remix")
        started_cover = start_cover_injection_task("a.mp3", "cover.png")
        polled = poll_metadata_edit_task("meta_001")
        stopped = stop_metadata_edit_task("meta_001")

        self.assertEqual(started_filename["task_id"], "meta_001")
        self.assertEqual(started_cover["task_id"], "meta_002")
        self.assertEqual(polled["status"], "success")
        self.assertTrue(stopped["accepted"])


if __name__ == "__main__":
    unittest.main()
