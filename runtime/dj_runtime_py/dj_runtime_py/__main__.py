from __future__ import annotations

import json
import sys
from typing import Any

from pathlib import Path


def _ensure_vendor_path() -> None:
    current = Path(__file__).resolve()
    for parent in current.parents:
        candidate = parent / "vendor"
        if candidate.exists():
            candidate_value = str(candidate)
            if candidate_value not in sys.path:
                sys.path.insert(0, candidate_value)
            return


_ensure_vendor_path()

def _resolve_unlock_worker_root() -> Path:
    current = Path(__file__).resolve()
    for parent in current.parents:
        candidate = parent / "runtime" / "unlock_music_node"
        if (candidate / "src" / "main.js").exists():
            return candidate
    return current.parents[3] / "runtime" / "unlock_music_node"


def _resolve_node_executable() -> str:
    current = Path(__file__).resolve()
    for parent in current.parents:
        bundled = parent / "runtime" / "nodejs" / "node.exe"
        if bundled.exists():
            return str(bundled)

        dev_node = parent / ".venv" / "Lib" / "site-packages" / "nodejs_wheel" / "node.exe"
        if dev_node.exists():
            return str(dev_node)

        dev_shim = parent / ".venv" / "Scripts" / "node.exe"
        if dev_shim.exists():
            return str(dev_shim)

    return "node"


def _build_runtime_factories() -> dict[str, Any]:
    def create_audio_transcode() -> Any:
        from .audio_transcode_service import AudioTranscodeRuntime

        return AudioTranscodeRuntime()

    def create_auth() -> Any:
        from .auth_runtime import AuthRuntime

        return AuthRuntime()

    def create_cleanup_dup() -> Any:
        from .service import CleanupDupRuntime

        return CleanupDupRuntime()

    def create_guest() -> Any:
        from .guest_runtime import GuestRuntime

        return GuestRuntime()

    def create_metadata_edit() -> Any:
        from .metadata_edit_service import MetadataEditRuntime

        return MetadataEditRuntime()

    def create_pinyin_generator() -> Any:
        from .pinyin_generator_service import PinyinGeneratorRuntime

        return PinyinGeneratorRuntime()

    def create_usb_backup() -> Any:
        from .usb_backup_service import UsbBackupRuntime

        return UsbBackupRuntime()

    def create_unlock_music() -> Any:
        from .unlock_music_service import UnlockMusicRuntime
        from .unlock_node_bridge import UnlockNodeBridge

        unlock_worker_root = _resolve_unlock_worker_root()
        unlock_bridge = UnlockNodeBridge(
            node_executable=_resolve_node_executable(),
            working_directory=str(unlock_worker_root),
            entry_script=str(unlock_worker_root / "src" / "main.js"),
        )
        return UnlockMusicRuntime(bridge=unlock_bridge)

    def create_search_download() -> Any:
        from .search_download_service import SearchDownloadRuntime

        return SearchDownloadRuntime()

    return {
        "audio_transcode": create_audio_transcode,
        "auth": create_auth,
        "cleanup_dup": create_cleanup_dup,
        "guest": create_guest,
        "metadata_edit": create_metadata_edit,
        "pinyin_generator": create_pinyin_generator,
        "usb_backup": create_usb_backup,
        "unlock_music": create_unlock_music,
        "search_download": create_search_download,
    }


def _humanize_runtime_boot_error(exc: Exception) -> str:
    message = str(exc).strip()
    lowered = message.lower()
    if "no module named" in lowered or "importerror" in lowered:
        return "运行模块初始化失败，请检查运行环境是否完整。"
    if "permission" in lowered:
        return "运行模块初始化失败，请检查目录权限后重试。"
    return "运行模块初始化失败，请稍后重试。"


def main() -> int:
    runtime_factories = _build_runtime_factories()
    runtimes: dict[str, Any] = {}
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            request: dict[str, Any] = json.loads(line)
        except json.JSONDecodeError as exc:
            response = {
                "request_id": None,
                "ok": False,
                "data": None,
                "error": {
                    "code": "INTERNAL_ERROR",
                    "message": "请求格式错误，请重试。",
                },
            }
        else:
            module = request.get("module")
            if not isinstance(module, str) or module not in runtime_factories:
                response = {
                    "request_id": request.get("request_id"),
                    "ok": False,
                    "data": None,
                    "error": {
                        "code": "INVALID_MODULE",
                        "message": "未知 module。",
                    },
                }
            else:
                runtime = runtimes.get(module)
                if runtime is None:
                    try:
                        runtime = runtime_factories[module]()
                        runtimes[module] = runtime
                    except Exception as exc:
                        response = {
                            "request_id": request.get("request_id"),
                            "ok": False,
                            "data": None,
                            "error": {
                                "code": "RUNTIME_INIT_FAILED",
                                "message": _humanize_runtime_boot_error(exc),
                            },
                        }
                        sys.stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
                        sys.stdout.flush()
                        continue
                response = runtime.handle_request(request)
        sys.stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    for runtime in runtimes.values():
        close = getattr(runtime, "close", None)
        if callable(close):
            close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
