from __future__ import annotations

import json
from functools import lru_cache
from typing import Any


class RustBridgeError(Exception):
    pass


@lru_cache(maxsize=1)
def _load_module():
    try:
        import dj_scan_core
    except ImportError as exc:
        raise RustBridgeError(str(exc)) from exc
    return dj_scan_core


def health_check() -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.health_check())
    except Exception as exc:
        raise RustBridgeError(str(exc)) from exc


def scan_music_by_tags(
    paths: list[str],
    fields: list[str] | None = None,
    approximate: bool = False,
) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(
            module.scan_music_by_tags(paths, fields or ["title"], approximate)
        )
    except Exception as exc:
        raise RustBridgeError(str(exc)) from exc


def scan_music_by_content(
    paths: list[str],
    compare_similar_titles_only: bool = False,
) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(
            module.scan_music_by_content(paths, compare_similar_titles_only)
        )
    except Exception as exc:
        raise RustBridgeError(str(exc)) from exc


def start_scan_music_by_content_task(
    paths: list[str],
    compare_similar_titles_only: bool = False,
) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(
            module.start_scan_music_by_content_task(
                paths,
                compare_similar_titles_only,
            )
        )
    except Exception as exc:
        raise RustBridgeError(str(exc)) from exc


def poll_scan_music_task(task_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.poll_scan_music_task(task_id))
    except Exception as exc:
        raise RustBridgeError(str(exc)) from exc


def stop_scan_music_task(task_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.stop_scan_music_task(task_id))
    except Exception as exc:
        raise RustBridgeError(str(exc)) from exc


def delete_paths(paths: list[str], move_to_recycle_bin: bool = True) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.delete_paths(paths, move_to_recycle_bin))
    except Exception as exc:
        raise RustBridgeError(str(exc)) from exc
