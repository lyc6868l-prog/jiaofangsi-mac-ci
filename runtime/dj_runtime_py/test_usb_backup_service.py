from __future__ import annotations

import tempfile
import time
import unittest
import subprocess
from pathlib import Path
from unittest.mock import call, patch

from dj_runtime_py.usb_backup_service import UsbBackupRuntime, UsbBackupRuntimeError, UsbVolume


class UsbBackupRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._access_patcher = patch("dj_runtime_py.usb_backup_service.require_module_access")
        self._access_patcher.start()
        self.addCleanup(self._access_patcher.stop)

    def test_backup_runtime_creates_snapshot_and_lists_latest_versions(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "USB_A"
            source.mkdir()
            (source / "PIONEER").mkdir()
            (source / "Contents").mkdir()
            (source / "Contents" / "demo.mp3").write_bytes(b"demo-music")
            repo_root = root / "repo"

            runtime = UsbBackupRuntime(repo_root=repo_root)
            runtime._list_usb_volumes = lambda: [
                UsbVolume(
                    path=str(source),
                    volume_name="PIONEER",
                    filesystem="exfat",
                    total_bytes=1024 * 1024 * 1024,
                    free_bytes=1024 * 1024 * 512,
                    bus_protocol="USB",
                    serial_number="serial-demo",
                    rekordbox_detected=True,
                    normalized_filesystem="exfat",
                    is_cdj_supported_fs=True,
                    requires_format_before_restore=False,
                )
            ]

            with patch(
                "dj_runtime_py.usb_backup_service.start_backup_task",
                return_value={
                    "task_id": "usb_backup_task_001",
                    "resumed_from_checkpoint": False,
                    "checkpoint_id": None,
                },
            ), patch(
                "dj_runtime_py.usb_backup_service.poll_usb_backup_task",
                side_effect=[
                    {
                        "status": "running",
                        "progress": 0.5,
                        "progress_hint_text": "正在扫描 U 盘内容...",
                        "display_name": "主演出盘",
                        "snapshot_id": None,
                        "total_files": 1,
                        "total_bytes": 9,
                    },
                    {
                        "status": "success",
                        "progress": 1.0,
                        "progress_hint_text": "备份完成。",
                        "display_name": "主演出盘",
                        "snapshot_id": "snapshot_001",
                        "total_files": 1,
                        "total_bytes": 9,
                    },
                ],
            ), patch(
                "dj_runtime_py.usb_backup_service.rust_list_snapshots",
                return_value={
                    "snapshots": [
                        {
                            "snapshot_id": "snapshot_001",
                            "display_name": "主演出盘",
                            "created_at": "2026-04-07T10:00:00Z",
                            "source_volume_name": "PIONEER",
                            "source_filesystem": "exfat",
                            "source_capacity_bytes": 1024,
                            "rekordbox_detected": True,
                            "validate_status": "success",
                            "total_files": 1,
                            "total_directories": 1,
                            "total_bytes": 9,
                        }
                    ]
                },
            ), patch(
                "dj_runtime_py.usb_backup_service.rust_list_pending_backups",
                return_value={"pending_backups": []},
            ):
                started = runtime.handle_request(
                    {
                        "request_id": "req_001",
                        "module": "usb_backup",
                        "action": "start_backup_usb",
                        "payload": {"source_path": str(source), "display_name": "主演出盘"},
                    }
                )
                self.assertTrue(started["ok"])
                task_id = started["data"]["task_id"]

                final_status = "running"
                for _ in range(120):
                    events = runtime.handle_request(
                        {
                            "request_id": "req_002",
                            "module": "usb_backup",
                            "action": "subscribe_task_events",
                            "payload": {"task_id": task_id},
                        }
                    )
                    self.assertTrue(events["ok"])
                    for event in events["data"]["events"]:
                        final_status = event["data"]["status"]
                    if final_status != "running":
                        break
                    time.sleep(0.05)

                self.assertEqual(final_status, "success")

                listed = runtime.handle_request(
                    {
                        "request_id": "req_003",
                        "module": "usb_backup",
                        "action": "list_backup_versions",
                        "payload": {"target_path": str(source)},
                    }
                )
                self.assertTrue(listed["ok"])
                self.assertEqual(len(listed["data"]["latest_versions"]), 1)
                self.assertEqual(listed["data"]["latest_versions"][0]["display_name"], "主演出盘")

    def test_runtime_surfaces_pending_backups_and_resume_flag(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "USB_A"
            source.mkdir()
            runtime = UsbBackupRuntime(repo_root=Path(temp_dir) / "repo")
            runtime._list_usb_volumes = lambda: [
                UsbVolume(
                    path=str(source),
                    volume_name="PIONEER",
                    filesystem="exfat",
                    total_bytes=1024 * 1024 * 1024,
                    free_bytes=1024 * 1024 * 512,
                    bus_protocol="USB",
                    serial_number="serial-demo",
                    rekordbox_detected=True,
                    normalized_filesystem="exfat",
                    is_cdj_supported_fs=True,
                    requires_format_before_restore=False,
                )
            ]

            with patch(
                "dj_runtime_py.usb_backup_service.rust_list_pending_backups",
                return_value={
                    "pending_backups": [
                        {
                            "checkpoint_id": "checkpoint_001",
                            "snapshot_id": "snapshot_resume",
                            "display_name": "主演出盘续传",
                            "created_at": "2026-04-07T10:00:00Z",
                            "updated_at": "2026-04-07T10:05:00Z",
                            "source_root": str(source),
                            "source_volume_name": "PIONEER",
                            "total_files": 100,
                            "completed_files": 40,
                            "total_bytes": 4096,
                            "completed_bytes": 2048,
                            "rekordbox_detected": True,
                        }
                    ]
                },
            ), patch(
                "dj_runtime_py.usb_backup_service.rust_list_snapshots",
                return_value={"snapshots": []},
            ), patch(
                "dj_runtime_py.usb_backup_service.start_backup_task",
                return_value={
                    "task_id": "usb_backup_task_001",
                    "resumed_from_checkpoint": True,
                    "checkpoint_id": None,
                },
            ):
                listed = runtime.handle_request(
                    {
                        "request_id": "req_pending",
                        "module": "usb_backup",
                        "action": "list_backup_versions",
                        "payload": {"target_path": str(source)},
                    }
                )
                self.assertTrue(listed["ok"])
                self.assertEqual(len(listed["data"]["pending_backups"]), 1)

                started = runtime.handle_request(
                    {
                        "request_id": "req_resume",
                        "module": "usb_backup",
                        "action": "start_backup_usb",
                        "payload": {"source_path": str(source)},
                    }
                )
                self.assertTrue(started["ok"])
                self.assertTrue(started["data"]["resumed_from_checkpoint"])

    def test_restore_is_blocked_for_unsupported_filesystem(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "USB_A"
            source.mkdir()
            runtime = UsbBackupRuntime(repo_root=Path(temp_dir) / "repo")
            runtime._list_usb_volumes = lambda: [
                UsbVolume(
                    path=str(source),
                    volume_name="BAD_USB",
                    filesystem="apfs",
                    total_bytes=1024 * 1024 * 1024,
                    free_bytes=1024 * 1024 * 512,
                    bus_protocol="USB",
                    serial_number="serial-demo",
                    rekordbox_detected=False,
                    normalized_filesystem="apfs",
                    is_cdj_supported_fs=False,
                    requires_format_before_restore=True,
                )
            ]

            with patch(
                "dj_runtime_py.usb_backup_service.rust_list_snapshots",
                return_value={
                    "snapshots": [
                        {
                            "snapshot_id": "snapshot_001",
                            "display_name": "主演出盘",
                            "created_at": "2026-04-07T10:00:00Z",
                            "source_volume_name": "PIONEER",
                            "source_filesystem": "exfat",
                            "source_capacity_bytes": 1024,
                            "rekordbox_detected": True,
                            "validate_status": "success",
                            "total_files": 1,
                            "total_directories": 1,
                            "total_bytes": 100,
                        }
                    ]
                },
            ), patch(
                "dj_runtime_py.usb_backup_service.rust_list_pending_backups",
                return_value={"pending_backups": []},
            ):
                listed = runtime.handle_request(
                    {
                        "request_id": "req_fs_list",
                        "module": "usb_backup",
                        "action": "list_backup_versions",
                        "payload": {"target_path": str(source)},
                    }
                )
                self.assertTrue(listed["ok"])
                self.assertFalse(listed["data"]["latest_versions"][0]["can_restore"])

                restore = runtime.handle_request(
                    {
                        "request_id": "req_fs_restore",
                        "module": "usb_backup",
                        "action": "start_restore_snapshot_to_usb",
                        "payload": {
                            "snapshot_id": "snapshot_001",
                            "target_path": str(source),
                        },
                    }
                )
                self.assertFalse(restore["ok"])
                self.assertEqual(restore["error"]["code"], "UNSUPPORTED_FILESYSTEM")

    def test_start_format_usb_launches_macos_diskutil_task(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            target = Path(temp_dir) / "USB_A"
            target.mkdir()
            resolved_target = str(target.resolve())
            runtime = UsbBackupRuntime(repo_root=Path(temp_dir) / "repo")
            call_count = 0

            def _volumes() -> list[UsbVolume]:
                nonlocal call_count
                call_count += 1
                if call_count >= 3:
                    return [
                        UsbVolume(
                            path=resolved_target,
                            volume_name="PIONEER",
                            filesystem="ms-dos fat32",
                            total_bytes=1024 * 1024 * 1024,
                            free_bytes=1024 * 1024 * 512,
                            bus_protocol="USB",
                            serial_number="serial-demo",
                            rekordbox_detected=False,
                            normalized_filesystem="fat32",
                            is_cdj_supported_fs=True,
                            requires_format_before_restore=False,
                            disk_identifier="disk4s1",
                            whole_disk_identifier="disk4",
                        )
                    ]
                return [
                    UsbVolume(
                        path=resolved_target,
                        volume_name="OLD_USB",
                        filesystem="apfs",
                        total_bytes=1024 * 1024 * 1024,
                        free_bytes=1024 * 1024 * 512,
                        bus_protocol="USB",
                        serial_number="serial-demo",
                        rekordbox_detected=False,
                        normalized_filesystem="apfs",
                        is_cdj_supported_fs=False,
                        requires_format_before_restore=True,
                        disk_identifier="disk4s1",
                        whole_disk_identifier="disk4",
                    )
                ]

            runtime._list_usb_volumes = _volumes

            class _Result:
                def __init__(self, stdout: str = "") -> None:
                    self.returncode = 0
                    self.stdout = stdout
                    self.stderr = ""

            with patch("platform.system", return_value="Darwin"), patch.object(
                runtime,
                "_detect_volume_usage",
                return_value=[],
            ), patch(
                "subprocess.run",
                side_effect=[
                    _Result("Device information"),
                    _Result("Unmount successful"),
                    _Result("Finished erase on disk4"),
                ],
            ) as mocked_run:
                started = runtime.handle_request(
                    {
                            "request_id": "req_format",
                            "module": "usb_backup",
                            "action": "start_format_usb",
                            "payload": {
                            "target_path": resolved_target,
                            "filesystem": "fat32",
                            "volume_label": "PIONEER",
                        },
                    }
                )
                self.assertTrue(started["ok"])
                task_id = started["data"]["task_id"]
                final_status = "running"
                for _ in range(160):
                    events = runtime.handle_request(
                        {
                            "request_id": "req_format_poll",
                            "module": "usb_backup",
                            "action": "subscribe_task_events",
                            "payload": {"task_id": task_id},
                        }
                    )
                    for event in events["data"]["events"]:
                        final_status = event["data"]["status"]
                    if final_status != "running":
                        break
                    time.sleep(0.02)
                self.assertEqual(final_status, "success")
                mocked_run.assert_has_calls(
                    [
                        call(
                            ["diskutil", "info", "disk4"],
                            capture_output=True,
                            text=True,
                            check=False,
                            timeout=12,
                        ),
                        call(
                            ["diskutil", "unmountDisk", "disk4"],
                            capture_output=True,
                            text=True,
                            check=False,
                            timeout=25,
                        ),
                        call(
                            ["diskutil", "eraseDisk", "FAT32", "PIONEER", "MBRFormat", "disk4"],
                            capture_output=True,
                            text=True,
                            check=False,
                            timeout=90,
                        ),
                    ]
                )

    def test_start_format_usb_retries_once_after_busy_error(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            target = Path(temp_dir) / "USB_A"
            target.mkdir()
            resolved_target = str(target.resolve())
            runtime = UsbBackupRuntime(repo_root=Path(temp_dir) / "repo")
            call_count = 0

            def _volumes() -> list[UsbVolume]:
                nonlocal call_count
                call_count += 1
                if call_count >= 4:
                    return [
                        UsbVolume(
                            path=resolved_target,
                            volume_name="PIONEER",
                            filesystem="ms-dos fat32",
                            total_bytes=1024 * 1024 * 1024,
                            free_bytes=1024 * 1024 * 512,
                            bus_protocol="USB",
                            serial_number="serial-demo",
                            rekordbox_detected=False,
                            normalized_filesystem="fat32",
                            is_cdj_supported_fs=True,
                            requires_format_before_restore=False,
                            disk_identifier="disk4s1",
                            whole_disk_identifier="disk4",
                        )
                    ]
                return [
                    UsbVolume(
                        path=resolved_target,
                        volume_name="OLD_USB",
                        filesystem="apfs",
                        total_bytes=1024 * 1024 * 1024,
                        free_bytes=1024 * 1024 * 512,
                        bus_protocol="USB",
                        serial_number="serial-demo",
                        rekordbox_detected=False,
                        normalized_filesystem="apfs",
                        is_cdj_supported_fs=False,
                        requires_format_before_restore=True,
                        disk_identifier="disk4s1",
                        whole_disk_identifier="disk4",
                    )
                ]

            runtime._list_usb_volumes = _volumes

            class _Result:
                def __init__(self, returncode: int, stdout: str = "", stderr: str = "") -> None:
                    self.returncode = returncode
                    self.stdout = stdout
                    self.stderr = stderr

            with patch("platform.system", return_value="Darwin"), patch.object(
                runtime,
                "_detect_volume_usage",
                return_value=[],
            ), patch(
                "subprocess.run",
                side_effect=[
                    _Result(0, stdout="Device information"),
                    _Result(0, stdout="Unmount successful"),
                    _Result(1, stderr="Resource busy"),
                    _Result(0, stdout="Unmount successful"),
                    _Result(0, stdout="Finished erase on disk4"),
                ],
            ) as mocked_run:
                started = runtime.handle_request(
                    {
                        "request_id": "req_format_retry",
                        "module": "usb_backup",
                        "action": "start_format_usb",
                        "payload": {
                            "target_path": resolved_target,
                            "filesystem": "fat32",
                            "volume_label": "PIONEER",
                        },
                    }
                )
                self.assertTrue(started["ok"])
                task_id = started["data"]["task_id"]
                final_status = "running"
                for _ in range(220):
                    events = runtime.handle_request(
                        {
                            "request_id": "req_format_retry_poll",
                            "module": "usb_backup",
                            "action": "subscribe_task_events",
                            "payload": {"task_id": task_id},
                        }
                    )
                    for event in events["data"]["events"]:
                        final_status = event["data"]["status"]
                    if final_status != "running":
                        break
                    time.sleep(0.02)

                self.assertEqual(final_status, "success")
                self.assertEqual(mocked_run.call_count, 5)

    def test_wait_for_formatted_volume_raises_when_filesystem_not_verified(self) -> None:
        runtime = UsbBackupRuntime(repo_root=Path("/tmp/repo"))
        mismatch_volume = UsbVolume(
            path="/Volumes/PIONEER",
            volume_name="PIONEER",
            filesystem="apfs",
            total_bytes=1024,
            free_bytes=512,
            bus_protocol="USB",
            serial_number="serial-demo",
            rekordbox_detected=False,
            normalized_filesystem="apfs",
            is_cdj_supported_fs=False,
            requires_format_before_restore=True,
            disk_identifier="disk4s1",
            whole_disk_identifier="disk4",
        )

        with patch.object(
            runtime,
            "_find_volume_by_whole_disk_identifier",
            return_value=mismatch_volume,
        ), patch(
            "dj_runtime_py.usb_backup_service.time.sleep",
            return_value=None,
        ), patch(
            "dj_runtime_py.usb_backup_service.time.monotonic",
            side_effect=[0.0, 0.1, 12.1],
        ):
            with self.assertRaisesRegex(UsbBackupRuntimeError, "不是期望的 ExFAT"):
                runtime._wait_for_formatted_volume(
                    whole_disk_identifier="disk4",
                    expected_filesystem="exfat",
                    expected_volume_label="PIONEER",
                )

    def test_wait_for_formatted_volume_accepts_label_mismatch_when_filesystem_matches(self) -> None:
        runtime = UsbBackupRuntime(repo_root=Path("/tmp/repo"))
        mismatch_volume = UsbVolume(
            path="/Volumes/演出盘",
            volume_name="演出盘",
            filesystem="exfat",
            total_bytes=1024,
            free_bytes=512,
            bus_protocol="USB",
            serial_number="serial-demo",
            rekordbox_detected=False,
            normalized_filesystem="exfat",
            is_cdj_supported_fs=True,
            requires_format_before_restore=False,
            disk_identifier="disk4s1",
            whole_disk_identifier="disk4",
        )

        with patch.object(
            runtime,
            "_find_volume_by_whole_disk_identifier",
            return_value=mismatch_volume,
        ), patch(
            "dj_runtime_py.usb_backup_service.time.sleep",
            return_value=None,
        ), patch(
            "dj_runtime_py.usb_backup_service.time.monotonic",
            side_effect=[0.0, 0.1],
        ):
            volume = runtime._wait_for_formatted_volume(
                whole_disk_identifier="disk4",
                expected_filesystem="exfat",
                expected_volume_label="PIONEER中文",
            )

        self.assertEqual(volume.volume_name, "演出盘")
        self.assertEqual(volume.normalized_filesystem, "exfat")

    def test_format_failure_message_adds_retry_hint_for_busy_disk(self) -> None:
        runtime = UsbBackupRuntime(repo_root=Path("/tmp/repo"))
        message = runtime._format_failure_message("Resource busy")
        self.assertIn("正被占用", message)
        self.assertIn("点击刷新再重试", message)

    def test_eject_usb_volume_calls_diskutil_eject(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            target = Path(temp_dir) / "USB_A"
            target.mkdir()
            resolved_target = str(target.resolve())
            runtime = UsbBackupRuntime(repo_root=Path(temp_dir) / "repo")
            call_count = 0

            def _volumes() -> list[UsbVolume]:
                nonlocal call_count
                call_count += 1
                if call_count >= 2:
                    return []
                return [
                    UsbVolume(
                        path=resolved_target,
                        volume_name="PIONEER",
                        filesystem="exfat",
                        total_bytes=1024 * 1024 * 1024,
                        free_bytes=1024 * 1024 * 512,
                        bus_protocol="USB",
                        serial_number="serial-demo",
                        rekordbox_detected=True,
                        normalized_filesystem="exfat",
                        is_cdj_supported_fs=True,
                        requires_format_before_restore=False,
                        disk_identifier="disk4s1",
                        whole_disk_identifier="disk4",
                    )
                ]

            runtime._list_usb_volumes = _volumes


            class _Result:
                def __init__(self) -> None:
                    self.returncode = 0
                    self.stdout = "Disk ejected"
                    self.stderr = ""

            with patch("platform.system", return_value="Darwin"), patch.object(
                runtime,
                "_detect_volume_usage",
                return_value=[],
            ), patch(
                "subprocess.run",
                side_effect=[_Result(), _Result()],
            ) as mocked_run:
                response = runtime.handle_request(
                    {
                        "request_id": "req_eject",
                        "module": "usb_backup",
                        "action": "eject_usb_volume",
                        "payload": {"target_path": resolved_target},
                    }
                )
                self.assertTrue(response["ok"])
                self.assertEqual(response["data"]["status"], "ejected")
                self.assertEqual(response["data"]["volume_name"], "PIONEER")
                mocked_run.assert_has_calls(
                    [
                        call(
                            ["diskutil", "info", "disk4"],
                            capture_output=True,
                            text=True,
                            check=False,
                            timeout=10,
                        ),
                        call(
                            ["diskutil", "eject", "disk4"],
                            capture_output=True,
                            text=True,
                            check=False,
                            timeout=25,
                        ),
                    ]
                )

    def test_eject_usb_volume_retries_once_after_busy_error(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            target = Path(temp_dir) / "USB_A"
            target.mkdir()
            resolved_target = str(target.resolve())
            runtime = UsbBackupRuntime(repo_root=Path(temp_dir) / "repo")
            volume = UsbVolume(
                path=resolved_target,
                volume_name="PIONEER",
                filesystem="exfat",
                total_bytes=1024 * 1024 * 1024,
                free_bytes=1024 * 1024 * 512,
                bus_protocol="USB",
                serial_number="serial-demo",
                rekordbox_detected=True,
                normalized_filesystem="exfat",
                is_cdj_supported_fs=True,
                requires_format_before_restore=False,
                disk_identifier="disk4s1",
                whole_disk_identifier="disk4",
            )
            listed_volumes = [[volume], [volume], []]

            def _volumes() -> list[UsbVolume]:
                if listed_volumes:
                    return listed_volumes.pop(0)
                return []

            runtime._list_usb_volumes = _volumes

            class _Result:
                def __init__(self, returncode: int, stdout: str = "", stderr: str = "") -> None:
                    self.returncode = returncode
                    self.stdout = stdout
                    self.stderr = stderr

            with patch("platform.system", return_value="Darwin"), patch.object(
                runtime,
                "_detect_volume_usage",
                return_value=["Finder"],
            ), patch(
                "subprocess.run",
                side_effect=[
                    _Result(0, stdout="Device information"),
                    _Result(1, stderr="Resource busy"),
                    _Result(0, stdout="Disk ejected"),
                ],
            ), patch(
                "dj_runtime_py.usb_backup_service.time.sleep",
                return_value=None,
            ):
                response = runtime.handle_request(
                    {
                        "request_id": "req_eject_retry",
                        "module": "usb_backup",
                        "action": "eject_usb_volume",
                        "payload": {"target_path": resolved_target},
                    }
                )

            self.assertTrue(response["ok"])
            self.assertEqual(response["data"]["status"], "ejected")

    def test_eject_usb_volume_reports_verify_failure_when_still_visible(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            target = Path(temp_dir) / "USB_A"
            target.mkdir()
            resolved_target = str(target.resolve())
            runtime = UsbBackupRuntime(repo_root=Path(temp_dir) / "repo")
            volume = UsbVolume(
                path=resolved_target,
                volume_name="PIONEER",
                filesystem="exfat",
                total_bytes=1024 * 1024 * 1024,
                free_bytes=1024 * 1024 * 512,
                bus_protocol="USB",
                serial_number="serial-demo",
                rekordbox_detected=True,
                normalized_filesystem="exfat",
                is_cdj_supported_fs=True,
                requires_format_before_restore=False,
                disk_identifier="disk4s1",
                whole_disk_identifier="disk4",
            )
            runtime._list_usb_volumes = lambda: [volume]

            class _Result:
                def __init__(self) -> None:
                    self.returncode = 0
                    self.stdout = "Disk ejected"
                    self.stderr = ""

            with patch("platform.system", return_value="Darwin"), patch.object(
                runtime,
                "_detect_volume_usage",
                return_value=[],
            ), patch(
                "subprocess.run",
                side_effect=[_Result(), _Result()],
            ), patch(
                "dj_runtime_py.usb_backup_service.time.sleep",
                return_value=None,
            ):
                response = runtime.handle_request(
                    {
                        "request_id": "req_eject_verify_fail",
                        "module": "usb_backup",
                        "action": "eject_usb_volume",
                        "payload": {"target_path": resolved_target},
                    }
                )

            self.assertFalse(response["ok"])
            self.assertIn("当前仍能检测到 PIONEER", response["error"]["message"])

    def test_volume_from_path_returns_none_when_statvfs_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            target = Path(temp_dir) / "USB_A"
            target.mkdir()
            runtime = UsbBackupRuntime(repo_root=Path(temp_dir) / "repo")

            with patch.object(runtime, "_diskutil_info", return_value=None), patch(
                "dj_runtime_py.usb_backup_service.os.statvfs",
                side_effect=OSError("device busy"),
            ):
                self.assertIsNone(runtime._volume_from_path(target))

    def test_diskutil_info_returns_none_when_diskutil_times_out(self) -> None:
        runtime = UsbBackupRuntime(repo_root=Path("/tmp/repo"))

        with patch(
            "dj_runtime_py.usb_backup_service.subprocess.run",
            side_effect=subprocess.TimeoutExpired(cmd=["diskutil", "info"], timeout=2.5),
        ):
            self.assertIsNone(runtime._diskutil_info(Path("/Volumes/PIONEER")))

    def test_list_usb_volumes_uses_diskutil_list_mount_points(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            mount_path = Path(temp_dir) / "PIONEER"
            mount_path.mkdir()
            runtime = UsbBackupRuntime(repo_root=Path("/tmp/repo"))
            expected_volume = UsbVolume(
                path=str(mount_path),
                volume_name="PIONEER",
                filesystem="exfat",
                total_bytes=1024,
                free_bytes=512,
                bus_protocol="USB",
                serial_number="serial-demo",
                rekordbox_detected=True,
                normalized_filesystem="exfat",
                is_cdj_supported_fs=True,
                requires_format_before_restore=False,
            )

            with patch("platform.system", return_value="Darwin"), patch.object(
                runtime,
                "_diskutil_list_external_physical",
                return_value={
                    "AllDisksAndPartitions": [
                        {
                            "DeviceIdentifier": "disk4",
                            "Partitions": [
                                {"MountPoint": str(mount_path)},
                                {"MountPoint": str(mount_path)},
                                {"DeviceIdentifier": "disk4s2"},
                            ],
                        }
                    ]
                },
            ), patch.object(runtime, "_volume_from_path", return_value=expected_volume) as mocked_volume:
                volumes = runtime._list_usb_volumes(force_refresh=True)

            self.assertEqual(len(volumes), 1)
            self.assertEqual(volumes[0].path, str(mount_path))
            mocked_volume.assert_called_once_with(mount_path)

    def test_list_usb_volumes_uses_short_lived_cache(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            mount_path = Path(temp_dir) / "PIONEER"
            mount_path.mkdir()
            runtime = UsbBackupRuntime(repo_root=Path("/tmp/repo"))
            expected_volume = UsbVolume(
                path=str(mount_path),
                volume_name="PIONEER",
                filesystem="exfat",
                total_bytes=1024,
                free_bytes=512,
                bus_protocol="USB",
                serial_number="serial-demo",
                rekordbox_detected=True,
                normalized_filesystem="exfat",
                is_cdj_supported_fs=True,
                requires_format_before_restore=False,
            )

            with patch("platform.system", return_value="Darwin"), patch.object(
                runtime,
                "_diskutil_list_external_physical",
                return_value={"AllDisksAndPartitions": [{"MountPoint": str(mount_path)}]},
            ) as mocked_list, patch.object(runtime, "_volume_from_path", return_value=expected_volume):
                first = runtime._list_usb_volumes(force_refresh=False)
                second = runtime._list_usb_volumes(force_refresh=False)

            self.assertEqual(len(first), 1)
            self.assertEqual(len(second), 1)
            self.assertEqual(mocked_list.call_count, 1)

    def test_delete_backup_version_calls_rust_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            runtime = UsbBackupRuntime(repo_root=Path(temp_dir) / "repo")
            with patch(
                "dj_runtime_py.usb_backup_service.rust_delete_snapshot",
                return_value={
                    "deleted_snapshots": 1,
                    "deleted_objects": 2,
                    "deleted_bytes": 2048,
                    "snapshot_id": "snapshot_001",
                },
            ):
                response = runtime.handle_request(
                    {
                        "request_id": "req_delete",
                        "module": "usb_backup",
                        "action": "delete_backup_version",
                        "payload": {"snapshot_id": "snapshot_001"},
                    }
                )
                self.assertTrue(response["ok"])
                self.assertEqual(response["data"]["deleted_snapshots"], 1)

    def test_cleanup_repository_calls_rust_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            runtime = UsbBackupRuntime(repo_root=Path(temp_dir) / "repo")
            with patch(
                "dj_runtime_py.usb_backup_service.rust_cleanup_repository",
                return_value={"deleted_objects": 3, "deleted_bytes": 4096},
            ):
                response = runtime.handle_request(
                    {
                        "request_id": "req_cleanup",
                        "module": "usb_backup",
                        "action": "cleanup_repository",
                        "payload": {},
                    }
                )
                self.assertTrue(response["ok"])
                self.assertEqual(response["data"]["deleted_objects"], 3)


if __name__ == "__main__":
    unittest.main()
