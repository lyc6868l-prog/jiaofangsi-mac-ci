#![allow(unsafe_op_in_unsafe_fn)]

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::thread;

use crossbeam_channel::{unbounded, Sender};
use czkawka_core::common::model::CheckingMethod;
use czkawka_core::common::progress_data::{CurrentStage, ProgressData};
use czkawka_core::common::tool_data::CommonData;
use czkawka_core::common::traits::Search;
use czkawka_core::tools::same_music::{
    MusicEntry, MusicSimilarity, SameMusic, SameMusicParameters,
};
use pyo3::exceptions::PyRuntimeError;
use pyo3::prelude::*;
use serde::Serialize;

static NEXT_SCAN_TASK_ID: AtomicU64 = AtomicU64::new(1);
static SCAN_TASKS: LazyLock<Mutex<HashMap<String, Arc<ScanTaskHandle>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

#[derive(Serialize)]
struct HealthCheckResponse {
    ok: bool,
    core_version: &'static str,
    capabilities: Vec<&'static str>,
}

#[derive(Clone, Serialize)]
struct ScanGroupEntry {
    path: String,
    name: String,
    size: String,
    is_auto_keep: bool,
    is_selected_to_delete: bool,
}

#[derive(Clone, Serialize)]
struct ScanGroup {
    group_name: String,
    entries: Vec<ScanGroupEntry>,
}

#[derive(Clone, Serialize)]
struct ScanResponse {
    ok: bool,
    duplicate_count: usize,
    groups: Vec<ScanGroup>,
}

#[derive(Serialize)]
struct DeletePathsResponse {
    ok: bool,
    deleted_count: usize,
    move_to_recycle_bin: bool,
}

#[derive(Serialize)]
struct StartScanTaskResponse {
    ok: bool,
    task_id: String,
}

#[derive(Serialize)]
struct StopScanTaskResponse {
    ok: bool,
    accepted: bool,
    task_id: String,
}

#[derive(Serialize)]
struct CleanupScanTaskResponse {
    ok: bool,
    removed: bool,
    task_id: String,
}

#[derive(Serialize)]
struct PollScanTaskResponse {
    ok: bool,
    task_id: String,
    status: String,
    progress: f64,
    progress_hint_text: String,
    result: Option<ScanResponse>,
    error: Option<String>,
}

struct ScanTaskHandle {
    stop_flag: Arc<AtomicBool>,
    state: Mutex<AsyncScanState>,
}

struct AsyncScanState {
    status: String,
    progress: f64,
    progress_hint_text: String,
    result: Option<ScanResponse>,
    error: Option<String>,
}

struct ScanExecutionResult {
    response: ScanResponse,
    stopped: bool,
}

impl AsyncScanState {
    fn running() -> Self {
        Self {
            status: "running".to_string(),
            progress: 0.03,
            progress_hint_text: "正在准备内容比对...".to_string(),
            result: None,
            error: None,
        }
    }
}

fn to_json<T: Serialize>(value: &T) -> PyResult<String> {
    serde_json::to_string(value).map_err(|error| PyRuntimeError::new_err(error.to_string()))
}

fn io_error(message: impl Into<String>) -> PyErr {
    PyRuntimeError::new_err(message.into())
}

fn task_not_found(task_id: &str) -> PyErr {
    io_error(format!("未找到扫描任务: {task_id}"))
}

fn ensure_task_is_terminal(status: &str, task_label: &str) -> PyResult<()> {
    if matches!(status, "success" | "cancelled" | "error") {
        Ok(())
    } else {
        Err(io_error(format!("{task_label}仍在进行中，暂不允许清理。")))
    }
}

#[pyfunction]
fn health_check() -> PyResult<String> {
    to_json(&HealthCheckResponse {
        ok: true,
        core_version: env!("CARGO_PKG_VERSION"),
        capabilities: vec![
            "health_check",
            "scan_music_by_tags",
            "scan_music_by_content",
            "start_scan_music_by_content_task",
            "poll_scan_music_task",
            "stop_scan_music_task",
            "cleanup_scan_music_task",
            "delete_paths",
        ],
    })
}

#[pyfunction]
fn scan_music_by_tags(
    paths: Vec<String>,
    fields: Vec<String>,
    approximate: bool,
) -> PyResult<String> {
    let similarity = music_similarity_from_fields(&fields);
    let result = perform_scan_music(
        paths,
        SameMusicParameters::new(
            similarity,
            approximate,
            CheckingMethod::AudioTags,
            5.0,
            3.0,
            false,
        ),
        None,
        &Arc::new(AtomicBool::new(false)),
    )
    .map_err(io_error)?;
    to_json(&result.response)
}

#[pyfunction]
fn scan_music_by_content(
    paths: Vec<String>,
    compare_similar_titles_only: bool,
) -> PyResult<String> {
    let result = perform_scan_music(
        paths,
        SameMusicParameters::new(
            MusicSimilarity::TRACK_TITLE,
            false,
            CheckingMethod::AudioContent,
            10.0,
            0.2,
            compare_similar_titles_only,
        ),
        None,
        &Arc::new(AtomicBool::new(false)),
    )
    .map_err(io_error)?;
    to_json(&result.response)
}

#[pyfunction]
fn start_scan_music_by_content_task(
    paths: Vec<String>,
    compare_similar_titles_only: bool,
) -> PyResult<String> {
    let task_id = format!(
        "scan_task_{:03}",
        NEXT_SCAN_TASK_ID.fetch_add(1, Ordering::Relaxed)
    );
    let task = Arc::new(ScanTaskHandle {
        stop_flag: Arc::new(AtomicBool::new(false)),
        state: Mutex::new(AsyncScanState::running()),
    });
    SCAN_TASKS
        .lock()
        .map_err(|_| io_error("扫描任务表已损坏"))?
        .insert(task_id.clone(), Arc::clone(&task));

    let progress_task = Arc::clone(&task);
    let stop_flag = Arc::clone(&task.stop_flag);
    let worker_paths = paths;
    thread::spawn(move || {
        let (progress_tx, progress_rx) = unbounded::<ProgressData>();
        let collector_task = Arc::clone(&progress_task);
        thread::spawn(move || {
            for progress in progress_rx {
                if let Ok(mut state) = collector_task.state.lock() {
                    if matches!(state.status.as_str(), "success" | "cancelled" | "error") {
                        continue;
                    }
                    state.progress = progress_value(&progress);
                    state.progress_hint_text = progress_hint_text(&progress);
                }
            }
        });

        let result = perform_scan_music(
            worker_paths,
            SameMusicParameters::new(
                MusicSimilarity::TRACK_TITLE,
                false,
                CheckingMethod::AudioContent,
                10.0,
                0.2,
                compare_similar_titles_only,
            ),
            Some(&progress_tx),
            &stop_flag,
        );
        drop(progress_tx);

        if let Ok(mut state) = progress_task.state.lock() {
            if stop_flag.load(Ordering::Relaxed) {
                state.status = "cancelled".to_string();
                state.progress_hint_text = "任务已由用户手动停止。".to_string();
                state.error = None;
                state.result = None;
                return;
            }
            match result {
                Ok(result) if result.stopped => {
                    state.status = "cancelled".to_string();
                    state.progress_hint_text = "任务已由用户手动停止。".to_string();
                    state.error = None;
                    state.result = None;
                }
                Ok(result) => {
                    let has_groups = !result.response.groups.is_empty();
                    state.status = "success".to_string();
                    state.progress = 1.0;
                    state.progress_hint_text = if has_groups {
                        "发现重复项，请审阅确认。".to_string()
                    } else {
                        "未发现重复项。".to_string()
                    };
                    state.error = None;
                    state.result = Some(result.response);
                }
                Err(error) => {
                    state.status = "error".to_string();
                    state.progress_hint_text = error.clone();
                    state.error = Some(error);
                    state.result = None;
                }
            }
        }
    });

    to_json(&StartScanTaskResponse { ok: true, task_id })
}

#[pyfunction]
fn poll_scan_music_task(task_id: String) -> PyResult<String> {
    let task = SCAN_TASKS
        .lock()
        .map_err(|_| io_error("扫描任务表已损坏"))?
        .get(&task_id)
        .cloned()
        .ok_or_else(|| task_not_found(&task_id))?;
    let state = task
        .state
        .lock()
        .map_err(|_| io_error("扫描任务状态已损坏"))?;
    to_json(&PollScanTaskResponse {
        ok: true,
        task_id,
        status: state.status.clone(),
        progress: state.progress,
        progress_hint_text: state.progress_hint_text.clone(),
        result: state.result.clone(),
        error: state.error.clone(),
    })
}

#[pyfunction]
fn stop_scan_music_task(task_id: String) -> PyResult<String> {
    let task = SCAN_TASKS
        .lock()
        .map_err(|_| io_error("扫描任务表已损坏"))?
        .get(&task_id)
        .cloned()
        .ok_or_else(|| task_not_found(&task_id))?;
    task.stop_flag.store(true, Ordering::Relaxed);
    if let Ok(mut state) = task.state.lock() {
        if !matches!(state.status.as_str(), "success" | "error") {
            state.status = "cancelled".to_string();
            state.progress_hint_text = "任务已由用户手动停止。".to_string();
            state.result = None;
            state.error = None;
        }
    }
    to_json(&StopScanTaskResponse {
        ok: true,
        accepted: true,
        task_id,
    })
}

#[pyfunction]
fn cleanup_scan_music_task(task_id: String) -> PyResult<String> {
    let mut tasks = SCAN_TASKS
        .lock()
        .map_err(|_| io_error("扫描任务表已损坏"))?;
    let task = tasks
        .get(&task_id)
        .cloned()
        .ok_or_else(|| task_not_found(&task_id))?;
    let state = task
        .state
        .lock()
        .map_err(|_| io_error("扫描任务状态已损坏"))?;
    ensure_task_is_terminal(&state.status, "扫描任务")?;
    drop(state);
    tasks.remove(&task_id);
    to_json(&CleanupScanTaskResponse {
        ok: true,
        removed: true,
        task_id,
    })
}

#[pyfunction]
fn delete_paths(paths: Vec<String>, move_to_recycle_bin: bool) -> PyResult<String> {
    for raw_path in &paths {
        let path = PathBuf::from(raw_path);
        if !path.exists() {
            return Err(io_error(format!("文件不存在: {}", path.display())));
        }
        if move_to_recycle_bin {
            move_file_to_trash(&path)?;
        } else {
            fs::remove_file(&path)
                .map_err(|error| io_error(format!("删除失败 {}: {}", path.display(), error)))?;
        }
    }

    to_json(&DeletePathsResponse {
        ok: true,
        deleted_count: paths.len(),
        move_to_recycle_bin,
    })
}

fn perform_scan_music(
    paths: Vec<String>,
    params: SameMusicParameters,
    progress_sender: Option<&Sender<ProgressData>>,
    stop_flag: &Arc<AtomicBool>,
) -> Result<ScanExecutionResult, String> {
    let mut finder = SameMusic::new(params);
    finder.set_included_paths(paths.into_iter().map(PathBuf::from).collect());
    finder.set_recursive_search(true);
    finder.set_use_cache(false);
    finder.search(stop_flag, progress_sender);

    let groups = finder
        .get_duplicated_music_entries()
        .iter()
        .map(|entries| to_scan_group(entries))
        .collect::<Vec<_>>();

    Ok(ScanExecutionResult {
        stopped: finder.get_stopped_search(),
        response: ScanResponse {
            ok: true,
            duplicate_count: groups.len(),
            groups,
        },
    })
}

fn music_similarity_from_fields(fields: &[String]) -> MusicSimilarity {
    let mut similarity = MusicSimilarity::NONE;
    for field in fields {
        match field.as_str() {
            "title" | "track_title" => similarity |= MusicSimilarity::TRACK_TITLE,
            "artist" | "track_artist" => similarity |= MusicSimilarity::TRACK_ARTIST,
            "year" => similarity |= MusicSimilarity::YEAR,
            "length" => similarity |= MusicSimilarity::LENGTH,
            "genre" => similarity |= MusicSimilarity::GENRE,
            "bitrate" => similarity |= MusicSimilarity::BITRATE,
            _ => {}
        }
    }
    if similarity.is_empty() {
        MusicSimilarity::TRACK_TITLE
    } else {
        similarity
    }
}

fn to_scan_group(entries: &[MusicEntry]) -> ScanGroup {
    let auto_keep_path = entries
        .iter()
        .max_by_key(|entry| {
            (
                entry.size,
                std::cmp::Reverse(entry.path.to_string_lossy().len()),
                entry.path.to_string_lossy().to_lowercase(),
            )
        })
        .map(|entry| entry.path.clone());

    let group_name = entries
        .iter()
        .find_map(|entry| {
            if entry.track_title.is_empty() {
                None
            } else {
                Some(entry.track_title.clone())
            }
        })
        .unwrap_or_else(|| {
            entries
                .first()
                .and_then(|entry| entry.path.file_stem())
                .map(|value| value.to_string_lossy().to_string())
                .unwrap_or_else(|| "未命名分组".to_string())
        });

    let mapped_entries = entries
        .iter()
        .map(|entry| {
            let is_auto_keep = auto_keep_path.as_ref() == Some(&entry.path);
            ScanGroupEntry {
                path: entry.path.to_string_lossy().to_string(),
                name: entry
                    .path
                    .file_name()
                    .map(|value| value.to_string_lossy().to_string())
                    .unwrap_or_else(|| entry.path.to_string_lossy().to_string()),
                size: format_size(entry.size),
                is_auto_keep,
                is_selected_to_delete: !is_auto_keep,
            }
        })
        .collect();

    ScanGroup {
        group_name,
        entries: mapped_entries,
    }
}

fn progress_value(progress: &ProgressData) -> f64 {
    let stages = f64::from(progress.max_stage_idx.max(1));
    let completed_stages = f64::from(progress.current_stage_idx.saturating_sub(1));
    let stage_progress = if progress.entries_to_check == 0 {
        0.0
    } else {
        (progress.entries_checked as f64 / progress.entries_to_check as f64).clamp(0.0, 1.0)
    };
    ((completed_stages + stage_progress) / stages).clamp(0.0, 0.99)
}

fn progress_hint_text(progress: &ProgressData) -> String {
    let label = match progress.sstage {
        CurrentStage::CollectingFiles => "正在收集音频文件",
        CurrentStage::SameMusicCacheLoadingTags => "正在加载标签缓存",
        CurrentStage::SameMusicReadingTags => "正在读取音频标签",
        CurrentStage::SameMusicCacheSavingTags => "正在保存标签缓存",
        CurrentStage::SameMusicCacheLoadingFingerprints => "正在加载内容指纹缓存",
        CurrentStage::SameMusicCalculatingFingerprints => "正在计算内容指纹",
        CurrentStage::SameMusicCacheSavingFingerprints => "正在保存内容指纹缓存",
        CurrentStage::SameMusicComparingTags => "正在比对标签",
        CurrentStage::SameMusicComparingFingerprints => "正在比对音频内容",
        _ => "正在执行扫描",
    };
    if progress.entries_to_check == 0 {
        format!("{}...", label)
    } else {
        format!(
            "{}... {}/{}",
            label,
            progress.entries_checked.min(progress.entries_to_check),
            progress.entries_to_check
        )
    }
}

fn move_file_to_trash(path: &Path) -> PyResult<()> {
    let home = std::env::var_os("HOME").ok_or_else(|| io_error("无法确定 HOME 目录"))?;
    let trash_dir = PathBuf::from(home).join(".Trash");
    fs::create_dir_all(&trash_dir).map_err(|error| {
        io_error(format!(
            "无法创建废纸篓目录 {}: {}",
            trash_dir.display(),
            error
        ))
    })?;

    let file_name = path
        .file_name()
        .ok_or_else(|| io_error(format!("无法解析文件名: {}", path.display())))?;
    let target = unique_path(trash_dir.join(file_name));

    match fs::rename(path, &target) {
        Ok(()) => Ok(()),
        Err(error) if error.raw_os_error() == Some(18) => {
            fs::copy(path, &target).map_err(|copy_error| {
                io_error(format!(
                    "移动到废纸篓失败 {} -> {}: {}",
                    path.display(),
                    target.display(),
                    copy_error
                ))
            })?;
            fs::remove_file(path).map_err(|remove_error| {
                io_error(format!(
                    "清理原文件失败 {}: {}",
                    path.display(),
                    remove_error
                ))
            })?;
            Ok(())
        }
        Err(error) => Err(io_error(format!(
            "移动到废纸篓失败 {} -> {}: {}",
            path.display(),
            target.display(),
            error
        ))),
    }
}

fn unique_path(path: PathBuf) -> PathBuf {
    if !path.exists() {
        return path;
    }
    let parent = path.parent().map(Path::to_path_buf).unwrap_or_default();
    let stem = path
        .file_stem()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_default();
    let suffix = path
        .extension()
        .map(|value| format!(".{}", value.to_string_lossy()))
        .unwrap_or_default();
    let mut counter = 1;
    loop {
        let candidate = parent.join(format!("{} ({}){}", stem, counter, suffix));
        if !candidate.exists() {
            return candidate;
        }
        counter += 1;
    }
}

fn format_size(size_bytes: u64) -> String {
    if size_bytes >= 1024 * 1024 {
        format!("{:.1} MB", size_bytes as f64 / (1024.0 * 1024.0))
    } else if size_bytes >= 1024 {
        format!("{:.1} KB", size_bytes as f64 / 1024.0)
    } else {
        format!("{} B", size_bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    use czkawka_core::common::model::{CheckingMethod, ToolType};
    use tempfile::tempdir;

    fn build_music_entry(path: &str, size: u64, title: &str) -> MusicEntry {
        MusicEntry {
            size,
            path: PathBuf::from(path),
            modified_date: 0,
            fingerprint: Vec::new(),
            track_title: title.to_string(),
            track_artist: String::new(),
            year: String::new(),
            length: 0,
            genre: String::new(),
            bitrate: 0,
        }
    }

    #[test]
    fn music_similarity_defaults_to_track_title() {
        let similarity = music_similarity_from_fields(&[]);
        assert_eq!(similarity, MusicSimilarity::TRACK_TITLE);
    }

    #[test]
    fn music_similarity_combines_known_fields() {
        let similarity = music_similarity_from_fields(&[
            "title".to_string(),
            "artist".to_string(),
            "genre".to_string(),
            "unknown".to_string(),
        ]);
        assert!(similarity.contains(MusicSimilarity::TRACK_TITLE));
        assert!(similarity.contains(MusicSimilarity::TRACK_ARTIST));
        assert!(similarity.contains(MusicSimilarity::GENRE));
        assert!(!similarity.contains(MusicSimilarity::YEAR));
    }

    #[test]
    fn to_scan_group_picks_largest_file_as_auto_keep() {
        let group = to_scan_group(&[
            build_music_entry("/tmp/a.mp3", 1024, "Track A"),
            build_music_entry("/tmp/b.mp3", 2048, "Track A"),
        ]);

        assert_eq!(group.group_name, "Track A");
        assert_eq!(group.entries.len(), 2);
        assert_eq!(group.entries[0].name, "a.mp3");
        assert!(!group.entries[0].is_auto_keep);
        assert!(group.entries[0].is_selected_to_delete);
        assert!(group.entries[1].is_auto_keep);
        assert!(!group.entries[1].is_selected_to_delete);
    }

    #[test]
    fn to_scan_group_falls_back_to_file_stem_when_title_missing() {
        let group = to_scan_group(&[build_music_entry("/tmp/fallback_name.mp3", 512, "")]);
        assert_eq!(group.group_name, "fallback_name");
    }

    #[test]
    fn progress_value_uses_stage_and_entry_progress() {
        let progress = ProgressData {
            sstage: CurrentStage::SameMusicReadingTags,
            checking_method: CheckingMethod::AudioTags,
            current_stage_idx: 2,
            max_stage_idx: 4,
            entries_checked: 5,
            entries_to_check: 10,
            bytes_checked: 0,
            bytes_to_check: 0,
            tool_type: ToolType::SameMusic,
        };

        assert_eq!(progress_value(&progress), 0.375);
    }

    #[test]
    fn progress_hint_text_formats_counts() {
        let progress = ProgressData {
            sstage: CurrentStage::SameMusicComparingFingerprints,
            checking_method: CheckingMethod::AudioContent,
            current_stage_idx: 3,
            max_stage_idx: 4,
            entries_checked: 2,
            entries_to_check: 5,
            bytes_checked: 0,
            bytes_to_check: 0,
            tool_type: ToolType::SameMusic,
        };

        assert_eq!(progress_hint_text(&progress), "正在比对音频内容... 2/5");
    }

    #[test]
    fn unique_path_adds_suffix_when_target_exists() {
        let dir = tempdir().expect("create temp dir");
        let path = dir.path().join("track.mp3");
        fs::write(&path, b"first").expect("write source file");

        let candidate = unique_path(path.clone());
        assert_eq!(candidate, dir.path().join("track (1).mp3"));
    }

    #[test]
    fn format_size_covers_bytes_kilobytes_and_megabytes() {
        assert_eq!(format_size(512), "512 B");
        assert_eq!(format_size(1536), "1.5 KB");
        assert_eq!(format_size(2 * 1024 * 1024), "2.0 MB");
    }

    #[test]
    fn cleanup_scan_music_task_removes_terminal_task() {
        let task_id = "scan_task_test_success".to_string();
        SCAN_TASKS.lock().expect("lock tasks").insert(
            task_id.clone(),
            Arc::new(ScanTaskHandle {
                stop_flag: Arc::new(AtomicBool::new(false)),
                state: Mutex::new(AsyncScanState {
                    status: "success".to_string(),
                    progress: 1.0,
                    progress_hint_text: "done".to_string(),
                    result: None,
                    error: None,
                }),
            }),
        );

        let response = cleanup_scan_music_task(task_id.clone()).expect("cleanup task");
        assert!(response.contains("\"removed\":true"));
        assert!(!SCAN_TASKS
            .lock()
            .expect("lock tasks after cleanup")
            .contains_key(&task_id));
    }

    #[test]
    fn cleanup_scan_music_task_rejects_running_task() {
        let task_id = "scan_task_test_running".to_string();
        SCAN_TASKS.lock().expect("lock tasks").insert(
            task_id.clone(),
            Arc::new(ScanTaskHandle {
                stop_flag: Arc::new(AtomicBool::new(false)),
                state: Mutex::new(AsyncScanState::running()),
            }),
        );

        let error = cleanup_scan_music_task(task_id.clone()).expect_err("reject running task");
        assert!(error.to_string().contains("暂不允许清理"));
        assert!(SCAN_TASKS
            .lock()
            .expect("lock tasks after failure")
            .contains_key(&task_id));
        SCAN_TASKS
            .lock()
            .expect("lock tasks for cleanup")
            .remove(&task_id);
    }
}

#[pymodule]
fn dj_scan_core(_py: Python<'_>, module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_function(wrap_pyfunction!(health_check, module)?)?;
    module.add_function(wrap_pyfunction!(scan_music_by_tags, module)?)?;
    module.add_function(wrap_pyfunction!(scan_music_by_content, module)?)?;
    module.add_function(wrap_pyfunction!(start_scan_music_by_content_task, module)?)?;
    module.add_function(wrap_pyfunction!(poll_scan_music_task, module)?)?;
    module.add_function(wrap_pyfunction!(stop_scan_music_task, module)?)?;
    module.add_function(wrap_pyfunction!(cleanup_scan_music_task, module)?)?;
    module.add_function(wrap_pyfunction!(delete_paths, module)?)?;
    Ok(())
}
