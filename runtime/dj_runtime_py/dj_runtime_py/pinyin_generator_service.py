from __future__ import annotations

import re
import threading
import time
import unicodedata
from pathlib import Path
from typing import Any

import mutagen
from mutagen import File as mutagen_file
from mutagen.id3 import ID3, ID3NoHeaderError, TALB

from .access_control import AccessControlError, require_module_access
from .protocol import ApiError, EventEnvelope, RequestEnvelope, ResponseEnvelope, iso_now

MODULE = "pinyin_generator"
PANELS = {"generator"}
TASK_TYPES = {"pinyin_generator"}
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
    "start_pinyin_generator_task",
    "fetch_pinyin_generator_result",
    "stop_task",
    "subscribe_task_events",
}
SUPPORTED_SUFFIXES = {".mp3", ".flac", ".m4a", ".ogg", ".wma", ".aiff", ".aac"}
UNSUPPORTED_SUFFIXES = {".wav"}
CHINESE_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")
MULTI_SPACE = re.compile(r"\s+")


class PinyinGeneratorRuntimeError(Exception):
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
        self.warning_message: str | None = None
        self.last_task_id: str | None = None


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
        self.progress_hint_text = "等待首拼任务载入..."
        self.worker_started = False
        self.cancel_requested = False
        self.error_message: str | None = None
        self.success_count = 0
        self.skipped_count = 0
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
            "skipped_count": self.skipped_count,
            "failed_count": self.failed_count,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
        }


class PinyinGeneratorRuntime:
    def __init__(self) -> None:
        self._panels = {"generator": PanelState("generator")}
        self._tasks: dict[str, TaskState] = {}
        self._events: list[EventEnvelope] = []
        self._task_index = 0
        self._events_lock = threading.Lock()

    def handle_request(self, raw_request: dict[str, Any]) -> dict[str, Any]:
        request_id = raw_request.get("request_id")
        try:
            request = RequestEnvelope.from_dict(raw_request)
            if request.module != MODULE:
                raise PinyinGeneratorRuntimeError(
                    "INVALID_MODULE", "module 必须是 pinyin_generator。"
                )
            if request.action not in ACTIONS:
                raise PinyinGeneratorRuntimeError(
                    "INVALID_CONFIG", f"未知 action: {request.action}"
                )
            require_module_access(MODULE, request.action)
            handler = getattr(self, f"_handle_{request.action}", None)
            if handler is None:
                raise PinyinGeneratorRuntimeError(
                    "INVALID_CONFIG", f"action 未实现: {request.action}"
                )
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
        except PinyinGeneratorRuntimeError as exc:
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
                ApiError("INTERNAL_ERROR", "首拼任务初始化失败，请稍后重试。"),
            ).to_dict()

    def _handle_load_targets(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = self._require_panel(payload.get("panel"))
        file_paths = payload.get("file_paths")
        if not isinstance(file_paths, list) or not file_paths:
            raise PinyinGeneratorRuntimeError("EMPTY_TARGETS", "file_paths 不能为空。")
        normalized, skipped_wav_count, ignored_non_audio_count = self._collect_targets(file_paths)
        if not normalized:
            if skipped_wav_count > 0:
                raise PinyinGeneratorRuntimeError(
                    "EMPTY_TARGETS",
                    "不支持 WAV 文件，请先转码后再使用首拼生成功能。",
                )
            if ignored_non_audio_count > 0:
                raise PinyinGeneratorRuntimeError(
                    "EMPTY_TARGETS", "该文件不是支持的音频格式，无法加入处理列表。"
                )
            raise PinyinGeneratorRuntimeError("EMPTY_TARGETS", "未找到可处理的音频文件。")
        warning_parts: list[str] = []
        if skipped_wav_count > 0:
            warning_parts.append("不支持 WAV 文件，请先转码后再使用首拼生成功能。")
        if ignored_non_audio_count > 0:
            warning_parts.append("检测到非音频文件，已自动忽略。")
        warning_message = "\n".join(warning_parts) if warning_parts else None
        state = self._panels[panel]
        state.file_paths = normalized
        state.status = "target_ready"
        state.warning_message = warning_message
        return {
            "panel": panel,
            "status": state.status,
            "file_count": len(normalized),
            "file_paths": list(normalized),
            "warning_message": warning_message,
            "skipped_wav_count": skipped_wav_count,
        }

    def _handle_lock_config(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = self._require_panel(payload.get("panel"))
        config = payload.get("config") or {}
        if not isinstance(config, dict):
            raise PinyinGeneratorRuntimeError("INVALID_CONFIG", "config 必须是对象。")
        self._validate_config(config)
        state = self._panels[panel]
        state.config = dict(config)
        state.status = "config_locked"
        return {"panel": panel, "status": state.status, "config": dict(state.config)}

    def _handle_start_pinyin_generator_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = payload.get("panel") or "generator"
        if panel != "generator":
            raise PinyinGeneratorRuntimeError(
                "INVALID_CONFIG", "首拼任务只能用于 generator 面板。"
            )
        return self._start_task().summary()

    def _handle_fetch_pinyin_generator_result(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        if task.status == "running":
            raise PinyinGeneratorRuntimeError("TASK_NOT_COMPLETED", "当前任务仍在运行中。")
        if task.status == "error":
            raise PinyinGeneratorRuntimeError(
                "INTERNAL_ERROR", task.error_message or task.progress_hint_text
            )
        return {
            "task_id": task.task_id,
            "status": task.status,
            "results": list(task.results),
            "success_count": task.success_count,
            "skipped_count": task.skipped_count,
            "failed_count": task.failed_count,
        }

    def _handle_stop_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        task.cancel_requested = True
        if task.status == "running":
            task.progress_hint_text = "任务正在停止..."
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
        state = self._panels["generator"]
        if not state.file_paths:
            raise PinyinGeneratorRuntimeError("EMPTY_TARGETS", "请先载入目标文件。")
        if self._has_active_task("generator"):
            raise PinyinGeneratorRuntimeError(
                "TASK_ALREADY_RUNNING", "当前面板已有进行中的任务。"
            )
        self._validate_config(state.config)
        resumable_task = self._find_resumable_task(state)
        if resumable_task is not None:
            processed_count = self._processed_count(resumable_task)
            resumable_task.cancel_requested = False
            resumable_task.status = "running"
            resumable_task.progress = (
                processed_count / resumable_task.file_count
                if resumable_task.file_count
                else 0.0
            )
            resumable_task.progress_hint_text = (
                f"正在继续首拼写入任务... {processed_count}/{resumable_task.file_count}"
            )
            resumable_task.updated_at = iso_now()
            state.status = resumable_task.status
            self._push_event("task_status_changed", resumable_task)
            self._start_worker(resumable_task)
            return resumable_task
        task = TaskState(
            task_id=self._next_task_id(),
            panel="generator",
            task_type="pinyin_generator",
            status="running",
            file_paths=list(state.file_paths),
            config=dict(state.config),
        )
        task.progress = 0.0
        task.progress_hint_text = "正在准备首拼写入任务..."
        self._tasks[task.task_id] = task
        state.status = task.status
        state.last_task_id = task.task_id
        self._push_event("task_created", task)
        self._start_worker(task)
        return task

    def _start_worker(self, task: TaskState) -> None:
        task.worker_started = True
        thread = threading.Thread(
            target=self._run_task_worker,
            args=(task.task_id,),
            daemon=True,
        )
        thread.start()

    def _run_task_worker(self, task_id: str) -> None:
        task = self._require_task(task_id)
        try:
            from pypinyin import Style, lazy_pinyin
        except ImportError as exc:
            task.status = "error"
            task.error_message = "缺少 pypinyin 依赖。"
            task.progress_hint_text = task.error_message
            task.updated_at = iso_now()
            self._panels[task.panel].status = task.status
            self._push_event("task_status_changed", task)
            self._push_event("task_finished", task)
            return

        write_mode = str(task.config.get("write_mode") or "overwrite")
        max_initials_length = int(task.config.get("max_initials_length") or 12)
        stopwords = self._normalize_stopwords(task.config.get("stopwords") or [])
        total = len(task.file_paths)
        processed_count = self._processed_count(task)

        for index, raw_path in enumerate(task.file_paths[processed_count:], start=processed_count + 1):
            if task.cancel_requested:
                task.status = "cancelled"
                task.progress_hint_text = "任务已由用户手动停止。"
                task.progress = self._processed_count(task) / total if total else 1.0
                task.updated_at = iso_now()
                self._panels[task.panel].status = task.status
                self._push_event("task_status_changed", task)
                self._push_event("task_finished", task)
                return

            path = Path(raw_path).resolve()
            if not path.exists():
                self._append_result(
                    task,
                    input_path=str(path),
                    input_name=path.name,
                    title_source="filename",
                    source_title=path.stem,
                    contains_chinese=False,
                    generated_initials=None,
                    album_before=None,
                    album_after=None,
                    status="failed",
                    message=f"文件不存在: {path}",
                )
                task.failed_count += 1
                self._update_progress(task, index, total, f"文件不存在，已跳过 {index}/{total}")
                continue

            try:
                _, album_before = self._read_metadata(path)
                title_source = "filename"
                source_title = self._clean_title_text(path.stem)
                if not source_title:
                    self._append_result(
                        task,
                        input_path=str(path),
                        input_name=path.name,
                        title_source=title_source,
                        source_title=path.stem,
                        contains_chinese=False,
                        generated_initials=None,
                        album_before=album_before,
                        album_after=album_before,
                        status="skipped",
                        message="未读取到可用标题。",
                    )
                    task.skipped_count += 1
                    self._update_progress(task, index, total, f"未读取到标题，已跳过 {index}/{total}")
                    continue

                cleaned_title = self._apply_stopwords(source_title, stopwords)
                contains_chinese = bool(CHINESE_RE.search(cleaned_title))
                if not contains_chinese:
                    self._append_result(
                        task,
                        input_path=str(path),
                        input_name=path.name,
                        title_source=title_source,
                        source_title=source_title,
                        contains_chinese=False,
                        generated_initials=None,
                        album_before=album_before,
                        album_after=album_before,
                        status="skipped",
                        message="标题不含中文，已跳过。",
                    )
                    task.skipped_count += 1
                    self._update_progress(task, index, total, f"标题不含中文，已跳过 {index}/{total}")
                    continue

                generated_initials = self._generate_initials(
                    cleaned_title,
                    max_initials_length,
                    lazy_pinyin,
                    Style,
                )
                if not generated_initials:
                    self._append_result(
                        task,
                        input_path=str(path),
                        input_name=path.name,
                        title_source=title_source,
                        source_title=source_title,
                        contains_chinese=True,
                        generated_initials=None,
                        album_before=album_before,
                        album_after=album_before,
                        status="skipped",
                        message="未生成有效首拼，已跳过。",
                    )
                    task.skipped_count += 1
                    self._update_progress(task, index, total, f"未生成有效首拼，已跳过 {index}/{total}")
                    continue

                album_after = self._compose_album(album_before, generated_initials, write_mode)
                self._write_album(path, album_after)
                _, verified_album = self._read_metadata(path)
                if (verified_album or "") != album_after:
                    raise PinyinGeneratorRuntimeError(
                        "INTERNAL_ERROR", f"写入回读校验失败: {path.name}"
                    )

                self._append_result(
                    task,
                    input_path=str(path),
                    input_name=path.name,
                    title_source=title_source,
                    source_title=source_title,
                    contains_chinese=True,
                    generated_initials=generated_initials,
                    album_before=album_before,
                    album_after=album_after,
                    status="success",
                    message="写入成功。",
                )
                task.success_count += 1
                self._update_progress(task, index, total, f"正在写入专辑字段... {index}/{total}")
            except PinyinGeneratorRuntimeError as exc:
                self._append_result(
                    task,
                    input_path=str(path),
                    input_name=path.name,
                    title_source="filename",
                    source_title=path.stem,
                    contains_chinese=bool(CHINESE_RE.search(path.stem)),
                    generated_initials=None,
                    album_before=None,
                    album_after=None,
                    status="failed",
                    message=exc.message,
                )
                task.failed_count += 1
                self._update_progress(task, index, total, f"写入失败，继续处理 {index}/{total}")
            except Exception as exc:
                self._append_result(
                    task,
                    input_path=str(path),
                    input_name=path.name,
                    title_source="filename",
                    source_title=path.stem,
                    contains_chinese=bool(CHINESE_RE.search(path.stem)),
                    generated_initials=None,
                    album_before=None,
                    album_after=None,
                    status="failed",
                    message="写入失败，请检查文件权限或标签格式。",
                )
                task.failed_count += 1
                self._update_progress(task, index, total, f"写入失败，继续处理 {index}/{total}")
            time.sleep(0.01)

        completed_count = self._processed_count(task)
        task.status = "success" if completed_count >= total else "cancelled"
        task.progress = completed_count / total if total else 1.0
        task.progress_hint_text = (
            "任务已由用户手动停止。"
            if task.status == "cancelled"
            else "首拼写入任务执行完毕。"
        )
        task.updated_at = iso_now()
        self._panels[task.panel].status = task.status
        if task.status == "cancelled":
            self._push_event("task_status_changed", task)
        self._push_event("task_finished", task)

    def _collect_targets(self, paths: list[Any]) -> tuple[list[str], int, int]:
        targets: list[str] = []
        seen: set[str] = set()
        skipped_wav_count = 0
        ignored_non_audio_count = 0
        for item in paths:
            path = Path(self._require_path(item)).expanduser().resolve()
            if not path.exists():
                raise PinyinGeneratorRuntimeError("TARGET_NOT_FOUND", f"路径不存在: {path}")
            if path.is_dir():
                for child in sorted(path.rglob("*")):
                    if not child.is_file():
                        continue
                    suffix = child.suffix.lower()
                    if suffix in UNSUPPORTED_SUFFIXES:
                        skipped_wav_count += 1
                        continue
                    if suffix not in SUPPORTED_SUFFIXES:
                        ignored_non_audio_count += 1
                        continue
                    child_value = str(child.resolve())
                    if child_value not in seen:
                        seen.add(child_value)
                        targets.append(child_value)
                continue
            suffix = path.suffix.lower()
            if suffix in UNSUPPORTED_SUFFIXES:
                skipped_wav_count += 1
                continue
            if suffix not in SUPPORTED_SUFFIXES:
                ignored_non_audio_count += 1
                continue
            path_value = str(path.resolve())
            if path_value not in seen:
                seen.add(path_value)
                targets.append(path_value)
        return targets, skipped_wav_count, ignored_non_audio_count

    def _validate_config(self, config: dict[str, Any]) -> None:
        write_mode = config.get("write_mode")
        if write_mode not in {"overwrite", "append"}:
            raise PinyinGeneratorRuntimeError("INVALID_CONFIG", "write_mode 不合法。")
        max_initials_length = config.get("max_initials_length")
        if isinstance(max_initials_length, bool) or not isinstance(max_initials_length, int):
            raise PinyinGeneratorRuntimeError(
                "INVALID_CONFIG", "max_initials_length 必须是整数。"
            )
        if max_initials_length <= 0 or max_initials_length > 32:
            raise PinyinGeneratorRuntimeError(
                "INVALID_CONFIG", "max_initials_length 必须在 1 到 32 之间。"
            )
        stopwords = config.get("stopwords")
        if not isinstance(stopwords, list):
            raise PinyinGeneratorRuntimeError("INVALID_CONFIG", "stopwords 必须是数组。")
        for stopword in stopwords:
            if not isinstance(stopword, str):
                raise PinyinGeneratorRuntimeError(
                    "INVALID_CONFIG", "stopwords 项必须是字符串。"
                )

    def _require_panel(self, panel: Any) -> str:
        if not isinstance(panel, str) or panel not in PANELS:
            raise PinyinGeneratorRuntimeError("INVALID_CONFIG", "panel 不合法。")
        return panel

    def _require_path(self, path: Any) -> str:
        if not isinstance(path, str) or not path.strip():
            raise PinyinGeneratorRuntimeError("TARGET_NOT_FOUND", "存在非法路径。")
        return path.strip()

    def _require_task(self, task_id: Any) -> TaskState:
        if not isinstance(task_id, str) or not task_id:
            raise PinyinGeneratorRuntimeError("TASK_NOT_FOUND", "task_id 不存在。")
        task = self._tasks.get(task_id)
        if task is None:
            raise PinyinGeneratorRuntimeError("TASK_NOT_FOUND", "未找到对应 task_id。")
        return task

    def _has_active_task(self, panel: str) -> bool:
        return any(task.panel == panel and task.status == "running" for task in self._tasks.values())

    def _find_resumable_task(self, state: PanelState) -> TaskState | None:
        task_id = state.last_task_id
        if task_id is None:
            return None
        task = self._tasks.get(task_id)
        if task is None or task.status != "cancelled":
            return None
        if task.file_paths != state.file_paths or task.config != state.config:
            return None
        if self._processed_count(task) >= task.file_count:
            return None
        return task

    def _processed_count(self, task: TaskState) -> int:
        return len(task.results)

    def _next_task_id(self) -> str:
        self._task_index += 1
        return f"task_pinyin_{self._task_index:03d}"

    def _push_event(self, event_name: str, task: TaskState) -> None:
        with self._events_lock:
            self._events.append(
                EventEnvelope(event_name, task.task_id, task.summary(), module=MODULE)
            )

    def _update_progress(
        self,
        task: TaskState,
        index: int,
        total: int,
        hint_text: str,
    ) -> None:
        task.progress = index / total if total else 1.0
        task.progress_hint_text = hint_text
        task.updated_at = iso_now()
        self._push_event("task_progress", task)

    def _append_result(
        self,
        task: TaskState,
        *,
        input_path: str,
        input_name: str,
        title_source: str,
        source_title: str,
        contains_chinese: bool,
        generated_initials: str | None,
        album_before: str | None,
        album_after: str | None,
        status: str,
        message: str,
    ) -> None:
        task.results.append(
            {
                "input_path": input_path,
                "input_name": input_name,
                "title_source": title_source,
                "source_title": source_title,
                "contains_chinese": contains_chinese,
                "generated_initials": generated_initials,
                "album_before": album_before,
                "album_after": album_after,
                "status": status,
                "message": message,
            }
        )

    def _normalize_stopwords(self, values: list[str]) -> set[str]:
        return {
            value.strip().lower()
            for value in values
            if isinstance(value, str) and value.strip()
        }

    def _clean_title_text(self, value: str | None) -> str:
        if value is None:
            return ""
        text = unicodedata.normalize("NFKC", value)
        text = text.replace("_", " ")
        text = MULTI_SPACE.sub(" ", text).strip()
        return text

    def _apply_stopwords(self, title: str, stopwords: set[str]) -> str:
        cleaned = title
        for stopword in stopwords:
            cleaned = re.sub(re.escape(stopword), " ", cleaned, flags=re.IGNORECASE)
        cleaned = MULTI_SPACE.sub(" ", cleaned)
        return cleaned.strip()

    def _generate_initials(
        self,
        title: str,
        max_initials_length: int,
        lazy_pinyin: Any,
        Style: Any,
    ) -> str:
        chinese_only_title = self._extract_chinese_text(title)
        if not chinese_only_title:
            return ""
        parts = lazy_pinyin(
            chinese_only_title,
            style=Style.FIRST_LETTER,
            strict=False,
        )
        initials = "".join(part.upper() for part in parts if part)
        initials = "".join(char for char in initials if char.isalnum())
        return initials[:max_initials_length]

    def _extract_chinese_text(self, value: str) -> str:
        return "".join(CHINESE_RE.findall(value))

    def _compose_album(
        self,
        album_before: str | None,
        generated_initials: str,
        write_mode: str,
    ) -> str:
        existing = (album_before or "").strip()
        if write_mode == "append" and existing:
            parts = [segment.strip() for segment in existing.split("/") if segment.strip()]
            if generated_initials in parts:
                return existing
            return f"{existing} / {generated_initials}"
        return generated_initials

    def _read_metadata(self, path: Path) -> tuple[str | None, str | None]:
        suffix = path.suffix.lower()
        if suffix == ".mp3" or suffix == ".aiff":
            return self._read_id3_metadata(path)
        audio = mutagen_file(path, easy=True)
        if audio is None:
            raise PinyinGeneratorRuntimeError(
                "INTERNAL_ERROR", f"不支持读取元数据: {path.name}"
            )
        tags = getattr(audio, "tags", None) or {}
        return self._first_text(tags.get("title")), self._first_text(tags.get("album"))

    def _read_id3_metadata(self, path: Path) -> tuple[str | None, str | None]:
        try:
            tags = ID3(path)
        except ID3NoHeaderError:
            return None, None
        title_frame = tags.get("TIT2")
        album_frame = tags.get("TALB")
        title = self._frame_text(title_frame)
        album = self._frame_text(album_frame)
        return title, album

    def _write_album(self, path: Path, album_value: str) -> None:
        suffix = path.suffix.lower()
        if suffix == ".mp3" or suffix == ".aiff":
            self._write_id3_album(path, album_value)
            return
        self._ensure_writable(path)
        audio = mutagen_file(path, easy=True)
        if audio is None:
            raise PinyinGeneratorRuntimeError(
                "INTERNAL_ERROR", f"不支持写入元数据: {path.name}"
            )
        if getattr(audio, "tags", None) is None and hasattr(audio, "add_tags"):
            audio.add_tags()
        try:
            audio["album"] = [album_value]
            audio.save()
        except Exception as exc:
            raise PinyinGeneratorRuntimeError(
                "INTERNAL_ERROR", f"写入专辑字段失败: {path.name}"
            ) from exc

    def _write_id3_album(self, path: Path, album_value: str) -> None:
        self._ensure_writable(path)
        try:
            tags = ID3(path)
        except ID3NoHeaderError:
            tags = ID3()
        tags.delall("TALB")
        tags.add(TALB(encoding=3, text=album_value))
        try:
            tags.save(path)
        except Exception as exc:
            raise PinyinGeneratorRuntimeError(
                "INTERNAL_ERROR", f"写入专辑字段失败: {path.name}"
            ) from exc

    def _ensure_writable(self, path: Path) -> None:
        import os
        import stat
        if not path.exists():
            return
        mode = path.stat().st_mode
        if not (mode & stat.S_IWUSR):
            try:
                os.chmod(path, mode | stat.S_IWUSR)
            except OSError as exc:
                raise PinyinGeneratorRuntimeError(
                    "INTERNAL_ERROR", f"无法移除只读属性: {path.name}"
                ) from exc

    def _first_text(self, value: Any) -> str | None:
        if isinstance(value, list) and value:
            first = value[0]
            return str(first).strip() or None
        if isinstance(value, str):
            return value.strip() or None
        return None

    def _frame_text(self, frame: Any) -> str | None:
        if frame is None:
            return None
        text = getattr(frame, "text", None)
        if isinstance(text, list) and text:
            first = str(text[0]).strip()
            return first or None
        if isinstance(text, str):
            return text.strip() or None
        return str(frame).strip() or None
