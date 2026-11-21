"""Compatibility boundary for the vendored musicdl package.

The upstream project changes private parser method names and source modules
between releases.  Search/download code should go through this module instead
of relying on one specific upstream implementation detail.
"""
from __future__ import annotations

import importlib
from typing import Any


EXPECTED_MUSICDL_VERSION = "2.14.2"
_PARSER_EXCLUDED = {"_parsewithofficialapiv1", "_parsewiththirdpartapis"}

_musicdl_module: Any | None = None
_sources_module: Any | None = None
_data_module: Any | None = None
_logger_module: Any | None = None


def load_musicdl_modules() -> tuple[Any, Any, Any, Any]:
    global _musicdl_module, _sources_module, _data_module, _logger_module
    if _musicdl_module is None:
        _musicdl_module = importlib.import_module("musicdl.musicdl")
    if _sources_module is None:
        _sources_module = importlib.import_module("musicdl.modules.sources")
    if _data_module is None:
        _data_module = importlib.import_module("musicdl.modules.utils.data")
    if _logger_module is None:
        _logger_module = importlib.import_module("musicdl.modules.utils.logger")
    return _musicdl_module, _sources_module, _data_module, _logger_module


def musicdl_version() -> str:
    module = importlib.import_module("musicdl")
    return str(getattr(module, "__version__", "unknown"))


def discover_parser_methods(music_client: Any, limit: int = 8) -> tuple[str, ...]:
    """Return parser methods that exist on the current upstream client."""
    names = sorted(
        name
        for name in dir(music_client)
        if name.startswith("_parsewith")
        and name not in _PARSER_EXCLUDED
        and callable(getattr(music_client, name, None))
    )
    return tuple(names[:limit])


def get_music_client(client: Any, source: str) -> Any | None:
    return getattr(client, "music_clients", {}).get(source)


def get_request_overrides(client: Any, source: str) -> dict[str, Any]:
    value = getattr(client, "requests_overrides", {}) or {}
    return dict(value.get(source) or {})


def get_source_threads(client: Any, source: str, default: int = 5) -> int:
    value = getattr(client, "clients_threadings", {}) or {}
    try:
        return int(value.get(source, default))
    except (TypeError, ValueError):
        return default
