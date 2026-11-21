from __future__ import annotations

import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from .access_control import AccessControlError, require_module_access
from .protocol import ApiError, EventEnvelope, RequestEnvelope, ResponseEnvelope, iso_now
from .transcode_rust_bridge import (
    TranscodeRustBridgeError,
    build_ffmpeg_plan,
    cleanup_transcode_task,
    poll_transcode_task,
    start_transcode_task,
    stop_transcode_task,
)

MODULE = "audio_transcode"
PANELS = {"transcode"}
TASK_TYPES = {"audio_transcode"}
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
    "start_audio_transcode_task",
    "fetch_transcode_result",
    "stop_task",
    "subscribe_task_events",
}
SUPPORTED_SUFFIXES = {
    ".mp3",
    ".wav",
    ".aiff",
    ".flac",
    ".m4a",
    ".ogg",
    ".aac",
    ".wma",
    ".dff",
}


class AudioTranscodeRuntimeError(Exception):
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
        self.resume_queue: list[str] = []
        self.last_output_dir: str | None = None


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
        self.current_file_path: str | None = None
        self.output_dir: str | None = None
        self.success_count = 0
        self.failed_count = 0
        self.results: list[dict[str, Any]] = []
        self.resume_remaining_paths: list[str] = []
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
            "error": self.error_message,
            "current_file_path": self.current_file_path,
            "output_dir": self.output_dir,
            "resume_remaining_count": len(self.resume_remaining_paths),
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }


class AudioTranscodeRuntime:
    def __init__(self) -> None:
        self._panels = {"transcode": PanelState("transcode")}
        self._tasks: dict[str, TaskState] = {}
        self._events: list[EventEnvelope] = []
        self._task_index = 0
        self._events_lock = threading.Lock()

    def handle_request(self, raw_request: dict[str, Any]) -> dict[str, Any]:
        request_id = raw_request.get("request_id")
        try:
            request = RequestEnvelope.from_dict(raw_request)
            if request.module != MODULE:
                raise AudioTranscodeRuntimeError("INVALID_MODULE", "module 必须是 audio_transcode。")
            if request.action not in ACTIONS:
                raise AudioTranscodeRuntimeError("INVALID_CONFIG", f"未知 action: {request.action}")
            require_module_access(MODULE, request.action)
            handler = getattr(self, f"_handle_{request.action}", None)
            if handler is None:
                raise AudioTranscodeRuntimeError("INVALID_CONFIG", f"action 未实现: {request.action}")
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
            return ResponseEnvelope(request_id, False, None, ApiError(exc.code, exc.message)).to_dict()
        except AudioTranscodeRuntimeError as exc:
            return ResponseEnvelope(request_id, False, None, ApiError(exc.code, exc.message)).to_dict()
        except Exception as exc:
            return ResponseEnvelope(
                request_id,
                False,
                None,
                ApiError("INTERNAL_ERROR", self._humanize_runtime_error(str(exc))),
            ).to_dict()

    def _handle_load_targets(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = self._require_panel(payload.get("panel"))
        file_paths = payload.get("file_paths")
        if not isinstance(file_paths, list) or not file_paths:
            raise AudioTranscodeRuntimeError("EMPTY_TARGETS", "file_paths 不能为空。")
        normalized = self._collect_targets(file_paths)
        if not normalized:
            raise AudioTranscodeRuntimeError("EMPTY_TARGETS", "未找到可处理的音频文件。")
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
            raise AudioTranscodeRuntimeError("INVALID_CONFIG", "config 必须是对象。")
        self._validate_config(config)
        state = self._panels[panel]
        state.config = dict(config)
        state.status = "config_locked"
        return {"panel": panel, "status": state.status, "config": dict(state.config)}

    def _handle_start_audio_transcode_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = payload.get("panel") or "transcode"
        if panel != "transcode":
            raise AudioTranscodeRuntimeError("INVALID_CONFIG", "转码任务只能用于 transcode 面板。")
        return self._start_task().summary()

    def _handle_fetch_transcode_result(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        if task.status == "running":
            raise AudioTranscodeRuntimeError("TASK_NOT_COMPLETED", "当前任务仍在运行中。")
        if task.status == "error" and not task.results:
            raise AudioTranscodeRuntimeError("INTERNAL_ERROR", task.error_message or task.progress_hint_text)
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
            task.progress_hint_text = "任务正在停止，已完成文件将保留，下次可继续转码。"
            task.updated_at = iso_now()
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
        state = self._panels["transcode"]
        if not state.file_paths:
            raise AudioTranscodeRuntimeError("EMPTY_TARGETS", "请先载入目标文件。")
        if self._has_active_task("transcode"):
            raise AudioTranscodeRuntimeError("TASK_ALREADY_RUNNING", "当前面板已有进行中的任务。")
        self._validate_config(state.config)
        file_paths = list(state.resume_queue or state.file_paths)
        task = TaskState(
            task_id=self._next_task_id(),
            panel="transcode",
            task_type="audio_transcode",
            status="running",
            file_paths=file_paths,
            config=dict(state.config),
        )
        task.progress = 0.01
        task.progress_hint_text = "正在准备转码任务..."
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
            output_mode = str(task.config.get("output_mode") or "custom")
            configured_output_dir = self._optional_string(task.config.get("output_dir"))
            output_format = str(task.config.get("output_format"))
            ffmpeg_path = self._optional_string(task.config.get("ffmpeg_path"))
            ffprobe_path = self._optional_string(task.config.get("ffprobe_path"))
            bitrate_kbps = self._optional_int(task.config.get("bitrate_kbps"))
            sample_rate_hz = self._optional_int(task.config.get("sample_rate_hz"))
            channels = self._optional_string(task.config.get("channels"))
            compression_level = self._optional_int(task.config.get("compression_level"))
            wav_codec = self._optional_string(task.config.get("wav_codec"))
            total = len(task.file_paths)
            task.resume_remaining_paths = list(task.file_paths)
            task_timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            task_output_dirs: dict[str, str] = {}

            for index, raw_path in enumerate(task.file_paths, start=1):
                input_path = Path(raw_path).resolve()
                if output_mode == "custom":
                    output_dir = self._resolve_output_dir(
                        raw_path=raw_path,
                        input_path=input_path,
                        output_mode=output_mode,
                        configured_output_dir=configured_output_dir,
                        output_format=output_format,
                        task_timestamp=task_timestamp,
                    )
                else:
                    source_parent = str(input_path.parent.resolve())
                    output_dir = task_output_dirs.get(source_parent)
                    if output_dir is None:
                        output_dir = self._resolve_output_dir(
                            raw_path=raw_path,
                            input_path=input_path,
                            output_mode=output_mode,
                            configured_output_dir=configured_output_dir,
                            output_format=output_format,
                            task_timestamp=task_timestamp,
                        )
                        task_output_dirs[source_parent] = output_dir
                task.current_file_path = raw_path
                task.output_dir = output_dir
                self._panels[task.panel].last_output_dir = output_dir
                if task.cancel_requested:
                    task.status = "cancelled"
                    task.progress_hint_text = "任务已由用户手动停止。"
                    task.updated_at = iso_now()
                    self._panels[task.panel].status = task.status
                    self._push_event("task_status_changed", task)
                    self._push_event("task_finished", task)
                    return

                started = start_transcode_task(
                    input_path=raw_path,
                    output_dir=output_dir,
                    output_format=output_format,
                    ffmpeg_path=ffmpeg_path,
                    ffprobe_path=ffprobe_path,
                    bitrate_kbps=bitrate_kbps,
                    sample_rate_hz=sample_rate_hz,
                    channels=channels,
                    compression_level=compression_level,
                    wav_codec=wav_codec,
                )
                rust_task_id = str(started["task_id"])

                try:
                    while True:
                        if task.cancel_requested:
                            stop_transcode_task(rust_task_id)
                        polled = poll_transcode_task(rust_task_id)
                        status = str(polled.get("status", "error"))
                        raw_progress = polled.get("progress")
                        file_progress = self._as_progress_fraction(raw_progress)
                        task.progress = (((index - 1) + file_progress) / total) * 100.0
                        task.progress_hint_text = self._build_progress_hint(
                            index=index,
                            total=total,
                            raw_path=raw_path,
                            file_progress=file_progress,
                            rust_hint=polled.get("progress_hint_text"),
                        )
                        task.updated_at = iso_now()
                        self._push_event("task_progress", task)

                        if status == "running":
                            time.sleep(0.05)
                            continue

                        if status == "success":
                            task.success_count += 1
                            task.results.append(
                                {
                                    "input_path": raw_path,
                                    "output_path": polled.get("output_path"),
                                    "success": True,
                                    "format": output_format,
                                    "error": None,
                                }
                            )
                            task.resume_remaining_paths = [
                                path for path in task.resume_remaining_paths if path != raw_path
                            ]
                        elif status == "cancelled":
                            task.status = "cancelled"
                            task.progress_hint_text = (
                                f"任务已停止，保留 {len(task.resume_remaining_paths)} 个待续转文件。"
                            )
                            task.updated_at = iso_now()
                            self._panels[task.panel].status = task.status
                            self._panels[task.panel].resume_queue = list(task.resume_remaining_paths)
                            self._push_event("task_status_changed", task)
                            self._push_event("task_finished", task)
                            return
                        else:
                            task.failed_count += 1
                            task.results.append(
                                {
                                    "input_path": raw_path,
                                    "output_path": polled.get("output_path"),
                                    "success": False,
                                    "format": output_format,
                                    "error": polled.get("error"),
                                }
                            )
                        break
                finally:
                    try:
                        cleanup_transcode_task(rust_task_id)
                    except TranscodeRustBridgeError:
                        pass

            task.status = "success" if task.failed_count == 0 else "error"
            task.progress = 100.0
            task.progress_hint_text = f"转码完成：成功 {task.success_count} 个，失败 {task.failed_count} 个。"
            if task.failed_count > 0 and task.success_count == 0:
                task.error_message = "本次转码全部失败，请检查源文件或转码格式设置。"
            elif task.failed_count > 0:
                task.error_message = f"本次转码部分失败，共失败 {task.failed_count} 个。"
            task.resume_remaining_paths = []
            task.updated_at = iso_now()
            self._panels[task.panel].status = task.status
            self._panels[task.panel].resume_queue = []
            self._push_event("task_finished", task)
        except TranscodeRustBridgeError as exc:
            task.status = "error"
            task.error_message = self._humanize_runtime_error(str(exc))
            task.progress_hint_text = task.error_message
            task.updated_at = iso_now()
            self._panels[task.panel].status = task.status
            self._push_event("task_status_changed", task)
            self._push_event("task_finished", task)
        except Exception as exc:
            task.status = "error"
            task.error_message = self._humanize_runtime_error(str(exc))
            task.progress_hint_text = task.error_message
            task.updated_at = iso_now()
            self._panels[task.panel].status = task.status
            self._push_event("task_status_changed", task)
            self._push_event("task_finished", task)

    def _collect_targets(self, paths: list[Any]) -> list[str]:
        targets: list[str] = []
        seen: set[str] = set()
        for item in paths:
            path = Path(self._require_path(item)).expanduser().resolve()
            if not path.exists():
                raise AudioTranscodeRuntimeError("TARGET_NOT_FOUND", f"路径不存在: {path}")
            if path.is_dir():
                for child in sorted(path.rglob("*")):
                    if child.is_file() and child.suffix.lower() in SUPPORTED_SUFFIXES:
                        child_value = str(child.resolve())
                        if child_value not in seen:
                            seen.add(child_value)
                            targets.append(child_value)
                continue
            if path.suffix.lower() not in SUPPORTED_SUFFIXES:
                continue
            value = str(path.resolve())
            if value not in seen:
                seen.add(value)
                targets.append(value)
        return targets

    def _validate_config(self, config: dict[str, Any]) -> None:
        output_mode = config.get("output_mode")
        if output_mode not in {"source_subdir", "custom", None}:
            raise AudioTranscodeRuntimeError("INVALID_CONFIG", "output_mode 不合法。")
        output_dir = config.get("output_dir")
        if output_mode == "custom" and (not isinstance(output_dir, str) or not output_dir.strip()):
            raise AudioTranscodeRuntimeError("INVALID_CONFIG", "output_dir 不能为空。")
        output_format = config.get("output_format")
        if output_format not in {"mp3", "wav", "aiff", "flac"}:
            raise AudioTranscodeRuntimeError("INVALID_CONFIG", "output_format 仅支持 mp3 / wav / aiff / flac。")
        channels = config.get("channels")
        if channels is not None and channels not in {"original", "mono", "stereo"}:
            raise AudioTranscodeRuntimeError("INVALID_CONFIG", "channels 不合法。")

    def _require_panel(self, panel: Any) -> str:
        if not isinstance(panel, str) or panel not in PANELS:
            raise AudioTranscodeRuntimeError("INVALID_CONFIG", "panel 不合法。")
        return panel

    def _require_path(self, path: Any) -> str:
        if not isinstance(path, str) or not path.strip():
            raise AudioTranscodeRuntimeError("TARGET_NOT_FOUND", "存在非法路径。")
        return path.strip()

    def _require_task(self, task_id: Any) -> TaskState:
        if not isinstance(task_id, str) or not task_id:
            raise AudioTranscodeRuntimeError("TASK_NOT_FOUND", "task_id 不存在。")
        task = self._tasks.get(task_id)
        if task is None:
            raise AudioTranscodeRuntimeError("TASK_NOT_FOUND", "未找到对应 task_id。")
        return task

    def _has_active_task(self, panel: str) -> bool:
        return any(task.panel == panel and task.status == "running" for task in self._tasks.values())

    def _next_task_id(self) -> str:
        self._task_index += 1
        return f"task_transcode_{self._task_index:03d}"

    def _push_event(self, event_name: str, task: TaskState) -> None:
        with self._events_lock:
            self._events.append(EventEnvelope(event_name, task.task_id, task.summary(), module=MODULE))

    def _optional_string(self, value: Any) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str):
            raise AudioTranscodeRuntimeError("INVALID_CONFIG", "字符串配置不合法。")
        return value.strip() or None

    def _optional_int(self, value: Any) -> int | None:
        if value is None:
            return None
        if isinstance(value, bool) or not isinstance(value, int):
            raise AudioTranscodeRuntimeError("INVALID_CONFIG", "整型配置不合法。")
        return value

    def _as_progress_fraction(self, value: Any) -> float:
        if isinstance(value, (int, float)):
            return max(0.0, min(float(value) / 100.0, 1.0))
        return 0.0

    def _build_progress_hint(
        self,
        *,
        index: int,
        total: int,
        raw_path: str,
        file_progress: float,
        rust_hint: Any,
    ) -> str:
        file_name = Path(raw_path).name
        percent = int(file_progress * 100)
        suffix = str(rust_hint).strip() if rust_hint is not None else ""
        if suffix:
            return f"正在转码 {index}/{total} · {file_name} · 当前文件 {percent}% · {suffix}"
        return f"正在转码 {index}/{total} · {file_name} · 当前文件 {percent}%"

    def _resolve_output_dir(
        self,
        *,
        raw_path: str,
        input_path: Path,
        output_mode: str,
        configured_output_dir: str | None,
        output_format: str,
        task_timestamp: str,
    ) -> str:
        if output_mode == "custom":
            return str(Path(configured_output_dir or input_path.parent).resolve())
        source_root_name = input_path.parent.name or input_path.parent.parent.name or "音频"
        folder_name = f"{source_root_name}_{output_format.upper()}_{task_timestamp}"
        return str((input_path.parent / folder_name).resolve())

    def _humanize_runtime_error(self, message: str) -> str:
        lower = message.lower()
        if "probe failed" in lower:
            if "no such file" in lower or "not found" in lower:
                return "文件读取失败，请确认源文件仍然存在。"
            if "invalid data" in lower or "moov atom not found" in lower:
                return "音频探测失败，文件格式异常或文件已损坏。"
            if "audio stream" in lower:
                return "当前文件无法识别，请检查源文件是否为有效音频。"
            return "音频探测失败，请检查源文件是否完整或格式是否异常。"
        if "spawn failed" in lower:
            return "转码器启动失败，请检查 ffmpeg 和 ffprobe 是否可用。"
        if "permission denied" in lower:
            return "文件写入失败，请检查输出目录权限。"
        if "no space left" in lower:
            return "转码失败，磁盘空间不足。"
        return message
