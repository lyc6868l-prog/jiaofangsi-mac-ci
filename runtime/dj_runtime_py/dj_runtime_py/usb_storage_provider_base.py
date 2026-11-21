from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any


class UsbStorageProviderError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass
class UsbVolumeInfo:
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


class UsbStorageProvider(ABC):
    @abstractmethod
    def list_volumes(self, force_refresh: bool = False) -> list[UsbVolumeInfo]:
        pass

    @abstractmethod
    def match_volume(self, path: str, force_refresh: bool = False) -> UsbVolumeInfo | None:
        pass

    @abstractmethod
    def find_volume_by_whole_disk_identifier(
        self, identifier: str, force_refresh: bool = False
    ) -> UsbVolumeInfo | None:
        pass

    @abstractmethod
    def detect_volume_usage(self, volume_path: str) -> list[str]:
        pass

    @abstractmethod
    def format_volume(
        self,
        volume: UsbVolumeInfo,
        filesystem: str,
        volume_label: str,
        task_callback: Any | None = None,
    ) -> UsbVolumeInfo:
        pass

    @abstractmethod
    def eject_volume(self, volume: UsbVolumeInfo) -> dict[str, Any]:
        pass