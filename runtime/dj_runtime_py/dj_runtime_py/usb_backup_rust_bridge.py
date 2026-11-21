from __future__ import annotations

import json
from functools import lru_cache
from typing import Any


class UsbBackupRustBridgeError(Exception):
    pass


@lru_cache(maxsize=1)
def _load_module():
    try:
        import dj_usb_backup_core
    except ImportError as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc
    return dj_usb_backup_core


def health_check() -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.health_check())
    except Exception as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc


def start_backup_task(
    repo_root: str,
    source_root: str,
    *,
    display_name: str | None = None,
    source_volume_name: str | None = None,
    source_filesystem: str | None = None,
    source_capacity_bytes: int | None = None,
) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(
            module.start_backup_task(
                repo_root,
                source_root,
                display_name,
                source_volume_name,
                source_filesystem,
                source_capacity_bytes,
            )
        )
    except Exception as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc


def start_restore_task(
    repo_root: str,
    snapshot_id: str,
    target_root: str,
    *,
    clear_target: bool = True,
) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(
            module.start_restore_task(repo_root, snapshot_id, target_root, clear_target)
        )
    except Exception as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc


def start_validate_task(repo_root: str, snapshot_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.start_validate_task(repo_root, snapshot_id))
    except Exception as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc


def poll_usb_backup_task(task_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.poll_usb_backup_task(task_id))
    except Exception as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc


def stop_usb_backup_task(task_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.stop_usb_backup_task(task_id))
    except Exception as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc


def cleanup_usb_backup_task(task_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.cleanup_usb_backup_task(task_id))
    except Exception as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc


def list_snapshots(repo_root: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.list_snapshots(repo_root))
    except Exception as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc


def list_pending_backups(repo_root: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.list_pending_backups_py(repo_root))
    except Exception as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc


def delete_snapshot(repo_root: str, snapshot_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.delete_snapshot(repo_root, snapshot_id))
    except Exception as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc


def cleanup_repository(repo_root: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.cleanup_repository(repo_root))
    except Exception as exc:
        raise UsbBackupRustBridgeError(str(exc)) from exc
