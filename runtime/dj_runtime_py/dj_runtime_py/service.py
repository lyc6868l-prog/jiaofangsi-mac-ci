from __future__ import annotations

import errno
import os
import re
import threading
import unicodedata
from pathlib import Path
from typing import Any

from .access_control import AccessControlError, require_module_access
from .protocol import ACTIONS, EVENTS, MODULE, PANELS, ApiError, EventEnvelope, RequestEnvelope, ResponseEnvelope, iso_now
from .rust_bridge import (
    RustBridgeError,
    delete_paths as rust_delete_paths,
    poll_scan_music_task,
    scan_music_by_content,
    start_scan_music_by_content_task,
    stop_scan_music_task,
)

AUDIO_SUFFIXES = {
    ".mp3",
    ".wav",
    ".flac",
    ".aac",
    ".m4a",
    ".aiff",
    ".ogg",
    ".wma",
}
COPY_MARKERS = re.compile(r"(?:\bcopy\s*\d+\b|\bcopy\b|副本\d*|复制|拷贝)", re.IGNORECASE)
MULTI_SPACE = re.compile(r"\s+")
EDGE_SEPARATORS = re.compile(r"^[\s._\-—–]+|[\s._\-—–]+$")


class CleanupDupRuntimeError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class PanelState:
    def __init__(self, panel: str) -> None:
        self.panel = panel
        self.file_paths: list[str] = []
        self.config: dict[str, Any] = {}
        self.status = "idle"


class TaskState:
    def __init__(
        self,
        task_id: str,
        panel: str,
        task_type: str,
        status: str,
        file_paths: list[str],
        config: dict[str, Any],
        progress: float = 0.0,
        progress_hint_text: str = "等待任务载入...",
        duplicate_count: int = 0,
        review_result: dict[str, Any] | None = None,
        rust_scan_task_id: str | None = None,
        cancel_requested: bool = False,
        worker_started: bool = False,
        error_message: str | None = None,
    ) -> None:
        self.task_id = task_id
        self.panel = panel
        self.task_type = task_type
        self.status = status
        self.file_paths = file_paths
        self.config = config
        self.progress = progress
        self.progress_hint_text = progress_hint_text
        self.duplicate_count = duplicate_count
        self.review_result = review_result
        self.rust_scan_task_id = rust_scan_task_id
        self.cancel_requested = cancel_requested
        self.worker_started = worker_started
        self.error_message = error_message
        self.created_at = iso_now()
        self.updated_at = self.created_at
        self.cleaned_count = 0
        self.skipped_count = 0
        self.deleted_count = 0

    @property
    def file_count(self) -> int:
        return len(self.file_paths)

    def summary(self) -> dict[str, Any]:
        return {
            "task_id": self.task_id,
            "panel": self.panel,
            "task_type": self.task_type,
            "status": self.status,
            "progress": self.progress,
            "progress_hint_text": self.progress_hint_text,
            "file_count": self.file_count,
            "duplicate_count": self.duplicate_count,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "cleaned_count": self.cleaned_count,
            "skipped_count": self.skipped_count,
            "deleted_count": self.deleted_count,
        }


class CleanupDupRuntime:
    def __init__(self) -> None:
        self._panels = {
            "title_clean": PanelState("title_clean"),
            "duplicate_search": PanelState("duplicate_search"),
        }
        self._panels_lock = threading.Lock()
        self._tasks_lock = threading.Lock()
        self._events_lock = threading.Lock()
        self._tasks: dict[str, TaskState] = {}
        self._events: list[EventEnvelope] = []
        self._task_index = 0

    def handle_request(self, raw_request: dict[str, Any]) -> dict[str, Any]:
        request_id = raw_request.get("request_id")
        try:
            request = RequestEnvelope.from_dict(raw_request)
            if request.module != MODULE:
                raise CleanupDupRuntimeError("INVALID_MODULE", "module 必须是 cleanup_dup。")
            if request.action not in ACTIONS:
                raise CleanupDupRuntimeError("INVALID_CONFIG", f"未知 action: {request.action}")
            require_module_access(MODULE, request.action)
            handler = getattr(self, f"_handle_{request.action}", None)
            if handler is None:
                raise CleanupDupRuntimeError("INVALID_CONFIG", f"action 未实现: {request.action}")
            data = handler(request.payload)
            return ResponseEnvelope(request.request_id, True, data, None).to_dict()
        except ValueError as exc:
            return ResponseEnvelope(
                request_id,
                False,
                None,
                ApiError("INVALID_CONFIG", "请求参数不合法，请检查后重试。"),
            ).to_dict()
        except AccessControlError as exc:
            return ResponseEnvelope(
                request_id,
                False,
                None,
                ApiError(exc.code, exc.message),
            ).to_dict()
        except CleanupDupRuntimeError as exc:
            return ResponseEnvelope(
                request_id,
                False,
                None,
                ApiError(exc.code, exc.message),
            ).to_dict()
        except Exception as exc:
            return ResponseEnvelope(
                request_id,
                False,
                None,
                ApiError("INTERNAL_ERROR", "处理失败，请稍后重试。"),
            ).to_dict()

    def _handle_load_targets(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = self._require_panel(payload.get("panel"))
        file_paths = payload.get("file_paths")
        if not isinstance(file_paths, list) or not file_paths:
            raise CleanupDupRuntimeError("EMPTY_TARGETS", "file_paths 不能为空。")
        normalized = self._collect_targets(file_paths)
        if not normalized:
            raise CleanupDupRuntimeError("EMPTY_TARGETS", "未找到可处理的音频文件。")
        state = self._panels[panel]
        state.file_paths = normalized
        state.status = "target_ready"
        return {
            "panel": panel,
            "status": state.status,
            "file_count": len(normalized),
            "file_paths": list(normalized),
        }

    def _handle_lock_config(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = self._require_panel(payload.get("panel"))
        config = payload.get("config") or {}
        if not isinstance(config, dict):
            raise CleanupDupRuntimeError("INVALID_CONFIG", "config 必须是对象。")
        self._validate_config(panel, config)
        state = self._panels[panel]
        state.config = dict(config)
        state.status = "config_locked"
        return {
            "panel": panel,
            "status": state.status,
            "config": dict(state.config),
        }

    def _handle_start_title_clean_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = payload.get("panel") or "title_clean"
        if panel != "title_clean":
            raise CleanupDupRuntimeError("INVALID_CONFIG", "title_clean 任务只能用于 title_clean 面板。")
        return self._start_task("title_clean", "title_clean").summary()

    def _handle_start_duplicate_check_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = payload.get("panel") or "duplicate_search"
        if panel != "duplicate_search":
            raise CleanupDupRuntimeError("INVALID_CONFIG", "duplicate_check 任务只能用于 duplicate_search 面板。")
        return self._start_task("duplicate_search", "duplicate_check").summary()

    def _handle_stop_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        task.cancel_requested = True
        if task.rust_scan_task_id is not None:
            try:
                stop_scan_music_task(task.rust_scan_task_id)
            except RustBridgeError:
                pass
        if task.task_type == "title_clean" and task.worker_started and task.status == "running":
            task.progress_hint_text = "任务正在停止..."
            task.updated_at = iso_now()
            return task.summary()
        task.status = "cancelled"
        task.progress_hint_text = "任务已由用户手动停止。"
        task.updated_at = iso_now()
        self._panels[task.panel].status = task.status
        self._push_event("task_status_changed", task)
        self._push_event("task_finished", task)
        return task.summary()

    def _handle_fetch_review_result(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        if task.status == "running":
            self._advance_task(task)
        if task.status == "error":
            raise CleanupDupRuntimeError("INTERNAL_ERROR", task.error_message or task.progress_hint_text)
        if task.status != "review_ready" or task.review_result is None:
            raise CleanupDupRuntimeError("TASK_NOT_REVIEW_READY", "当前任务还未进入 review_ready。")
        return {
            "task_id": task.task_id,
            "panel": task.panel,
            "status": task.status,
            **task.review_result,
        }

    def _handle_execute_delete(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        if task.status != "review_ready" or task.review_result is None:
            raise CleanupDupRuntimeError("TASK_NOT_REVIEW_READY", "删除前必须先完成审阅。")
        selected_files = payload.get("selected_files")
        if not isinstance(selected_files, list) or not selected_files:
            raise CleanupDupRuntimeError("DELETE_SELECTION_EMPTY", "请至少勾选 1 项删除目标。")
        move_to_recycle_bin = bool(payload.get("move_to_recycle_bin", True))
        deletable_paths = self._review_deletable_paths(task.review_result)
        selected_paths: list[Path] = []
        for item in selected_files:
            if not isinstance(item, dict):
                raise CleanupDupRuntimeError("INVALID_CONFIG", "selected_files 项格式不合法。")
            path_value = item.get("path")
            if not isinstance(path_value, str):
                raise CleanupDupRuntimeError("INVALID_CONFIG", "selected_files 项缺少 path。")
            path = Path(path_value).resolve()
            if str(path) not in deletable_paths:
                raise CleanupDupRuntimeError("INVALID_CONFIG", "存在不允许删除的文件。")
            if not path.exists():
                raise CleanupDupRuntimeError("FILE_DELETE_FAILED", f"文件不存在: {path}")
            selected_paths.append(path)
        task.status = "executing"
        task.progress = 1.0
        task.progress_hint_text = "正在执行删除..."
        task.updated_at = iso_now()
        self._panels[task.panel].status = task.status
        self._push_event("task_status_changed", task)
        self._delete_paths(selected_paths, move_to_recycle_bin)
        task.deleted_count = len(selected_paths)
        task.status = "success"
        task.progress_hint_text = "执行成功。"
        task.updated_at = iso_now()
        self._panels[task.panel].status = task.status
        self._panels[task.panel].file_paths = [
            path for path in self._panels[task.panel].file_paths if path not in {str(item) for item in selected_paths}
        ]
        self._push_event("task_finished", task)
        return {
            **task.summary(),
            "deleted_count": len(selected_paths),
            "move_to_recycle_bin": move_to_recycle_bin,
        }

    def _handle_subscribe_task_events(self, payload: dict[str, Any]) -> dict[str, Any]:
        task_id = payload.get("task_id")
        if task_id is not None:
            task = self._require_task(task_id)
            self._advance_task(task)
            with self._events_lock:
                events = [event for event in self._events if event.task_id == task_id]
                self._events = [event for event in self._events if event.task_id != task_id]
            return {"events": [event.to_dict() for event in events]}
        self._advance_all_tasks()
        with self._events_lock:
            events = [event.to_dict() for event in self._events]
            self._events.clear()
        return {"events": events}

    def _start_task(self, panel: str, task_type: str) -> TaskState:
        state = self._panels[panel]
        if not state.file_paths:
            raise CleanupDupRuntimeError("EMPTY_TARGETS", "请先载入目标文件。")
        if self._has_active_task(panel):
            raise CleanupDupRuntimeError("TASK_ALREADY_RUNNING", "当前面板已有进行中的任务。")
        self._validate_config(panel, state.config)
        task = TaskState(
            task_id=self._next_task_id(task_type),
            panel=panel,
            task_type=task_type,
            status="running",
            file_paths=list(state.file_paths),
            config=dict(state.config),
            progress=0.12,
            progress_hint_text="正在高速扫描扇区数据...",
        )
        self._tasks[task.task_id] = task
        state.status = task.status
        self._push_event("task_created", task)
        if task.task_type == "title_clean":
            self._start_title_clean_worker(task)
        return task

    def _advance_all_tasks(self) -> None:
        for task in self._tasks.values():
            self._advance_task(task)

    def _advance_task(self, task: TaskState) -> None:
        if task.status != "running":
            return
        if task.task_type == "title_clean":
            return
        task.progress = 1.0
        task.updated_at = iso_now()
        self._run_duplicate_check(task)

    def _start_title_clean_worker(self, task: TaskState) -> None:
        task.worker_started = True
        thread = threading.Thread(
            target=self._run_title_clean_worker,
            args=(task.task_id,),
            daemon=True,
        )
        thread.start()

    def _run_title_clean_worker(self, task_id: str) -> None:
        task = self._require_task(task_id)
        try:
            self._run_title_clean(task)
        except CleanupDupRuntimeError as exc:
            task.status = "error"
            task.error_message = exc.message
            task.progress_hint_text = exc.message
            task.updated_at = iso_now()
            self._panels[task.panel].status = task.status
            self._push_event("task_status_changed", task)
            self._push_event("task_finished", task)
        except Exception as exc:
            task.status = "error"
            task.error_message = "处理失败，请稍后重试。"
            task.progress_hint_text = task.error_message
            task.updated_at = iso_now()
            self._panels[task.panel].status = task.status
            self._push_event("task_status_changed", task)
            self._push_event("task_finished", task)

    def _run_title_clean(self, task: TaskState) -> None:
        delete_text = str(task.config.get("delete_text", "")).strip()
        if not delete_text:
            raise CleanupDupRuntimeError("INVALID_CONFIG", "请输入要清除的文本内容。")
        total = len(task.file_paths)
        next_paths: list[str] = []
        renamed_files: list[dict[str, str]] = []
        for index, raw_path in enumerate(task.file_paths, start=1):
            if task.cancel_requested:
                task.status = "cancelled"
                task.progress_hint_text = "任务已由用户手动停止。"
                task.updated_at = iso_now()
                self._panels[task.panel].status = task.status
                self._push_event("task_status_changed", task)
                self._push_event("task_finished", task)
                return
            path = Path(raw_path)
            if not path.exists():
                raise CleanupDupRuntimeError("TARGET_NOT_FOUND", f"文件不存在: {path}")
            cleaned_stem = self._clean_title(path.stem, delete_text)
            if not cleaned_stem or cleaned_stem == path.stem:
                task.skipped_count += 1
                next_paths.append(str(path.resolve()))
            else:
                target_path = self._unique_path(path.with_name(f"{cleaned_stem}{path.suffix}"))
                path.rename(target_path)
                task.cleaned_count += 1
                renamed_files.append({"old_path": str(path.resolve()), "new_path": str(target_path.resolve())})
                next_paths.append(str(target_path.resolve()))
            task.progress = index / total if total else 1.0
            task.progress_hint_text = f"正在清理标题... {index}/{total}"
            task.updated_at = iso_now()
            self._push_event("task_progress", task)
        task.file_paths = next_paths
        self._panels[task.panel].file_paths = list(next_paths)
        task.status = "success"
        task.progress = 1.0
        task.progress_hint_text = "任务执行完毕。"
        task.updated_at = iso_now()
        self._panels[task.panel].status = task.status
        task.review_result = {
            "renamed_files": renamed_files,
            "cleaned_count": task.cleaned_count,
            "skipped_count": task.skipped_count,
        }
        self._push_event("task_finished", task)

    def _run_duplicate_check(self, task: TaskState) -> None:
        if self._uses_async_content_scan(task):
            self._run_duplicate_check_via_rust_task(task)
            return
        groups = self._scan_duplicate_groups(task.file_paths, task.config)
        task.duplicate_count = len(groups)
        if not groups:
            task.status = "success"
            task.progress_hint_text = "未发现重复项。"
            self._panels[task.panel].status = task.status
            self._push_event("task_progress", task)
            self._push_event("task_finished", task)
            return
        task.review_result = {
            "duplicate_count": len(groups),
            "groups": groups,
        }
        task.status = "review_ready"
        task.progress_hint_text = "发现重复项，请审阅确认。"
        self._panels[task.panel].status = task.status
        self._push_event("task_progress", task)
        self._push_event("review_ready", task)

    def _push_event(self, event_name: str, task: TaskState) -> None:
        if event_name not in EVENTS:
            raise CleanupDupRuntimeError("INTERNAL_ERROR", f"未知 event: {event_name}")
        with self._events_lock:
            self._events.append(EventEnvelope(event_name, task.task_id, task.summary()))

    def _has_active_task(self, panel: str) -> bool:
        return any(
            task.panel == panel and task.status in {"running", "review_ready", "executing"}
            for task in self._tasks.values()
        )

    def _next_task_id(self, task_type: str) -> str:
        self._task_index += 1
        prefix = "task_title" if task_type == "title_clean" else "task_dup"
        return f"{prefix}_{self._task_index:03d}"

    def _require_panel(self, panel: Any) -> str:
        if not isinstance(panel, str) or panel not in PANELS:
            raise CleanupDupRuntimeError("INVALID_CONFIG", "panel 不合法。")
        return panel

    def _require_task(self, task_id: Any) -> TaskState:
        if not isinstance(task_id, str) or not task_id:
            raise CleanupDupRuntimeError("TASK_NOT_FOUND", "task_id 不存在。")
        task = self._tasks.get(task_id)
        if task is None:
            raise CleanupDupRuntimeError("TASK_NOT_FOUND", "未找到对应 task_id。")
        return task

    def _validate_config(self, panel: str, config: dict[str, Any]) -> None:
        if panel == "title_clean":
            delete_text = config.get("delete_text")
            if not isinstance(delete_text, str) or not delete_text.strip():
                raise CleanupDupRuntimeError("INVALID_CONFIG", "请输入要清除的文本内容。")
            return
        matching_mode = config.get("matching_mode")
        if matching_mode is not None and not isinstance(matching_mode, str):
            raise CleanupDupRuntimeError("INVALID_CONFIG", "matching_mode 必须是字符串。")
        move_to_recycle_bin = config.get("move_to_recycle_bin")
        if move_to_recycle_bin is not None and not isinstance(move_to_recycle_bin, bool):
            raise CleanupDupRuntimeError("INVALID_CONFIG", "move_to_recycle_bin 必须是布尔值。")

    def _collect_targets(self, paths: list[Any]) -> list[str]:
        targets: list[str] = []
        seen: set[str] = set()
        for item in paths:
            path = Path(self._require_path(item)).expanduser().resolve()
            if not path.exists():
                raise CleanupDupRuntimeError("TARGET_NOT_FOUND", f"路径不存在: {path}")
            if path.is_dir():
                for child in sorted(path.rglob("*")):
                    if child.is_file() and child.suffix.lower() in AUDIO_SUFFIXES:
                        child_value = str(child.resolve())
                        if child_value not in seen:
                            seen.add(child_value)
                            targets.append(child_value)
                continue
            if path.suffix.lower() not in AUDIO_SUFFIXES:
                continue
            path_value = str(path)
            if path_value not in seen:
                seen.add(path_value)
                targets.append(path_value)
        return targets

    def _require_path(self, path: Any) -> str:
        if not isinstance(path, str) or not path.strip():
            raise CleanupDupRuntimeError("TARGET_NOT_FOUND", "存在非法路径。")
        return path.strip()

    def _clean_title(self, title: str, delete_text: str) -> str:
        pattern = re.compile(re.escape(delete_text), re.IGNORECASE)
        cleaned = pattern.sub(" ", title)
        cleaned = cleaned.replace("_", " ")
        cleaned = MULTI_SPACE.sub(" ", cleaned).strip()
        cleaned = EDGE_SEPARATORS.sub("", cleaned)
        return cleaned or title.strip()

    def _scan_duplicate_groups(
        self,
        file_paths: list[str],
        config: dict[str, Any],
    ) -> list[dict[str, Any]]:
        matching_mode = str(config.get("matching_mode", "极速比对"))
        if matching_mode == "内容比对":
            try:
                result = scan_music_by_content(file_paths, False)
            except RustBridgeError:
                return self._scan_duplicate_groups_by_name(file_paths)
            groups = result.get("groups")
            return groups if isinstance(groups, list) else []
        return self._scan_duplicate_groups_by_name(file_paths)

    def _uses_async_content_scan(self, task: TaskState) -> bool:
        return str(task.config.get("matching_mode", "极速比对")) == "内容比对"

    def _run_duplicate_check_via_rust_task(self, task: TaskState) -> None:
        if task.rust_scan_task_id is None:
            try:
                started = start_scan_music_by_content_task(task.file_paths, False)
                rust_task_id = started.get("task_id")
                if not isinstance(rust_task_id, str) or not rust_task_id:
                    raise CleanupDupRuntimeError("INTERNAL_ERROR", "Rust 扫描任务启动失败。")
                task.rust_scan_task_id = rust_task_id
                task.progress = 0.03
                task.progress_hint_text = "正在准备内容比对..."
                task.updated_at = iso_now()
                self._panels[task.panel].status = task.status
                self._push_event("task_progress", task)
                return
            except RustBridgeError:
                groups = self._scan_duplicate_groups_by_name(task.file_paths)
                self._finish_duplicate_check(task, groups)
                return

        try:
            polled = poll_scan_music_task(task.rust_scan_task_id)
        except RustBridgeError as exc:
            raise CleanupDupRuntimeError("INTERNAL_ERROR", "内容比对执行失败，请稍后重试。") from exc

        status = polled.get("status")
        task.progress = float(polled.get("progress") or task.progress)
        task.progress_hint_text = str(
            polled.get("progress_hint_text") or task.progress_hint_text
        )
        task.updated_at = iso_now()
        self._panels[task.panel].status = task.status
        self._push_event("task_progress", task)

        if status == "running":
            return
        if status == "cancelled":
            task.status = "cancelled"
            task.progress_hint_text = "任务已由用户手动停止。"
            self._panels[task.panel].status = task.status
            self._push_event("task_status_changed", task)
            self._push_event("task_finished", task)
            return
        if status == "error":
            error_message = str(polled.get("error") or "内容比对执行失败。")
            raise CleanupDupRuntimeError("INTERNAL_ERROR", error_message)

        result = polled.get("result")
        groups = []
        if isinstance(result, dict):
            raw_groups = result.get("groups")
            if isinstance(raw_groups, list):
                groups = raw_groups
        self._finish_duplicate_check(task, groups)

    def _finish_duplicate_check(
        self,
        task: TaskState,
        groups: list[dict[str, Any]],
    ) -> None:
        task.duplicate_count = len(groups)
        if not groups:
            task.status = "success"
            task.progress = 1.0
            task.progress_hint_text = "未发现重复项。"
            task.review_result = None
            self._panels[task.panel].status = task.status
            self._push_event("task_progress", task)
            self._push_event("task_finished", task)
            return
        task.review_result = {
            "duplicate_count": len(groups),
            "groups": groups,
        }
        task.status = "review_ready"
        task.progress = 1.0
        task.progress_hint_text = "发现重复项，请审阅确认。"
        self._panels[task.panel].status = task.status
        self._push_event("task_progress", task)
        self._push_event("review_ready", task)

    def _scan_duplicate_groups_by_name(self, file_paths: list[str]) -> list[dict[str, Any]]:
        grouped: dict[str, list[Path]] = {}
        for raw_path in file_paths:
            path = Path(raw_path)
            if not path.exists() or not path.is_file():
                continue
            key = self._normalize_duplicate_key(path.stem)
            if not key:
                continue
            grouped.setdefault(key, []).append(path.resolve())
        groups: list[dict[str, Any]] = []
        for paths in grouped.values():
            if len(paths) < 2:
                continue
            ordered = sorted(paths, key=lambda item: item.name.lower())
            keep_path = self._choose_keep_path(ordered)
            entries: list[dict[str, Any]] = []
            for path in ordered:
                entries.append(
                    {
                        "path": str(path),
                        "name": path.name,
                        "size": self._format_size(path.stat().st_size),
                        "is_auto_keep": path == keep_path,
                        "is_selected_to_delete": path != keep_path,
                    }
                )
            groups.append(
                {
                    "group_name": keep_path.stem,
                    "entries": entries,
                }
            )
        groups.sort(key=lambda item: str(item["group_name"]).lower())
        return groups

    def _normalize_duplicate_key(self, title: str) -> str:
        text = unicodedata.normalize("NFKC", title).lower()
        text = text.replace("_", " ")
        text = re.sub(r"[\[\](){}【】（）]", " ", text)
        text = COPY_MARKERS.sub(" ", text)
        text = MULTI_SPACE.sub(" ", text).strip()
        text = EDGE_SEPARATORS.sub("", text)
        return text

    def _choose_keep_path(self, paths: list[Path]) -> Path:
        return max(
            paths,
            key=lambda path: (
                path.stat().st_size,
                -len(path.name),
                path.name.lower(),
            ),
        )

    def _review_deletable_paths(self, review_result: dict[str, Any]) -> set[str]:
        groups = review_result.get("groups")
        if not isinstance(groups, list):
            return set()
        deletable: set[str] = set()
        for group in groups:
            if not isinstance(group, dict):
                continue
            entries = group.get("entries")
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                if entry.get("is_auto_keep"):
                    continue
                path = entry.get("path")
                if isinstance(path, str):
                    deletable.add(str(Path(path).resolve()))
        return deletable

    def _delete_paths(self, paths: list[Path], move_to_recycle_bin: bool) -> None:
        try:
            rust_delete_paths([str(path) for path in paths], move_to_recycle_bin)
            return
        except RustBridgeError:
            pass
        for path in paths:
            if move_to_recycle_bin:
                self._move_to_trash(path)
                continue
            path.unlink()

    def _move_to_trash(self, path: Path) -> None:
        trash_dir = self._resolve_trash_directory()
        trash_dir.mkdir(parents=True, exist_ok=True)
        target = self._unique_path(trash_dir / path.name)
        try:
            path.rename(target)
        except OSError as exc:
            if exc.errno != errno.EXDEV:
                raise
            target.write_bytes(path.read_bytes())
            path.unlink()

    def _resolve_trash_directory(self) -> Path:
        if os.name == "nt":
            recycle_root = os.environ.get("LOCALAPPDATA") or str(Path.home())
            return Path(recycle_root) / "JFSRecycleBin"
        return Path.home() / ".Trash"

    def _unique_path(self, path: Path) -> Path:
        if not path.exists():
            return path
        counter = 1
        while True:
            candidate = path.with_name(f"{path.stem} ({counter}){path.suffix}")
            if not candidate.exists():
                return candidate
            counter += 1

    def _format_size(self, size_bytes: int) -> str:
        if size_bytes >= 1024 * 1024:
            return f"{size_bytes / (1024 * 1024):.1f} MB"
        if size_bytes >= 1024:
            return f"{size_bytes / 1024:.1f} KB"
        return f"{size_bytes} B"
