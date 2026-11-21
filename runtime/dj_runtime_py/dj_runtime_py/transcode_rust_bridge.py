from __future__ import annotations

import json
from functools import lru_cache
from typing import Any


class TranscodeRustBridgeError(Exception):
    pass


@lru_cache(maxsize=1)
def _load_module():
    try:
        import dj_transcode_core
    except ImportError as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc
    return dj_transcode_core


def health_check() -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.health_check())
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc


def probe_audio_file(input_path: str, ffprobe_path: str | None = None) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.probe_audio_file(input_path, ffprobe_path))
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc


def build_ffmpeg_plan(
    input_path: str,
    output_dir: str,
    output_format: str,
    *,
    ffmpeg_path: str | None = None,
    bitrate_kbps: int | None = None,
    sample_rate_hz: int | None = None,
    channels: str | None = None,
    compression_level: int | None = None,
    wav_codec: str | None = None,
) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(
            module.build_ffmpeg_plan(
                input_path,
                output_dir,
                output_format,
                ffmpeg_path,
                bitrate_kbps,
                sample_rate_hz,
                channels,
                compression_level,
                wav_codec,
            )
        )
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc


def scan_audio_targets(input_paths: list[str]) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.scan_audio_targets_py(input_paths))
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc


def start_transcode_task(
    input_path: str,
    output_dir: str,
    output_format: str,
    *,
    ffmpeg_path: str | None = None,
    ffprobe_path: str | None = None,
    bitrate_kbps: int | None = None,
    sample_rate_hz: int | None = None,
    channels: str | None = None,
    compression_level: int | None = None,
    wav_codec: str | None = None,
) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(
            module.start_transcode_task(
                input_path,
                output_dir,
                output_format,
                ffmpeg_path,
                ffprobe_path,
                bitrate_kbps,
                sample_rate_hz,
                channels,
                compression_level,
                wav_codec,
            )
        )
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc


def poll_transcode_task(task_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.poll_transcode_task(task_id))
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc


def stop_transcode_task(task_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.stop_transcode_task(task_id))
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc


def cleanup_transcode_task(task_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.cleanup_transcode_task(task_id))
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc


def start_filename_injection_task(
    input_path: str,
    append_text: str,
    ffmpeg_path: str | None = None,
    ffprobe_path: str | None = None,
) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(
            module.start_filename_injection_task(
                input_path,
                append_text,
                ffmpeg_path,
                ffprobe_path,
            )
        )
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc


def start_cover_injection_task(
    input_path: str,
    cover_image_path: str,
    ffmpeg_path: str | None = None,
    ffprobe_path: str | None = None,
) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(
            module.start_cover_injection_task(
                input_path,
                cover_image_path,
                ffmpeg_path,
                ffprobe_path,
            )
        )
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc


def poll_metadata_edit_task(task_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.poll_metadata_edit_task(task_id))
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc


def stop_metadata_edit_task(task_id: str) -> dict[str, Any]:
    module = _load_module()
    try:
        return json.loads(module.stop_metadata_edit_task(task_id))
    except Exception as exc:
        raise TranscodeRustBridgeError(str(exc)) from exc
