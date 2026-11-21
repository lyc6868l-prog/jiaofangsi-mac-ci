from __future__ import annotations

import json
import platform
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

from .usb_storage_provider_base import (
    UsbStorageProvider,
    UsbStorageProviderError,
    UsbVolumeInfo,
)

SUPPORTED_CDJ_FILESYSTEMS = {"fat32", "exfat"}


class WindowsUsbStorageProvider(UsbStorageProvider):
    def __init__(self) -> None:
        self._volume_cache: list[UsbVolumeInfo] | None = None

    def list_volumes(self, force_refresh: bool = False) -> list[UsbVolumeInfo]:
        if not force_refresh and self._volume_cache is not None:
            return self._volume_cache

        volumes = self._enumerate_usb_volumes()
        self._volume_cache = volumes
        return volumes

    def match_volume(self, path: str, force_refresh: bool = False) -> UsbVolumeInfo | None:
        volumes = self.list_volumes(force_refresh=force_refresh)
        normalized_path = path.rstrip("\\").rstrip("/") + "\\"
        for vol in volumes:
            if vol.path.rstrip("\\") == normalized_path.rstrip("\\"):
                return vol
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
        return self._detect_volume_usage_windows(volume_path)

    def format_volume(
        self,
        volume: UsbVolumeInfo,
        filesystem: str,
        volume_label: str,
        task_callback: Any | None = None,
    ) -> UsbVolumeInfo:
        return self._format_volume_windows(volume, filesystem, volume_label, task_callback)

    def eject_volume(self, volume: UsbVolumeInfo) -> dict[str, Any]:
        return self._eject_volume_windows(volume)

    def _enumerate_usb_volumes(self) -> list[UsbVolumeInfo]:
        try:
            disks_json = self._run_powershell_script(
                _GET_USB_DISKS_SCRIPT,
                timeout_seconds=90,
            )
            if disks_json is None:
                raise UsbStorageProviderError(
                    "ENUMERATION_FAILED", "PowerShell 返回空结果"
                )
            disks = json.loads(disks_json) if disks_json else []
            if isinstance(disks, dict):
                disks = [disks]
            elif not isinstance(disks, list):
                disks = []
        except Exception as exc:
            raise UsbStorageProviderError(
                "ENUMERATION_FAILED", f"获取 USB 磁盘列表失败: {exc}"
            ) from exc

        volumes: list[UsbVolumeInfo] = []
        for disk in disks:
            if not isinstance(disk, dict):
                continue
            if not self._is_likely_external_disk(disk):
                continue
            try:
                vol_info = self._build_volume_from_disk_info(disk)
                if vol_info:
                    volumes.append(vol_info)
            except Exception:
                continue

        return volumes

    def _build_volume_from_disk_info(self, disk: dict[str, Any]) -> UsbVolumeInfo | None:
        drive_letter = disk.get("DriveLetter")
        if not drive_letter:
            return None

        path = f"{drive_letter}\\"
        volume_name = disk.get("VolumeName") or disk.get("FriendlyName") or "USB Drive"
        filesystem = disk.get("FileSystem")
        total_bytes = disk.get("Size", 0)
        free_bytes = disk.get("SizeRemaining", 0)
        bus_protocol = disk.get("BusType")
        serial_number = disk.get("SerialNumber") or disk.get("UniqueId")

        normalized_filesystem = self._normalize_filesystem(filesystem)
        is_cdj_supported = normalized_filesystem in SUPPORTED_CDJ_FILESYSTEMS

        disk_number = disk.get("DiskNumber")
        pnp_device_id = disk.get("PNPDeviceID")
        unique_id = disk.get("UniqueId")

        disk_identifier = (
            f"disk:{disk_number}|part:0"
            if disk_number is not None
            else None
        )
        whole_disk_identifier = (
            f"disk:{disk_number}|uid:{pnp_device_id or unique_id}"
            if disk_number is not None
            else None
        )

        rekordbox_detected = self._check_rekordbox_structure(path)

        return UsbVolumeInfo(
            path=path,
            volume_name=volume_name,
            filesystem=filesystem,
            total_bytes=int(total_bytes) if total_bytes else 0,
            free_bytes=int(free_bytes) if free_bytes else 0,
            bus_protocol=bus_protocol,
            serial_number=serial_number,
            rekordbox_detected=rekordbox_detected,
            normalized_filesystem=normalized_filesystem,
            is_cdj_supported_fs=is_cdj_supported,
            requires_format_before_restore=not is_cdj_supported,
            disk_identifier=disk_identifier,
            whole_disk_identifier=whole_disk_identifier,
        )

    def _is_likely_external_disk(self, disk: dict[str, Any]) -> bool:
        if disk.get("IsBoot") or disk.get("IsSystem"):
            return False

        bus_type = self._normalize_bus_type(disk.get("BusType"))
        if bus_type == "usb":
            return True

        if self._looks_like_usb_pnp_device(disk.get("PNPDeviceID")):
            return True

        if self._normalize_bus_type(disk.get("InterfaceType")) == "usb":
            return True

        media_type = str(disk.get("MediaType") or "").strip().lower()
        if media_type == "removable media":
            return True

        removable = disk.get("IsRemovable")
        if isinstance(removable, bool) and removable:
            return True

        return False

    def _is_safe_external_disk(self, disk: dict[str, Any]) -> bool:
        if disk.get("IsBoot") or disk.get("IsSystem"):
            return False

        bus_type = self._normalize_bus_type(disk.get("BusType"))
        if bus_type == "usb":
            return True

        if self._looks_like_usb_pnp_device(disk.get("PNPDeviceID")):
            return True

        if self._normalize_bus_type(disk.get("InterfaceType")) == "usb":
            return True

        media_type = str(disk.get("MediaType") or "").strip().lower()
        if media_type == "removable media":
            return True

        removable = disk.get("IsRemovable")
        if isinstance(removable, bool):
            return removable

        return False

    def _normalize_bus_type(self, bus_type: Any) -> str:
        return str(bus_type or "").strip().lower()

    def _looks_like_usb_pnp_device(self, pnp_device_id: Any) -> bool:
        if not pnp_device_id:
            return False
        normalized = str(pnp_device_id).upper()
        return "USB" in normalized

    def _normalize_filesystem(self, filesystem: str | None) -> str | None:
        if not filesystem:
            return None
        lowered = filesystem.lower().strip()
        if lowered in ("fat32", "fat"):
            return "fat32"
        if lowered in ("exfat", "exfat"):
            return "exfat"
        if lowered in ("ntfs"):
            return "ntfs"
        return lowered

    def _check_rekordbox_structure(self, drive_path: str) -> bool:
        try:
            drive = Path(drive_path)
            rekordbox_paths = [
                drive / "PIONEER",
                drive / "rekordbox",
                drive / "Contents",
            ]
            for p in rekordbox_paths:
                if p.exists() and p.is_dir():
                    return True
            return False
        except Exception:
            return False

    def _detect_volume_usage_windows(self, volume_path: str) -> list[str]:
        try:
            script = f'''
$path = "{volume_path}"
$processes = Get-Process | Where-Object {{
    $_.Modules | Where-Object {{ $_.FileName -like "$path*" }}
}} | Select-Object -ExpandProperty ProcessName -Unique
$processes | ConvertTo-Json
'''
            result = self._run_powershell_script(script)
            if result:
                processes = json.loads(result)
                if isinstance(processes, list):
                    return processes
                if isinstance(processes, str):
                    return [processes]
            return []
        except Exception:
            return []

    def _format_volume_windows(
        self,
        volume: UsbVolumeInfo,
        filesystem: str,
        volume_label: str,
        task_callback: Any | None = None,
    ) -> UsbVolumeInfo:
        disk_number = self._extract_disk_number(volume.whole_disk_identifier)
        if disk_number is None:
            raise UsbStorageProviderError("INVALID_CONFIG", "无法识别目标磁盘编号。")

        # Safety check
        disk_info = self._get_disk_info_by_number(disk_number)
        if disk_info and not self._is_safe_external_disk(disk_info):
            if disk_info.get("IsBoot") or disk_info.get("IsSystem"):
                raise UsbStorageProviderError("SAFETY_CHECK_FAILED", "目标磁盘是系统盘，不允许格式化。")
            raise UsbStorageProviderError("SAFETY_CHECK_FAILED", "目标磁盘不是可安全格式化的外接盘。")

        # FAT32/exFAT 卷标最多 11 个字符
        safe_label = volume_label[:11]

        if filesystem == "fat32":
            # FAT32 使用 fat32format.exe（支持大容量，无需 UAC）
            formatter_path = Path(__file__).parent.parent.parent / "disk_formatter" / "fat32format.exe"
            if not formatter_path.exists():
                raise UsbStorageProviderError(
                    "FORMATTER_NOT_FOUND",
                    "fat32format.exe 未找到，无法格式化 FAT32。请下载该工具并放入 runtime/disk_formatter 目录。",
                )
            
            drive_letter = volume.path.rstrip("\\")
            result = subprocess.run(
                [str(formatter_path), drive_letter],
                input="y\n",
                capture_output=True,
                timeout=120,
                encoding="gbk",
                errors="replace",
            )
            
            if result.returncode != 0 or "Done" not in result.stdout:
                raise UsbStorageProviderError(
                    "FORMAT_FAILED",
                    f"FAT32 格式化失败: {result.stderr.strip() or result.stdout.strip()}",
                )
            
            # fat32format 不支持卷标参数，格式化后用 label 命令设置
            if safe_label:
                label_result = subprocess.run(
                    ["label", drive_letter, safe_label],
                    capture_output=True,
                    timeout=10,
                    encoding="gbk",
                    errors="replace",
                )
                if label_result.returncode != 0:
                    # 卷标设置失败不影响格式化结果，只记录日志
                    import sys
                    sys.stderr.write(f"[WARN] 设置 FAT32 卷标失败: {label_result.stderr}\n")
        else:
            # exFAT 使用 diskpart（需要 UAC）
            script_file = Path(tempfile.gettempdir()) / f"format_disk_{disk_number}.txt"
            script_content = f"""select disk {disk_number}
clean
create partition primary
format fs=exfat label="{safe_label}" quick
assign
"""
            script_file.write_text(script_content, encoding="utf-8")

            result = subprocess.run(
                [
                    "powershell",
                    "-Command",
                    f"$p = Start-Process diskpart -ArgumentList '/s','{script_file}' -Verb RunAs -Wait -PassThru; if ($null -eq $p) {{ exit 1 }}; exit $p.ExitCode",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                encoding="gbk",
                errors="replace",
            )
            script_file.unlink(missing_ok=True)
            if result.returncode != 0:
                raise UsbStorageProviderError(
                    "FORMAT_FAILED",
                    f"exFAT 格式化失败: {result.stderr.strip() or result.stdout.strip() or '用户取消或 diskpart 执行失败'}",
                )

        # 等待新卷出现并验证文件系统
        time.sleep(2)
        volumes = self.list_volumes(force_refresh=True)
        for vol in volumes:
            if vol.whole_disk_identifier != volume.whole_disk_identifier:
                continue
            if vol.normalized_filesystem != filesystem:
                raise UsbStorageProviderError(
                    "FORMAT_FAILED",
                    f"格式化后文件系统校验失败，当前为 {vol.filesystem or '未知'}，期望为 {filesystem.upper()}。",
                )
            return vol

        raise UsbStorageProviderError(
            "TARGET_NOT_FOUND",
            "格式化完成后无法找到目标 U 盘。",
        )

    def _eject_volume_windows(self, volume: UsbVolumeInfo) -> dict[str, Any]:
        drive_letter = volume.path.rstrip("\\")[0]
        
        eject_script = f'''
$shell = New-Object -ComObject Shell.Application
$driveObj = $shell.NameSpace(17).ParseName("{drive_letter}:")
if ($driveObj) {{
    $driveObj.InvokeVerb("Eject")
    Start-Sleep -Seconds 3
    $vol = Get-Volume -DriveLetter {drive_letter} -ErrorAction SilentlyContinue
    if (-not $vol -or $vol.Size -eq 0) {{
        "ejected"
    }} else {{
        "still_present"
    }}
}} else {{
    "not_found"
}}
'''
        result = self._run_powershell_script(eject_script)

        if result.strip() == "ejected":
            self._volume_cache = None
            return {"status": "ejected", "message": "设备已弹出"}

        if result.strip() == "still_present":
            raise UsbStorageProviderError(
                "EJECT_FAILED",
                f"设备仍在系统中，可能有程序占用 {volume.volume_name}。",
            )

        raise UsbStorageProviderError("EJECT_FAILED", "无法找到目标设备。请点击刷新确认当前U盘状态。")

    def _extract_disk_number(self, identifier: str | None) -> int | None:
        if not identifier:
            return None
        if identifier.startswith("disk:"):
            parts = identifier.split("|")
            for part in parts:
                if part.startswith("disk:"):
                    try:
                        return int(part.replace("disk:", ""))
                    except ValueError:
                        return None
        return None

    def _get_disk_info_by_number(self, disk_number: int) -> dict[str, Any] | None:
        script = f'''
Get-Disk -Number {disk_number} | Select-Object DiskNumber, IsBoot, IsSystem, BusType, FriendlyName, SerialNumber, UniqueId, IsOffline, IsReadOnly | ConvertTo-Json
'''
        try:
            result = self._run_powershell_script(script)
            if result:
                return json.loads(result)
        except Exception:
            pass
        return None

    def _run_powershell_command(self, command: str) -> None:
        result = subprocess.run(
            ["powershell", "-Command", command],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode != 0:
            raise UsbStorageProviderError(
                "POWERSHELL_ERROR", result.stderr or "PowerShell 执行失败"
            )

    def _run_powershell_script(self, script: str, timeout_seconds: int = 30) -> str:
        result = subprocess.run(
            ["powershell", "-Command", script],
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            encoding="gbk",
            errors="replace",
        )
        if result.returncode != 0:
            error_msg = result.stderr if result.stderr else "PowerShell 执行失败"
            raise UsbStorageProviderError("POWERSHELL_ERROR", error_msg)
        
        stdout = result.stdout
        if stdout is None:
            return ""
        return stdout.strip()


_GET_USB_DISKS_SCRIPT = '''
$disks = Get-Disk | Where-Object {
    -not $_.IsBoot -and
    -not $_.IsSystem
}
$partitions = Get-Partition | Where-Object { $_.DriveLetter }
$volumes = Get-Volume | Where-Object { $_.DriveLetter }
$diskDrives = Get-CimInstance Win32_DiskDrive
$result = foreach ($disk in $disks) {
    $diskPartitions = $partitions | Where-Object { $_.DiskNumber -eq $disk.Number }
    foreach ($partition in $diskPartitions) {
        $volume = $volumes | Where-Object { $_.DriveLetter -eq $partition.DriveLetter } | Select-Object -First 1
        if (-not $volume) {
            continue
        }
        $cim = $diskDrives | Where-Object { $_.Index -eq $disk.Number } | Select-Object -First 1
        [PSCustomObject]@{
            DiskNumber = $disk.Number
            DriveLetter = if ($partition.DriveLetter) { "$($partition.DriveLetter):" } else { $null }
            VolumeName = $volume.FileSystemLabel
            FriendlyName = $disk.FriendlyName
            FileSystem = $volume.FileSystem
            Size = if ($volume.Size) { $volume.Size } else { $disk.Size }
            SizeRemaining = if ($volume.SizeRemaining) { $volume.SizeRemaining } else { 0 }
            BusType = $disk.BusType.ToString()
            SerialNumber = if ($cim) { $cim.SerialNumber } else { $disk.SerialNumber }
            UniqueId = $disk.UniqueId
            PNPDeviceID = if ($cim) { $cim.PNPDeviceID } else { $null }
            MediaType = if ($cim) { $cim.MediaType } else { $null }
            Model = if ($cim) { $cim.Model } else { $null }
            InterfaceType = if ($cim) { $cim.InterfaceType } else { $null }
            IsBoot = $disk.IsBoot
            IsSystem = $disk.IsSystem
        }
    }
}
$result | ConvertTo-Json -Depth 3
'''
