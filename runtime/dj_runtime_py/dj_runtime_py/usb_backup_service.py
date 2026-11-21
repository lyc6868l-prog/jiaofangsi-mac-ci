from __future__ import annotations

import json
import os
import plistlib
import platform
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from platformdirs import user_data_dir

from .access_control import AccessControlError, require_module_access
from .protocol import ApiError, EventEnvelope, RequestEnvelope, ResponseEnvelope, iso_now
from .usb_backup_rust_bridge import (
    UsbBackupRustBridgeError,
    cleanup_usb_backup_task,
    cleanup_repository as rust_cleanup_repository,
    delete_snapshot as rust_delete_snapshot,
    health_check as rust_health_check,
    list_pending_backups as rust_list_pending_backups,
    list_snapshots as rust_list_snapshots,
    poll_usb_backup_task,
    start_backup_task,
    start_restore_task,
    start_validate_task,
    stop_usb_backup_task,
)
from .usb_storage_provider_base import UsbVolumeInfo
from .usb_storage_provider_macos import MacOSUsbStorageProvider
from .usb_storage_provider_windows import WindowsUsbStorageProvider

MODULE = "usb_backup"
ACTIONS = {
    "list_usb_volumes",
    "list_backup_versions",
    "start_backup_usb",
    "start_restore_snapshot_to_usb",
    "start_format_usb",
    "start_validate_snapshot",
    "delete_backup_version",
    "cleanup_repository",
    "eject_usb_volume",
    "stop_task",
    "subscribe_task_events",
}
EVENTS = {"task_created", "task_progress", "task_status_changed", "task_finished"}
TERMINAL_STATUSES = {"success", "cancelled", "error"}
SUPPORTED_CDJ_FILESYSTEMS = {"fat32", "exfat"}


class UsbBackupRuntimeError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class _DiskutilCommandError(Exception):
    def __init__(self, kind: str, message: str) -> None:
        super().__init__(message)
        self.kind = kind
        self.message = message


@dataclass
class UsbVolume:
    path: str
    volume_name: str
    filesystem: str | None
    total_bytes: int
    free_bytes: int
    bus_protocol: str | None
    serial_number: str | None
    rekordbox_detected: bool
    normalized_filesystem: str | None = None
    is_cdj_supported_fs: bool = False
    requires_format_before_restore: bool = True
    disk_identifier: str | None = None
    whole_disk_identifier: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "path": self.path,
            "volume_name": self.volume_name,
            "filesystem": self.filesystem,
            "total_bytes": self.total_bytes,
            "free_bytes": self.free_bytes,
            "bus_protocol": self.bus_protocol,
            "serial_number": self.serial_number,
            "rekordbox_detected": self.rekordbox_detected,
            "normalized_filesystem": self.normalized_filesystem,
            "is_cdj_supported_fs": self.is_cdj_supported_fs,
            "requires_format_before_restore": self.requires_format_before_restore,
            "disk_identifier": self.disk_identifier,
            "whole_disk_identifier": self.whole_disk_identifier,
        }

    @classmethod
    def from_info(cls, info: UsbVolumeInfo) -> UsbVolume:
        return cls(
            path=info.path,
            volume_name=info.volume_name,
            filesystem=info.filesystem,
            total_bytes=info.total_bytes,
            free_bytes=info.free_bytes,
            bus_protocol=info.bus_protocol,
            serial_number=info.serial_number,
            rekordbox_detected=info.rekordbox_detected,
            normalized_filesystem=info.normalized_filesystem,
            is_cdj_supported_fs=info.is_cdj_supported_fs,
            requires_format_before_restore=info.requires_format_before_restore,
            disk_identifier=info.disk_identifier,
            whole_disk_identifier=info.whole_disk_identifier,
        )


class TaskState:
    def __init__(
        self,
        *,
        task_id: str,
        task_type: str,
        rust_task_id: str | None,
        source_path: str | None = None,
        target_path: str | None = None,
        snapshot_id: str | None = None,
    ) -> None:
        self.task_id = task_id
        self.task_type = task_type
        self.rust_task_id = rust_task_id
        self.source_path = source_path
        self.target_path = target_path
        self.snapshot_id = snapshot_id
        self.status = "running"
        self.progress = 0.01
        self.progress_hint_text = "任务已创建，等待执行..."
        self.display_name: str | None = None
        self.total_files = 0
        self.total_bytes = 0
        self.restored_files = 0
        self.validated_files = 0
        self.error_message: str | None = None
        self.resumed_from_checkpoint = False
        self.checkpoint_id: str | None = None
        self.restore_validation: dict[str, Any] | None = None
        self.created_at = iso_now()
        self.updated_at = self.created_at
        self._finished_emitted = False

    def summary(self) -> dict[str, Any]:
        return {
            "task_id": self.task_id,
            "task_type": self.task_type,
            "status": self.status,
            "progress": self.progress,
            "progress_hint_text": self.progress_hint_text,
            "display_name": self.display_name,
            "snapshot_id": self.snapshot_id,
            "source_path": self.source_path,
            "target_path": self.target_path,
            "total_files": self.total_files,
            "total_bytes": self.total_bytes,
            "restored_files": self.restored_files,
            "validated_files": self.validated_files,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "error_message": self.error_message,
            "resumed_from_checkpoint": self.resumed_from_checkpoint,
            "checkpoint_id": self.checkpoint_id,
            "restore_validation": self.restore_validation,
        }


def _humanize_usb_backup_error(exc: Exception) -> str:
    message = str(exc).strip()
    lowered = message.lower()
    if "permission" in lowered:
        return "磁盘操作被系统拒绝，请检查权限后重试。"
    if "not found" in lowered or "no such file" in lowered:
        return "目标设备或文件不存在，请刷新后重试。"
    if "timeout" in lowered or "timed out" in lowered:
        return "磁盘操作超时，请稍后重试。"
    if "poisoned" in lowered:
        return "备份任务状态异常，请重新操作。"
    return "备份任务失败，请稍后重试。"


class UsbBackupRuntime:
    def __init__(self, repo_root: Path | None = None) -> None:
        default_repo_root = Path(user_data_dir("JiaoFangSiDJ")) / "usb_backup" / "repo"
        self._repo_root = repo_root or default_repo_root
        self._tasks: dict[str, TaskState] = {}
        self._events: list[EventEnvelope] = []
        self._events_lock = threading.Lock()
        self._tasks_lock = threading.Lock()
        self._task_index = 0
        self._volume_cache: list[UsbVolume] = []
        self._volume_cache_deadline = 0.0
        self._volume_cache_lock = threading.Lock()
        self._storage_provider = self._create_storage_provider()

    def _create_storage_provider(self):
        system = platform.system()
        if system == "Darwin":
            return MacOSUsbStorageProvider()
        elif system == "Windows":
            return WindowsUsbStorageProvider()
        else:
            raise UsbBackupRuntimeError("UNSUPPORTED_PLATFORM", f"不支持的平台: {system}")

    def _list_usb_volumes(self, force_refresh: bool = False) -> list[UsbVolume]:
        infos = self._storage_provider.list_volumes(force_refresh=force_refresh)
        return [UsbVolume.from_info(info) for info in infos]

    def _match_volume(self, path: str | None, *, force_refresh: bool = False) -> UsbVolume | None:
        if path is None:
            return None
        info = self._storage_provider.match_volume(path, force_refresh=force_refresh)
        if info:
            return UsbVolume.from_info(info)
        return None

    def _find_volume_by_whole_disk_identifier(
        self, whole_disk_identifier: str, *, force_refresh: bool = False
    ) -> UsbVolume | None:
        info = self._storage_provider.find_volume_by_whole_disk_identifier(
            whole_disk_identifier, force_refresh=force_refresh
        )
        if info:
            return UsbVolume.from_info(info)
        return None

    def handle_request(self, raw_request: dict[str, Any]) -> dict[str, Any]:
        request_id = raw_request.get("request_id")
        try:
            request = RequestEnvelope.from_dict(raw_request)
            if request.module != MODULE:
                raise UsbBackupRuntimeError("INVALID_MODULE", "module 必须是 usb_backup。")
            if request.action not in ACTIONS:
                raise UsbBackupRuntimeError("INVALID_CONFIG", f"未知 action: {request.action}")
            require_module_access(MODULE, request.action)
            handler = getattr(self, f"_handle_{request.action}", None)
            if handler is None:
                raise UsbBackupRuntimeError("INVALID_CONFIG", f"action 未实现: {request.action}")
            data = handler(request.payload)
            return ResponseEnvelope(request.request_id, True, data, None).to_dict()
        except ValueError as exc:
            return ResponseEnvelope(
                request_id,
                False,
                None,
                ApiError("INVALID_CONFIG", "请求参数不合法，请检查后重试。"),
            ).to_dict()
        except AccessControlError as exc:
            return ResponseEnvelope(request_id, False, None, ApiError(exc.code, exc.message)).to_dict()
        except UsbBackupRuntimeError as exc:
            return ResponseEnvelope(request_id, False, None, ApiError(exc.code, exc.message)).to_dict()
        except Exception as exc:
            return ResponseEnvelope(
                request_id,
                False,
                None,
                ApiError("INTERNAL_ERROR", _humanize_usb_backup_error(exc)),
            ).to_dict()

    def _handle_list_usb_volumes(self, payload: dict[str, Any]) -> dict[str, Any]:
        force_refresh = bool(payload.get("force_refresh", False))
        volumes = self._list_usb_volumes(force_refresh=force_refresh)
        selected_path = payload.get("selected_path")
        return {
            "volumes": [volume.to_dict() for volume in volumes],
            "selected_path": selected_path if isinstance(selected_path, str) else None,
            "core": rust_health_check(),
        }

    def _handle_list_backup_versions(self, payload: dict[str, Any]) -> dict[str, Any]:
        target_path = payload.get("target_path")
        target_volume = self._match_volume(target_path) if isinstance(target_path, str) else None
        snapshots = rust_list_snapshots(str(self._repo_root)).get("snapshots", [])
        pending_backups = rust_list_pending_backups(str(self._repo_root)).get("pending_backups", [])
        versions = [self._enrich_snapshot(snapshot, target_volume) for snapshot in snapshots if isinstance(snapshot, dict)]
        latest_versions = versions[:3]
        return {
            "repo_root": str(self._repo_root),
            "versions": versions,
            "latest_versions": latest_versions,
            "pending_backups": [item for item in pending_backups if isinstance(item, dict)],
            "target_volume": target_volume.to_dict() if target_volume else None,
            "can_restore_any": any(item["can_restore"] for item in latest_versions),
        }

    def _handle_start_backup_usb(self, payload: dict[str, Any]) -> dict[str, Any]:
        source_path = self._require_path(payload.get("source_path"), "source_path")
        display_name = payload.get("display_name")
        if display_name is not None and not isinstance(display_name, str):
            raise UsbBackupRuntimeError("INVALID_CONFIG", "display_name 必须是字符串。")
        volume = self._match_volume(source_path)
        if volume is None:
            source_dir = Path(source_path)
            volume = UsbVolume(
                path=str(source_dir),
                volume_name=source_dir.name or "USB",
                filesystem=None,
                total_bytes=0,
                free_bytes=0,
                bus_protocol=None,
                serial_number=None,
                rekordbox_detected=(source_dir / "PIONEER").exists() or (source_dir / ".PIONEER").exists(),
                normalized_filesystem=None,
                is_cdj_supported_fs=False,
                requires_format_before_restore=True,
            )
        rust_started = start_backup_task(
            str(self._repo_root),
            source_path,
            display_name=display_name,
            source_volume_name=volume.volume_name,
            source_filesystem=volume.filesystem,
            source_capacity_bytes=volume.total_bytes or None,
        )
        task = self._create_task(
            task_type="backup",
            rust_task_id=str(rust_started["task_id"]),
            source_path=source_path,
        )
        task.display_name = display_name or None
        task.resumed_from_checkpoint = bool(rust_started.get("resumed_from_checkpoint"))
        task.checkpoint_id = rust_started.get("checkpoint_id") if isinstance(rust_started.get("checkpoint_id"), str) else None
        task.progress_hint_text = "备份任务已提交，正在扫描 U 盘内容..."
        if task.resumed_from_checkpoint:
            task.progress_hint_text = "检测到未完成备份，正在继续上次进度..."
        self._push_event("task_created", task)
        return task.summary()

    def _handle_start_restore_snapshot_to_usb(self, payload: dict[str, Any]) -> dict[str, Any]:
        snapshot_id = payload.get("snapshot_id")
        if not isinstance(snapshot_id, str) or not snapshot_id:
            raise UsbBackupRuntimeError("INVALID_CONFIG", "snapshot_id 不能为空。")
        target_path = self._require_path(payload.get("target_path"), "target_path")
        clear_target = bool(payload.get("clear_target", True))
        volume = self._match_volume(target_path)
        if volume is None:
            raise UsbBackupRuntimeError("TARGET_NOT_FOUND", "未找到目标 U 盘。")
        if not volume.is_cdj_supported_fs:
            raise UsbBackupRuntimeError(
                "UNSUPPORTED_FILESYSTEM",
                self._unsupported_filesystem_message(volume),
            )
        snapshots = rust_list_snapshots(str(self._repo_root)).get("snapshots", [])
        snapshot = next((item for item in snapshots if isinstance(item, dict) and item.get("snapshot_id") == snapshot_id), None)
        if snapshot is None:
            raise UsbBackupRuntimeError("SNAPSHOT_NOT_FOUND", "未找到备份版本。")
        required_bytes = int(snapshot.get("total_bytes") or 0)
        available_bytes = volume.total_bytes if clear_target else volume.free_bytes
        if required_bytes > available_bytes:
            raise UsbBackupRuntimeError("CAPACITY_INSUFFICIENT", "目标U盘容量不足，无法恢复该备份。")
        rust_started = start_restore_task(
            str(self._repo_root),
            snapshot_id,
            target_path,
            clear_target=clear_target,
        )
        task = self._create_task(
            task_type="restore",
            rust_task_id=str(rust_started["task_id"]),
            target_path=target_path,
            snapshot_id=snapshot_id,
        )
        task.display_name = snapshot.get("display_name") if isinstance(snapshot.get("display_name"), str) else None
        task.progress_hint_text = "恢复任务已提交，正在准备目标 U 盘..."
        task.total_bytes = int(snapshot.get("total_bytes") or 0)
        task.total_files = int(snapshot.get("total_files") or 0)
        self._push_event("task_created", task)
        return task.summary()

    def _handle_start_validate_snapshot(self, payload: dict[str, Any]) -> dict[str, Any]:
        snapshot_id = payload.get("snapshot_id")
        if not isinstance(snapshot_id, str) or not snapshot_id:
            raise UsbBackupRuntimeError("INVALID_CONFIG", "snapshot_id 不能为空。")
        rust_started = start_validate_task(str(self._repo_root), snapshot_id)
        task = self._create_task(
            task_type="validate",
            rust_task_id=str(rust_started["task_id"]),
            snapshot_id=snapshot_id,
        )
        task.progress_hint_text = "校验任务已提交，正在检查对象仓库..."
        self._push_event("task_created", task)
        return task.summary()

    def _handle_delete_backup_version(self, payload: dict[str, Any]) -> dict[str, Any]:
        snapshot_id = payload.get("snapshot_id")
        if not isinstance(snapshot_id, str) or not snapshot_id:
            raise UsbBackupRuntimeError("INVALID_CONFIG", "snapshot_id 不能为空。")
        try:
            return rust_delete_snapshot(str(self._repo_root), snapshot_id)
        except UsbBackupRustBridgeError as exc:
            message = str(exc)
            if "未找到指定备份版本" in message:
                raise UsbBackupRuntimeError("SNAPSHOT_NOT_FOUND", "未找到备份版本。") from exc
            raise UsbBackupRuntimeError(
                "INTERNAL_ERROR",
                _humanize_usb_backup_error(exc),
            ) from exc

    def _handle_cleanup_repository(self, payload: dict[str, Any]) -> dict[str, Any]:
        del payload
        try:
            return rust_cleanup_repository(str(self._repo_root))
        except UsbBackupRustBridgeError as exc:
            raise UsbBackupRuntimeError(
                "INTERNAL_ERROR",
                _humanize_usb_backup_error(exc),
            ) from exc

    def _handle_eject_usb_volume(self, payload: dict[str, Any]) -> dict[str, Any]:
        target_path = self._require_path(payload.get("target_path"), "target_path")
        volume = self._match_volume(target_path, force_refresh=True)
        if volume is None:
            raise UsbBackupRuntimeError("TARGET_NOT_FOUND", "未找到目标 U 盘。")
        identifier = volume.whole_disk_identifier or volume.disk_identifier
        if identifier is None:
            raise UsbBackupRuntimeError("INVALID_CONFIG", "当前目标盘缺少可弹出的磁盘标识。")
        try:
            usage_sources = self._detect_volume_usage(volume.path)
            info = UsbVolumeInfo(
                path=volume.path,
                volume_name=volume.volume_name,
                filesystem=volume.filesystem,
                total_bytes=volume.total_bytes,
                free_bytes=volume.free_bytes,
                bus_protocol=volume.bus_protocol,
                serial_number=volume.serial_number,
                rekordbox_detected=volume.rekordbox_detected,
                normalized_filesystem=volume.normalized_filesystem,
                is_cdj_supported_fs=volume.is_cdj_supported_fs,
                requires_format_before_restore=volume.requires_format_before_restore,
                disk_identifier=volume.disk_identifier,
                whole_disk_identifier=volume.whole_disk_identifier,
            )
            result = self._storage_provider.eject_volume(info)
            return {
                "path": volume.path,
                "volume_name": volume.volume_name,
                "disk_identifier": volume.disk_identifier,
                "whole_disk_identifier": volume.whole_disk_identifier,
                "status": result.get("status", "ejected"),
            }
        except Exception as exc:
            raise UsbBackupRuntimeError(
                "INTERNAL_ERROR",
                self._eject_failure_message(_humanize_usb_backup_error(exc), usage_sources=[]),
            ) from exc

    def _handle_start_format_usb(self, payload: dict[str, Any]) -> dict[str, Any]:
        target_path = self._require_path(payload.get("target_path"), "target_path")
        filesystem = payload.get("filesystem")
        if not isinstance(filesystem, str) or not filesystem.strip():
            raise UsbBackupRuntimeError("INVALID_CONFIG", "filesystem 不能为空。")
        normalized_filesystem = self._normalize_filesystem(filesystem)
        if normalized_filesystem not in SUPPORTED_CDJ_FILESYSTEMS:
            raise UsbBackupRuntimeError(
                "INVALID_CONFIG",
                "格式化目标文件系统只允许 FAT32 或 ExFAT。",
            )
        volume_label = payload.get("volume_label")
        if volume_label is None:
            volume_label = "PIONEER"
        if not isinstance(volume_label, str) or not volume_label.strip():
            raise UsbBackupRuntimeError("INVALID_CONFIG", "volume_label 不能为空。")
        final_volume_label = volume_label.strip()[:32]
        volume = self._match_volume(target_path, force_refresh=True)
        if volume is None:
            raise UsbBackupRuntimeError(
                "TARGET_NOT_FOUND",
                "未找到目标 U 盘。设备可能刚重挂载，请重新插拔后点击刷新再重试。",
            )
        if volume.whole_disk_identifier is None:
            raise UsbBackupRuntimeError(
                "INVALID_CONFIG",
                "当前目标盘缺少可格式化磁盘标识，无法执行格式化。请点击刷新后重试。",
            )
        task = self._create_task(task_type="format", rust_task_id=None, target_path=target_path)
        task.display_name = final_volume_label
        task.progress_hint_text = "格式化任务已提交，正在校验目标 U 盘..."
        self._push_event("task_created", task)

        worker = threading.Thread(
            target=self._run_format_task,
            args=(task.task_id, volume, normalized_filesystem, final_volume_label),
            daemon=True,
        )
        worker.start()
        return task.summary()

    def _handle_stop_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        if task.rust_task_id is None:
            raise UsbBackupRuntimeError("INVALID_CONFIG", "当前任务不支持中途停止。")
        rust_task_id = task.rust_task_id
        stop_usb_backup_task(rust_task_id)
        task.progress_hint_text = "任务正在停止..."
        task.updated_at = iso_now()
        return task.summary()

    def _handle_subscribe_task_events(self, payload: dict[str, Any]) -> dict[str, Any]:
        task_id = payload.get("task_id")
        if task_id is not None:
            task = self._require_task(task_id)
            self._advance_task(task)
            with self._events_lock:
                events = [event for event in self._events if event.task_id == task.task_id]
                self._events = [event for event in self._events if event.task_id != task.task_id]
            return {"events": [event.to_dict() for event in events]}

        self._advance_all_tasks()
        with self._events_lock:
            events = [event.to_dict() for event in self._events]
            self._events.clear()
        return {"events": events}

    def _advance_all_tasks(self) -> None:
        with self._tasks_lock:
            tasks = list(self._tasks.values())
        for task in tasks:
            if task.status in TERMINAL_STATUSES and task._finished_emitted:
                continue
            self._advance_task(task)

    def _advance_task(self, task: TaskState) -> None:
        if task.rust_task_id is None:
            return
        polled = poll_usb_backup_task(task.rust_task_id)
        previous_status = task.status
        previous_progress = task.progress
        task.status = str(polled.get("status") or task.status)
        task.progress = float(polled.get("progress") or task.progress)
        task.progress_hint_text = str(polled.get("progress_hint_text") or task.progress_hint_text)
        task.display_name = polled.get("display_name") if isinstance(polled.get("display_name"), str) else task.display_name
        task.snapshot_id = polled.get("snapshot_id") if isinstance(polled.get("snapshot_id"), str) else task.snapshot_id
        task.total_files = int(polled.get("total_files") or task.total_files)
        task.total_bytes = int(polled.get("total_bytes") or task.total_bytes)
        task.restored_files = int(polled.get("restored_files") or task.restored_files)
        task.validated_files = int(polled.get("validated_files") or task.validated_files)
        task.error_message = polled.get("error") if isinstance(polled.get("error"), str) else task.error_message
        task.resumed_from_checkpoint = bool(polled.get("resumed_from_checkpoint", task.resumed_from_checkpoint))
        task.checkpoint_id = polled.get("checkpoint_id") if isinstance(polled.get("checkpoint_id"), str) else task.checkpoint_id
        task.restore_validation = (
            polled.get("restore_validation")
            if isinstance(polled.get("restore_validation"), dict)
            else task.restore_validation
        )
        task.updated_at = iso_now()

        if previous_status != task.status:
            self._push_event("task_status_changed", task)
        elif task.status == "running" and previous_progress != task.progress:
            self._push_event("task_progress", task)

        if task.status in TERMINAL_STATUSES and not task._finished_emitted:
            task._finished_emitted = True
            self._push_event("task_finished", task)
            if task.rust_task_id is not None:
                try:
                    cleanup_usb_backup_task(task.rust_task_id)
                except UsbBackupRustBridgeError:
                    pass
                task.rust_task_id = None

    def _enrich_snapshot(self, snapshot: dict[str, Any], target_volume: UsbVolume | None) -> dict[str, Any]:
        total_bytes = int(snapshot.get("total_bytes") or 0)
        can_restore = True
        disabled_reason: str | None = None
        if target_volume is not None:
            if not target_volume.is_cdj_supported_fs:
                can_restore = False
                disabled_reason = self._unsupported_filesystem_message(target_volume)
            elif total_bytes > target_volume.free_bytes:
                can_restore = False
                disabled_reason = "目标U盘容量不足，无法恢复该备份。"
        return {
            **snapshot,
            "can_restore": can_restore,
            "disabled_reason": disabled_reason,
            "recommended": target_volume is not None and can_restore,
        }

    def _normalize_filesystem(self, filesystem: str | None) -> str | None:
        if filesystem is None:
            return None
        normalized = filesystem.strip().lower()
        aliases = {
            "exfat": "exfat",
            "fat32": "fat32",
            "fat": "fat32",
            "ms-dos fat32": "fat32",
            "ms-dos fat": "fat32",
            "msdos": "fat32",
            "ms-dos": "fat32",
        }
        return aliases.get(normalized, normalized)

    def _unsupported_filesystem_message(self, volume: UsbVolume) -> str:
        display_filesystem = volume.filesystem or volume.normalized_filesystem or "未知格式"
        return (
            f"当前U盘文件系统为 {display_filesystem}，CDJ 仅支持 FAT32 或 ExFAT。"
            "请先格式化后再恢复。"
        )

    def _format_display_name(self, filesystem: str) -> str:
        return "FAT32" if filesystem == "fat32" else "ExFAT"

    def _classify_diskutil_issue(self, message: str) -> str:
        lowered = message.lower()
        if self._is_busy_format_error(message):
            return "busy"
        if (
            "not found" in lowered
            or "no such disk" in lowered
            or "media not present" in lowered
            or "could not find" in lowered
        ):
            return "missing"
        if "permission" in lowered or "not permitted" in lowered:
            return "permission"
        if "timed out" in lowered or "timeout" in lowered:
            return "timeout"
        return "unknown"

    def _format_failure_message(self, message: str) -> str:
        kind = self._classify_diskutil_issue(message)
        if kind == "busy":
            return (
                f"{message} 目标 U 盘当前正被占用。请关闭 Finder 窗口、播放器或其他占用程序，"
                "重新插拔后点击刷新再重试。"
            )
        if kind == "missing":
            return f"{message} 目标 U 盘可能已断开或刚重挂载，请重新插拔后点击刷新再试。"
        if kind == "permission":
            return f"{message} 系统拒绝了本次磁盘操作，请检查系统权限后重试。"
        if kind == "timeout":
            return f"{message} 目标 U 盘响应较慢，请等待设备稳定后点击刷新再重试。"
        return f"{message} 请重新插拔 U 盘并点击刷新后重试。"

    def _eject_failure_message(self, message: str, *, usage_sources: list[str]) -> str:
        kind = self._classify_diskutil_issue(message)
        usage_hint = (
            f" 可能占用进程: {', '.join(usage_sources)}。" if usage_sources else ""
        )
        if kind == "busy":
            return (
                f"{message} 目标 U 盘当前正被占用。请关闭 Finder 窗口、播放器或其他占用程序。"
                f"{usage_hint}"
            )
        if kind == "missing":
            return f"{message} 目标 U 盘可能已断开或刚重挂载，请点击刷新确认当前状态。"
        if kind == "permission":
            return f"{message} 系统拒绝了本次弹出操作，请检查系统权限后重试。"
        if kind == "timeout":
            return f"{message} 目标 U 盘响应较慢，请稍后点击刷新确认是否已安全弹出。"
        return f"{message} 请点击刷新确认当前 U 盘状态。"

    def _is_busy_format_error(self, message: str) -> bool:
        lowered = message.lower()
        return (
            "busy" in lowered
            or "in use" in lowered
            or "couldn't unmount" in lowered
            or "dissenter" in lowered
            or "resource temporarily unavailable" in lowered
        )

    def _require_path(self, value: Any, field_name: str) -> str:
        if not isinstance(value, str) or not value.strip():
            raise UsbBackupRuntimeError("INVALID_CONFIG", f"{field_name} 不能为空。")
        path = Path(value).expanduser().resolve()
        if not path.exists():
            raise UsbBackupRuntimeError("TARGET_NOT_FOUND", f"路径不存在: {path}")
        return str(path)

    def _create_task(
        self,
        *,
        task_type: str,
        rust_task_id: str | None,
        source_path: str | None = None,
        target_path: str | None = None,
        snapshot_id: str | None = None,
    ) -> TaskState:
        with self._tasks_lock:
            self._task_index += 1
            task = TaskState(
                task_id=f"usb_task_{self._task_index:03}",
                task_type=task_type,
                rust_task_id=rust_task_id,
                source_path=source_path,
                target_path=target_path,
                snapshot_id=snapshot_id,
            )
            self._tasks[task.task_id] = task
        return task

    def _push_event(self, event_name: str, task: TaskState) -> None:
        if event_name not in EVENTS:
            return
        event = EventEnvelope(
            event=event_name,
            task_id=task.task_id,
            data=task.summary(),
            module=MODULE,
        )
        with self._events_lock:
            self._events.append(event)

    def _require_task(self, task_id: Any) -> TaskState:
        if not isinstance(task_id, str) or not task_id:
            raise UsbBackupRuntimeError("INVALID_CONFIG", "task_id 不能为空。")
        with self._tasks_lock:
            task = self._tasks.get(task_id)
        if task is None:
            raise UsbBackupRuntimeError("TASK_NOT_FOUND", "未找到任务。")
        return task

    def _preflight_format_environment(self, volume: UsbVolume) -> None:
        if shutil.which("diskutil") is None:
            raise UsbBackupRuntimeError("INTERNAL_ERROR", "系统缺少 diskutil，无法执行磁盘格式化。")
        try:
            self._run_diskutil_command(
                ["diskutil", "info", volume.whole_disk_identifier or volume.path],
                timeout=12,
            )
        except _DiskutilCommandError as error:
            raise UsbBackupRuntimeError(
                "INTERNAL_ERROR",
                self._format_failure_message(error.message),
            ) from error

    def _wait_for_stable_volume(
        self,
        *,
        task_id: str,
        whole_disk_identifier: str,
        preferred_path: str,
    ) -> UsbVolume:
        self._update_local_task(
            task_id,
            lambda task: self._apply_task_updates(
                task,
                progress=0.14,
                progress_hint_text="正在等待目标 U 盘挂载状态稳定...",
            ),
            event_name="task_progress",
        )
        stable_count = 0
        last_path: str | None = None
        deadline = time.monotonic() + 3.6
        last_volume: UsbVolume | None = None
        while time.monotonic() < deadline:
            volume = self._find_volume_by_whole_disk_identifier(
                whole_disk_identifier,
                force_refresh=True,
            )
            if volume is not None:
                last_volume = volume
                if last_path == volume.path:
                    stable_count += 1
                else:
                    last_path = volume.path
                    stable_count = 1
                if stable_count >= 2:
                    return volume
            time.sleep(0.9)
        if last_volume is not None:
            return last_volume
        candidate = Path(preferred_path)
        if candidate.exists() and candidate.is_dir():
            fallback = self._volume_from_path(candidate)
            if fallback is not None:
                return fallback
            raise UsbBackupRuntimeError(
                "TARGET_NOT_FOUND",
                "目标 U 盘尚未稳定挂载，请等待 1-2 秒后点击刷新再重试。",
            )

    def _preflight_eject_environment(self, volume: UsbVolume) -> None:
        if shutil.which("diskutil") is None:
            raise UsbBackupRuntimeError("INTERNAL_ERROR", "系统缺少 diskutil，无法执行安全弹出。")
        try:
            self._run_diskutil_command(
                ["diskutil", "info", volume.whole_disk_identifier or volume.path],
                timeout=10,
            )
        except _DiskutilCommandError as error:
            raise UsbBackupRuntimeError(
                "INTERNAL_ERROR",
                self._eject_failure_message(error.message, usage_sources=[]),
            ) from error

    def _run_eject_with_retry(
        self,
        *,
        identifier: str,
        volume_name: str,
        volume_path: str,
        usage_sources: list[str],
    ) -> None:
        attempt = 0
        while True:
            try:
                self._run_diskutil_command(
                    ["diskutil", "eject", identifier],
                    timeout=25 if attempt == 0 else 35,
                )
                return
            except _DiskutilCommandError as error:
                if error.kind in {"missing", "permission"}:
                    raise UsbBackupRuntimeError(
                        "INTERNAL_ERROR",
                        self._eject_failure_message(error.message, usage_sources=usage_sources),
                    ) from error
                if attempt >= 1 or error.kind not in {"busy", "timeout", "unknown"}:
                    raise UsbBackupRuntimeError(
                        "INTERNAL_ERROR",
                        self._eject_failure_message(error.message, usage_sources=usage_sources),
                    ) from error
                time.sleep(1.2)
                usage_sources = self._detect_volume_usage(volume_path) or usage_sources
                attempt += 1

    def _verify_volume_ejected(self, volume: UsbVolume, identifier: str) -> None:
        for _ in range(4):
            refreshed = self._find_volume_by_whole_disk_identifier(
                volume.whole_disk_identifier or identifier,
                force_refresh=True,
            )
            if refreshed is None:
                return
            time.sleep(0.8)
        raise UsbBackupRuntimeError(
            "INTERNAL_ERROR",
            f"系统返回弹出成功，但当前仍能检测到 {volume.volume_name}。请稍后点击刷新确认，必要时手动从 Finder 弹出。",
        )

    def _detect_volume_usage(self, volume_path: str) -> list[str]:
        return self._storage_provider.detect_volume_usage(volume_path)

    def _run_format_task(
        self,
        task_id: str,
        volume: UsbVolume,
        filesystem: str,
        volume_label: str,
    ) -> None:
        self._update_local_task(
            task_id,
            lambda task: self._apply_task_updates(
                task,
                progress=0.1,
                progress_hint_text="正在校验目标磁盘安全性...",
            ),
            event_name="task_progress",
        )
        try:
            if volume.whole_disk_identifier is None:
                raise UsbBackupRuntimeError("INVALID_CONFIG", "缺少 whole disk 标识，无法格式化。")
            live_volume = self._find_volume_by_whole_disk_identifier(
                volume.whole_disk_identifier,
                force_refresh=True,
            )
            if live_volume is None:
                raise UsbBackupRuntimeError(
                    "TARGET_NOT_FOUND",
                    "目标 U 盘已离线或刚重挂载，请重新插拔后点击刷新再试。",
                )
            usage_sources = self._detect_volume_usage(live_volume.path)

            self._update_local_task(
                task_id,
                lambda task: self._apply_task_updates(
                    task,
                    progress=0.2,
                    progress_hint_text=f"正在卸载 {live_volume.volume_name}，准备格式化...",
                ),
                event_name="task_progress",
            )

            info = UsbVolumeInfo(
                path=live_volume.path,
                volume_name=live_volume.volume_name,
                filesystem=live_volume.filesystem,
                total_bytes=live_volume.total_bytes,
                free_bytes=live_volume.free_bytes,
                bus_protocol=live_volume.bus_protocol,
                serial_number=live_volume.serial_number,
                rekordbox_detected=live_volume.rekordbox_detected,
                normalized_filesystem=live_volume.normalized_filesystem,
                is_cdj_supported_fs=live_volume.is_cdj_supported_fs,
                requires_format_before_restore=live_volume.requires_format_before_restore,
                disk_identifier=live_volume.disk_identifier,
                whole_disk_identifier=live_volume.whole_disk_identifier,
            )

            self._update_local_task(
                task_id,
                lambda task: self._apply_task_updates(
                    task,
                    progress=0.5,
                    progress_hint_text=f"正在格式化 {live_volume.volume_name} 为 {self._format_display_name(filesystem)}...",
                ),
                event_name="task_progress",
            )

            new_info = self._storage_provider.format_volume(
                info, filesystem, volume_label
            )
            new_volume = UsbVolume.from_info(new_info)

            self._update_local_task(
                task_id,
                lambda task: self._apply_task_updates(
                    task,
                    status="success",
                    progress=1.0,
                    progress_hint_text=(
                        f"格式化完成，已确认文件系统为 "
                        f"{self._format_display_name(filesystem)}，当前卷标为 {new_volume.volume_name}。"
                    ),
                    display_name=volume_label,
                ),
                event_name="task_finished",
            )
        except UsbBackupRuntimeError as exc:
            self._update_local_task(
                task_id,
                lambda task: self._apply_task_updates(
                    task,
                    status="error",
                    progress=1.0,
                    progress_hint_text=exc.message,
                    error_message=exc.message,
                ),
                event_name="task_finished",
            )
        except Exception as exc:
            message = _humanize_usb_backup_error(exc)
            self._update_local_task(
                task_id,
                lambda task: self._apply_task_updates(
                    task,
                    status="error",
                    progress=1.0,
                    progress_hint_text=message,
                    error_message=message,
                ),
                event_name="task_finished",
            )

    def _run_format_attempts(
        self,
        *,
        task_id: str,
        volume_name: str,
        whole_disk_identifier: str,
        diskutil_format: str,
        volume_label: str,
        volume_path: str,
        usage_sources: list[str],
    ) -> None:
        self._run_unmount_with_retry(
            task_id=task_id,
            volume_name=volume_name,
            whole_disk_identifier=whole_disk_identifier,
            usage_sources=usage_sources,
        )
        self._run_erase_with_retry(
            task_id=task_id,
            volume_name=volume_name,
            volume_path=volume_path,
            whole_disk_identifier=whole_disk_identifier,
            diskutil_format=diskutil_format,
            volume_label=volume_label,
        )

    def _run_unmount_with_retry(
        self,
        *,
        task_id: str,
        volume_name: str,
        whole_disk_identifier: str,
        usage_sources: list[str],
    ) -> None:
        attempt = 0
        while True:
            hint = f"正在卸载 {volume_name}，准备格式化..."
            if usage_sources and attempt == 0:
                hint = (
                    f"检测到可能占用 {volume_name} 的进程: {', '.join(usage_sources)}。"
                    "正在先尝试卸载磁盘..."
                )
            elif attempt > 0:
                hint = f"正在重试卸载 {volume_name}，准备再次格式化..."
            self._update_local_task(
                task_id,
                lambda task: self._apply_task_updates(
                    task,
                    progress=0.2 if attempt == 0 else 0.28,
                    progress_hint_text=hint,
                ),
                event_name="task_progress",
            )
            try:
                self._run_diskutil_command(
                    ["diskutil", "unmountDisk", whole_disk_identifier],
                    timeout=25 if attempt == 0 else 35,
                )
                return
            except _DiskutilCommandError as error:
                if error.kind in {"missing", "permission"}:
                    raise UsbBackupRuntimeError(
                        "INTERNAL_ERROR",
                        self._format_failure_message(error.message),
                    ) from error
                if attempt >= 1 or error.kind not in {"busy", "timeout", "unknown"}:
                    raise UsbBackupRuntimeError(
                        "INTERNAL_ERROR",
                        self._format_failure_message(error.message),
                    ) from error
                self._update_local_task(
                    task_id,
                    lambda task: self._apply_task_updates(
                        task,
                        progress=0.34,
                        progress_hint_text=(
                            "卸载目标 U 盘时仍检测到占用，正在等待系统释放后再试一次..."
                        ),
                    ),
                    event_name="task_progress",
                )
                time.sleep(1.8)
                attempt += 1

    def _run_erase_with_retry(
        self,
        *,
        task_id: str,
        volume_name: str,
        volume_path: str,
        whole_disk_identifier: str,
        diskutil_format: str,
        volume_label: str,
    ) -> None:
        attempt = 0
        while True:
            self._update_local_task(
                task_id,
                lambda task: self._apply_task_updates(
                    task,
                    progress=0.46 if attempt == 0 else 0.58,
                    progress_hint_text=(
                        f"正在格式化 {volume_name} 为 {diskutil_format}..."
                        if attempt == 0
                        else f"正在重试格式化 {volume_name} 为 {diskutil_format}..."
                    ),
                ),
                event_name="task_progress",
            )
            try:
                self._run_diskutil_command(
                    [
                        "diskutil",
                        "eraseDisk",
                        diskutil_format,
                        volume_label,
                        "MBRFormat",
                        whole_disk_identifier,
                    ],
                    timeout=90 if attempt == 0 else 120,
                )
                return
            except _DiskutilCommandError as error:
                if error.kind in {"missing", "permission"}:
                    raise UsbBackupRuntimeError(
                        "INTERNAL_ERROR",
                        self._format_failure_message(error.message),
                    ) from error
                if attempt >= 1 or error.kind not in {"busy", "timeout", "unknown"}:
                    raise UsbBackupRuntimeError(
                        "INTERNAL_ERROR",
                        self._format_failure_message(error.message),
                    ) from error
                self._update_local_task(
                    task_id,
                    lambda task: self._apply_task_updates(
                        task,
                        progress=0.68,
                        progress_hint_text=(
                            "格式化过程中设备仍忙或响应较慢，正在重新卸载并自动重试一次..."
                        ),
                    ),
                    event_name="task_progress",
                )
                time.sleep(1.8)
                usage_sources = self._detect_volume_usage(volume_path)
                self._run_unmount_with_retry(
                    task_id=task_id,
                    volume_name=volume_name,
                    whole_disk_identifier=whole_disk_identifier,
                    usage_sources=usage_sources,
                )
                attempt += 1

    def _run_diskutil_command(
        self,
        command: list[str],
        *,
        timeout: int,
    ) -> subprocess.CompletedProcess[str]:
        try:
            completed = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=False,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired as exc:
            joined = " ".join(command)
            raise _DiskutilCommandError(
                "timeout",
                f"命令执行超时：{joined}。目标 U 盘响应较慢，请稍后点击刷新后重试。",
            ) from exc
        except OSError as exc:
            raise _DiskutilCommandError(
                "environment",
                f"无法执行磁盘命令：{exc}",
            ) from exc
        if completed.returncode != 0:
            message = completed.stderr.strip() or completed.stdout.strip() or "diskutil 命令执行失败。"
            raise _DiskutilCommandError(self._classify_diskutil_issue(message), message)
        return completed

    def _wait_for_formatted_volume(
        self,
        *,
        whole_disk_identifier: str,
        expected_filesystem: str,
        expected_volume_label: str,
    ) -> UsbVolume:
        deadline = time.monotonic() + 12.0
        last_volume: UsbVolume | None = None
        while time.monotonic() < deadline:
            volume = self._find_volume_by_whole_disk_identifier(
                whole_disk_identifier,
                force_refresh=True,
            )
            if volume is not None:
                last_volume = volume
                if volume.normalized_filesystem == expected_filesystem:
                    return volume
            time.sleep(0.8)
        expected_name = self._format_display_name(expected_filesystem)
        if last_volume is None:
            raise UsbBackupRuntimeError(
                "FORMAT_VERIFY_FAILED",
                f"格式化命令已完成，但系统未重新识别目标 U 盘，无法确认是否已写入 {expected_name}。"
                "请重新插拔后点击刷新确认，如仍异常请重试格式化。",
            )
        actual_name = last_volume.filesystem or last_volume.normalized_filesystem or "未知格式"
        if last_volume.normalized_filesystem == expected_filesystem:
            return last_volume
        raise UsbBackupRuntimeError(
            "FORMAT_VERIFY_FAILED",
            f"格式化命令已完成，但当前检测到的文件系统为 {actual_name}，不是期望的 {expected_name}。"
            "请重新插拔后点击刷新确认，如仍异常请重试格式化。",
        )

    def _update_local_task(
        self,
        task_id: str,
        updater: Any,
        *,
        event_name: str | None = None,
    ) -> None:
        with self._tasks_lock:
            task = self._tasks.get(task_id)
            if task is None:
                return
            updater(task)
        if event_name is not None:
            self._push_event(event_name, task)

    def _apply_task_updates(
        self,
        task: TaskState,
        *,
        status: str | None = None,
        progress: float | None = None,
        progress_hint_text: str | None = None,
        display_name: str | None = None,
        error_message: str | None = None,
    ) -> None:
        if status is not None:
            task.status = status
        if progress is not None:
            task.progress = progress
        if progress_hint_text is not None:
            task.progress_hint_text = progress_hint_text
        if display_name is not None:
            task.display_name = display_name
        if error_message is not None:
            task.error_message = error_message
        task.updated_at = iso_now()
        if task.status in TERMINAL_STATUSES:
            task._finished_emitted = True
