from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from dj_runtime_py.unlock_music_service import UnlockMusicRuntime
from dj_runtime_py.unlock_node_bridge import UnlockNodeBridgeError


class _FakeBridge:
    def __init__(self, *, fail_on: str | None = None, startup_error: str | None = None) -> None:
        self.fail_on = fail_on
        self.startup_error = startup_error
        self.ensure_started_called = 0
        self.closed = False

    def ensure_started(self) -> None:
        self.ensure_started_called += 1
        if self.startup_error is not None:
            raise UnlockNodeBridgeError("INTERNAL_ERROR", self.startup_error)

    def unlock_file(
        self,
        *,
        input_path: str,
        output_dir: str,
        overwrite: bool,
        keep_source: bool,
    ) -> dict[str, object]:
        if self.fail_on is not None and Path(input_path).name == self.fail_on:
            raise UnlockNodeBridgeError("UNLOCK_FAILED", f"failed: {self.fail_on}")
        return {
            "result": {
                "input_path": input_path,
                "output_path": str(Path(output_dir) / (Path(input_path).stem + ".mp3")),
                "success": True,
                "error": None,
            }
        }

    def close(self) -> None:
        self.closed = True


class UnlockMusicRuntimeTest(unittest.TestCase):
    def test_load_targets_collects_supported_files_only(self) -> None:
        runtime = UnlockMusicRuntime(bridge=_FakeBridge())
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "demo.ncm").write_bytes(b"demo")
            (root / "ignore.txt").write_text("demo", encoding="utf-8")

            response = runtime.handle_request(
                {
                    "request_id": "req_001",
                    "module": "unlock_music",
                    "action": "load_targets",
                    "payload": {"panel": "unlock", "file_paths": [str(root)]},
                }
            )

            self.assertTrue(response["ok"])
            self.assertEqual(response["data"]["file_count"], 1)
            self.assertTrue(response["data"]["file_paths"][0].endswith("demo.ncm"))

    def test_start_task_records_partial_failures(self) -> None:
        bridge = _FakeBridge(fail_on="bad.ncm")
        runtime = UnlockMusicRuntime(bridge=bridge)
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            first = root / "good.ncm"
            second = root / "bad.ncm"
            first.write_bytes(b"demo")
            second.write_bytes(b"demo")

            runtime._panels["unlock"].file_paths = [str(first), str(second)]
            runtime._panels["unlock"].config = {
                "output_dir": str(root / "out"),
                "overwrite": False,
                "keep_source": True,
            }
            with patch.object(runtime, "_start_worker"):
                task = runtime._start_task()

            runtime._run_task_worker(task.task_id)

            self.assertGreaterEqual(bridge.ensure_started_called, 1)
            self.assertEqual(task.status, "success")
            self.assertEqual(task.success_count, 1)
            self.assertEqual(task.failed_count, 1)
            self.assertEqual(len(task.results), 2)
            self.assertEqual(task.results[1]["error"], "failed: bad.ncm")

    def test_start_task_creates_timestamped_output_dir_under_source_when_missing(self) -> None:
        runtime = UnlockMusicRuntime(bridge=_FakeBridge())
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source_dir = root / "album"
            source_dir.mkdir()
            source = source_dir / "demo.ncm"
            source.write_bytes(b"demo")

            runtime._panels["unlock"].file_paths = [str(source)]
            runtime._panels["unlock"].config = {
                "output_dir": str(root / "missing-output"),
                "overwrite": False,
                "keep_source": True,
            }
            with patch.object(runtime, "_start_worker"):
                task = runtime._start_task()

            output_dir = Path(str(task.config["output_dir"]))
            self.assertTrue(output_dir.exists())
            self.assertTrue(output_dir.is_dir())
            self.assertEqual(output_dir.parent, source_dir)
            self.assertTrue(output_dir.name.startswith("解锁输出-"))

    def test_start_task_reports_bridge_startup_error(self) -> None:
        runtime = UnlockMusicRuntime(bridge=_FakeBridge(startup_error="worker boom"))
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "demo.ncm"
            source.write_bytes(b"demo")

            runtime._panels["unlock"].file_paths = [str(source)]
            runtime._panels["unlock"].config = {
                "output_dir": str(root / "out"),
                "overwrite": True,
                "keep_source": False,
            }
            with patch.object(runtime, "_start_worker"):
                task = runtime._start_task()

            runtime._run_task_worker(task.task_id)

            self.assertEqual(task.status, "error")
            self.assertEqual(task.error_message, "worker boom")
            self.assertEqual(runtime._panels["unlock"].status, "error")

    def test_close_delegates_to_bridge(self) -> None:
        bridge = _FakeBridge()
        runtime = UnlockMusicRuntime(bridge=bridge)
        runtime.close()
        self.assertTrue(bridge.closed)


if __name__ == "__main__":
    unittest.main()
