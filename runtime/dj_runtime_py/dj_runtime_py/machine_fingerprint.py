from __future__ import annotations

import hashlib
import json
import platform
import subprocess
import uuid

from .system_secret_store import SystemSecretStore


class MachineFingerprint:
    _DEVICE_ID_SECRET = "install_instance_id"

    def __init__(self) -> None:
        self._secret_store = SystemSecretStore()

    def _get_hardware_uuid(self) -> str | None:
        if platform.system() == "Darwin":
            try:
                result = subprocess.run(
                    ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                if result.returncode != 0:
                    return None
                for line in result.stdout.splitlines():
                    if "IOPlatformUUID" in line:
                        parts = line.split("=")
                        if len(parts) >= 2:
                            uuid_str = parts[-1].strip().strip('"')
                            if uuid_str:
                                return uuid_str
            except OSError:
                pass
        elif platform.system() == "Windows":
            try:
                result = subprocess.run(
                    ["wmic", "csproduct", "get", "uuid"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                if result.returncode == 0:
                    for line in result.stdout.strip().splitlines():
                        line = line.strip()
                        if line and line != "UUID":
                            return line
            except OSError:
                pass
        return None

    def _get_primary_mac_address(self) -> str | None:
        if platform.system() == "Darwin":
            try:
                result = subprocess.run(
                    ["ifconfig", "en0"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                if result.returncode != 0:
                    return None
                for line in result.stdout.splitlines():
                    if "ether" in line:
                        parts = line.split()
                        if len(parts) >= 2:
                            mac = parts[1].strip()
                            if mac and mac != "00:00:00:00:00:00":
                                return mac
            except OSError:
                pass
        elif platform.system() == "Windows":
            try:
                result = subprocess.run(
                    ["getmac"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                if result.returncode == 0:
                    for line in result.stdout.strip().splitlines():
                        line = line.strip()
                        if line and "-" in line:
                            return line.replace("-", ":")
            except OSError:
                pass
        return None

    def _get_disk_serial(self) -> str | None:
        if platform.system() == "Darwin":
            try:
                result = subprocess.run(
                    ["diskutil", "info", "disk0"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                if result.returncode != 0:
                    return None
                for line in result.stdout.splitlines():
                    if "Volume Name" in line or "Device Identifier" in line:
                        continue
                    if "Disk / Partition UUID" in line:
                        parts = line.split(":")
                        if len(parts) >= 2:
                            uuid_str = parts[-1].strip()
                            if uuid_str:
                                return uuid_str
            except OSError:
                pass
        elif platform.system() == "Windows":
            try:
                result = subprocess.run(
                    ["wmic", "diskdrive", "get", "serialnumber"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                if result.returncode == 0:
                    for line in result.stdout.strip().splitlines():
                        line = line.strip()
                        if line and line != "SerialNumber":
                            return line
            except OSError:
                pass
        return None

    def _generate_device_id(self) -> str:
        hw_uuid = self._get_hardware_uuid()
        mac_addr = self._get_primary_mac_address()
        disk_serial = self._get_disk_serial()

        system_info = {
            "hardware_uuid": hw_uuid,
            "mac_address": mac_addr,
            "disk_serial": disk_serial,
            "platform": platform.system(),
            "machine": platform.machine(),
        }

        if hw_uuid or mac_addr:
            info_str = json.dumps(system_info, sort_keys=True)
            return hashlib.sha256(info_str.encode()).hexdigest()

        system_info["fallback_uuid"] = str(uuid.uuid4())
        info_str = json.dumps(system_info, sort_keys=True)
        return hashlib.sha256(info_str.encode()).hexdigest()

    def load_or_create(self) -> str:
        return self._secret_store.load_or_create(
            self._DEVICE_ID_SECRET,
            factory=self._generate_device_id,
        )
