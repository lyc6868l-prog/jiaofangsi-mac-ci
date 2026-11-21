from __future__ import annotations

import json
import threading
import time
from pathlib import Path
from typing import Any

from platformdirs import user_data_dir

from .access_control import AccessControlError, require_module_access
from .protocol import ApiError, EventEnvelope, RequestEnvelope, ResponseEnvelope, iso_now
from .transcode_rust_bridge import (
    TranscodeRustBridgeError,
    poll_metadata_edit_task,
    scan_audio_targets,
    start_cover_injection_task,
    start_filename_injection_task,
    stop_metadata_edit_task,
)

MODULE = "metadata_edit"
PANELS = {"metadata_edit"}
TASK_TYPES = {"cover_injection", "filename_injection"}
STATUSES = {
    "idle",
    "target_ready",
    "config_locked",
    "running",
    "success",
    "cancelled",
    "error",
}
EVENTS = {"task_created", "task_progress", "task_status_changed", "task_finished"}
ACTIONS = {
    "load_targets",
    "lock_config",
    "start_cover_injection_task",
    "start_filename_injection_task",
    "fetch_metadata_edit_result",
    "stop_task",
    "subscribe_task_events",
    "load_templates",
    "save_template",
    "delete_template",
}
DEFAULT_TEMPLATES = ["remix版", "私改版"]
MAX_TEMPLATES = 9


class MetadataEditRuntimeError(Exception):
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
        self.progress_hint_text = "等待信息修改任务载入..."
        self.worker_started = False
        self.cancel_requested = False
        self.error_message: str | None = None
        self.success_count = 0
        self.skipped_count = 0
        self.need_count = 0
        self.failed_count = 0
        self.results: list[dict[str, Any]] = []
        self.log_lines: list[str] = []
        self.created_at = iso_now()
        self.updated_at = self.created_at
        self.rust_task_id: str | None = None

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
            "skipped_count": self.skipped_count,
            "need_count": self.need_count,
            "failed_count": self.failed_count,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "log_lines": list(self.log_lines[-40:]),
        }


class MetadataTemplateStore:
    def __init__(self) -> None:
        data_root = Path(user_data_dir("dj_runtime_py", "dj")) / "metadata_edit"
        data_root.mkdir(parents=True, exist_ok=True)
        self._path = data_root / "templates.json"
        self._lock = threading.Lock()

    @property
    def path(self) -> Path:
        return self._path

    def load(self) -> list[str]:
        with self._lock:
            return self._load_unlocked()

    def save(self, template: str) -> list[str]:
        text = template.strip()
        if not text:
            raise MetadataEditRuntimeError("INVALID_CONFIG", "template 不能为空。")
        with self._lock:
            templates = self._load_unlocked()
            if text in templates:
                return templates
            if len(templates) >= MAX_TEMPLATES:
                raise MetadataEditRuntimeError("INVALID_CONFIG", f"模板最多保存 {MAX_TEMPLATES} 个。")
            custom = [item for item in templates if item not in DEFAULT_TEMPLATES]
            custom.append(text)
            self._write_unlocked(custom)
            return self._load_unlocked()

    def delete(self, template: str) -> list[str]:
        text = template.strip()
        if not text:
            raise MetadataEditRuntimeError("INVALID_CONFIG", "template 不能为空。")
        with self._lock:
            custom = [
                item for item in self._load_unlocked() if item not in DEFAULT_TEMPLATES and item != text
            ]
            self._write_unlocked(custom)
            return self._load_unlocked()

    def _load_unlocked(self) -> list[str]:
        templates = list(DEFAULT_TEMPLATES)
        if self._path.exists():
            try:
                data = json.loads(self._path.read_text(encoding="utf-8"))
            except Exception:
                data = []
            if isinstance(data, list):
                for item in data:
                    if isinstance(item, str):
                        text = item.strip()
                        if text and text not in templates:
                            templates.append(text)
        return templates[:MAX_TEMPLATES]

    def _write_unlocked(self, custom_templates: list[str]) -> None:
        self._path.write_text(
            json.dumps(custom_templates, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )


def _humanize_metadata_edit_error(exc: Exception) -> str:
    message = str(exc).strip()
    lowered = message.lower()
    if "permission denied" in lowered:
        return "写入文件失败，请检查文件权限后重试。"
    if "not found" in lowered or "does not exist" in lowered:
        return "目标文件不存在，请重新载入后重试。"
    if "timeout" in lowered or "timed out" in lowered:
        return "信息修改任务超时，请稍后重试。"
    if "poisoned" in lowered:
        return "信息修改任务状态异常，请重新操作。"
    return "信息修改失败，请稍后重试。"


class MetadataEditRuntime:
    def __init__(self) -> None:
        self._panels = {"metadata_edit": PanelState("metadata_edit")}
        self._tasks: dict[str, TaskState] = {}
        self._events: list[EventEnvelope] = []
        self._task_index = 0
        self._events_lock = threading.Lock()
        self._template_store = MetadataTemplateStore()

    def handle_request(self, raw_request: dict[str, Any]) -> dict[str, Any]:
        request_id = raw_request.get("request_id")
        try:
            request = RequestEnvelope.from_dict(raw_request)
            if request.module != MODULE:
                raise MetadataEditRuntimeError("INVALID_MODULE", "module 必须是 metadata_edit。")
            if request.action not in ACTIONS:
                raise MetadataEditRuntimeError("INVALID_CONFIG", f"未知 action: {request.action}")
            require_module_access(MODULE, request.action)
            handler = getattr(self, f"_handle_{request.action}", None)
            if handler is None:
                raise MetadataEditRuntimeError("INVALID_CONFIG", f"action 未实现: {request.action}")
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
        except MetadataEditRuntimeError as exc:
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
                ApiError("INTERNAL_ERROR", _humanize_metadata_edit_error(exc)),
            ).to_dict()

    def _handle_load_targets(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = self._require_panel(payload.get("panel"))
        file_paths = payload.get("file_paths")
        if not isinstance(file_paths, list) or not file_paths:
            raise MetadataEditRuntimeError("EMPTY_TARGETS", "file_paths 不能为空。")
        normalized_paths = [self._require_path(item) for item in file_paths]
        try:
            result = scan_audio_targets(normalized_paths)
        except TranscodeRustBridgeError as exc:
            raise MetadataEditRuntimeError(
                "INTERNAL_ERROR",
                _humanize_metadata_edit_error(exc),
            ) from exc
        normalized = [str(Path(item).resolve()) for item in result.get("files", []) if isinstance(item, str)]
        if not normalized:
            raise MetadataEditRuntimeError("EMPTY_TARGETS", "未找到可处理的音频文件。")
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
            raise MetadataEditRuntimeError("INVALID_CONFIG", "config 必须是对象。")
        self._validate_config(config)
        state = self._panels[panel]
        state.config = dict(config)
        state.status = "config_locked"
        return {"panel": panel, "status": state.status, "config": dict(state.config)}

    def _handle_start_cover_injection_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = payload.get("panel") or "metadata_edit"
        if panel != "metadata_edit":
            raise MetadataEditRuntimeError("INVALID_CONFIG", "封面注入任务只能用于 metadata_edit 面板。")
        return self._start_task("cover_injection").summary()

    def _handle_start_filename_injection_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = payload.get("panel") or "metadata_edit"
        if panel != "metadata_edit":
            raise MetadataEditRuntimeError("INVALID_CONFIG", "文件名注入任务只能用于 metadata_edit 面板。")
        return self._start_task("filename_injection").summary()

    def _handle_fetch_metadata_edit_result(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        if task.status == "running":
            raise MetadataEditRuntimeError("TASK_NOT_COMPLETED", "当前任务仍在运行中。")
        if task.status == "error":
            raise MetadataEditRuntimeError("INTERNAL_ERROR", task.error_message or task.progress_hint_text)
        return {
            "task_id": task.task_id,
            "status": task.status,
            "results": list(task.results),
            "success_count": task.success_count,
            "skipped_count": task.skipped_count,
            "need_count": task.need_count,
            "failed_count": task.failed_count,
            "log_lines": list(task.log_lines),
        }

    def _handle_stop_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        task.cancel_requested = True
        if task.rust_task_id:
            try:
                stop_metadata_edit_task(task.rust_task_id)
            except TranscodeRustBridgeError:
                pass
        if task.status == "running":
            task.progress_hint_text = "任务正在停止..."
            task.updated_at = iso_now()
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

    def _handle_load_templates(self, payload: dict[str, Any]) -> dict[str, Any]:
        return {
            "templates": self._template_store.load(),
            "max_templates": MAX_TEMPLATES,
            "template_file_path": str(self._template_store.path),
        }

    def _handle_save_template(self, payload: dict[str, Any]) -> dict[str, Any]:
        template = payload.get("template")
        if not isinstance(template, str):
            raise MetadataEditRuntimeError("INVALID_CONFIG", "template 必须是字符串。")
        return {
            "templates": self._template_store.save(template),
            "max_templates": MAX_TEMPLATES,
            "template_file_path": str(self._template_store.path),
        }

    def _handle_delete_template(self, payload: dict[str, Any]) -> dict[str, Any]:
        template = payload.get("template")
        if not isinstance(template, str):
            raise MetadataEditRuntimeError("INVALID_CONFIG", "template 必须是字符串。")
        return {
            "templates": self._template_store.delete(template),
            "max_templates": MAX_TEMPLATES,
            "template_file_path": str(self._template_store.path),
        }

    def _start_task(self, task_type: str) -> TaskState:
        state = self._panels["metadata_edit"]
        if not state.file_paths:
            raise MetadataEditRuntimeError("EMPTY_TARGETS", "请先载入目标文件。")
        if self._has_active_task("metadata_edit"):
            raise MetadataEditRuntimeError("TASK_ALREADY_RUNNING", "当前面板已有进行中的任务。")
        self._validate_config(state.config)
        resumable = self._find_resumable_task(task_type, state.config, state.file_paths)
        task = TaskState(
            task_id=self._next_task_id(),
            panel="metadata_edit",
            task_type=task_type,
            status="running",
            file_paths=list(state.file_paths),
            config=dict(state.config),
        )
        if resumable is not None:
            task.results = list(resumable.results)
            task.success_count = resumable.success_count
            task.skipped_count = resumable.skipped_count
            task.need_count = resumable.need_count
            task.failed_count = resumable.failed_count
            task.log_lines = list(resumable.log_lines)
            task.progress = len(task.results) / len(task.file_paths) * 100 if task.file_paths else 0.0
            task.progress_hint_text = f"检测到中断任务，继续执行剩余 {len(task.file_paths) - len(task.results)} 项..."
        else:
            task.progress = 0.01
            task.progress_hint_text = "正在准备信息修改任务..."
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
            total = len(task.file_paths)
            completed_count = len(task.results)
            ffmpeg_path = self._optional_string(task.config.get("ffmpeg_path"))
            ffprobe_path = self._optional_string(task.config.get("ffprobe_path"))
            cover_image_path = self._optional_string(task.config.get("cover_image_path"))
            append_text = self._optional_string(task.config.get("append_text"))

            for index, raw_path in enumerate(task.file_paths[completed_count:], start=completed_count + 1):
                if task.cancel_requested:
                    self._finish_cancelled_task(task)
                    return
                task.progress = ((index - 1) / total) * 100.0 if total else 0.0
                task.progress_hint_text = f"正在处理 {index}/{total}: {Path(raw_path).name}"
                task.updated_at = iso_now()
                self._append_log(task, task.progress_hint_text)
                self._push_event("task_progress", task)

                if task.task_type == "cover_injection":
                    if not cover_image_path:
                        raise MetadataEditRuntimeError("INVALID_CONFIG", "cover_image_path 不能为空。")
                    started = start_cover_injection_task(
                        input_path=raw_path,
                        cover_image_path=cover_image_path,
                        ffmpeg_path=ffmpeg_path,
                        ffprobe_path=ffprobe_path,
                    )
                else:
                    if not append_text:
                        raise MetadataEditRuntimeError("INVALID_CONFIG", "append_text 不能为空。")
                    started = start_filename_injection_task(
                        input_path=raw_path,
                        append_text=append_text,
                        ffmpeg_path=ffmpeg_path,
                        ffprobe_path=ffprobe_path,
                    )
                task.rust_task_id = str(started.get("task_id") or "")
                if not task.rust_task_id:
                    raise MetadataEditRuntimeError("INTERNAL_ERROR", "Rust 任务启动失败。")

                while True:
                    if task.cancel_requested:
                        try:
                            stop_metadata_edit_task(task.rust_task_id)
                        except TranscodeRustBridgeError:
                            pass
                    polled = poll_metadata_edit_task(task.rust_task_id)
                    status = str(polled.get("status") or "error")
                    raw_progress = polled.get("progress")
                    task.progress = (((index - 1) + self._as_progress_fraction(raw_progress)) / total) * 100.0
                    task.progress_hint_text = str(
                        polled.get("progress_hint_text") or f"正在处理 {index}/{total}: {Path(raw_path).name}"
                    )
                    task.updated_at = iso_now()
                    self._push_event("task_progress", task)

                    if status == "running":
                        time.sleep(0.05)
                        continue
                    if status == "cancelled":
                        self._finish_cancelled_task(task)
                        return
                    if status == "error":
                        message = str(polled.get("error") or polled.get("progress_hint_text") or "处理失败")
                        self._append_result(
                            task,
                            result={
                                "status": "fail",
                                "input_path": raw_path,
                                "output_path": raw_path,
                                "changed": False,
                                "backup_path": None,
                                "message": message,
                            },
                        )
                        task.failed_count += 1
                        task.rust_task_id = None
                        self._append_log(task, f"FAIL {Path(raw_path).name}: {message}")
                        break

                    result = polled.get("result")
                    if not isinstance(result, dict):
                        raise MetadataEditRuntimeError("INTERNAL_ERROR", "缺少 Rust 结果数据。")
                    self._append_result(task, result=result)
                    task.rust_task_id = None
                    status_value = str(result.get("status") or "fail")
                    message = str(result.get("message") or "")
                    if status_value == "ok":
                        task.success_count += 1
                        self._append_log(task, f"OK {Path(raw_path).name}: {message}")
                    elif status_value == "skip":
                        task.skipped_count += 1
                        self._append_log(task, f"SKIP {Path(raw_path).name}: {message}")
                    elif status_value == "need":
                        task.need_count += 1
                        self._append_log(task, f"NEED {Path(raw_path).name}: {message}")
                    else:
                        task.failed_count += 1
                        self._append_log(task, f"FAIL {Path(raw_path).name}: {message}")
                    break

            task.status = "success"
            task.progress = 100.0
            task.progress_hint_text = "信息修改任务执行完毕。"
            task.updated_at = iso_now()
            task.rust_task_id = None
            self._panels[task.panel].status = task.status
            self._push_event("task_finished", task)
        except MetadataEditRuntimeError as exc:
            self._finish_error_task(task, exc.message)
        except TranscodeRustBridgeError as exc:
            self._finish_error_task(task, _humanize_metadata_edit_error(exc))
        except Exception as exc:
            self._finish_error_task(task, _humanize_metadata_edit_error(exc))

    def _finish_cancelled_task(self, task: TaskState) -> None:
        task.status = "cancelled"
        task.progress_hint_text = "任务已由用户手动停止。"
        task.updated_at = iso_now()
        task.rust_task_id = None
        self._panels[task.panel].status = task.status
        self._push_event("task_status_changed", task)
        self._push_event("task_finished", task)

    def _finish_error_task(self, task: TaskState, message: str) -> None:
        task.status = "error"
        task.error_message = message
        task.progress_hint_text = message
        task.updated_at = iso_now()
        task.rust_task_id = None
        self._panels[task.panel].status = task.status
        self._append_log(task, f"FAIL 任务异常: {message}")
        self._push_event("task_status_changed", task)
        self._push_event("task_finished", task)

    def _validate_config(self, config: dict[str, Any]) -> None:
        operation = config.get("operation")
        if operation not in {"cover_injection", "filename_injection"}:
            raise MetadataEditRuntimeError("INVALID_CONFIG", "operation 不合法。")
        ffmpeg_path = config.get("ffmpeg_path")
        if ffmpeg_path is not None and not isinstance(ffmpeg_path, str):
            raise MetadataEditRuntimeError("INVALID_CONFIG", "ffmpeg_path 必须是字符串。")
        ffprobe_path = config.get("ffprobe_path")
        if ffprobe_path is not None and not isinstance(ffprobe_path, str):
            raise MetadataEditRuntimeError("INVALID_CONFIG", "ffprobe_path 必须是字符串。")
        if operation == "cover_injection":
            cover_image_path = config.get("cover_image_path")
            if not isinstance(cover_image_path, str) or not cover_image_path.strip():
                raise MetadataEditRuntimeError("INVALID_CONFIG", "cover_image_path 不能为空。")
        if operation == "filename_injection":
            append_text = config.get("append_text")
            if not isinstance(append_text, str) or not append_text.strip():
                raise MetadataEditRuntimeError("INVALID_CONFIG", "append_text 不能为空。")

    def _require_panel(self, panel: Any) -> str:
        if not isinstance(panel, str) or panel not in PANELS:
            raise MetadataEditRuntimeError("INVALID_CONFIG", "panel 不合法。")
        return panel

    def _require_path(self, path: Any) -> str:
        if not isinstance(path, str) or not path.strip():
            raise MetadataEditRuntimeError("TARGET_NOT_FOUND", "存在非法路径。")
        return path.strip()

    def _require_task(self, task_id: Any) -> TaskState:
        if not isinstance(task_id, str) or not task_id:
            raise MetadataEditRuntimeError("TASK_NOT_FOUND", "task_id 不存在。")
        task = self._tasks.get(task_id)
        if task is None:
            raise MetadataEditRuntimeError("TASK_NOT_FOUND", "未找到对应 task_id。")
        return task

    def _has_active_task(self, panel: str) -> bool:
        return any(task.panel == panel and task.status == "running" for task in self._tasks.values())

    def _find_resumable_task(
        self,
        task_type: str,
        config: dict[str, Any],
        file_paths: list[str],
    ) -> TaskState | None:
        for task in reversed(list(self._tasks.values())):
            if task.panel != "metadata_edit":
                continue
            if task.task_type != task_type:
                continue
            if task.status != "cancelled":
                continue
            if task.config != config:
                continue
            if task.file_paths != file_paths:
                continue
            if len(task.results) >= len(task.file_paths):
                continue
            return task
        return None

    def _next_task_id(self) -> str:
        self._task_index += 1
        return f"task_metadata_edit_{self._task_index:03d}"

    def _push_event(self, event_name: str, task: TaskState) -> None:
        with self._events_lock:
            self._events.append(EventEnvelope(event_name, task.task_id, task.summary(), module=MODULE))

    def _append_result(self, task: TaskState, result: dict[str, Any]) -> None:
        task.results.append(
            {
                "status": str(result.get("status") or "fail"),
                "input_path": str(result.get("input_path") or ""),
                "output_path": str(result.get("output_path") or result.get("input_path") or ""),
                "changed": bool(result.get("changed")),
                "backup_path": result.get("backup_path"),
                "message": str(result.get("message") or ""),
            }
        )

    def _append_log(self, task: TaskState, message: str) -> None:
        timestamp = iso_now()
        task.log_lines.append(f"[{timestamp}] {message}")

    def _optional_string(self, value: Any) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str):
            raise MetadataEditRuntimeError("INVALID_CONFIG", "字符串配置不合法。")
        return value.strip() or None

    def _as_progress_fraction(self, value: Any) -> float:
        if isinstance(value, (int, float)):
            return max(0.0, min(float(value) / 100.0, 1.0))
        return 0.0
