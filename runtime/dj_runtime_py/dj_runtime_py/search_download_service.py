from __future__ import annotations

import concurrent.futures
import contextlib
import io
import pickle
import threading
import time
from pathlib import Path
from typing import Any

from .access_control import AccessControlError, require_module_access
from .musicdl_adapter import discover_parser_methods, get_request_overrides, get_source_threads, load_musicdl_modules
from .protocol import ApiError, EventEnvelope, RequestEnvelope, ResponseEnvelope, iso_now

MODULE = "search_download"
PANELS = {"search"}
TASK_TYPES = {"search", "download", "playlist_parse"}
STATUSES = {
    "idle",
    "target_ready",
    "config_locked",
    "running",
    "review_ready",
    "executing",
    "success",
    "cancelled",
    "error",
}
EVENTS = {
    "task_created",
    "task_progress",
    "task_status_changed",
    "review_ready",
    "task_finished",
}
ACTIONS = {
    "lock_config",
    "start_search_task",
    "start_playlist_parse_task",
    "fetch_search_result",
    "start_download_task",
    "fetch_download_result",
    "stop_task",
    "subscribe_task_events",
}
SOURCE_LABELS = {
    "QQ音乐": "QQMusicClient",
    "网易云": "NeteaseMusicClient",
    "酷狗": "KugouMusicClient",
    "酷我音乐": "KuwoMusicClient",
    "咪咕音乐": "MiguMusicClient",
    "千千音乐": "QianqianMusicClient",
    "汽水音乐": "SodaMusicClient",
    "Bilibili音乐": "BilibiliMusicClient",
    "5SING音乐": "FiveSingMusicClient",
    "街声": "StreetVoiceMusicClient",
}
_MUSICDL_MODULE: Any | None = None
_MUSICDL_SOURCES_MODULE: Any | None = None
_MUSICDL_DATA_MODULE: Any | None = None
_MUSICDL_LOGGER_MODULE: Any | None = None
THIRD_PARTY_METHODS: dict[str, tuple[str, ...]] = {
    "QQMusicClient": (
        "_parsewithvkeysapi",
        "_parsewithtangapi",
        "_parsewithnkiapi",
        "_parsewithxianyuwapi",
        "_parsewithlittleyouziapi",
    ),
    "NeteaseMusicClient": (
        "_parsewithcggapi",
        "_parsewithxuanluogeapi",
        "_parsewithtmetuapi",
        "_parsewithbugpkapi",
        "_parsewithcyruiapi",
        "_parsewithcunyuapi",
        "_parsewithyutangxiaowuapi",
        "_parsewithnycnmbyfunsapi",
        "_parsewithxianyuwapi",
        "_parsewithxiaoqinapi",
    ),
    "KugouMusicClient": (
        "_parsewithcggapi",
        "_parsewithjbsouapi",
    ),
}
THIRD_PARTY_METHOD_LABELS: dict[str, str] = {
    "_parsewithvkeysapi": "api.vkeys.cn",
    "_parsewithtangapi": "tang.api.s01s.cn",
    "_parsewithnkiapi": "api.nki.pw",
    "_parsewithxianyuwapi": "apii.xianyuw.cn",
    "_parsewithlittleyouziapi": "www.littleyouzi.com",
    "_parsewithcggapi": "api-v2.cenguigui.cn / music-api2.cenguigui.cn",
    "_parsewithxuanluogeapi": "music.xuanluoge.top",
    "_parsewithtmetuapi": "music.rrvenn.cn",
    "_parsewithbugpkapi": "api.bugpk.com",
    "_parsewithcyruiapi": "blog.cyrui.cn",
    "_parsewithcunyuapi": "www.cunyuapi.top",
    "_parsewithyutangxiaowuapi": "yutangxiaowu.cn:4000",
    "_parsewithnycnmbyfunsapi": "api.nycnm.cn + api.byfuns.top",
    "_parsewithxiaoqinapi": "wyapi-eo.toubiec.cn",
    "_parsewithjbsouapi": "www.jbsou.cn",
}
THIRD_PARTY_HEALTH_CACHE_TTL_SECONDS = 300.0
FAST_AUDIO_LINK_TEST_TIMEOUT = (2, 4)
PARSE_METHOD_TIMEOUT_SECONDS = 15.0
DOWNLOAD_SOURCE_TIMEOUT_SECONDS = 60.0
SEARCH_TASK_TIMEOUT_SECONDS = 75.0
SEARCH_SOURCE_DEADLINE_SECONDS = 20.0


class SearchDownloadRuntimeError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class PanelState:
    def __init__(self, panel: str) -> None:
        self.panel = panel
        self.config: dict[str, Any] = {}
        self.status = "idle"
        self.playlist_name: str | None = None


class TaskState:
    def __init__(
        self,
        task_id: str,
        panel: str,
        task_type: str,
        status: str,
        config: dict[str, Any],
    ) -> None:
        self.task_id = task_id
        self.panel = panel
        self.task_type = task_type
        self.status = status
        self.config = config
        self.progress = 0.0
        self.progress_hint_text = "等待任务载入..."
        self.worker_started = False
        self.cancel_requested = False
        self.error_message: str | None = None
        self.success_count = 0
        self.failed_count = 0
        self.total_count = 0
        self.log_lines: list[str] = []
        self.search_results: list[dict[str, Any]] = []
        self.selected_song_infos: list[dict[str, Any]] = []
        self.download_results: list[dict[str, Any]] = []
        self.work_dirs: list[str] = []
        self.log_file_path: str | None = None
        self.output_dir: str | None = None
        self.playlist_name: str | None = None
        self.created_at = iso_now()
        self.updated_at = self.created_at

    def summary(self) -> dict[str, Any]:
        return {
            "task_id": self.task_id,
            "panel": self.panel,
            "task_type": self.task_type,
            "status": self.status,
            "progress": self.progress,
            "progress_hint_text": self.progress_hint_text,
            "total_count": self.total_count,
            "success_count": self.success_count,
            "failed_count": self.failed_count,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "log_lines": list(self.log_lines[-40:]),
            "output_dir": self.output_dir,
            "playlist_name": self.playlist_name,
        }


def _ensure_musicdl_loaded() -> tuple[Any, Any, Any, Any]:
    global _MUSICDL_MODULE, _MUSICDL_SOURCES_MODULE, _MUSICDL_DATA_MODULE, _MUSICDL_LOGGER_MODULE
    modules = load_musicdl_modules()
    _MUSICDL_MODULE, _MUSICDL_SOURCES_MODULE, _MUSICDL_DATA_MODULE, _MUSICDL_LOGGER_MODULE = modules
    return modules


def _humanize_search_download_error(exc: Exception) -> str:
    message = str(exc).strip()
    lowered = message.lower()
    if "timeout" in lowered or "timed out" in lowered:
        return "搜索或下载超时，请稍后重试。"
    if "network" in lowered or "connection" in lowered:
        return "搜索或下载失败，请检查网络后重试。"
    if "permission denied" in lowered:
        return "下载目录写入失败，请检查目录权限后重试。"
    return "搜索或下载失败，请稍后重试。"


class SearchDownloadRuntime:
    def __init__(self) -> None:
        self._panels = {"search": PanelState("search")}
        self._tasks: dict[str, TaskState] = {}
        self._events: list[EventEnvelope] = []
        self._task_index = 0
        self._events_lock = threading.Lock()
        self._third_party_health_cache: dict[str, tuple[float, list[str]]] = {}

    def handle_request(self, raw_request: dict[str, Any]) -> dict[str, Any]:
        request_id = raw_request.get("request_id")
        try:
            request = RequestEnvelope.from_dict(raw_request)
            if request.module != MODULE:
                raise SearchDownloadRuntimeError("INVALID_MODULE", "module 必须是 search_download。")
            if request.action not in ACTIONS:
                raise SearchDownloadRuntimeError("INVALID_CONFIG", f"未知 action: {request.action}")
            require_module_access(MODULE, request.action)
            handler = getattr(self, f"_handle_{request.action}", None)
            if handler is None:
                raise SearchDownloadRuntimeError("INVALID_CONFIG", f"action 未实现: {request.action}")
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
        except SearchDownloadRuntimeError as exc:
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
                ApiError("INTERNAL_ERROR", _humanize_search_download_error(exc)),
            ).to_dict()

    def _handle_lock_config(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = self._require_panel(payload.get("panel"))
        config = payload.get("config") or {}
        if not isinstance(config, dict):
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "config 必须是对象。")
        self._validate_config(config)
        state = self._panels[panel]
        state.config = dict(config)
        if "playlist_url" in config:
            state.playlist_name = None
        state.status = "config_locked"
        return {
            "status": state.status,
            "available_sources": self._available_sources(),
        }


    def _handle_start_search_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = payload.get("panel") or "search"
        if panel != "search":
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "search 任务只能用于 search 面板。")
        return self._start_task(task_type="search").summary()

    def _handle_start_playlist_parse_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = payload.get("panel") or "search"
        if panel != "search":
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "playlist 任务只能用于 search 面板。")
        return self._start_task(task_type="playlist_parse").summary()

    def _handle_fetch_search_result(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        if task.status == "running":
            raise SearchDownloadRuntimeError("TASK_NOT_COMPLETED", "当前任务仍在运行中。")
        if task.status == "error":
            raise SearchDownloadRuntimeError("INTERNAL_ERROR", task.error_message or task.progress_hint_text)
        results = list(task.search_results) or self._load_task_result_pickles(task, result_kind="search")
        return {
            "task_id": task.task_id,
            "status": task.status,
            "task_type": task.task_type,
            "results": results,
            "total_count": task.total_count,
            "success_count": task.success_count,
            "failed_count": task.failed_count,
            "log_lines": self._collect_task_log_lines(task),
            "output_dir": task.output_dir,
            "playlist_name": task.playlist_name,
        }

    def _handle_start_download_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        panel = payload.get("panel") or "search"
        if panel != "search":
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "download 任务只能用于 search 面板。")
        song_infos = payload.get("song_infos")
        if not isinstance(song_infos, list) or not song_infos:
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "song_infos 不能为空。")
        normalized = [self._normalize_song_info(item) for item in song_infos]
        task = self._start_task(task_type="download", selected_song_infos=normalized)
        return task.summary()

    def _handle_fetch_download_result(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        if task.status == "running":
            raise SearchDownloadRuntimeError("TASK_NOT_COMPLETED", "当前任务仍在运行中。")
        if task.status == "error":
            raise SearchDownloadRuntimeError("INTERNAL_ERROR", task.error_message or task.progress_hint_text)
        results = list(task.download_results) or self._load_task_result_pickles(task, result_kind="download")
        return {
            "task_id": task.task_id,
            "status": task.status,
            "task_type": task.task_type,
            "results": results,
            "total_count": task.total_count,
            "success_count": task.success_count,
            "failed_count": task.failed_count,
            "log_lines": self._collect_task_log_lines(task),
            "output_dir": task.output_dir,
            "playlist_name": task.playlist_name,
        }

    def _handle_stop_task(self, payload: dict[str, Any]) -> dict[str, Any]:
        task = self._require_task(payload.get("task_id"))
        task.cancel_requested = True
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

    def _start_task(
        self,
        *,
        task_type: str,
        selected_song_infos: list[dict[str, Any]] | None = None,
    ) -> TaskState:
        panel = "search"
        state = self._panels[panel]
        self._validate_config(state.config)
        if self._has_active_task(panel):
            raise SearchDownloadRuntimeError("TASK_ALREADY_RUNNING", "当前面板已有进行中的任务。")
        self._task_index += 1
        task_id = f"search_task_{self._task_index}"
        task = TaskState(
            task_id=task_id,
            panel=panel,
            task_type=task_type,
            status="running",
            config=dict(state.config),
        )
        task.playlist_name = state.playlist_name

        if selected_song_infos is not None:
            task.selected_song_infos = selected_song_infos
            task.total_count = len(selected_song_infos)
        task.progress = 0.01
        task.progress_hint_text = "正在准备任务..."
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
            if task.task_type == "search":
                self._run_search_task(task)
            elif task.task_type == "playlist_parse":
                self._run_playlist_task(task)
            elif task.task_type == "download":
                self._run_download_task(task)
            else:
                raise SearchDownloadRuntimeError("INVALID_CONFIG", f"未知 task_type: {task.task_type}")
        except SearchDownloadRuntimeError as exc:
            task.status = "error"
            task.error_message = exc.message
            task.progress_hint_text = exc.message
            task.updated_at = iso_now()
            self._panels[task.panel].status = task.status
            self._push_event("task_status_changed", task)
            self._push_event("task_finished", task)
        except Exception as exc:
            task.status = "error"
            task.error_message = _humanize_search_download_error(exc)
            task.progress_hint_text = task.error_message
            task.updated_at = iso_now()
            self._panels[task.panel].status = task.status
            self._push_event("task_status_changed", task)
            self._push_event("task_finished", task)

    def _run_search_task(self, task: TaskState) -> None:
        keyword = str(task.config.get("keyword") or "").strip()
        sources = self._resolve_sources(task.config.get("sources"))
        if not keyword:
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "keyword 不能为空。")
        musicdl_module, _, _, logger_module = _ensure_musicdl_loaded()
        logger = logger_module.LoggerHandle()
        task.log_file_path = getattr(logger, "log_file_path", None)
        client = musicdl_module.MusicClient(
            music_sources=sources,
            init_music_clients_cfg=self._build_client_cfg(task.config),
            requests_overrides=self._build_search_request_overrides(sources),
        )
        client.logger_handle = logger
        task.log_lines.append(f"[System] 开始搜索: {keyword}")
        task.progress_hint_text = f"正在搜索: {keyword}"
        self._update_task_progress(task, progress=0.05)
        # Use musicdl's public MusicClient.search() instead of maintaining a
        # private lightweight-search implementation.  Upstream changes the
        # per-source request signatures regularly (e.g. QQ page_no), so the
        # public API is the safer compatibility boundary.
        task.progress_hint_text = f"正在搜索 {len(sources)} 个来源，请稍候..."
        self._update_task_progress(task, progress=0.15)
        lightweight_results: list[Any] = []
        try:
            lightweight_results = self._call_with_timeout(
                lambda: self._run_lightweight_search(task, client, keyword),
                timeout=20.0,
            )
        except Exception as error:
            task.log_lines.append(f"[System] 轻搜索回退完整搜索: {error}")
        if lightweight_results:
            task.search_results = [
                self._song_info_to_json(song_info)
                for song_info in lightweight_results
            ]
            task.work_dirs = self._resolve_task_work_dirs(
                client, lightweight_results
            )
        else:
            results = self._call_with_timeout(
                lambda: self._capture_noisy_call(
                    task, client.search, keyword=keyword
                ),
                timeout=SEARCH_TASK_TIMEOUT_SECONDS,
            )
            task.search_results = self._flatten_search_results(results)
            task.work_dirs = self._resolve_task_work_dirs(
                client,
                [
                    item
                    for items in results.values()
                    if isinstance(items, list)
                    for item in items
                    if item is not None
                ],
            )
        task.total_count = len(task.search_results)
        task.success_count = len(task.search_results)

        task.failed_count = 0
        task.progress = 1.0
        task.status = "success"
        task.progress_hint_text = f"搜索完成，共 {len(task.search_results)} 条结果。"
        task.log_lines.append(task.progress_hint_text)
        self._refresh_task_logs(task)
        task.updated_at = iso_now()
        self._panels[task.panel].status = task.status
        self._push_event("task_finished", task)

    def _run_playlist_task(self, task: TaskState) -> None:
        playlist_url = str(task.config.get("playlist_url") or "").strip()
        sources = self._resolve_sources(task.config.get("sources"))
        if not playlist_url:
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "playlist_url 不能为空。")
        musicdl_module, _, _, logger_module = _ensure_musicdl_loaded()
        logger = logger_module.LoggerHandle()
        task.log_file_path = getattr(logger, "log_file_path", None)
        client = musicdl_module.MusicClient(
            music_sources=sources,
            init_music_clients_cfg=self._build_client_cfg(task.config),
        )
        client.logger_handle = logger
        task.log_lines.append(f"[System] 开始解析歌单: {playlist_url}")
        task.progress_hint_text = "正在解析歌单..."
        task.updated_at = iso_now()
        self._push_event("task_progress", task)
        playlist_song_infos = self._capture_noisy_call(task, client.parseplaylist, playlist_url=playlist_url)
        if not isinstance(playlist_song_infos, list):
            playlist_song_infos = list(playlist_song_infos or [])
        playlist_song_infos = [song_info for song_info in playlist_song_infos if song_info is not None]
        task.playlist_name = self._resolve_playlist_name(playlist_song_infos)
        self._panels[task.panel].playlist_name = task.playlist_name
        task.search_results = [self._song_info_to_json(song_info) for song_info in playlist_song_infos]
        task.work_dirs = self._resolve_task_work_dirs(client, playlist_song_infos)
        if playlist_song_infos:
            try:
                task.output_dir = str(Path(str(getattr(playlist_song_infos[0], "work_dir", ""))).resolve())
            except Exception:
                task.output_dir = None
        task.total_count = len(task.search_results)
        task.success_count = len(task.search_results)
        task.failed_count = 0
        task.progress = 1.0
        task.status = "success"
        task.progress_hint_text = f"歌单解析完成，共 {len(task.search_results)} 条结果。"
        task.log_lines.append(task.progress_hint_text)
        self._refresh_task_logs(task)
        task.updated_at = iso_now()
        self._panels[task.panel].status = task.status
        self._push_event("task_finished", task)

    def _run_download_task(self, task: TaskState) -> None:

        musicdl_module, _, data_module, logger_module = _ensure_musicdl_loaded()
        sources = sorted({str(item.get("source")) for item in task.selected_song_infos if item.get("source")})
        logger = logger_module.LoggerHandle()
        task.log_file_path = getattr(logger, "log_file_path", None)
        client = musicdl_module.MusicClient(
            music_sources=sources,
            init_music_clients_cfg=self._build_client_cfg(task.config),
        )
        client.logger_handle = logger
        task.progress_hint_text = "正在下载选中项..."
        output_dir = Path(str(task.config.get("output_dir"))).expanduser().resolve()
        output_dir.mkdir(parents=True, exist_ok=True)
        task.output_dir = str(output_dir)
        self._update_task_progress(task, progress=0.05)
        preferred_methods = self._collect_preferred_third_party_methods(task, client)
        song_infos = self._resolve_download_song_infos(task, client, preferred_methods)
        self._update_task_progress(
            task,
            progress=0.88 if song_infos else 0.82,
            progress_hint_text="正在写入文件到输出目录..." if song_infos else "未找到可下载直链，正在整理结果...",
        )
        downloaded_song_infos = self._download_with_source_timeout(task, client, song_infos) if song_infos else []
        task.download_results = [self._song_info_to_json(song_info) for song_info in downloaded_song_infos or song_infos]
        task.work_dirs = self._resolve_task_work_dirs(client, downloaded_song_infos or song_infos)
        task.total_count = len(task.selected_song_infos)
        task.success_count = len(task.download_results)
        task.failed_count = max(0, len(task.selected_song_infos) - len(task.download_results))
        task.progress = 1.0
        task.status = "success"
        task.progress_hint_text = f"下载完成，共 {len(task.download_results)} 项。"
        if task.failed_count:
            task.log_lines.append(f"[System] 有 {task.failed_count} 项在补全阶段失败，未进入下载。")
        task.log_lines.append(task.progress_hint_text)
        self._refresh_task_logs(task)
        task.updated_at = iso_now()
        self._panels[task.panel].status = task.status
        self._push_event("task_finished", task)

    def _build_client_cfg(self, config: dict[str, Any]) -> dict[str, Any]:
        output_dir = Path(str(config.get("output_dir"))).expanduser().resolve()
        return {
            source: {
                "work_dir": str(output_dir),
                "disable_print": True,
                # Search is interactive: fail fast and let the UI move on
                # instead of waiting for the upstream default retry count.
                "max_retries": 1,
                "search_size_per_source": 5,
            }
            for source in self._resolve_sources(config.get("sources"))
        }

    def _build_search_request_overrides(
        self, sources: list[str]
    ) -> dict[str, dict[str, Any]]:
        return {
            source: {"timeout": (5, 12)}
            for source in sources
        }

    def _download_with_source_timeout(self, task: TaskState, client: Any, song_infos: list[Any]) -> list[Any]:
        classified_song_infos: dict[str, list[Any]] = {}
        downloaded_song_infos: list[Any] = []
        for song_info in song_infos:
            source = str(getattr(song_info, "source", "") or "")
            if not source:
                continue
            classified_song_infos.setdefault(source, []).append(song_info)
        total_sources = max(1, len(classified_song_infos))
        for index, (source, source_song_infos) in enumerate(classified_song_infos.items(), start=1):
            if task.cancel_requested:
                raise SearchDownloadRuntimeError("TASK_CANCELLED", "任务已取消。")
            music_client = client.music_clients.get(source)
            if music_client is None:
                task.log_lines.append(f"[System] 下载阶段未找到平台客户端: {source}")
                task.failed_count += len(source_song_infos)
                continue
            task.progress_hint_text = f"正在下载 {source} ({index}/{total_sources})..."
            self._update_task_progress(
                task,
                progress=min(0.97, 0.88 + (index - 1) / total_sources * 0.09),
                progress_hint_text=task.progress_hint_text,
            )
            request_overrides = get_request_overrides(client, source)
            request_overrides.setdefault("timeout", (8, 25))
            try:
                results = self._call_with_timeout(
                    lambda: self._capture_noisy_call(
                        task,
                        music_client.download,
                        song_infos=source_song_infos,
                        num_threadings=get_source_threads(client, source),
                        request_overrides=request_overrides,
                    ),
                    timeout=DOWNLOAD_SOURCE_TIMEOUT_SECONDS,
                )
            except TimeoutError:
                task.log_lines.append(
                    f"[System] {source} 下载阶段超过 {int(DOWNLOAD_SOURCE_TIMEOUT_SECONDS)} 秒未完成，已跳过该下载源。"
                )
                task.failed_count += len(source_song_infos)
                continue
            except Exception as error:
                task.log_lines.append(f"[System] {source} 下载失败，已跳过该下载源: {error}")
                task.failed_count += len(source_song_infos)
                continue
            if isinstance(results, list):
                downloaded_song_infos.extend(results)
            else:
                downloaded_song_infos.extend(source_song_infos)
        return downloaded_song_infos

    def _call_with_timeout(self, func: Any, *, timeout: float) -> Any:
        executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        future = executor.submit(func)
        try:
            return future.result(timeout=timeout)
        except concurrent.futures.TimeoutError as exc:
            future.cancel()
            executor.shutdown(wait=False, cancel_futures=True)
            raise TimeoutError from exc
        finally:
            executor.shutdown(wait=False, cancel_futures=True)

    def _invoke_parse_method(
        self,
        method: Any,
        music_client: Any,
        raw_search: dict[str, Any],
        request_overrides: dict[str, Any],
        **kwargs: Any,
    ) -> Any:
        request_overrides = dict(request_overrides)
        request_overrides.setdefault("timeout", (8, 25))
        with self._fast_audio_link_testing(music_client):
            return method(search_result=raw_search, request_overrides=request_overrides, **kwargs)

    def _capture_noisy_call(self, task: TaskState, func: Any, /, *args: Any, **kwargs: Any) -> Any:
        stdout_buffer = io.StringIO()
        stderr_buffer = io.StringIO()
        with contextlib.redirect_stdout(stdout_buffer), contextlib.redirect_stderr(stderr_buffer):
            result = func(*args, **kwargs)
        for line in [*stdout_buffer.getvalue().splitlines(), *stderr_buffer.getvalue().splitlines()]:
            line = line.strip()
            if line:
                task.log_lines.append(line)
        return result

    def _refresh_task_logs(self, task: TaskState) -> None:
        log_lines = self._read_log_file_lines(task.log_file_path)
        if log_lines:
            task.log_lines = self._dedupe_log_lines([*task.log_lines, *log_lines])

    def _collect_task_log_lines(self, task: TaskState) -> list[str]:
        return self._dedupe_log_lines([*task.log_lines, *self._read_log_file_lines(task.log_file_path)])

    def _dedupe_log_lines(self, lines: list[str]) -> list[str]:
        merged: list[str] = []
        for line in lines:
            if not line:
                continue
            if not merged or merged[-1] != line:
                merged.append(line)
        return merged[-200:]

    def _read_log_file_lines(self, log_file_path: str | None) -> list[str]:
        if not log_file_path:
            return []
        path = Path(log_file_path)
        if not path.exists():
            return []
        try:
            return [line.strip() for line in path.read_text(encoding="utf-8", errors="ignore").splitlines() if line.strip()]
        except Exception:
            return []

    def _load_task_result_pickles(self, task: TaskState, *, result_kind: str) -> list[dict[str, Any]]:
        file_name = "search_results.pkl" if result_kind == "search" else "download_results.pkl"
        results: list[dict[str, Any]] = []
        _, _, data_module, _ = _ensure_musicdl_loaded()
        for work_dir in task.work_dirs:
            candidate = Path(work_dir) / file_name
            if not candidate.exists():
                continue
            try:
                with candidate.open("rb") as file:
                    payload = pickle.load(file)
            except Exception:
                continue
            if not isinstance(payload, list):
                continue
            for item in payload:
                if isinstance(item, data_module.SongInfo):
                    results.append(self._song_info_to_json(item))
                elif isinstance(item, dict):
                    results.append(self._song_info_to_json(data_module.SongInfo.fromdict(item)))
        return results

    def _resolve_task_work_dirs(self, client: Any, song_infos: list[Any]) -> list[str]:
        work_dirs = {
            str(getattr(client, "work_dir", "") or "") for client in getattr(client, "music_clients", {}).values()
        }
        for song_info in song_infos:
            work_dir = getattr(song_info, "work_dir", None)
            if work_dir:
                work_dirs.add(str(work_dir))
        return sorted(path for path in work_dirs if path)


    def _search_sources_parallel(
        self,
        task: TaskState,
        client: Any,
        keyword: str,
        sources: list[str],
    ) -> dict[str, list[Any]]:
        """Search sources concurrently and return before the slowest one.

        musicdl's public search waits for every source.  Some free sources can
        take 20-60 seconds while another source already has results.  Waiting
        for all of them makes the UI look frozen, so this method uses a
        deadline and returns whatever completed sources are available.
        """
        source_clients = {
            source: music_client
            for source in sources
            if (music_client := getattr(client, "music_clients", {}).get(source))
            is not None
        }
        if not source_clients:
            results = self._capture_noisy_call(task, client.search, keyword=keyword)
            return results if isinstance(results, dict) else {}

        if not all(callable(getattr(item, "search", None)) for item in source_clients.values()):
            results = self._capture_noisy_call(task, client.search, keyword=keyword)
            return results if isinstance(results, dict) else {}

        futures: dict[Any, str] = {}
        results: dict[str, list[Any]] = {}
        executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=min(len(source_clients), 5)
        )
        try:
            for source, music_client in source_clients.items():
                future = executor.submit(
                    self._capture_noisy_call,
                    task,
                    music_client.search,
                    keyword=keyword,
                    num_threadings=get_source_threads(client, source),
                    request_overrides=get_request_overrides(client, source),
                )
                futures[future] = source
            deadline = time.monotonic() + SEARCH_SOURCE_DEADLINE_SECONDS
            while futures:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                done, _ = concurrent.futures.wait(
                    futures,
                    timeout=remaining,
                    return_when=concurrent.futures.FIRST_COMPLETED,
                )
                if not done:
                    break
                for future in done:
                    source = futures.pop(future)
                    try:
                        song_infos = future.result()
                    except Exception as error:
                        task.log_lines.append(
                            f"[System] {source} 搜索失败，已跳过: {error}"
                        )
                        continue
                    if isinstance(song_infos, list):
                        results[source] = song_infos
                        self._update_task_progress(
                            task,
                            progress=min(0.8, 0.2 + len(results) / max(1, len(source_clients)) * 0.55),
                            success_count=sum(len(items) for items in results.values()),
                            progress_hint_text=f"已收到 {len(results)} 个来源的结果，继续搜索...",
                        )
            if futures:
                task.log_lines.append(
                    f"[System] 搜索达到 {int(SEARCH_SOURCE_DEADLINE_SECONDS)} 秒上限，"
                    f"已跳过 {len(futures)} 个较慢来源。"
                )
        finally:
            for future in futures:
                future.cancel()
            executor.shutdown(wait=False, cancel_futures=True)
        return results

    def _run_lightweight_search(self, task: TaskState, client: Any, keyword: str) -> list[Any]:
        """Run the fast source-specific search paths concurrently.

        The old implementation waited for each source in order.  A single
        slow/offline source could therefore consume the whole search budget.
        """
        lightweight_song_infos: list[Any] = []
        source_clients = {
            source: music_client
            for source in getattr(client, "music_sources", [])
            if (music_client := getattr(client, "music_clients", {}).get(source))
            is not None
        }
        if not source_clients:
            return lightweight_song_infos
        executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=min(len(source_clients), 4)
        )
        futures: dict[Any, str] = {}
        try:
            for source, music_client in source_clients.items():
                future = executor.submit(
                    self._lightweight_search_source,
                    task,
                    music_client,
                    keyword,
                )
                futures[future] = source
            deadline = time.monotonic() + 8.0
            while futures:
                if task.cancel_requested:
                    raise SearchDownloadRuntimeError("TASK_CANCELLED", "任务已取消。")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                done, _ = concurrent.futures.wait(
                    futures,
                    timeout=remaining,
                    return_when=concurrent.futures.FIRST_COMPLETED,
                )
                if not done:
                    break
                for future in done:
                    source = futures.pop(future)
                    try:
                        per_source_results = future.result()
                    except Exception as error:
                        task.log_lines.append(
                            f"[System] {source} 轻搜索失败，继续其他来源: {error}"
                        )
                        continue
                    lightweight_song_infos.extend(per_source_results)
                    task.log_lines.append(
                        f"[System] {source} 轻搜索得到 {len(per_source_results)} 条结果。"
                    )
            if futures:
                task.log_lines.append(
                    f"[System] 轻搜索达到 8 秒上限，已跳过 {len(futures)} 个较慢来源。"
                )
        finally:
            for future in futures:
                future.cancel()
            executor.shutdown(wait=False, cancel_futures=True)
        return lightweight_song_infos

    def _lightweight_search_source(self, task: TaskState, music_client: Any, keyword: str) -> list[Any]:
        _, _, data_module, _ = _ensure_musicdl_loaded()
        request_overrides = client_request_overrides = {"timeout": (3, 8)}
        search_rule = {}
        source_name = getattr(music_client, "source", type(music_client).__name__)
        search_urls = music_client._constructsearchurls(keyword=keyword, rule=search_rule, request_overrides=request_overrides)
        song_infos: list[Any] = []
        for search_url in search_urls:
            if task.cancel_requested:
                raise SearchDownloadRuntimeError("TASK_CANCELLED", "任务已取消。")
            search_meta = dict(search_url) if isinstance(search_url, dict) else search_url
            raw_results = self._fetch_lightweight_search_payload(music_client, search_meta, client_request_overrides)
            for raw_item in raw_results:
                song_info = self._build_lightweight_song_info(data_module, source_name, raw_item)
                if song_info is None:
                    continue
                song_infos.append(song_info)
                if music_client.strict_limit_search_size_per_page and len(song_infos) >= music_client.search_size_per_page:
                    return song_infos
        return song_infos

    def _fetch_lightweight_search_payload(self, music_client: Any, search_url: Any, request_overrides: dict[str, Any]) -> list[dict[str, Any]]:
        source_name = getattr(music_client, "source", type(music_client).__name__)
        request_overrides = dict(request_overrides)
        if source_name == "QQMusicClient":
            copy_dict = dict(search_url)
            copy_dict.pop("page_no", None)
            url = copy_dict.pop("url")
            response = music_client.post(url, **copy_dict, **request_overrides)
            return response.json()["music.search.SearchCgiService.DoSearchForQQMusicMobile"]["data"]["body"].get("item_song", [])
        if source_name == "NeteaseMusicClient":
            search_meta = dict(search_url)
            url = search_meta.pop("url")
            response = music_client.post(url, **search_meta, **request_overrides)
            return response.json().get("result", {}).get("songs", [])
        if source_name == "KugouMusicClient":
            response = music_client.get(search_url, **request_overrides)
            return response.json().get("data", {}).get("info", [])
        if source_name == "KuwoMusicClient":
            response = music_client.get(search_url, **request_overrides)
            return response.json().get("abslist", [])
        if source_name == "MiguMusicClient":
            response = music_client.get(search_url, **request_overrides)
            return response.json().get("songResultData", {}).get("result", [])
        if source_name == "QianqianMusicClient":
            response = music_client.get(search_url, **request_overrides)
            return response.json().get("data", {}).get("typeTrack", [])
        raise SearchDownloadRuntimeError("INVALID_CONFIG", f"暂未支持轻搜索平台: {source_name}")

    def _build_lightweight_song_info(self, data_module: Any, source_name: str, raw_item: dict[str, Any]) -> Any | None:
        if not isinstance(raw_item, dict):
            return None
        identifier = None
        song_name = None
        singers = None
        album = None
        duration = None
        duration_s = None
        cover_url = None
        ext = "mp3"
        file_size = "待解析"
        if source_name == "QQMusicClient":
            identifier = raw_item.get("mid") or raw_item.get("songmid")
            song_name = raw_item.get("title") or raw_item.get("songname")
            singers = ", ".join([item.get("name", "") for item in raw_item.get("singer", []) if isinstance(item, dict) and item.get("name")]) or None
            album = (raw_item.get("album") or {}).get("title") if isinstance(raw_item.get("album"), dict) else raw_item.get("albumname")
            duration_s = raw_item.get("interval")
            cover_url = None
        elif source_name == "NeteaseMusicClient":
            identifier = raw_item.get("id")
            song_name = raw_item.get("name")
            singers = ", ".join([item.get("name", "") for item in raw_item.get("ar", []) if isinstance(item, dict) and item.get("name")]) or None
            album = (raw_item.get("al") or {}).get("name") if isinstance(raw_item.get("al"), dict) else None
            duration_s = int((raw_item.get("dt") or 0) / 1000) if raw_item.get("dt") else raw_item.get("duration")
            cover_url = (raw_item.get("al") or {}).get("picUrl") if isinstance(raw_item.get("al"), dict) else None
        elif source_name == "KugouMusicClient":
            identifier = raw_item.get("hash")
            song_name = raw_item.get("songname") or raw_item.get("filename") or raw_item.get("name")
            singers = raw_item.get("singername")
            album = raw_item.get("album_name")
            duration_s = raw_item.get("duration") or int((raw_item.get("timelen") or 0) / 1000) if raw_item.get("timelen") else 0
            cover_url = None
        elif source_name == "KuwoMusicClient":
            identifier = str(raw_item.get("MUSICRID") or raw_item.get("musicrid") or "").removeprefix("MUSIC_")
            song_name = raw_item.get("SONGNAME") or raw_item.get("name")
            singers = raw_item.get("ARTIST") or raw_item.get("artist")
            album = raw_item.get("ALBUM") or raw_item.get("album")
            duration_s = raw_item.get("DURATION") or raw_item.get("duration")
            cover_url = raw_item.get("hts_MVPIC") or raw_item.get("albumpic")
        elif source_name == "MiguMusicClient":
            identifier = raw_item.get("contentId")
            song_name = raw_item.get("name") or raw_item.get("songName")
            singers = ", ".join([item.get("name", "") for item in (raw_item.get("singers") or raw_item.get("singerList") or []) if isinstance(item, dict) and item.get("name")]) or None
            album = raw_item.get("album") or ", ".join([item.get("name", "") for item in raw_item.get("albums", []) if isinstance(item, dict) and item.get("name")]) or None
            cover_url = next((raw_item.get(key) for key in ("img3", "img2", "img1") if raw_item.get(key)), None)
            duration_s = None
            ext = "flac"
        elif source_name == "QianqianMusicClient":
            identifier = raw_item.get("TSID")
            song_name = raw_item.get("title")
            singers = ", ".join([item.get("name", "") for item in raw_item.get("artist", []) if isinstance(item, dict) and item.get("name")]) or None
            album = raw_item.get("albumTitle")
            cover_url = raw_item.get("pic")
            duration_s = None
        if not identifier or not song_name:
            return None
        if isinstance(duration_s, str) and duration_s.isdigit():
            duration_s = int(duration_s)
        if isinstance(duration_s, (int, float)):
            duration = self._seconds_to_hms(int(duration_s))
        else:
            duration = None
        song_info = data_module.SongInfo(
            raw_data={"search": raw_item, "is_lightweight": True},
            source=source_name,
            root_source=source_name,
            song_name=str(song_name),
            singers=singers,
            album=album,
            ext=ext,
            file_size=file_size,
            duration_s=duration_s if isinstance(duration_s, int) else None,
            duration=duration,
            lyric="NULL",
            cover_url=cover_url,
            identifier=str(identifier),
            download_url=None,
            download_url_status={"ok": False, "lightweight": True},
        )
        return song_info

    def _resolve_download_song_infos(
        self,
        task: TaskState,
        client: Any,
        preferred_methods: dict[str, list[str]],
    ) -> list[Any]:
        _, _, data_module, _ = _ensure_musicdl_loaded()
        resolved_song_infos: list[Any] = []
        total_items = max(1, len(task.selected_song_infos))
        for index, item in enumerate(task.selected_song_infos, start=1):
            if task.cancel_requested:
                raise SearchDownloadRuntimeError("TASK_CANCELLED", "任务已取消。")
            source = str(item.get("source") or "")
            music_client = client.music_clients.get(source)
            if music_client is None:
                task.log_lines.append(f"[System] 未找到平台客户端: {source}")
                self._update_task_progress(
                    task,
                    progress=min(0.82, 0.1 + index / total_items * 0.7),
                    failed_count=index - len(resolved_song_infos),
                )
                continue
            task.progress_hint_text = f"正在补全下载信息: {item.get('song_name') or item.get('identifier') or source}"
            self._update_task_progress(
                task,
                progress=min(0.78, 0.08 + (index - 1) / total_items * 0.7),
            )
            song_info = self._resolve_full_song_info(
                task,
                music_client,
                item,
                preferred_methods.get(source),
            )
            if song_info is None or not getattr(song_info, "with_valid_download_url", False):
                self._update_task_progress(
                    task,
                    progress=min(0.82, 0.1 + index / total_items * 0.7),
                    success_count=len(resolved_song_infos),
                    failed_count=index - len(resolved_song_infos),
                    progress_hint_text=f"正在补全下载信息 ({index}/{total_items})...",
                )
                continue
            output_dir = Path(str(task.config.get("output_dir"))).expanduser().resolve()
            song_info.work_dir = str(output_dir)
            resolved_song_infos.append(song_info)
            self._update_task_progress(
                task,
                progress=min(0.82, 0.1 + index / total_items * 0.7),
                success_count=len(resolved_song_infos),
                failed_count=index - len(resolved_song_infos),
                progress_hint_text=f"正在补全下载信息 ({index}/{total_items})...",
            )
        return resolved_song_infos

    def _update_task_progress(
        self,
        task: TaskState,
        *,
        progress: float | None = None,
        progress_hint_text: str | None = None,
        success_count: int | None = None,
        failed_count: int | None = None,
    ) -> None:
        if progress is not None:
            task.progress = max(0.0, min(1.0, progress))
        if progress_hint_text is not None:
            task.progress_hint_text = progress_hint_text
        if success_count is not None:
            task.success_count = max(0, success_count)
        if failed_count is not None:
            task.failed_count = max(0, failed_count)
        task.updated_at = iso_now()
        self._push_event("task_progress", task)

    def _resolve_full_song_info(
        self,
        task: TaskState,
        music_client: Any,
        item: dict[str, Any],
        preferred_methods: list[str] | None = None,
    ) -> Any | None:
        raw_search = item.get("raw_data", {}).get("search") if isinstance(item.get("raw_data"), dict) else None
        if not isinstance(raw_search, dict):
            return None
        request_overrides: dict[str, Any] = {}
        source_name = getattr(music_client, "source", type(music_client).__name__)
        if source_name in THIRD_PARTY_METHODS:
            song_info_flac = self._resolve_third_party_song_info(
                task,
                music_client,
                raw_search,
                preferred_methods,
            )
            lossless_quality_is_sufficient = False if getattr(music_client, "default_cookies", None) or request_overrides.get("cookies") else True
            song_info = self._call_parse_if_exists(
                music_client,
                "_parsewithofficialapiv1",
                raw_search,
                request_overrides,
                song_info_flac=song_info_flac,
                lossless_quality_is_sufficient=lossless_quality_is_sufficient,
            )
            if not getattr(song_info, "with_valid_download_url", False):
                song_info = song_info_flac
            return song_info
        if source_name == "KuwoMusicClient":
            song_info_flac = self._call_parse_if_exists(music_client, "_parsewiththirdpartapis", raw_search, request_overrides)
            lossless_quality_is_sufficient = False if getattr(music_client, "default_cookies", None) or request_overrides.get("cookies") else True
            song_info = self._call_parse_if_exists(
                music_client,
                "_parsewithofficialapiv1",
                raw_search,
                request_overrides,
                song_info_flac=song_info_flac,
                lossless_quality_is_sufficient=lossless_quality_is_sufficient,
            )
            if not getattr(song_info, "with_valid_download_url", False):
                song_info = song_info_flac
            return song_info
        if source_name in {"MiguMusicClient", "QianqianMusicClient"}:
            return self._call_parse_if_exists(
                music_client,
                "_parsewithofficialapiv1",
                raw_search,
                request_overrides,
                song_info_flac=None,
                lossless_quality_is_sufficient=False,
            )
        _, _, data_module, _ = _ensure_musicdl_loaded()
        return data_module.SongInfo.fromdict(item)

    def _collect_preferred_third_party_methods(self, task: TaskState, client: Any) -> dict[str, list[str]]:
        preferred: dict[str, list[str]] = {}
        for source_name, music_client in getattr(client, "music_clients", {}).items():
            if music_client is None:
                continue
            method_names = self._candidate_parse_methods(music_client, source_name)
            if not method_names:
                continue
            raw_search = self._first_raw_search_for_source(task.selected_song_infos, source_name)
            if raw_search is None:
                continue
            cached = self._load_cached_third_party_methods(source_name)
            if cached is not None:
                cached = [name for name in cached if callable(getattr(music_client, name, None))]
                if cached:
                    preferred[source_name] = cached
                    labels = self._method_labels(cached)
                    task.log_lines.append(f"[System] {source_name} 复用可用下载源: {', '.join(labels)}")
                    continue
            available_methods = self._detect_available_third_party_methods(
                task,
                music_client,
                source_name,
                raw_search,
                method_names,
            )
            if available_methods:
                self._third_party_health_cache[source_name] = (time.monotonic(), list(available_methods))
                preferred[source_name] = available_methods
        return preferred

    def _candidate_parse_methods(self, music_client: Any, source_name: str) -> tuple[str, ...]:
        """Return parser methods that actually exist on the current upstream client.

        musicdl changes private parser names frequently. The old hard-coded list is
        kept as a preferred order, but we must not keep calling methods removed by
        a newer upstream release.
        """
        preferred = tuple(
            name
            for name in THIRD_PARTY_METHODS.get(source_name, ())
            if callable(getattr(music_client, name, None))
        )
        discovered = discover_parser_methods(music_client)
        if preferred:
            return tuple(dict.fromkeys(preferred))
        return discovered[:8]


    def _first_raw_search_for_source(self, items: list[dict[str, Any]], source_name: str) -> dict[str, Any] | None:
        for item in items:
            if str(item.get("source") or "") != source_name:
                continue
            raw_data = item.get("raw_data")
            raw_search = raw_data.get("search") if isinstance(raw_data, dict) else None
            if isinstance(raw_search, dict):
                return raw_search
        return None

    def _load_cached_third_party_methods(self, source_name: str) -> list[str] | None:
        cached = self._third_party_health_cache.get(source_name)
        if cached is None:
            return None
        checked_at, method_names = cached
        if (time.monotonic() - checked_at) > THIRD_PARTY_HEALTH_CACHE_TTL_SECONDS:
            self._third_party_health_cache.pop(source_name, None)
            return None
        return list(method_names)

    def _detect_available_third_party_methods(
        self,
        task: TaskState,
        music_client: Any,
        source_name: str,
        raw_search: dict[str, Any],
        method_names: tuple[str, ...],
    ) -> list[str]:
        available_methods: list[str] = []
        fallback_methods: list[str] = []
        failed_labels: list[str] = []
        for method_name in method_names:
            song_info, failed = self._call_parse_with_health(music_client, method_name, raw_search)
            if failed:
                failed_labels.append(self._method_label(method_name))
                continue
            if getattr(song_info, "with_valid_download_url", False):
                available_methods.append(method_name)
            else:
                fallback_methods.append(method_name)
        if available_methods:
            task.log_lines.append(
                f"[System] {source_name} 预检测可用下载源: {', '.join(self._method_labels(available_methods))}"
            )
        elif fallback_methods:
            task.log_lines.append(
                f"[System] {source_name} 预检测未拿到直链，保留候选下载源: {', '.join(self._method_labels(fallback_methods))}"
            )
        if failed_labels:
            task.log_lines.append(
                f"[System] {source_name} 已跳过异常下载源: {', '.join(failed_labels)}"
            )
        return available_methods or fallback_methods

    def _resolve_third_party_song_info(
        self,
        task: TaskState,
        music_client: Any,
        raw_search: dict[str, Any],
        preferred_methods: list[str] | None,
    ) -> Any:
        _, _, data_module, _ = _ensure_musicdl_loaded()
        source_name = getattr(music_client, "source", type(music_client).__name__)
        method_names = preferred_methods or list(self._candidate_parse_methods(music_client, source_name))
        for method_name in method_names:
            song_info, failed = self._call_parse_with_health(music_client, method_name, raw_search)
            if failed:
                task.log_lines.append(
                    f"[System] {source_name} 下载源 {self._method_label(method_name)} 调用失败，已跳过。"
                )
                continue
            if getattr(song_info, "with_valid_download_url", False):
                return song_info
        return data_module.SongInfo(source=source_name)

    def _call_parse_with_health(
        self,
        music_client: Any,
        method_name: str,
        raw_search: dict[str, Any],
    ) -> tuple[Any, bool]:
        _, _, data_module, _ = _ensure_musicdl_loaded()
        method = getattr(music_client, method_name, None)
        if method is None:
            return data_module.SongInfo(source=getattr(music_client, "source", type(music_client).__name__)), True
        try:
            song_info = self._call_with_timeout(
                lambda: self._invoke_parse_method(method, music_client, raw_search, {}),
                timeout=PARSE_METHOD_TIMEOUT_SECONDS,
            )
        except Exception:
            return data_module.SongInfo(source=getattr(music_client, "source", type(music_client).__name__)), True
        if song_info is None:
            return data_module.SongInfo(source=getattr(music_client, "source", type(music_client).__name__)), False
        return song_info, False

    @contextlib.contextmanager
    def _fast_audio_link_testing(self, music_client: Any):
        patched_testers: list[tuple[Any, Any]] = []
        for attr_name in ("audio_link_tester", "quark_audio_link_tester"):
            tester = getattr(music_client, attr_name, None)
            if tester is None or not hasattr(tester, "timeout"):
                continue
            patched_testers.append((tester, getattr(tester, "timeout")))
            tester.timeout = FAST_AUDIO_LINK_TEST_TIMEOUT
        try:
            yield
        finally:
            for tester, original_timeout in patched_testers:
                tester.timeout = original_timeout

    def _method_label(self, method_name: str) -> str:
        return THIRD_PARTY_METHOD_LABELS.get(method_name, method_name)

    def _method_labels(self, method_names: list[str]) -> list[str]:
        return [self._method_label(method_name) for method_name in method_names]

    def _call_parse_if_exists(self, music_client: Any, method_name: str, raw_search: dict[str, Any], request_overrides: dict[str, Any], **kwargs: Any) -> Any:
        _, _, data_module, _ = _ensure_musicdl_loaded()
        method = getattr(music_client, method_name, None)
        if method is None:
            return data_module.SongInfo(source=getattr(music_client, "source", type(music_client).__name__))
        try:
            return self._call_with_timeout(
                lambda: self._invoke_parse_method(method, music_client, raw_search, request_overrides, **kwargs),
                timeout=PARSE_METHOD_TIMEOUT_SECONDS,
            )
        except Exception:
            return data_module.SongInfo(source=getattr(music_client, "source", type(music_client).__name__))

    def _seconds_to_hms(self, seconds: int) -> str:
        hours, remainder = divmod(max(0, int(seconds)), 3600)
        minutes, secs = divmod(remainder, 60)
        if hours:
            return f"{hours:02d}:{minutes:02d}:{secs:02d}"
        return f"{minutes:02d}:{secs:02d}"

    def _flatten_search_results(self, results: dict[str, Any]) -> list[dict[str, Any]]:
        _, _, data_module, _ = _ensure_musicdl_loaded()
        flattened: list[dict[str, Any]] = []
        for _, items in results.items():
            if not isinstance(items, list):
                continue
            for item in items:
                if isinstance(item, data_module.SongInfo):
                    flattened.append(self._song_info_to_json(item))
                elif isinstance(item, dict):
                    flattened.append(self._song_info_to_json(data_module.SongInfo.fromdict(item)))
        return flattened

    def _song_info_to_json(self, song_info: Any) -> dict[str, Any]:
        data = song_info.todict()
        save_path = None
        try:
            save_path = getattr(song_info, "_save_path", None) or song_info.save_path
        except Exception:
            save_path = data.get("_save_path")
        return {
            **data,
            "save_path": save_path,
            "with_valid_download_url": song_info.with_valid_download_url,
        }

    def _resolve_playlist_name(self, song_infos: list[Any]) -> str | None:
        for song_info in song_infos:
            try:
                work_dir = getattr(song_info, "work_dir", None)
            except Exception:
                work_dir = None
            if not work_dir:
                continue
            name = Path(str(work_dir)).name.strip()
            if not name:
                continue
            if "playlist-" in name.lower():
                continue
            parts = name.split(" ", 1)
            if len(parts) == 2 and self._looks_like_musicdl_timestamp(parts[0]):
                candidate = parts[1].strip()
                if candidate:
                    return candidate
            return name
        return None

    def _looks_like_musicdl_timestamp(self, value: str) -> bool:
        parts = value.split("-")
        if len(parts) != 6:
            return False
        return all(part.isdigit() for part in parts)

    def _normalize_song_info(self, item: Any) -> dict[str, Any]:
        if not isinstance(item, dict):
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "song_infos 存在非法项。")
        _, _, data_module, _ = _ensure_musicdl_loaded()
        return data_module.SongInfo.fromdict(item).todict()

    def _validate_config(self, config: dict[str, Any]) -> None:
        output_dir = config.get("output_dir")
        if not isinstance(output_dir, str) or not output_dir.strip():
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "output_dir 不能为空。")
        sources = config.get("sources")
        if sources is not None and not isinstance(sources, list):
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "sources 必须是数组。")
        keyword = config.get("keyword")
        if keyword is not None and not isinstance(keyword, str):
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "keyword 必须是字符串。")
        playlist_url = config.get("playlist_url")
        if playlist_url is not None and not isinstance(playlist_url, str):
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "playlist_url 必须是字符串。")

    def _resolve_sources(self, raw_sources: Any) -> list[str]:
        _, sources_module, _, _ = _ensure_musicdl_loaded()
        registered_modules = sources_module.MusicClientBuilder.REGISTERED_MODULES
        if raw_sources is None:
            return [
                "QQMusicClient",
                "NeteaseMusicClient",
                "KugouMusicClient",
                "KuwoMusicClient",
                "MiguMusicClient",
                "QianqianMusicClient",
            ]
        if not isinstance(raw_sources, list) or not raw_sources:
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "sources 不能为空。")
        resolved: list[str] = []
        for item in raw_sources:
            if not isinstance(item, str):
                raise SearchDownloadRuntimeError("INVALID_CONFIG", "sources 存在非法项。")
            source = SOURCE_LABELS.get(item, item)
            if source not in registered_modules:
                raise SearchDownloadRuntimeError("INVALID_CONFIG", f"未知平台: {item}")
            if source not in resolved:
                resolved.append(source)
        return resolved

    def _available_sources(self) -> list[dict[str, str]]:
        _, sources_module, _, _ = _ensure_musicdl_loaded()
        registered_modules = sources_module.MusicClientBuilder.REGISTERED_MODULES
        return [
            {"label": label, "value": value}
            for label, value in SOURCE_LABELS.items()
            if value in registered_modules
        ]

    def _require_panel(self, panel: Any) -> str:
        if not isinstance(panel, str) or panel not in PANELS:
            raise SearchDownloadRuntimeError("INVALID_CONFIG", "panel 不合法。")
        return panel

    def _require_task(self, task_id: Any) -> TaskState:
        if not isinstance(task_id, str) or not task_id:
            raise SearchDownloadRuntimeError("TASK_NOT_FOUND", "task_id 不存在。")
        task = self._tasks.get(task_id)
        if task is None:
            raise SearchDownloadRuntimeError("TASK_NOT_FOUND", "未找到对应 task_id。")
        return task

    def _has_active_task(self, panel: str) -> bool:
        return any(
            task.panel == panel and task.status == "running"
            for task in self._tasks.values()
        )

    def _next_task_id(self, task_type: str) -> str:
        self._task_index += 1
        return f"task_{task_type}_{self._task_index:03d}"

    def _push_event(self, event_name: str, task: TaskState) -> None:
        if event_name not in EVENTS:
            raise SearchDownloadRuntimeError("INTERNAL_ERROR", f"未知 event: {event_name}")
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
        return None
