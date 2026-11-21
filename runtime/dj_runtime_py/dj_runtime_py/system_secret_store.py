from __future__ import annotations

import os
import secrets
from pathlib import Path
from typing import Callable

try:
    from platformdirs import user_data_dir
except ImportError:
    def user_data_dir(app_name: str) -> str:
        return str(Path.home() / ".local" / "share" / app_name)


class SystemSecretStore:
    _APP_NAME = "JiaoFangSiDJ"

    def __init__(self) -> None:
        self._storage_dir = Path(user_data_dir(self._APP_NAME)) / "auth"
        self._storage_dir.mkdir(parents=True, exist_ok=True)

    def load_or_create(
        self,
        name: str,
        *,
        factory: Callable[[], str] | None = None,
        nbytes: int = 32,
    ) -> str:
        existing = self.load(name)
        if existing:
            return existing
        value = factory() if factory is not None else secrets.token_urlsafe(nbytes)
        self.save(name, value)
        return value

    def load(self, name: str) -> str | None:
        file_path = self._file_path(name)
        if not file_path.exists():
            return None
        try:
            value = file_path.read_text(encoding="utf-8").strip()
        except OSError:
            return None
        return value or None

    def save(self, name: str, value: str) -> None:
        file_path = self._file_path(name)
        file_path.write_text(value, encoding="utf-8")
        os.chmod(file_path, 0o600)

    def delete(self, name: str) -> None:
        file_path = self._file_path(name)
        if file_path.exists():
            file_path.unlink()

    def _file_path(self, name: str) -> Path:
        return self._storage_dir / f"{name}.secret"
