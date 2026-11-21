from __future__ import annotations

import os
import threading
from pathlib import Path
from typing import Any

from .access_control import AccessControlError, require_module_access
from .protocol import ApiError, EventEnvelope, RequestEnvelope, ResponseEnvelope, iso_now
from .unlock_node_bridge import UnlockNodeBridge, UnlockNodeBridgeError

MODULE = "unlock_music"
PANELS = {"unlock"}
TASK_TYPES = {"unlock"}
STATUSES = {
    "idle",
    "target_ready",
    "config_locked",
    "running",
    "success",
    "cancelled",
    "error",
}
EVENTS = {
    "task_created",
    "task_progress",
    "task_status_changed",
    "task_finished",
}
ACTIONS = {
    "load_targets",
    "remove_target",
    "clear_targets",
    "lock_config",
    "start_unlock_task",
    "fetch_unlock_result",
    "stop_task",
    "subscribe_task_events",
}
ERROR_CODES = {
    "INVALID_MODULE",
    "INVALID_CONFIG",
    "EMPTY_TARGETS",
    "TARGET_NOT_FOUND",
    "TASK_NOT_FOUND",
    "TASK_ALREADY_RUNNING",
    "TASK_NOT_COMPLETED",
    "TARGET_LIMIT_EXCEEDED",
    "INTERNAL_ERROR",
}
SUPPORTED_SUFFIXES = {
    ".ncm",
    ".uc",
    ".cache",
    ".qmc0",
    ".qmc2",
    ".qmc3",
    ".qmcflac",
    ".qmcogg",
    ".mgg",
    ".mgg0",
    ".mgg1",
    ".mggl",
    ".mflac",
    ".mflac0",
    ".mmp4",
    ".bkcmp3",
    ".bkcflac",
    ".tkm",
    ".666c6163",
    ".6d7033",
    ".6f6767",
    ".6d3461",
    ".776176",
    ".kgm",
    ".kgma",
    ".vpr",
    ".kwm",
    ".xm",
    ".tm0",
    ".tm2",
    ".tm3",
    ".tm6",
    ".mp3",
    ".flac",
    ".m4a",
    ".ogg",
    ".wav",
    ".wma",
    ".aac",
    ".dff",
    ".ofl_en",
}
MAX_TARGET_FILES = 2000
MAX_DIRECTORY_WALKS = 20000
try:
    _MAX_INPUT_MB = max(1, int(os.environ.get("DJ_UNLOCK_MAX_INPUT_MB", "1024")))
except ValueError:
    _MAX_INPUT_MB = 1024
MAX_INPUT_SIZE_BYTES = _MAX_INPUT_MB * 1024 * 1024


class UnlockMusicRuntimeError(Exception):
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
    ) -> None:
        self.task_id = task_id
        self.panel = panel
        self.task_type = task_type
        self.status = status
        self.file_paths = file_paths
        self.config = config
        self.progress = 0.0
        self.progress_hint_text = "等待任务载入..."
        self.worker_started = False
        self.cancel_requested = False
        self.error_message: str | None = None
        self.success_count = 0
        self.failed_count = 0
        self.results: list[dict[str, Any]] = []
        self.created_at = iso_now()
        self.updated_at = self.created_at

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
            "success_count": self.success_count,
            "failed_count": self.failed_count,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }


def _humanize_unlock_music_error(exc: Exception) -> str:
    message = str(exc).strip()
    lowered = message.lower()
    if "timeout" in lowered or "timed out" in lowered:
        return "解锁任务超时，请稍后重试。"
    if "permission denied" in lowered:
        return "文件写入失败，请检查输出目录权限。"
    if "not found" in lowered or "no such file" in lowered:
        return "目标文件不存在，请重新载入后重试。"
    if "network" in lowered or "connection" in lowered:
        return "解锁服务连接失败，请稍后重试。"
    return "解锁失败，请稍后重试。"


class UnlockMusicRuntime:
    def __init__(self, bridge: UnlockNodeBridge) -> None:
        self._bridge = bridge
        self._panels = {"unlock": PanelState("unlock")}
        self._tasks: dict[str, TaskState] = {}
        self._events: list[EventEnvelope] = []
        self._task_index = 0
        self._events_lock = threading.Lock()

    def handle_request(self, raw_request: dict[str, Any]) -> dict[str, Any]:
        request_id = raw_request.get("request_id")
        try:
            request = RequestEnvelope.from_dict(raw_request)
            if request.module != MODULE:
                raise UnlockMusicRuntimeError("INVALID_MODULE", "module 必须是 unlock_music。")
            if request.action not in ACTIONS:
                raise UnlockMusicRuntimeError("INVALID_CONFIG", f"未知 action: {request.action}")
            require_module_access(MODULE, request.action)
            handler = getattr(self, f"_handle_{request.action}", None)
            if handler is None:
                raise UnlockMusicRuntimeError("INVALID_CONFIG", f"action 未实现: {request.action}")
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
        except UnlockMusicRuntimeError as exc:
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
                ApiError("INTERNAL_ERROR", _humanize_unlock_music_error(exc)),
            ).to_dict()

    def _handle_load_targets(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = self._require_panel(payload.get("panel"))
        file_paths = payload.get("file_paths")
        append = bool(payload.get("append", False))
        if not isinstance(file_paths, list) or not file_paths:
            raise UnlockMusicRuntimeError("EMPTY_TARGETS", "file_paths 不能为空。")
        normalized, skipped = self._collect_targets(file_paths)
        if not normalized:
            raise UnlockMusicRuntimeError(
                "EMPTY_TARGETS",
                "未找到可处理的解锁文件。",
            )
        state = self._panels[panel]
        original = list(state.file_paths)
        if append:
            merged = list(original)
            seen = set(original)
            added_paths: list[str] = []
            for path in normalized:
                if path not in seen:
                    seen.add(path)
                    merged.append(path)
                    added_paths.append(path)
            state.file_paths = merged
        else:
            state.file_paths = list(normalized)
            added_paths = [path for path in normalized if path not in set(original)]
        state.status = "target_ready" if state.file_paths else "idle"
        return self._load_result(state.file_paths, added_paths, skipped)

    def _handle_remove_target(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = self._require_panel(payload.get("panel"))
        file_path = Path(self._require_path(payload.get("file_path"))).expanduser().resolve()
        state = self._panels[panel]
        value = str(file_path)
        state.file_paths = [path for path in state.file_paths if path != value]
        state.status = "target_ready" if state.file_paths else "idle"
        return self._load_result(state.file_paths, [], [])

    def _handle_clear_targets(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = self._require_panel(payload.get("panel"))
        state = self._panels[panel]
        state.file_paths = []
        state.status = "idle"
        return self._load_result([], [], [])

    def _handle_lock_config(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = self._require_panel(payload.get("panel"))
        config = payload.get("config") or {}
        if not isinstance(config, dict):
            raise UnlockMusicRuntimeError("INVALID_CONFIG", "config 必须是对象。")
        self._validate_config(config)
        state = self._panels[panel]
        state.config = dict(config)
        state.status = "config_locked"
        return {
            "panel": panel,
            "status": state.status,
            "config": dict(state.config),
        }

    def _handle_start_unlock_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = payload.get("panel") or "unlock"
        if panel != "unlock":
            raise UnlockMusicRuntimeError("INVALID_CONFIG", "unlock 任务只能用于 unlock 面板。")
        return self._start_task().summary()

    def _handle_fetch_unlock_result(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        if task.status == "running":
            raise UnlockMusicRuntimeError("TASK_NOT_COMPLETED", "当前任务仍在运行中。")
        if task.status == "error":
            raise UnlockMusicRuntimeError("INTERNAL_ERROR", task.error_message or task.progress_hint_text)
        return {
            "task_id": task.task_id,
            "status": task.status,
            "results": list(task.results),
            "success_count": task.success_count,
            "failed_count": task.failed_count,
        }

    def _handle_stop_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        task.cancel_requested = True
        if task.status == "running":
            task.progress_hint_text = "任务正在停止..."
            task.updated_at = iso_now()
            cancel_current = getattr(self._bridge, "cancel_current", None)
            if callable(cancel_current):
                cancel_current()
            return task.summary()
        return task.summary()

    def _handle_subscribe_task_events(self, payload: dict[str, Any]) -> dict[str, Any]:
        task_id = payload.get("task_id")
        if task_id is not None:
            self._require_task(task_id)
            with self._events_lock:
                events = [event for event in self._events if event.task_id == task_id]
                self._events = [event for event in self._events if event.task_id != task_id]
            return {"events": [event.to_dict() for event in events]}
        with self._events_lock:
            events = [event.to_dict() for event in self._events]
            self._events.clear()
        return {"events": events}

    def _start_task(self) -> TaskState:
        state = self._panels["unlock"]
        if not state.file_paths:
            raise UnlockMusicRuntimeError("EMPTY_TARGETS", "请先载入目标文件。")
        if self._has_active_task("unlock"):
            raise UnlockMusicRuntimeError("TASK_ALREADY_RUNNING", "当前面板已有进行中的任务。")
        self._validate_config(state.config)
        task = TaskState(
            task_id=self._next_task_id(),
            panel="unlock",
            task_type="unlock",
            status="running",
            file_paths=list(state.file_paths),
            config=dict(state.config),
        )
        task.progress = 0.01
        task.progress_hint_text = "正在准备解锁任务..."
        self._tasks[task.task_id] = task
        state.status = task.status
        self._push_event("task_created", task)
        self._start_worker(task)
        return task

    def _start_worker(self, task: TaskState) -> None:
        task.worker_started = True
        thread = threading.Thread(target=self._run_task_worker, args=(task.task_id,), daemon=True)
        thread.start()

    def _run_task_worker(self, task_id: str) -> None:
        task = self._require_task(task_id)
        try:
            self._bridge.ensure_started()
            output_dir = str(Path(str(task.config.get("output_dir"))).resolve())
            overwrite = bool(task.config.get("overwrite", False))
            keep_source = bool(task.config.get("keep_source", True))
            total = len(task.file_paths)
            for index, raw_path in enumerate(task.file_paths, start=1):
                if task.cancel_requested:
                    task.status = "cancelled"
                    task.progress_hint_text = "任务已由用户手动停止。"
                    task.updated_at = iso_now()
                    self._panels[task.panel].status = task.status
                    self._push_event("task_status_changed", task)
                    self._push_event("task_finished", task)
                    return
                try:
                    input_size = os.path.getsize(raw_path)
                except OSError as exc:
                    task.results.append(
                        {
                            "input_path": raw_path,
                            "output_path": None,
                            "success": False,
                            "error": f"无法读取文件信息: {exc}",
                        }
                    )
                    task.failed_count += 1
                    task.progress = index / total if total else 1.0
                    task.updated_at = iso_now()
                    self._push_event("task_progress", task)
                    continue
                if input_size > MAX_INPUT_SIZE_BYTES:
                    limit_mb = MAX_INPUT_SIZE_BYTES // (1024 * 1024)
                    task.results.append(
                        {
                            "input_path": raw_path,
                            "output_path": None,
                            "success": False,
                            "error": f"文件超过 {limit_mb} MB 上限，已跳过。",
                        }
                    )
                    task.failed_count += 1
                    task.progress = index / total if total else 1.0
                    task.progress_hint_text = f"已跳过超大文件 ({index}/{total})..."
                    task.updated_at = iso_now()
                    self._push_event("task_progress", task)
                    continue
                try:
                    unlocked = self._bridge.unlock_file(
                        input_path=raw_path,
                        output_dir=output_dir,
                        overwrite=overwrite,
                        keep_source=keep_source,
                    )
                    result = unlocked.get("result")
                    if isinstance(result, dict) and result.get("success") is True:
                        task.results.append(result)
                        task.success_count += 1
                        if not keep_source:
                            input_path = str(result.get("input_path") or raw_path)
                            output_path = str(result.get("output_path") or "")
                            try:
                                if output_path and os.path.abspath(input_path) != os.path.abspath(output_path):
                                    os.unlink(input_path)
                            except OSError:
                                pass
                    else:
                        task.results.append(
                            {
                                "input_path": raw_path,
                                "output_path": None,
                                "success": False,
                                "error": "解锁失败",
                            }
                        )
                        task.failed_count += 1
                except UnlockNodeBridgeError as exc:
                    if task.cancel_requested or exc.code == "CANCELLED":
                        task.status = "cancelled"
                        task.error_message = "任务已由用户手动停止。"
                        task.progress_hint_text = task.error_message
                        task.updated_at = iso_now()
                        self._panels[task.panel].status = task.status
                        self._push_event("task_status_changed", task)
                        self._push_event("task_finished", task)
                        return
                    task.results.append(
                        {
                            "input_path": raw_path,
                            "output_path": None,
                            "success": False,
                            "error": exc.message,
                        }
                    )
                    task.failed_count += 1
                task.progress = index / total if total else 1.0
                task.progress_hint_text = f"正在解锁... {index}/{total}"
                task.updated_at = iso_now()
                self._push_event("task_progress", task)
            task.progress = 1.0
            if task.success_count == 0 and task.failed_count > 0:
                task.status = "error"
                task.error_message = "全部文件解锁失败。"
                task.progress_hint_text = task.error_message
            else:
                task.status = "success"
                if task.failed_count > 0:
                    task.progress_hint_text = (
                        f"解锁任务执行完毕：成功 {task.success_count}，失败 {task.failed_count}。"
                    )
                else:
                    task.progress_hint_text = "解锁任务执行完毕。"
            task.updated_at = iso_now()
            self._panels[task.panel].status = task.status
            self._push_event("task_finished", task)
        except UnlockNodeBridgeError as exc:
            task.status = "error"
            task.error_message = exc.message
            task.progress_hint_text = exc.message
            task.updated_at = iso_now()
            self._panels[task.panel].status = task.status
            self._push_event("task_status_changed", task)
            self._push_event("task_finished", task)
        except Exception as exc:
            task.status = "error"
            task.error_message = _humanize_unlock_music_error(exc)
            task.progress_hint_text = task.error_message
            task.updated_at = iso_now()
            self._panels[task.panel].status = task.status
            self._push_event("task_status_changed", task)
            self._push_event("task_finished", task)

    def _collect_targets(self, paths: list[Any]) -> tuple[list[str], list[str]]:
        targets: list[str] = []
        skipped: list[str] = []
        seen: set[str] = set()
        walked = 0
        for item in paths:
            path = Path(self._require_path(item)).expanduser().resolve()
            if not path.exists():
                raise UnlockMusicRuntimeError("TARGET_NOT_FOUND", f"路径不存在: {path}")
            if path.is_dir():
                for child in sorted(path.rglob("*")):
                    walked += 1
                    if walked > MAX_DIRECTORY_WALKS:
                        raise UnlockMusicRuntimeError(
                            "TARGET_LIMIT_EXCEEDED",
                            f"扫描目录过大，请缩小导入范围后重试（最多扫描 {MAX_DIRECTORY_WALKS} 个节点）。",
                        )
                    if not child.is_file():
                        continue
                    child_value = str(child.resolve())
                    if child.suffix.lower() not in SUPPORTED_SUFFIXES:
                        skipped.append(child_value)
                        continue
                    if child_value not in seen:
                        seen.add(child_value)
                        targets.append(child_value)
                        if len(targets) > MAX_TARGET_FILES:
                            raise UnlockMusicRuntimeError(
                                "TARGET_LIMIT_EXCEEDED",
                                f"单次最多导入 {MAX_TARGET_FILES} 个文件，请分批处理。",
                            )
                continue
            value = str(path.resolve())
            if path.suffix.lower() not in SUPPORTED_SUFFIXES:
                skipped.append(value)
                continue
            if value not in seen:
                seen.add(value)
                targets.append(value)
                if len(targets) > MAX_TARGET_FILES:
                    raise UnlockMusicRuntimeError(
                        "TARGET_LIMIT_EXCEEDED",
                        f"单次最多导入 {MAX_TARGET_FILES} 个文件，请分批处理。",
                    )
        return targets, skipped

    def _load_result(
        self,
        file_paths: list[str],
        added_paths: list[str],
        skipped_paths: list[str],
    ) -> dict[str, Any]:
        return {
            "file_count": len(file_paths),
            "file_paths": list(file_paths),
            "added_paths": list(added_paths),
            "skipped_paths": list(skipped_paths),
        }

    def _validate_config(self, config: dict[str, Any]) -> None:
        output_dir = config.get("output_dir")
        if not isinstance(output_dir, str) or not output_dir.strip():
            raise UnlockMusicRuntimeError("INVALID_CONFIG", "output_dir 不能为空。")
        overwrite = config.get("overwrite")
        if overwrite is not None and not isinstance(overwrite, bool):
            raise UnlockMusicRuntimeError("INVALID_CONFIG", "overwrite 必须是布尔值。")
        keep_source = config.get("keep_source")
        if keep_source is not None and not isinstance(keep_source, bool):
            raise UnlockMusicRuntimeError("INVALID_CONFIG", "keep_source 必须是布尔值。")

    def _require_panel(self, panel: Any) -> str:
        if not isinstance(panel, str) or panel not in PANELS:
            raise UnlockMusicRuntimeError("INVALID_CONFIG", "panel 不合法。")
        return panel

    def _require_path(self, path: Any) -> str:
        if not isinstance(path, str) or not path.strip():
            raise UnlockMusicRuntimeError("TARGET_NOT_FOUND", "存在非法路径。")
        return path.strip()

    def _require_task(self, task_id: Any) -> TaskState:
        if not isinstance(task_id, str) or not task_id:
            raise UnlockMusicRuntimeError("TASK_NOT_FOUND", "task_id 不存在。")
        task = self._tasks.get(task_id)
        if task is None:
            raise UnlockMusicRuntimeError("TASK_NOT_FOUND", "未找到对应 task_id。")
        return task

    def _has_active_task(self, panel: str) -> bool:
        return any(
            task.panel == panel and task.status == "running"
            for task in self._tasks.values()
        )

    def _next_task_id(self) -> str:
        self._task_index += 1
        return f"task_unlock_{self._task_index:03d}"

    def _push_event(self, event_name: str, task: TaskState) -> None:
        if event_name not in EVENTS:
            raise UnlockMusicRuntimeError("INTERNAL_ERROR", f"未知 event: {event_name}")
        with self._events_lock:
            self._events.append(
                EventEnvelope(
                    event_name,
                    task.task_id,
                    task.summary(),
                    module=MODULE,
                )
            )

    def close(self) -> None:
        self._bridge.close()
