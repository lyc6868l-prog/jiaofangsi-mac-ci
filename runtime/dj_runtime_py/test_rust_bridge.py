from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from dj_runtime_py.rust_bridge import (
    RustBridgeError,
    delete_paths,
    health_check,
    poll_scan_music_task,
    scan_music_by_content,
    scan_music_by_tags,
    start_scan_music_by_content_task,
    stop_scan_music_task,
)


class RustBridgeTest(unittest.TestCase):
    def test_health_check_imports_or_fails_cleanly(self) -> None:
        try:
            result = health_check()
        except RustBridgeError as error:
            self.assertIsInstance(str(error), str)
        else:
            self.assertTrue(result["ok"])
            self.assertIn("health_check", result["capabilities"])

    def test_tags_scan_real_same_music_returns_structured_result(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "A.mp3").write_bytes(b"fake audio a")
            (root / "B.mp3").write_bytes(b"fake audio b")
            try:
                result = scan_music_by_tags([temp_dir], ["title", "artist"], False)
            except RustBridgeError as error:
                self.assertIsInstance(str(error), str)
            else:
                self.assertTrue(result["ok"])
                self.assertIn("duplicate_count", result)
                self.assertIsInstance(result["duplicate_count"], int)
                self.assertIn("groups", result)
                self.assertIsInstance(result["groups"], list)
                self.assertEqual(result["duplicate_count"], len(result["groups"]))
                for group in result["groups"]:
                    self.assertIsInstance(group, dict)
                    self.assertIn("group_name", group)
                    self.assertIsInstance(group["group_name"], str)
                    self.assertIn("entries", group)
                    self.assertIsInstance(group["entries"], list)
                    for entry in group["entries"]:
                        self.assertIsInstance(entry, dict)
                        self.assertIn("path", entry)
                        self.assertIn("name", entry)
                        self.assertIn("size", entry)
                        self.assertIn("is_auto_keep", entry)
                        self.assertIn("is_selected_to_delete", entry)

    def test_content_scan_returns_structured_result_or_fails_cleanly(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "A.mp3").write_bytes(b"fake audio a")
            (root / "B.mp3").write_bytes(b"fake audio b")
            try:
                result = scan_music_by_content([temp_dir], False)
            except RustBridgeError as error:
                self.assertIsInstance(str(error), str)
            else:
                self.assertTrue(result["ok"])
                self.assertIn("duplicate_count", result)
                self.assertIsInstance(result["duplicate_count"], int)
                self.assertIn("groups", result)
                self.assertIsInstance(result["groups"], list)

    def test_async_content_scan_task_lifecycle_or_fails_cleanly(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "A.mp3").write_bytes(b"fake audio a")
            (root / "B.mp3").write_bytes(b"fake audio b")
            try:
                started = start_scan_music_by_content_task(
                    [str(root / "A.mp3"), str(root / "B.mp3")],
                    False,
                )
            except RustBridgeError as error:
                self.assertIsInstance(str(error), str)
            else:
                self.assertTrue(started["ok"])
                task_id = started["task_id"]
                polled = poll_scan_music_task(task_id)
                self.assertTrue(polled["ok"])
                self.assertEqual(polled["task_id"], task_id)
                self.assertIn(polled["status"], {"running", "success", "cancelled", "error"})
                stopped = stop_scan_music_task(task_id)
                self.assertTrue(stopped["ok"])
                self.assertTrue(stopped["accepted"])

    def test_delete_paths_removes_file_or_fails_cleanly(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            target = root / "Delete Me.mp3"
            target.write_bytes(b"1234")
            try:
                result = delete_paths([str(target)], False)
            except RustBridgeError as error:
                self.assertIsInstance(str(error), str)
            else:
                self.assertTrue(result["ok"])
                self.assertEqual(result["deleted_count"], 1)
                self.assertFalse(result["move_to_recycle_bin"])
                self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
