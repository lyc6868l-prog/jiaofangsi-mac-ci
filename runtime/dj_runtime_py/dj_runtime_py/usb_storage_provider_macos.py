from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

from .usb_storage_provider_base import (
    UsbStorageProvider,
    UsbStorageProviderError,
    UsbVolumeInfo,
)

SUPPORTED_CDJ_FILESYSTEMS = {"fat32", "exfat"}


class MacOSUsbStorageProvider(UsbStorageProvider):
    def __init__(self) -> None:
        self._volume_cache: list[UsbVolumeInfo] | None = None
        self._cache_deadline: float = 0

    def list_volumes(self, force_refresh: bool = False) -> list[UsbVolumeInfo]:
        if not force_refresh and self._volume_cache is not None and time.monotonic() < self._cache_deadline:
            return self._volume_cache

        paths = self._list_usb_volume_paths()
        if paths is None:
            self._volume_cache = []
            self._cache_deadline = time.monotonic() + 1.2
            return []

        volumes: list[UsbVolumeInfo] = []
        for path in paths:
            vol = self._volume_from_path(path)
            if vol:
                volumes.append(vol)

        self._volume_cache = volumes
        self._cache_deadline = time.monotonic() + 1.2
        return volumes

    def match_volume(self, path: str, force_refresh: bool = False) -> UsbVolumeInfo | None:
        volumes = self.list_volumes(force_refresh=force_refresh)
        for vol in volumes:
            if vol.path == path:
                return vol
        candidate = Path(path)
        if candidate.exists() and candidate.is_dir():
            return self._volume_from_path(candidate)
        return None

    def find_volume_by_whole_disk_identifier(
        self, identifier: str, force_refresh: bool = False
    ) -> UsbVolumeInfo | None:
        volumes = self.list_volumes(force_refresh=force_refresh)
        for vol in volumes:
            if vol.whole_disk_identifier == identifier:
                return vol
        return None

    def detect_volume_usage(self, volume_path: str) -> list[str]:
        lsof_path = shutil.which("lsof")
        if lsof_path is None:
            return []
        try:
            completed = subprocess.run(
                [lsof_path, volume_path],
                capture_output=True,
                text=True,
                check=False,
                timeout=4,
            )
        except (OSError, subprocess.TimeoutExpired):
            return []
        if completed.returncode != 0 and not completed.stdout.strip():
            return []
        processes: list[str] = []
        for line in completed.stdout.splitlines()[1:]:
            parts = line.split()
            if not parts:
                continue
            command = parts[0]
            if command == "lsof" or command in processes:
                continue
            processes.append(command)
            if len(processes) >= 4:
                break
        return processes

    def format_volume(
        self,
        volume: UsbVolumeInfo,
        filesystem: str,
        volume_label: str,
        task_callback: Any | None = None,
    ) -> UsbVolumeInfo:
        if shutil.which("diskutil") is None:
            raise UsbStorageProviderError("INTERNAL_ERROR", "系统缺少 diskutil，无法执行磁盘格式化。")

        whole_disk_identifier = volume.whole_disk_identifier
        if whole_disk_identifier is None:
            raise UsbStorageProviderError("INVALID_CONFIG", "缺少 whole disk 标识，无法格式化。")

        diskutil_format = "FAT32" if filesystem == "fat32" else "ExFAT"

        # Unmount
        self._run_diskutil_command(["diskutil", "unmountDisk", whole_disk_identifier], timeout=25)

        # Erase
        self._run_diskutil_command(
            [
                "diskutil",
                "eraseDisk",
                diskutil_format,
                volume_label,
                "MBRFormat",
                whole_disk_identifier,
            ],
            timeout=90,
        )

        # Wait for volume to reappear
        new_volume = self._wait_for_formatted_volume(
            whole_disk_identifier=whole_disk_identifier,
            expected_filesystem=filesystem,
            expected_volume_label=volume_label,
        )
        return new_volume

    def eject_volume(self, volume: UsbVolumeInfo) -> dict[str, Any]:
        if shutil.which("diskutil") is None:
            raise UsbStorageProviderError("INTERNAL_ERROR", "系统缺少 diskutil，无法执行安全弹出。")

        identifier = volume.whole_disk_identifier or volume.disk_identifier
        if identifier is None:
            raise UsbStorageProviderError("INVALID_CONFIG", "当前目标盘缺少可弹出的磁盘标识。")

        try:
            self._run_diskutil_command(["diskutil", "eject", identifier], timeout=25)
        except UsbStorageProviderError:
            # Retry once
            time.sleep(1.2)
            self._run_diskutil_command(["diskutil", "eject", identifier], timeout=35)

        # Verify ejected
        for _ in range(4):
            refreshed = self.find_volume_by_whole_disk_identifier(
                volume.whole_disk_identifier or identifier,
                force_refresh=True,
            )
            if refreshed is None:
                return {"status": "ejected", "message": "设备已弹出"}
            time.sleep(0.8)

        raise UsbStorageProviderError(
            "INTERNAL_ERROR",
            f"系统返回弹出成功，但当前仍能检测到 {volume.volume_name}。",
        )

    def _list_usb_volume_paths(self) -> list[Path] | None:
        disk_list = self._diskutil_list_external_physical()
        if disk_list is None:
            return None
        seen: set[str] = set()
        paths: list[Path] = []
        for mount_point in self._collect_mount_points(disk_list):
            if mount_point in seen:
                continue
            seen.add(mount_point)
            path = Path(mount_point)
            if path.exists() and path.is_dir():
                paths.append(path)
        return paths

    def _diskutil_list_external_physical(self) -> dict[str, Any] | None:
        try:
            completed = subprocess.run(
                ["diskutil", "list", "-plist", "external", "physical"],
                capture_output=True,
                check=True,
                timeout=2.5,
            )
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            return None
        try:
            data = plistlib.loads(completed.stdout)
        except Exception:
            return None
        return data if isinstance(data, dict) else None

    def _collect_mount_points(self, value: Any) -> list[str]:
        mount_points: list[str] = []
        if isinstance(value, dict):
            mount_point = value.get("MountPoint")
            if isinstance(mount_point, str) and mount_point:
                mount_points.append(mount_point)
            for child in value.values():
                mount_points.extend(self._collect_mount_points(child))
        elif isinstance(value, list):
            for child in value:
                mount_points.extend(self._collect_mount_points(child))
        return mount_points

    def _volume_from_path(self, path: Path) -> UsbVolumeInfo | None:
        filesystem: str | None = None
        bus_protocol: str | None = None
        serial_number: str | None = None
        volume_name = path.name
        disk_info = self._diskutil_info(path)
        if disk_info:
            if bool(disk_info.get("Internal")):
                return None
            if str(disk_info.get("VirtualOrPhysical") or "").lower() == "virtual":
                return None
            bus_protocol = disk_info.get("BusProtocol") if isinstance(disk_info.get("BusProtocol"), str) else None
            if bus_protocol and bus_protocol.lower() not in {"usb", "thunderbolt", "firewire"}:
                return None
            filesystem = disk_info.get("FilesystemType") if isinstance(disk_info.get("FilesystemType"), str) else None
            serial_number = disk_info.get("VolumeUUID") if isinstance(disk_info.get("VolumeUUID"), str) else None
            if isinstance(disk_info.get("VolumeName"), str) and str(disk_info.get("VolumeName")).strip():
                volume_name = str(disk_info.get("VolumeName")).strip()

        disk_identifier = (
            disk_info.get("DeviceIdentifier")
            if isinstance(disk_info, dict) and isinstance(disk_info.get("DeviceIdentifier"), str)
            else None
        )
        whole_disk_identifier = None
        if isinstance(disk_info, dict):
            if isinstance(disk_info.get("ParentWholeDisk"), str):
                whole_disk_identifier = disk_info.get("ParentWholeDisk")
            elif isinstance(disk_info.get("DeviceIdentifier"), str):
                whole_disk_identifier = disk_info.get("DeviceIdentifier")

        try:
            fs_stats = os.statvfs(path)
        except OSError:
            return None
        total_bytes = fs_stats.f_frsize * fs_stats.f_blocks
        free_bytes = fs_stats.f_frsize * fs_stats.f_bavail

        rekordbox_detected = (path / "PIONEER").exists() or (path / ".PIONEER").exists()
        normalized_filesystem = self._normalize_filesystem(filesystem)
        is_cdj_supported_fs = normalized_filesystem in SUPPORTED_CDJ_FILESYSTEMS

        return UsbVolumeInfo(
            path=str(path),
            volume_name=volume_name,
            filesystem=filesystem,
            total_bytes=total_bytes,
            free_bytes=free_bytes,
            bus_protocol=bus_protocol,
            serial_number=serial_number,
            rekordbox_detected=rekordbox_detected,
            normalized_filesystem=normalized_filesystem,
            is_cdj_supported_fs=is_cdj_supported_fs,
            requires_format_before_restore=not is_cdj_supported_fs,
            disk_identifier=disk_identifier,
            whole_disk_identifier=whole_disk_identifier,
        )

    def _diskutil_info(self, path: Path) -> dict[str, Any] | None:
        try:
            completed = subprocess.run(
                ["diskutil", "info", "-plist", str(path)],
                capture_output=True,
                check=True,
                timeout=2.5,
            )
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            return None
        try:
            data = plistlib.loads(completed.stdout)
        except Exception:
            return None
        return data if isinstance(data, dict) else None

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

    def _run_diskutil_command(self, args: list[str], timeout: int = 25) -> None:
        try:
            completed = subprocess.run(
                args,
                capture_output=True,
                text=True,
                check=False,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired as exc:
            raise UsbStorageProviderError("timeout", f"diskutil 命令超时: {args[1]}") from exc
        except OSError as exc:
            raise UsbStorageProviderError("missing", f"无法执行 diskutil: {exc}") from exc
        if completed.returncode != 0:
            message = completed.stderr.strip() or completed.stdout.strip() or "diskutil 命令执行失败。"
            raise UsbStorageProviderError("error", message)

    def _wait_for_formatted_volume(
        self,
        whole_disk_identifier: str,
        expected_filesystem: str,
        expected_volume_label: str,
    ) -> UsbVolumeInfo:
        deadline = time.monotonic() + 3.6
        while time.monotonic() < deadline:
            volume = self.find_volume_by_whole_disk_identifier(whole_disk_identifier, force_refresh=True)
            if volume:
                if volume.normalized_filesystem == expected_filesystem:
                    return volume
            time.sleep(0.9)

        # Fallback: try to find by path
        volumes = self.list_volumes(force_refresh=True)
        for vol in volumes:
            if vol.normalized_filesystem == expected_filesystem:
                return vol

        raise UsbStorageProviderError(
            "TARGET_NOT_FOUND",
            "格式化完成后无法找到目标 U 盘，请重新插拔后点击刷新。",
        )