from __future__ import annotations

import base64
import json
import os
from pathlib import Path
from typing import Any

from cryptography.fernet import Fernet

from .system_secret_store import SystemSecretStore

try:
    from platformdirs import user_data_dir
except ImportError:
    def user_data_dir(app_name: str) -> str:
        return str(Path.home() / ".local" / "share" / app_name)


class SecureStorage:
    _APP_NAME = "JiaoFangSiDJ"
    _MASTER_KEY_NAME = "storage_master_key"

    def __init__(self) -> None:
        self._storage_dir = Path(user_data_dir(self._APP_NAME)) / "auth"
        self._storage_dir.mkdir(parents=True, exist_ok=True)
        self._secret_store = SystemSecretStore()
        self._fernet = self._load_current_fernet()

    def _load_current_fernet(self) -> Fernet:
        key = self._secret_store.load_or_create(
            self._MASTER_KEY_NAME,
            factory=lambda: base64.urlsafe_b64encode(os.urandom(32)).decode("utf-8"),
        )
        try:
            return Fernet(key.encode("utf-8"))
        except Exception:
            key = base64.urlsafe_b64encode(os.urandom(32)).decode("utf-8")
            self._secret_store.save(self._MASTER_KEY_NAME, key)
            return Fernet(key.encode("utf-8"))

    def _encrypt(self, data: dict[str, Any]) -> bytes:
        json_data = json.dumps(data, ensure_ascii=False)
        return self._fernet.encrypt(json_data.encode())

    def _decrypt(self, encrypted: bytes) -> dict[str, Any] | None:
        try:
            decrypted = self._fernet.decrypt(encrypted)
            return json.loads(decrypted.decode())
        except Exception:
            return None

    def _get_file_path(self, name: str) -> Path:
        return self._storage_dir / f"{name}.bin"

    def _write_record(self, name: str, data: dict[str, Any]) -> None:
        path = self._get_file_path(name)
        path.write_bytes(self._encrypt(data))
        os.chmod(path, 0o600)

    def _load_record(self, name: str) -> dict[str, Any] | None:
        path = self._get_file_path(name)
        if not path.exists():
            return None
        return self._decrypt(path.read_bytes())

    def save_user_session(self, session: dict[str, Any]) -> None:
        self._write_record("user_session", session)

    def load_user_session(self) -> dict[str, Any] | None:
        return self._load_record("user_session")

    def clear_user_session(self) -> None:
        path = self._get_file_path("user_session")
        if path.exists():
            path.unlink()

    def save_guest_session(self, session: dict[str, Any]) -> None:
        self._write_record("guest_session", session)

    def load_guest_session(self) -> dict[str, Any] | None:
        return self._load_record("guest_session")

    def update_guest_session(self, updates: dict[str, Any]) -> dict[str, Any] | None:
        current = self.load_guest_session()
        if current is None:
            return None
        current.update(updates)
        self.save_guest_session(current)
        return current

    def clear_guest_session(self) -> None:
        path = self._get_file_path("guest_session")
        if path.exists():
            path.unlink()

    def save_guest_trust_anchor(self, payload: dict[str, Any]) -> None:
        self._write_record("guest_trust_anchor", payload)

    def load_guest_trust_anchor(self) -> dict[str, Any] | None:
        return self._load_record("guest_trust_anchor")

    def update_guest_trust_anchor(self, updates: dict[str, Any]) -> dict[str, Any] | None:
        current = self.load_guest_trust_anchor() or {}
        current.update(updates)
        self.save_guest_trust_anchor(current)
        return current

    def clear_guest_trust_anchor(self) -> None:
        path = self._get_file_path("guest_trust_anchor")
        if path.exists():
            path.unlink()

    def save_login_credential(self, account: str, password: str) -> None:
        records = self._load_record("login_credentials") or {}
        records[str(account)] = str(password)
        self._write_record("login_credentials", records)

    def load_login_credential(self, account: str) -> str | None:
        records = self._load_record("login_credentials") or {}
        value = records.get(str(account))
        return str(value) if value is not None else None

    def clear_login_credential(self, account: str | None = None) -> None:
        if account is None:
            path = self._get_file_path("login_credentials")
            if path.exists():
                path.unlink()
            return
        records = self._load_record("login_credentials") or {}
        records.pop(str(account), None)
        if records:
            self._write_record("login_credentials", records)
        else:
            path = self._get_file_path("login_credentials")
            if path.exists():
                path.unlink()

    def save_login_prefill(self, payload: dict[str, Any]) -> None:
        self._write_record("login_prefill", payload)

    def load_login_prefill(self) -> dict[str, Any] | None:
        return self._load_record("login_prefill")
