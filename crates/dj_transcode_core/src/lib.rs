#![allow(unsafe_op_in_unsafe_fn)]

pub mod audio_probe;
pub mod ffmpeg_builder;
pub mod metadata_edit;
pub mod progress_parser;
pub mod transcode_preset;
pub mod transcode_queue;
pub mod transcode_runner;
pub mod transcode_task;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::thread;

use pyo3::exceptions::PyRuntimeError;
use pyo3::prelude::*;
use serde::Serialize;

pub use audio_probe::{probe_audio_file, AudioProbeConfig, AudioProbeResult};
pub use ffmpeg_builder::{build_ffmpeg_command, build_output_path, FfmpegCommandSpec};
pub use metadata_edit::{
    inject_cover_art, inject_filename_text, scan_audio_targets, MetadataEditResult,
    ScanAudioTargetsResult,
};
pub use progress_parser::{parse_ffmpeg_progress_line, parse_ffmpeg_timestamp, TranscodeProgress};
pub use transcode_preset::{
    AudioChannelMode, AudioOutputFormat, FlacPreset, Mp3Preset, TranscodePreset, WavCodec,
    WavPreset,
};
pub use transcode_queue::{
    TranscodeQueue, TranscodeQueueConfig, TranscodeQueueEvent, TranscodeToolchain,
};
pub use transcode_runner::run_transcode_task;
pub use transcode_task::{
    TranscodeCompletion, TranscodeError, TranscodeTask, TranscodeTaskSnapshot, TranscodeTaskStatus,
};

static NEXT_TRANSCODE_TASK_ID: AtomicU64 = AtomicU64::new(1);
static NEXT_METADATA_EDIT_TASK_ID: AtomicU64 = AtomicU64::new(1);
static TRANSCODE_TASKS: LazyLock<Mutex<HashMap<String, Arc<AsyncTranscodeTaskHandle>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static METADATA_EDIT_TASKS: LazyLock<Mutex<HashMap<String, Arc<AsyncMetadataEditTaskHandle>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

struct AsyncTranscodeTaskHandle {
    cancel_flag: Arc<AtomicBool>,
    state: Mutex<AsyncTranscodeState>,
}

struct AsyncMetadataEditTaskHandle {
    cancel_flag: Arc<AtomicBool>,
    state: Mutex<AsyncMetadataEditState>,
}

#[derive(Serialize)]
struct AsyncTranscodeState {
    status: String,
    progress: f64,
    progress_hint_text: String,
    output_path: Option<String>,
    error: Option<String>,
}

impl AsyncTranscodeState {
    fn running() -> Self {
        Self {
            status: "running".to_string(),
            progress: 0.01,
            progress_hint_text: "正在准备转码任务...".to_string(),
            output_path: None,
            error: None,
        }
    }
}

struct AsyncMetadataEditState {
    status: String,
    progress: f64,
    progress_hint_text: String,
    result: Option<MetadataEditResult>,
    error: Option<String>,
}

impl AsyncMetadataEditState {
    fn running(hint: &str) -> Self {
        Self {
            status: "running".to_string(),
            progress: 0.01,
            progress_hint_text: hint.to_string(),
            result: None,
            error: None,
        }
    }
}

#[derive(Serialize)]
struct HealthCheckResponse {
    ok: bool,
    core_version: &'static str,
    capabilities: Vec<&'static str>,
}

#[derive(Serialize)]
struct BuildPlanResponse {
    ok: bool,
    program: String,
    args: Vec<String>,
    output_path: String,
}

#[derive(Serialize)]
struct StartTaskResponse {
    ok: bool,
    task_id: String,
}

#[derive(Serialize)]
struct StopTaskResponse {
    ok: bool,
    accepted: bool,
    task_id: String,
}

#[derive(Serialize)]
struct CleanupTaskResponse {
    ok: bool,
    removed: bool,
    task_id: String,
}

#[derive(Serialize)]
struct PollTaskResponse {
    ok: bool,
    task_id: String,
    status: String,
    progress: f64,
    progress_hint_text: String,
    output_path: Option<String>,
    error: Option<String>,
}

fn to_json<T: Serialize>(value: &T) -> PyResult<String> {
    serde_json::to_string(value).map_err(|error| PyRuntimeError::new_err(error.to_string()))
}

fn to_py_error(error: impl ToString) -> PyErr {
    PyRuntimeError::new_err(error.to_string())
}

fn ensure_task_is_terminal(status: &str, task_label: &str) -> PyResult<()> {
    if matches!(status, "success" | "cancelled" | "error") {
        Ok(())
    } else {
        Err(to_py_error(format!(
            "{task_label}仍在进行中，暂不允许清理。"
        )))
    }
}

#[pyfunction]
fn health_check() -> PyResult<String> {
    to_json(&HealthCheckResponse {
        ok: true,
        core_version: env!("CARGO_PKG_VERSION"),
        capabilities: vec![
            "health_check",
            "probe_audio_file",
            "build_ffmpeg_plan",
            "start_transcode_task",
            "poll_transcode_task",
            "stop_transcode_task",
            "cleanup_transcode_task",
            "scan_audio_targets",
            "start_filename_injection_task",
            "start_cover_injection_task",
            "poll_metadata_edit_task",
            "stop_metadata_edit_task",
            "cleanup_metadata_edit_task",
        ],
    })
}

#[pyfunction(name = "probe_audio_file")]
#[pyo3(signature = (input_path, ffprobe_path=None))]
fn probe_audio_file_py(input_path: String, ffprobe_path: Option<String>) -> PyResult<String> {
    let input_path = PathBuf::from(input_path);
    let ffprobe_path = PathBuf::from(ffprobe_path.unwrap_or_else(|| "ffprobe".to_string()));
    let result =
        probe_audio_file(input_path.as_path(), ffprobe_path.as_path()).map_err(to_py_error)?;
    to_json(&result)
}

#[pyfunction]
fn scan_audio_targets_py(input_paths: Vec<String>) -> PyResult<String> {
    let result = scan_audio_targets(&input_paths).map_err(to_py_error)?;
    to_json(&result)
}

#[pyfunction]
#[pyo3(signature = (
    input_path,
    output_dir,
    output_format,
    ffmpeg_path=None,
    bitrate_kbps=None,
    sample_rate_hz=None,
    channels=None,
    compression_level=None,
    wav_codec=None,
))]
fn build_ffmpeg_plan(
    input_path: String,
    output_dir: String,
    output_format: String,
    ffmpeg_path: Option<String>,
    bitrate_kbps: Option<u16>,
    sample_rate_hz: Option<u32>,
    channels: Option<String>,
    compression_level: Option<u8>,
    wav_codec: Option<String>,
) -> PyResult<String> {
    let preset = parse_preset(
        &output_format,
        bitrate_kbps,
        sample_rate_hz,
        channels.as_deref(),
        compression_level,
        wav_codec.as_deref(),
    )
    .map_err(to_py_error)?;

    let input_path = PathBuf::from(input_path);
    let output_dir = PathBuf::from(output_dir);
    let ffmpeg_path = PathBuf::from(ffmpeg_path.unwrap_or_else(|| "ffmpeg".to_string()));
    let spec = build_ffmpeg_command(
        ffmpeg_path.as_path(),
        input_path.as_path(),
        output_dir.as_path(),
        &preset,
    )
    .map_err(to_py_error)?;

    to_json(&BuildPlanResponse {
        ok: true,
        program: spec.program.to_string_lossy().to_string(),
        args: spec.args,
        output_path: spec.output_path.to_string_lossy().to_string(),
    })
}

#[pyfunction]
#[pyo3(signature = (
    input_path,
    output_dir,
    output_format,
    ffmpeg_path=None,
    ffprobe_path=None,
    bitrate_kbps=None,
    sample_rate_hz=None,
    channels=None,
    compression_level=None,
    wav_codec=None,
))]
fn start_transcode_task(
    input_path: String,
    output_dir: String,
    output_format: String,
    ffmpeg_path: Option<String>,
    ffprobe_path: Option<String>,
    bitrate_kbps: Option<u16>,
    sample_rate_hz: Option<u32>,
    channels: Option<String>,
    compression_level: Option<u8>,
    wav_codec: Option<String>,
) -> PyResult<String> {
    let task_id = format!(
        "transcode_task_{:03}",
        NEXT_TRANSCODE_TASK_ID.fetch_add(1, Ordering::Relaxed)
    );
    let preset = parse_preset(
        &output_format,
        bitrate_kbps,
        sample_rate_hz,
        channels.as_deref(),
        compression_level,
        wav_codec.as_deref(),
    )
    .map_err(to_py_error)?;
    let task = TranscodeTask {
        id: task_id.clone(),
        input_path: PathBuf::from(input_path),
        output_dir: PathBuf::from(output_dir),
        preset,
    };
    let handle = Arc::new(AsyncTranscodeTaskHandle {
        cancel_flag: Arc::new(AtomicBool::new(false)),
        state: Mutex::new(AsyncTranscodeState::running()),
    });
    TRANSCODE_TASKS
        .lock()
        .map_err(|_| to_py_error("转码任务状态异常，请重新操作。"))?
        .insert(task_id.clone(), Arc::clone(&handle));

    let ffmpeg_path = PathBuf::from(ffmpeg_path.unwrap_or_else(|| "ffmpeg".to_string()));
    let ffprobe_path = PathBuf::from(ffprobe_path.unwrap_or_else(|| "ffprobe".to_string()));
    let cancel_flag = Arc::clone(&handle.cancel_flag);
    thread::spawn(move || {
        let result = run_transcode_task(
            &task,
            ffmpeg_path.as_path(),
            ffprobe_path.as_path(),
            cancel_flag.as_ref(),
            |progress| {
                if let Ok(mut state) = handle.state.lock() {
                    if state.status != "running" {
                        return;
                    }
                    state.progress = progress.percent;
                    state.progress_hint_text = format!(
                        "正在转码... {:.2}s / {}",
                        progress.elapsed_secs,
                        progress
                            .total_secs
                            .map(|value| format!("{value:.2}s"))
                            .unwrap_or_else(|| "unknown".to_string())
                    );
                }
            },
        );

        if let Ok(mut state) = handle.state.lock() {
            if cancel_flag.load(Ordering::Relaxed) {
                state.status = "cancelled".to_string();
                state.progress_hint_text = "任务已由用户手动停止。".to_string();
                state.output_path = None;
                state.error = None;
                return;
            }
            match result {
                Ok(completion) => {
                    state.status = "success".to_string();
                    state.progress = 100.0;
                    state.progress_hint_text = "转码任务执行完毕。".to_string();
                    state.output_path = Some(completion.output_path.to_string_lossy().to_string());
                    state.error = None;
                }
                Err(TranscodeError::Cancelled(_)) => {
                    state.status = "cancelled".to_string();
                    state.progress_hint_text = "任务已由用户手动停止。".to_string();
                    state.output_path = None;
                    state.error = None;
                }
                Err(error) => {
                    state.status = "error".to_string();
                    state.progress_hint_text = error.user_message();
                    state.output_path = None;
                    state.error = Some(error.user_message());
                }
            }
        }
    });

    to_json(&StartTaskResponse { ok: true, task_id })
}

#[pyfunction]
fn poll_transcode_task(task_id: String) -> PyResult<String> {
    let tasks = TRANSCODE_TASKS
        .lock()
        .map_err(|_| to_py_error("transcode task registry is poisoned"))?;
    let handle = tasks
        .get(&task_id)
        .ok_or_else(|| to_py_error(format!("未找到转码任务: {task_id}")))?;
    let state = handle
        .state
        .lock()
        .map_err(|_| to_py_error("转码任务状态异常，请重新操作。"))?;
    to_json(&PollTaskResponse {
        ok: true,
        task_id,
        status: state.status.clone(),
        progress: state.progress,
        progress_hint_text: state.progress_hint_text.clone(),
        output_path: state.output_path.clone(),
        error: state.error.clone(),
    })
}

#[pyfunction]
fn stop_transcode_task(task_id: String) -> PyResult<String> {
    let tasks = TRANSCODE_TASKS
        .lock()
        .map_err(|_| to_py_error("transcode task registry is poisoned"))?;
    let handle = tasks
        .get(&task_id)
        .ok_or_else(|| to_py_error(format!("未找到转码任务: {task_id}")))?;
    handle.cancel_flag.store(true, Ordering::Relaxed);
    if let Ok(mut state) = handle.state.lock() {
        if state.status == "running" {
            state.progress_hint_text = "任务正在停止...".to_string();
        }
    }
    to_json(&StopTaskResponse {
        ok: true,
        accepted: true,
        task_id,
    })
}

#[pyfunction]
fn cleanup_transcode_task(task_id: String) -> PyResult<String> {
    let mut tasks = TRANSCODE_TASKS
        .lock()
        .map_err(|_| to_py_error("transcode task registry is poisoned"))?;
    let handle = tasks
        .get(&task_id)
        .cloned()
        .ok_or_else(|| to_py_error(format!("未找到转码任务: {task_id}")))?;
    let state = handle
        .state
        .lock()
        .map_err(|_| to_py_error("转码任务状态异常，请重新操作。"))?;
    ensure_task_is_terminal(&state.status, "转码任务")?;
    drop(state);
    tasks.remove(&task_id);
    to_json(&CleanupTaskResponse {
        ok: true,
        removed: true,
        task_id,
    })
}

#[derive(Serialize)]
struct StartMetadataEditTaskResponse {
    ok: bool,
    task_id: String,
}

#[derive(Serialize)]
struct PollMetadataEditTaskResponse {
    ok: bool,
    task_id: String,
    status: String,
    progress: f64,
    progress_hint_text: String,
    result: Option<MetadataEditResult>,
    error: Option<String>,
}

#[pyfunction]
#[pyo3(signature = (input_path, append_text, ffmpeg_path=None, ffprobe_path=None))]
fn start_filename_injection_task(
    input_path: String,
    append_text: String,
    ffmpeg_path: Option<String>,
    ffprobe_path: Option<String>,
) -> PyResult<String> {
    let task_id = format!(
        "metadata_edit_task_{:03}",
        NEXT_METADATA_EDIT_TASK_ID.fetch_add(1, Ordering::Relaxed)
    );
    let handle = Arc::new(AsyncMetadataEditTaskHandle {
        cancel_flag: Arc::new(AtomicBool::new(false)),
        state: Mutex::new(AsyncMetadataEditState::running("正在准备文件名注入任务...")),
    });
    METADATA_EDIT_TASKS
        .lock()
        .map_err(|_| to_py_error("信息修改任务状态异常，请重新操作。"))?
        .insert(task_id.clone(), Arc::clone(&handle));

    let input_path = PathBuf::from(input_path);
    let _ffmpeg_path = PathBuf::from(ffmpeg_path.unwrap_or_else(|| "ffmpeg".to_string()));
    let ffprobe_path = PathBuf::from(ffprobe_path.unwrap_or_else(|| "ffprobe".to_string()));
    thread::spawn(move || {
        if let Ok(mut state) = handle.state.lock() {
            state.progress = 15.0;
            state.progress_hint_text = "正在执行文件名注入...".to_string();
        }
        if handle.cancel_flag.load(Ordering::Relaxed) {
            if let Ok(mut state) = handle.state.lock() {
                state.status = "cancelled".to_string();
                state.progress_hint_text = "任务已由用户手动停止。".to_string();
            }
            return;
        }
        let result =
            inject_filename_text(input_path.as_path(), &append_text, ffprobe_path.as_path());
        if let Ok(mut state) = handle.state.lock() {
            match result {
                Ok(result) => {
                    state.status = "success".to_string();
                    state.progress = 100.0;
                    state.progress_hint_text = "文件名注入任务执行完毕。".to_string();
                    state.result = Some(result);
                    state.error = None;
                }
                Err(error) => {
                    let message = error.user_message();
                    state.status = "error".to_string();
                    state.progress_hint_text = message.clone();
                    state.result = None;
                    state.error = Some(message);
                }
            }
        }
    });

    to_json(&StartMetadataEditTaskResponse { ok: true, task_id })
}

#[pyfunction]
#[pyo3(signature = (input_path, cover_image_path, ffmpeg_path=None, ffprobe_path=None))]
fn start_cover_injection_task(
    input_path: String,
    cover_image_path: String,
    ffmpeg_path: Option<String>,
    ffprobe_path: Option<String>,
) -> PyResult<String> {
    let task_id = format!(
        "metadata_edit_task_{:03}",
        NEXT_METADATA_EDIT_TASK_ID.fetch_add(1, Ordering::Relaxed)
    );
    let handle = Arc::new(AsyncMetadataEditTaskHandle {
        cancel_flag: Arc::new(AtomicBool::new(false)),
        state: Mutex::new(AsyncMetadataEditState::running("正在准备封面注入任务...")),
    });
    METADATA_EDIT_TASKS
        .lock()
        .map_err(|_| to_py_error("信息修改任务状态异常，请重新操作。"))?
        .insert(task_id.clone(), Arc::clone(&handle));

    let input_path = PathBuf::from(input_path);
    let cover_image_path = PathBuf::from(cover_image_path);
    let ffmpeg_path = PathBuf::from(ffmpeg_path.unwrap_or_else(|| "ffmpeg".to_string()));
    let ffprobe_path = PathBuf::from(ffprobe_path.unwrap_or_else(|| "ffprobe".to_string()));
    thread::spawn(move || {
        if let Ok(mut state) = handle.state.lock() {
            state.progress = 10.0;
            state.progress_hint_text = "正在执行封面注入...".to_string();
        }
        if handle.cancel_flag.load(Ordering::Relaxed) {
            if let Ok(mut state) = handle.state.lock() {
                state.status = "cancelled".to_string();
                state.progress_hint_text = "任务已由用户手动停止。".to_string();
            }
            return;
        }
        let result = inject_cover_art(
            input_path.as_path(),
            cover_image_path.as_path(),
            ffmpeg_path.as_path(),
            ffprobe_path.as_path(),
        );
        if let Ok(mut state) = handle.state.lock() {
            match result {
                Ok(result) => {
                    state.status = "success".to_string();
                    state.progress = 100.0;
                    state.progress_hint_text = "封面注入任务执行完毕。".to_string();
                    state.result = Some(result);
                    state.error = None;
                }
                Err(error) => {
                    let message = error.user_message();
                    state.status = "error".to_string();
                    state.progress_hint_text = message.clone();
                    state.result = None;
                    state.error = Some(message);
                }
            }
        }
    });

    to_json(&StartMetadataEditTaskResponse { ok: true, task_id })
}

#[pyfunction]
fn poll_metadata_edit_task(task_id: String) -> PyResult<String> {
    let tasks = METADATA_EDIT_TASKS
        .lock()
        .map_err(|_| to_py_error("信息修改任务状态异常，请重新操作。"))?;
    let handle = tasks
        .get(&task_id)
        .ok_or_else(|| to_py_error(format!("未找到信息修改任务: {task_id}")))?;
    let state = handle
        .state
        .lock()
        .map_err(|_| to_py_error("信息修改任务状态异常，请重新操作。"))?;
    to_json(&PollMetadataEditTaskResponse {
        ok: true,
        task_id,
        status: state.status.clone(),
        progress: state.progress,
        progress_hint_text: state.progress_hint_text.clone(),
        result: state.result.as_ref().map(|value| MetadataEditResult {
            ok: value.ok,
            status: value.status.clone(),
            input_path: value.input_path.clone(),
            output_path: value.output_path.clone(),
            changed: value.changed,
            backup_path: value.backup_path.clone(),
            message: value.message.clone(),
        }),
        error: state.error.clone(),
    })
}

#[pyfunction]
fn stop_metadata_edit_task(task_id: String) -> PyResult<String> {
    let tasks = METADATA_EDIT_TASKS
        .lock()
        .map_err(|_| to_py_error("信息修改任务状态异常，请重新操作。"))?;
    let handle = tasks
        .get(&task_id)
        .ok_or_else(|| to_py_error(format!("未找到信息修改任务: {task_id}")))?;
    handle.cancel_flag.store(true, Ordering::Relaxed);
    if let Ok(mut state) = handle.state.lock() {
        if state.status == "running" {
            state.progress_hint_text = "任务正在停止...".to_string();
        }
    }
    to_json(&StopTaskResponse {
        ok: true,
        accepted: true,
        task_id,
    })
}

#[pyfunction]
fn cleanup_metadata_edit_task(task_id: String) -> PyResult<String> {
    let mut tasks = METADATA_EDIT_TASKS
        .lock()
        .map_err(|_| to_py_error("信息修改任务状态异常，请重新操作。"))?;
    let handle = tasks
        .get(&task_id)
        .cloned()
        .ok_or_else(|| to_py_error(format!("未找到信息修改任务: {task_id}")))?;
    let state = handle
        .state
        .lock()
        .map_err(|_| to_py_error("信息修改任务状态异常，请重新操作。"))?;
    ensure_task_is_terminal(&state.status, "信息修改任务")?;
    drop(state);
    tasks.remove(&task_id);
    to_json(&CleanupTaskResponse {
        ok: true,
        removed: true,
        task_id,
    })
}

fn parse_preset(
    output_format: &str,
    bitrate_kbps: Option<u16>,
    sample_rate_hz: Option<u32>,
    channels: Option<&str>,
    compression_level: Option<u8>,
    wav_codec: Option<&str>,
) -> Result<TranscodePreset, String> {
    let channel_mode = parse_channel_mode(channels)?;
    match output_format.trim().to_ascii_lowercase().as_str() {
        "mp3" => Ok(TranscodePreset::Mp3(Mp3Preset {
            bitrate_kbps: bitrate_kbps.unwrap_or(320),
            sample_rate_hz,
            channels: channel_mode,
        })),
        "wav" => Ok(TranscodePreset::Wav(WavPreset {
            codec: parse_wav_codec(wav_codec)?,
            sample_rate_hz,
            channels: channel_mode,
        })),
        "aiff" => Ok(TranscodePreset::Aiff(WavPreset {
            codec: WavCodec::PcmS16Le,
            sample_rate_hz: Some(44_100),
            channels: AudioChannelMode::Stereo,
        })),
        "flac" => Ok(TranscodePreset::Flac(FlacPreset {
            compression_level: compression_level.unwrap_or(5),
            sample_rate_hz,
            channels: channel_mode,
        })),
        other => Err(format!("unsupported output_format: {other}")),
    }
}

fn parse_channel_mode(raw: Option<&str>) -> Result<AudioChannelMode, String> {
    match raw
        .unwrap_or("original")
        .trim()
        .to_ascii_lowercase()
        .as_str()
    {
        "original" => Ok(AudioChannelMode::Original),
        "mono" => Ok(AudioChannelMode::Mono),
        "stereo" => Ok(AudioChannelMode::Stereo),
        other => Err(format!("unsupported channels value: {other}")),
    }
}

fn parse_wav_codec(raw: Option<&str>) -> Result<WavCodec, String> {
    match raw
        .unwrap_or("pcm_s16le")
        .trim()
        .to_ascii_lowercase()
        .as_str()
    {
        "pcm_s16le" => Ok(WavCodec::PcmS16Le),
        other => Err(format!("unsupported wav_codec value: {other}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_preset_forces_cdj_safe_aiff_settings() {
        let preset = parse_preset("aiff", None, Some(48_000), Some("mono"), None, None)
            .expect("aiff preset should parse");

        match preset {
            TranscodePreset::Aiff(config) => {
                assert_eq!(config.sample_rate_hz, Some(44_100));
                assert_eq!(config.channels, AudioChannelMode::Stereo);
            }
            other => panic!("unexpected preset: {other:?}"),
        }
    }

    #[test]
    fn cleanup_transcode_task_removes_terminal_task() {
        let task_id = "transcode_task_test_success".to_string();
        TRANSCODE_TASKS.lock().expect("lock tasks").insert(
            task_id.clone(),
            Arc::new(AsyncTranscodeTaskHandle {
                cancel_flag: Arc::new(AtomicBool::new(false)),
                state: Mutex::new(AsyncTranscodeState {
                    status: "success".to_string(),
                    progress: 100.0,
                    progress_hint_text: "done".to_string(),
                    output_path: None,
                    error: None,
                }),
            }),
        );

        let response = cleanup_transcode_task(task_id.clone()).expect("cleanup task");
        assert!(response.contains("\"removed\":true"));
        assert!(!TRANSCODE_TASKS
            .lock()
            .expect("lock tasks after cleanup")
            .contains_key(&task_id));
    }

    #[test]
    fn cleanup_transcode_task_rejects_running_task() {
        let task_id = "transcode_task_test_running".to_string();
        TRANSCODE_TASKS.lock().expect("lock tasks").insert(
            task_id.clone(),
            Arc::new(AsyncTranscodeTaskHandle {
                cancel_flag: Arc::new(AtomicBool::new(false)),
                state: Mutex::new(AsyncTranscodeState::running()),
            }),
        );

        let error = cleanup_transcode_task(task_id.clone()).expect_err("reject running task");
        assert!(error.to_string().contains("暂不允许清理"));
        assert!(TRANSCODE_TASKS
            .lock()
            .expect("lock tasks after failure")
            .contains_key(&task_id));
        TRANSCODE_TASKS
            .lock()
            .expect("lock tasks for cleanup")
            .remove(&task_id);
    }

    #[test]
    fn cleanup_metadata_edit_task_removes_terminal_task() {
        let task_id = "metadata_edit_task_test_success".to_string();
        METADATA_EDIT_TASKS.lock().expect("lock tasks").insert(
            task_id.clone(),
            Arc::new(AsyncMetadataEditTaskHandle {
                cancel_flag: Arc::new(AtomicBool::new(false)),
                state: Mutex::new(AsyncMetadataEditState {
                    status: "cancelled".to_string(),
                    progress: 100.0,
                    progress_hint_text: "done".to_string(),
                    result: None,
                    error: None,
                }),
            }),
        );

        let response = cleanup_metadata_edit_task(task_id.clone()).expect("cleanup task");
        assert!(response.contains("\"removed\":true"));
        assert!(!METADATA_EDIT_TASKS
            .lock()
            .expect("lock tasks after cleanup")
            .contains_key(&task_id));
    }

    #[test]
    fn cleanup_metadata_edit_task_rejects_running_task() {
        let task_id = "metadata_edit_task_test_running".to_string();
        METADATA_EDIT_TASKS.lock().expect("lock tasks").insert(
            task_id.clone(),
            Arc::new(AsyncMetadataEditTaskHandle {
                cancel_flag: Arc::new(AtomicBool::new(false)),
                state: Mutex::new(AsyncMetadataEditState::running("running")),
            }),
        );

        let error = cleanup_metadata_edit_task(task_id.clone())
            .expect_err("reject running metadata edit task");
        assert!(error.to_string().contains("暂不允许清理"));
        assert!(METADATA_EDIT_TASKS
            .lock()
            .expect("lock tasks after failure")
            .contains_key(&task_id));
        METADATA_EDIT_TASKS
            .lock()
            .expect("lock tasks for cleanup")
            .remove(&task_id);
    }
}

#[pymodule]
fn dj_transcode_core(_py: Python<'_>, module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_function(wrap_pyfunction!(health_check, module)?)?;
    module.add_function(wrap_pyfunction!(probe_audio_file_py, module)?)?;
    module.add_function(wrap_pyfunction!(scan_audio_targets_py, module)?)?;
    module.add_function(wrap_pyfunction!(build_ffmpeg_plan, module)?)?;
    module.add_function(wrap_pyfunction!(start_transcode_task, module)?)?;
    module.add_function(wrap_pyfunction!(poll_transcode_task, module)?)?;
    module.add_function(wrap_pyfunction!(stop_transcode_task, module)?)?;
    module.add_function(wrap_pyfunction!(cleanup_transcode_task, module)?)?;
    module.add_function(wrap_pyfunction!(start_filename_injection_task, module)?)?;
    module.add_function(wrap_pyfunction!(start_cover_injection_task, module)?)?;
    module.add_function(wrap_pyfunction!(poll_metadata_edit_task, module)?)?;
    module.add_function(wrap_pyfunction!(stop_metadata_edit_task, module)?)?;
    module.add_function(wrap_pyfunction!(cleanup_metadata_edit_task, module)?)?;
    Ok(())
}
