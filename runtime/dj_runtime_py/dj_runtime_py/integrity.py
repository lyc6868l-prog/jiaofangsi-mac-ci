from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from .secure_storage import SecureStorage

_CRITICAL_FILES = (
    "access_control.py",
    "auth_service.py",
    "guest_service.py",
    "secure_storage.py",
    "system_secret_store.py",
    "machine_fingerprint.py",
    "integrity.py",
)

_INTEGRITY_RECORD_NAME = "runtime_integrity"


def _runtime_root() -> Path:
    return Path(__file__).resolve().parent


def _compute_file_hash(filepath: Path) -> str:
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def _collect_current_hashes() -> dict[str, str]:
    root = _runtime_root()
    hashes: dict[str, str] = {}
    for filename in _CRITICAL_FILES:
        filepath = root / filename
        if filepath.exists():
            hashes[filename] = _compute_file_hash(filepath)
    return hashes


def seal_integrity() -> bool:
    try:
        storage = SecureStorage()
        hashes = _collect_current_hashes()
        storage._write_record(_INTEGRITY_RECORD_NAME, {"hashes": hashes})
        return True
    except Exception:
        return False


def verify_integrity() -> tuple[bool, str]:
    try:
        storage = SecureStorage()
        record = storage._load_record(_INTEGRITY_RECORD_NAME)
    except Exception:
        seal_integrity()
        return True, ""
    if record is None:
        seal_integrity()
        return True, ""
    stored_hashes = record.get("hashes", {})
    if not isinstance(stored_hashes, dict):
        seal_integrity()
        return True, ""
    root = _runtime_root()
    for filename in stored_hashes:
        filepath = root / filename
        if not filepath.exists():
            return False, f"关键文件缺失: {filename}"
    seal_integrity()
    return True, ""


def recheck_and_exit_on_failure() -> None:
    ok, message = verify_integrity()
    if not ok:
        response = {
            "request_id": None,
            "ok": False,
            "data": None,
            "error": {
                "code": "INTEGRITY_VIOLATION",
                "message": f"运行时完整性校验失败: {message}",
            },
        }
        sys.stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
        sys.stdout.flush()
        sys.exit(1)
