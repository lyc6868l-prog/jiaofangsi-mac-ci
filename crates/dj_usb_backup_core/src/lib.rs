#![allow(unsafe_op_in_unsafe_fn)]

use std::collections::{HashMap, HashSet};
use std::ffi::OsStr;
use std::fs::{self, File};
use std::io::{self, BufReader, BufWriter, Read, Write};
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

use chrono::Utc;
use filetime::{set_file_mtime, FileTime};
use pyo3::exceptions::PyRuntimeError;
use pyo3::prelude::*;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use walkdir::WalkDir;

static NEXT_TASK_ID: AtomicU64 = AtomicU64::new(1);
static NEXT_TEMP_ID: AtomicU64 = AtomicU64::new(1);
static TASKS: LazyLock<Mutex<HashMap<String, Arc<BackupTaskHandle>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

#[derive(Debug, thiserror::Error)]
enum UsbBackupError {
    #[error("{0}")]
    Message(String),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Walkdir(#[from] walkdir::Error),
}

#[derive(Clone, Serialize, Deserialize)]
struct SnapshotDirectoryEntry {
    relative_path: String,
    modified_at_ms: i64,
}

#[derive(Clone, Serialize, Deserialize)]
struct SnapshotFileEntry {
    relative_path: String,
    object_id: String,
    size_bytes: u64,
    modified_at_ms: i64,
}

#[derive(Clone, Serialize, Deserialize)]
struct RekordboxSummary {
    has_pioneer_dir: bool,
    has_dot_pioneer_dir: bool,
    has_contents_dir: bool,
    has_export_library_db: bool,
    audio_file_count: usize,
    artwork_file_count: usize,
    analysis_file_count: usize,
    playlist_sync_count: usize,
    database_file_count: usize,
    music_bytes: u64,
}

#[derive(Clone, Serialize, Deserialize)]
struct RestoreValidationResult {
    checked_at: String,
    target_root: String,
    files_present_ok: bool,
    rekordbox_layout_ok: bool,
    missing_files: usize,
    mismatched_files: usize,
    message: String,
    rekordbox_summary: RekordboxSummary,
}

#[derive(Clone, Serialize, Deserialize)]
struct SnapshotManifest {
    snapshot_id: String,
    display_name: String,
    created_at: String,
    source_root: String,
    source_volume_name: String,
    source_filesystem: Option<String>,
    source_capacity_bytes: Option<u64>,
    rekordbox_detected: bool,
    validate_status: String,
    rekordbox_summary: RekordboxSummary,
    total_files: usize,
    total_directories: usize,
    total_bytes: u64,
    directories: Vec<SnapshotDirectoryEntry>,
    files: Vec<SnapshotFileEntry>,
}

#[derive(Clone, Serialize, Deserialize)]
struct SnapshotSummary {
    snapshot_id: String,
    display_name: String,
    created_at: String,
    source_volume_name: String,
    source_filesystem: Option<String>,
    source_capacity_bytes: Option<u64>,
    rekordbox_detected: bool,
    validate_status: String,
    rekordbox_summary: RekordboxSummary,
    total_files: usize,
    total_directories: usize,
    total_bytes: u64,
}

#[derive(Clone, Serialize, Deserialize)]
struct PendingCheckpointFileEntry {
    source_path: String,
    relative_path: String,
    size_bytes: u64,
    modified_at_ms: i64,
}

#[derive(Clone, Serialize, Deserialize)]
struct BackupCheckpoint {
    checkpoint_id: String,
    snapshot_id: String,
    display_name: String,
    created_at: String,
    updated_at: String,
    source_root: String,
    source_volume_name: String,
    source_filesystem: Option<String>,
    source_capacity_bytes: Option<u64>,
    rekordbox_detected: bool,
    rekordbox_summary: RekordboxSummary,
    total_files: usize,
    total_directories: usize,
    total_bytes: u64,
    directories: Vec<SnapshotDirectoryEntry>,
    completed_files: Vec<SnapshotFileEntry>,
    pending_files: Vec<PendingCheckpointFileEntry>,
}

#[derive(Clone, Serialize, Deserialize)]
struct PendingBackupSummary {
    checkpoint_id: String,
    snapshot_id: String,
    display_name: String,
    created_at: String,
    updated_at: String,
    source_root: String,
    source_volume_name: String,
    total_files: usize,
    completed_files: usize,
    total_bytes: u64,
    completed_bytes: u64,
    rekordbox_detected: bool,
    rekordbox_summary: RekordboxSummary,
}

#[derive(Serialize)]
struct HealthCheckResponse {
    ok: bool,
    core_version: &'static str,
    capabilities: Vec<&'static str>,
}

#[derive(Serialize)]
struct StartTaskResponse {
    ok: bool,
    task_id: String,
    resumed_from_checkpoint: bool,
    checkpoint_id: Option<String>,
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
    operation: String,
    status: String,
    progress: f64,
    progress_hint_text: String,
    snapshot_id: Option<String>,
    display_name: Option<String>,
    total_files: usize,
    total_bytes: u64,
    restored_files: usize,
    validated_files: usize,
    error: Option<String>,
    resumed_from_checkpoint: bool,
    checkpoint_id: Option<String>,
    restore_validation: Option<RestoreValidationResult>,
}

#[derive(Serialize)]
struct SnapshotListResponse {
    ok: bool,
    snapshots: Vec<SnapshotSummary>,
}

#[derive(Serialize)]
struct DeleteSnapshotResponse {
    ok: bool,
    snapshot_id: String,
    deleted_snapshots: usize,
    deleted_objects: usize,
    deleted_bytes: u64,
}

#[derive(Serialize)]
struct CleanupRepositoryResponse {
    ok: bool,
    deleted_objects: usize,
    deleted_bytes: u64,
}

#[derive(Serialize)]
struct PendingBackupListResponse {
    ok: bool,
    pending_backups: Vec<PendingBackupSummary>,
}

struct BackupTaskHandle {
    cancel_flag: Arc<AtomicBool>,
    state: Mutex<BackupTaskState>,
}

struct BackupTaskState {
    operation: String,
    status: String,
    progress: f64,
    progress_hint_text: String,
    snapshot_id: Option<String>,
    display_name: Option<String>,
    total_files: usize,
    total_bytes: u64,
    restored_files: usize,
    validated_files: usize,
    error: Option<String>,
    resumed_from_checkpoint: bool,
    checkpoint_id: Option<String>,
    restore_validation: Option<RestoreValidationResult>,
}

impl BackupTaskState {
    fn new(operation: &str) -> Self {
        Self {
            operation: operation.to_string(),
            status: "running".to_string(),
            progress: 0.01,
            progress_hint_text: format!("正在准备{}任务...", operation_label(operation)),
            snapshot_id: None,
            display_name: None,
            total_files: 0,
            total_bytes: 0,
            restored_files: 0,
            validated_files: 0,
            error: None,
            resumed_from_checkpoint: false,
            checkpoint_id: None,
            restore_validation: None,
        }
    }
}

struct PendingFileEntry {
    source_path: PathBuf,
    relative_path: String,
    size_bytes: u64,
    modified_at_ms: i64,
}

struct ScannedSource {
    directories: Vec<SnapshotDirectoryEntry>,
    files: Vec<PendingFileEntry>,
    total_bytes: u64,
    rekordbox_detected: bool,
}

fn operation_label(operation: &str) -> &str {
    match operation {
        "backup" => "备份",
        "restore" => "恢复",
        "validate" => "校验",
        _ => "执行",
    }
}

fn to_json<T: Serialize>(value: &T) -> PyResult<String> {
    serde_json::to_string(value).map_err(|error| PyRuntimeError::new_err(error.to_string()))
}

fn to_py_error(error: impl ToString) -> PyErr {
    PyRuntimeError::new_err(error.to_string())
}

fn io_error(message: impl Into<String>) -> UsbBackupError {
    UsbBackupError::Message(message.into())
}

fn humanize_usb_backup_error(error: &UsbBackupError) -> String {
    let message = error.to_string();
    let lower = message.to_lowercase();
    if lower.contains("permission denied") || lower.contains("access is denied") {
        return "磁盘操作被系统拒绝，请检查权限后重试。".to_string();
    }
    if lower.contains("not found") || lower.contains("no such file") {
        return "目标设备或文件不存在，请刷新后重试。".to_string();
    }
    if lower.contains("timed out") || lower.contains("timeout") {
        return "磁盘操作超时，请稍后重试。".to_string();
    }
    if lower.contains("registry poisoned") || lower.contains("state poisoned") {
        return "备份任务状态异常，请重新操作。".to_string();
    }
    message
}

fn should_restart_backup_checkpoint(error: &UsbBackupError) -> bool {
    let message = error.to_string();
    message.contains("检测到备份源内容已变化") || message.contains("断点续备份源文件缺失")
}

fn io_error_with_path(action: &str, path: &Path, error: &io::Error) -> UsbBackupError {
    io_error(format!("{action}失败: {} ({})", path.display(), error))
}

fn repo_snapshots_dir(repo_root: &Path) -> PathBuf {
    repo_root.join("snapshots")
}

fn repo_objects_dir(repo_root: &Path) -> PathBuf {
    repo_root.join("objects")
}

fn repo_tmp_dir(repo_root: &Path) -> PathBuf {
    repo_objects_dir(repo_root).join(".tmp")
}

fn repo_tasks_dir(repo_root: &Path) -> PathBuf {
    repo_root.join("tasks")
}

fn ensure_repo_dirs(repo_root: &Path) -> Result<(), UsbBackupError> {
    fs::create_dir_all(repo_snapshots_dir(repo_root))?;
    fs::create_dir_all(repo_objects_dir(repo_root))?;
    fs::create_dir_all(repo_tmp_dir(repo_root))?;
    fs::create_dir_all(repo_tasks_dir(repo_root))?;
    Ok(())
}

fn object_path(repo_root: &Path, object_id: &str) -> PathBuf {
    let (prefix, suffix) = object_id.split_at(2);
    repo_objects_dir(repo_root).join(prefix).join(suffix)
}

fn snapshot_path(repo_root: &Path, snapshot_id: &str) -> PathBuf {
    repo_snapshots_dir(repo_root).join(format!("{snapshot_id}.json"))
}

fn checkpoint_path(repo_root: &Path, source_root: &Path) -> PathBuf {
    let key = hex::encode(Sha256::digest(source_root.to_string_lossy().as_bytes()));
    repo_tasks_dir(repo_root).join(format!("backup_{key}.json"))
}

fn update_task_state(handle: &Arc<BackupTaskHandle>, update: impl FnOnce(&mut BackupTaskState)) {
    if let Ok(mut state) = handle.state.lock() {
        update(&mut state);
    }
}

fn ensure_task_is_terminal(status: &str) -> PyResult<()> {
    if matches!(status, "success" | "cancelled" | "error") {
        Ok(())
    } else {
        Err(to_py_error("任务仍在进行中，暂不允许清理。"))
    }
}

fn snapshot_summary(manifest: &SnapshotManifest) -> SnapshotSummary {
    SnapshotSummary {
        snapshot_id: manifest.snapshot_id.clone(),
        display_name: manifest.display_name.clone(),
        created_at: manifest.created_at.clone(),
        source_volume_name: manifest.source_volume_name.clone(),
        source_filesystem: manifest.source_filesystem.clone(),
        source_capacity_bytes: manifest.source_capacity_bytes,
        rekordbox_detected: manifest.rekordbox_detected,
        validate_status: manifest.validate_status.clone(),
        rekordbox_summary: manifest.rekordbox_summary.clone(),
        total_files: manifest.total_files,
        total_directories: manifest.total_directories,
        total_bytes: manifest.total_bytes,
    }
}

fn pending_backup_summary(checkpoint: &BackupCheckpoint) -> PendingBackupSummary {
    PendingBackupSummary {
        checkpoint_id: checkpoint.checkpoint_id.clone(),
        snapshot_id: checkpoint.snapshot_id.clone(),
        display_name: checkpoint.display_name.clone(),
        created_at: checkpoint.created_at.clone(),
        updated_at: checkpoint.updated_at.clone(),
        source_root: checkpoint.source_root.clone(),
        source_volume_name: checkpoint.source_volume_name.clone(),
        total_files: checkpoint.total_files,
        completed_files: checkpoint.completed_files.len(),
        total_bytes: checkpoint.total_bytes,
        completed_bytes: checkpoint
            .completed_files
            .iter()
            .map(|item| item.size_bytes)
            .sum(),
        rekordbox_detected: checkpoint.rekordbox_detected,
        rekordbox_summary: checkpoint.rekordbox_summary.clone(),
    }
}

fn system_time_to_unix_ms(value: SystemTime) -> i64 {
    value
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or_default()
}

fn unix_ms_to_file_time(value: i64) -> FileTime {
    let seconds = value.div_euclid(1000);
    let millis = value.rem_euclid(1000);
    FileTime::from_unix_time(seconds, (millis as u32) * 1_000_000)
}

fn lower_path(value: &str) -> String {
    value.replace('\\', "/").to_ascii_lowercase()
}

fn file_name_lower(value: &str) -> String {
    Path::new(value)
        .file_name()
        .and_then(|item| item.to_str())
        .unwrap_or(value)
        .to_ascii_lowercase()
}

fn extension_lower(value: &str) -> Option<String> {
    Path::new(value)
        .extension()
        .and_then(|item| item.to_str())
        .map(|item| item.to_ascii_lowercase())
}

fn summarize_rekordbox_entries(
    directories: &[SnapshotDirectoryEntry],
    files: &[(String, u64)],
) -> RekordboxSummary {
    let mut summary = RekordboxSummary {
        has_pioneer_dir: false,
        has_dot_pioneer_dir: false,
        has_contents_dir: false,
        has_export_library_db: false,
        audio_file_count: 0,
        artwork_file_count: 0,
        analysis_file_count: 0,
        playlist_sync_count: 0,
        database_file_count: 0,
        music_bytes: 0,
    };

    for directory in directories {
        let relative = lower_path(&directory.relative_path);
        if relative == "pioneer" || relative.starts_with("pioneer/") {
            summary.has_pioneer_dir = true;
        }
        if relative == ".pioneer" || relative.starts_with(".pioneer/") {
            summary.has_dot_pioneer_dir = true;
        }
        if relative == "contents" || relative.starts_with("contents/") {
            summary.has_contents_dir = true;
        }
    }

    for (relative_path, size_bytes) in files {
        let relative = lower_path(relative_path);
        let file_name = file_name_lower(relative_path);
        let extension = extension_lower(relative_path);

        if file_name == "exportlibrary.db" {
            summary.has_export_library_db = true;
        }

        match extension.as_deref() {
            Some("mp3" | "wav" | "flac" | "aif" | "aiff" | "m4a" | "aac" | "ogg") => {
                summary.audio_file_count += 1;
                summary.music_bytes = summary.music_bytes.saturating_add(*size_bytes);
            }
            Some("jpg" | "jpeg" | "png" | "bmp" | "gif" | "webp") => {
                summary.artwork_file_count += 1;
            }
            Some("dat" | "ext") => {
                summary.analysis_file_count += 1;
            }
            Some("db" | "sqlite" | "sqlite3") => {
                summary.database_file_count += 1;
            }
            _ => {}
        }

        if file_name.ends_with(".sync") {
            summary.playlist_sync_count += 1;
        }

        if relative.starts_with("contents/") {
            summary.has_contents_dir = true;
        }
        if relative.starts_with("pioneer/") {
            summary.has_pioneer_dir = true;
        }
        if relative.starts_with(".pioneer/") {
            summary.has_dot_pioneer_dir = true;
        }
    }

    summary
}

fn verify_restored_target(
    target_root: &Path,
    manifest: &SnapshotManifest,
    handle: Option<&Arc<BackupTaskHandle>>,
) -> Result<RestoreValidationResult, UsbBackupError> {
    let mut missing_files = 0_usize;
    let mut mismatched_files = 0_usize;
    let mut restored_files = Vec::with_capacity(manifest.files.len());
    let total_files = manifest.files.len().max(1);

    for (index, file_entry) in manifest.files.iter().enumerate() {
        if let Some(handle) = handle {
            if handle.cancel_flag.load(Ordering::Relaxed) {
                return Err(io_error("任务已由用户取消。"));
            }
        }
        let target_path = relative_to_target(target_root, &file_entry.relative_path)?;
        if !target_path.exists() {
            missing_files += 1;
            continue;
        }
        let metadata = fs::metadata(&target_path)
            .map_err(|error| io_error_with_path("读取恢复结果文件信息", &target_path, &error))?;
        if metadata.len() != file_entry.size_bytes {
            mismatched_files += 1;
        } else {
            let actual_hash = hash_file_with_cancel(&target_path, handle)?;
            if actual_hash != file_entry.object_id {
                mismatched_files += 1;
            }
        }
        restored_files.push((file_entry.relative_path.clone(), metadata.len()));
        if let Some(handle) = handle {
            let fraction = ((index + 1) as f64 / total_files as f64).clamp(0.0, 1.0);
            update_task_state(handle, |state| {
                state.progress = 0.95 + (fraction * 0.04);
                state.validated_files = index + 1;
                state.progress_hint_text =
                    format!("正在校验恢复结果... {}/{}", index + 1, manifest.total_files);
            });
        }
    }

    let summary = summarize_rekordbox_entries(&manifest.directories, &restored_files);
    let files_present_ok = missing_files == 0 && mismatched_files == 0;
    let has_layout_marker = summary.has_pioneer_dir
        || summary.has_dot_pioneer_dir
        || summary.has_contents_dir
        || summary.has_export_library_db
        || summary.analysis_file_count > 0
        || summary.playlist_sync_count > 0;
    let rekordbox_layout_ok = if manifest.rekordbox_detected {
        has_layout_marker
    } else {
        true
    };
    let message = if files_present_ok && rekordbox_layout_ok {
        if manifest.rekordbox_detected {
            format!(
                "恢复后校验通过：音频 {} 个，封面 {} 个，分析文件 {} 个。",
                summary.audio_file_count, summary.artwork_file_count, summary.analysis_file_count
            )
        } else {
            "恢复后文件校验通过。".to_string()
        }
    } else if !files_present_ok {
        format!(
            "恢复后校验失败：缺失 {} 个文件，{} 个文件大小不匹配。",
            missing_files, mismatched_files
        )
    } else {
        "恢复后文件已写入，但未检测到完整的 Rekordbox 结构标记。".to_string()
    };

    Ok(RestoreValidationResult {
        checked_at: Utc::now().to_rfc3339(),
        target_root: target_root.to_string_lossy().to_string(),
        files_present_ok,
        rekordbox_layout_ok,
        missing_files,
        mismatched_files,
        message,
        rekordbox_summary: summary,
    })
}

fn normalize_relative_path(path: &Path) -> Result<String, UsbBackupError> {
    let mut parts: Vec<String> = Vec::new();
    for component in path.components() {
        match component {
            Component::Normal(value) => parts.push(value.to_string_lossy().to_string()),
            Component::CurDir => {}
            _ => return Err(io_error("发现不安全的相对路径。")),
        }
    }
    if parts.is_empty() {
        return Err(io_error("相对路径不能为空。"));
    }
    Ok(parts.join("/"))
}

fn relative_to_target(root: &Path, relative_path: &str) -> Result<PathBuf, UsbBackupError> {
    let relative = Path::new(relative_path);
    let mut target = PathBuf::from(root);
    for component in relative.components() {
        match component {
            Component::Normal(value) => target.push(value),
            Component::CurDir => {}
            _ => return Err(io_error("恢复目标包含不安全路径。")),
        }
    }
    Ok(target)
}

fn read_manifest(repo_root: &Path, snapshot_id: &str) -> Result<SnapshotManifest, UsbBackupError> {
    let path = snapshot_path(repo_root, snapshot_id);
    let file =
        File::open(&path).map_err(|error| io_error_with_path("打开备份快照清单", &path, &error))?;
    Ok(serde_json::from_reader(BufReader::new(file))?)
}

fn write_manifest(repo_root: &Path, manifest: &SnapshotManifest) -> Result<(), UsbBackupError> {
    let path = snapshot_path(repo_root, &manifest.snapshot_id);
    let temp_path = path.with_extension("json.tmp");
    let file = File::create(&temp_path)?;
    serde_json::to_writer_pretty(BufWriter::new(file), manifest)?;
    fs::rename(temp_path, path)?;
    Ok(())
}

fn read_checkpoint(
    repo_root: &Path,
    source_root: &Path,
) -> Result<Option<BackupCheckpoint>, UsbBackupError> {
    let path = checkpoint_path(repo_root, source_root);
    if !path.exists() {
        return Ok(None);
    }
    let file = File::open(path)?;
    Ok(Some(serde_json::from_reader(BufReader::new(file))?))
}

fn write_checkpoint(
    repo_root: &Path,
    source_root: &Path,
    checkpoint: &BackupCheckpoint,
) -> Result<(), UsbBackupError> {
    let path = checkpoint_path(repo_root, source_root);
    let temp_path = path.with_extension("json.tmp");
    let file = File::create(&temp_path)?;
    serde_json::to_writer_pretty(BufWriter::new(file), checkpoint)?;
    fs::rename(temp_path, path)?;
    Ok(())
}

fn remove_checkpoint(repo_root: &Path, source_root: &Path) -> Result<(), UsbBackupError> {
    let path = checkpoint_path(repo_root, source_root);
    if path.exists() {
        fs::remove_file(path)?;
    }
    Ok(())
}

fn is_ignored_relative_backup_path(relative: &Path) -> bool {
    let mut components = relative.components();
    let Some(first) = components.next() else {
        return false;
    };
    let Component::Normal(first_name) = first else {
        return false;
    };
    let first_name = first_name.to_string_lossy();
    if first_name.starts_with('.') && first_name.as_ref() != ".PIONEER" {
        return true;
    }
    if matches!(
        first_name.as_ref(),
        ".Spotlight-V100"
            | ".Trashes"
            | ".fseventsd"
            | ".TemporaryItems"
            | ".DocumentRevisions-V100"
            | ".Trash"
            | ".Trash-1000"
            | ".Trash-501"
            | ".VolumeIcon.icns"
            | ".com.apple.timemachine.donotpresent"
            | "System Volume Information"
            | "RECYCLED"
            | "$RECYCLE.BIN"
    ) {
        return true;
    }
    if relative.components().count() == 1 && matches!(first_name.as_ref(), ".DS_Store") {
        return true;
    }
    if let Some(file_name) = relative.file_name().and_then(|value| value.to_str()) {
        if file_name.starts_with("._") {
            return true;
        }
    }
    false
}

fn is_ignored_backup_path(path: &Path, source_root: &Path) -> bool {
    let Ok(relative) = path.strip_prefix(source_root) else {
        return false;
    };
    is_ignored_relative_backup_path(relative)
}

fn scan_source_tree(source_root: &Path) -> Result<ScannedSource, UsbBackupError> {
    if !source_root.exists() {
        return Err(io_error("备份源路径不存在。"));
    }
    if !source_root.is_dir() {
        return Err(io_error("备份源路径必须是文件夹。"));
    }
    let mut directories = Vec::new();
    let mut files = Vec::new();
    let mut total_bytes = 0_u64;

    let walker = WalkDir::new(source_root)
        .sort_by_file_name()
        .into_iter()
        .filter_entry(|entry| !is_ignored_backup_path(entry.path(), source_root));
    for entry in walker {
        let entry = match entry {
            Ok(entry) => entry,
            Err(error) => {
                if error
                    .path()
                    .is_some_and(|path| is_ignored_backup_path(path, source_root))
                {
                    continue;
                }
                return Err(error.into());
            }
        };
        let path = entry.path();
        if path == source_root {
            continue;
        }
        if is_ignored_backup_path(path, source_root) {
            continue;
        }
        let relative = normalize_relative_path(
            path.strip_prefix(source_root)
                .map_err(|_| io_error("无法计算相对路径。"))?,
        )?;
        let metadata = entry.metadata()?;
        let modified_at_ms = system_time_to_unix_ms(metadata.modified().unwrap_or(UNIX_EPOCH));
        if metadata.is_dir() {
            directories.push(SnapshotDirectoryEntry {
                relative_path: relative,
                modified_at_ms,
            });
            continue;
        }
        if metadata.is_file() {
            total_bytes = total_bytes.saturating_add(metadata.len());
            files.push(PendingFileEntry {
                source_path: path.to_path_buf(),
                relative_path: relative,
                size_bytes: metadata.len(),
                modified_at_ms,
            });
        }
    }

    let rekordbox_detected = ["PIONEER", ".PIONEER", "Contents"]
        .iter()
        .any(|name| source_root.join(name).exists());

    Ok(ScannedSource {
        directories,
        files,
        total_bytes,
        rekordbox_detected,
    })
}

#[cfg(test)]
fn hash_file(path: &Path) -> Result<String, UsbBackupError> {
    hash_file_with_cancel(path, None)
}

fn hash_file_with_cancel(
    path: &Path,
    handle: Option<&Arc<BackupTaskHandle>>,
) -> Result<String, UsbBackupError> {
    let mut file = BufReader::new(
        File::open(path).map_err(|error| io_error_with_path("打开校验文件", path, &error))?,
    );
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 1024 * 128];
    loop {
        if let Some(handle) = handle {
            if handle.cancel_flag.load(Ordering::Relaxed) {
                return Err(io_error("任务已由用户取消。"));
            }
        }
        let read = file
            .read(&mut buffer)
            .map_err(|error| io_error_with_path("读取校验文件", path, &error))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hex::encode(hasher.finalize()))
}

fn build_new_checkpoint(
    source_root: &Path,
    display_name: Option<String>,
    source_volume_name: Option<String>,
    source_filesystem: Option<String>,
    source_capacity_bytes: Option<u64>,
    scanned: ScannedSource,
) -> BackupCheckpoint {
    let checkpoint_id = format!("checkpoint_{}", Utc::now().format("%Y%m%dT%H%M%SZ"));
    let snapshot_id = format!("snapshot_{}", Utc::now().format("%Y%m%dT%H%M%SZ"));
    let created_at = Utc::now().to_rfc3339();
    let fallback_name = source_volume_name
        .clone()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| {
            source_root
                .file_name()
                .unwrap_or_else(|| OsStr::new("USB"))
                .to_string_lossy()
                .to_string()
        });
    let final_display_name = display_name
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| {
            format!(
                "{}_{}",
                fallback_name,
                Utc::now().format("%Y-%m-%d %H:%M:%S")
            )
        });
    let mut directories = scanned.directories;
    directories.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    let mut pending_files: Vec<PendingCheckpointFileEntry> = scanned
        .files
        .into_iter()
        .map(|entry| PendingCheckpointFileEntry {
            source_path: entry.source_path.to_string_lossy().to_string(),
            relative_path: entry.relative_path,
            size_bytes: entry.size_bytes,
            modified_at_ms: entry.modified_at_ms,
        })
        .collect();
    pending_files.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    let file_pairs: Vec<(String, u64)> = pending_files
        .iter()
        .map(|entry| (entry.relative_path.clone(), entry.size_bytes))
        .collect();
    let rekordbox_summary = summarize_rekordbox_entries(&directories, &file_pairs);
    BackupCheckpoint {
        checkpoint_id,
        snapshot_id,
        display_name: final_display_name,
        created_at: created_at.clone(),
        updated_at: created_at,
        source_root: source_root.to_string_lossy().to_string(),
        source_volume_name: source_volume_name.unwrap_or(fallback_name),
        source_filesystem,
        source_capacity_bytes,
        rekordbox_detected: scanned.rekordbox_detected,
        rekordbox_summary,
        total_files: pending_files.len(),
        total_directories: directories.len(),
        total_bytes: scanned.total_bytes,
        directories,
        completed_files: Vec::new(),
        pending_files,
    }
}

fn sanitize_checkpoint(
    repo_root: &Path,
    source_root: &Path,
    checkpoint: &mut BackupCheckpoint,
) -> Result<(), UsbBackupError> {
    let mut restored_pending = Vec::new();
    checkpoint.completed_files.retain(|entry| {
        let object_exists = object_path(repo_root, &entry.object_id).exists();
        if !object_exists {
            restored_pending.push(PendingCheckpointFileEntry {
                source_path: source_root
                    .join(&entry.relative_path)
                    .to_string_lossy()
                    .to_string(),
                relative_path: entry.relative_path.clone(),
                size_bytes: entry.size_bytes,
                modified_at_ms: entry.modified_at_ms,
            });
        }
        object_exists
    });
    checkpoint.pending_files.extend(restored_pending);
    checkpoint
        .pending_files
        .sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    let rescanned = scan_source_tree(source_root)?;
    let mut metadata_by_path: HashMap<String, (u64, i64)> = HashMap::new();
    for file in rescanned.files {
        metadata_by_path.insert(file.relative_path, (file.size_bytes, file.modified_at_ms));
    }
    for (relative_path, size_bytes, modified_at_ms) in checkpoint
        .completed_files
        .iter()
        .map(|item| (&item.relative_path, item.size_bytes, item.modified_at_ms))
        .chain(
            checkpoint
                .pending_files
                .iter()
                .map(|item| (&item.relative_path, item.size_bytes, item.modified_at_ms)),
        )
    {
        let Some((current_size, current_mtime)) = metadata_by_path.get(relative_path) else {
            return Err(io_error(
                "检测到备份源内容已变化，无法继续旧断点，请重新发起完整备份。",
            ));
        };
        if *current_size != size_bytes || *current_mtime != modified_at_ms {
            return Err(io_error(
                "检测到备份源内容已变化，无法继续旧断点，请重新发起完整备份。",
            ));
        }
    }
    for entry in &checkpoint.pending_files {
        let path = Path::new(&entry.source_path);
        if !path.exists() {
            return Err(io_error(format!(
                "断点续备份源文件缺失: {}",
                entry.relative_path
            )));
        }
    }
    Ok(())
}

fn checkpoint_to_manifest(checkpoint: BackupCheckpoint) -> SnapshotManifest {
    let mut files = checkpoint.completed_files;
    files.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    SnapshotManifest {
        snapshot_id: checkpoint.snapshot_id,
        display_name: checkpoint.display_name,
        created_at: checkpoint.created_at,
        source_root: checkpoint.source_root,
        source_volume_name: checkpoint.source_volume_name,
        source_filesystem: checkpoint.source_filesystem,
        source_capacity_bytes: checkpoint.source_capacity_bytes,
        rekordbox_detected: checkpoint.rekordbox_detected,
        validate_status: "success".to_string(),
        rekordbox_summary: checkpoint.rekordbox_summary,
        total_files: checkpoint.total_files,
        total_directories: checkpoint.total_directories,
        total_bytes: checkpoint.total_bytes,
        directories: checkpoint.directories,
        files,
    }
}

fn restore_stage_path(target_root: &Path) -> PathBuf {
    let stage_id = NEXT_TEMP_ID.fetch_add(1, Ordering::Relaxed);
    target_root.join(format!(".dj_restore_staging_{stage_id:016}"))
}

fn restore_backup_path(target_root: &Path) -> PathBuf {
    let backup_id = NEXT_TEMP_ID.fetch_add(1, Ordering::Relaxed);
    target_root.join(format!(".dj_restore_backup_{backup_id:016}"))
}

fn move_staged_contents_into_target(
    stage_root: &Path,
    target_root: &Path,
    handle: &Arc<BackupTaskHandle>,
    moved_names: &mut Vec<String>,
) -> Result<(), UsbBackupError> {
    for entry in fs::read_dir(stage_root)? {
        if handle.cancel_flag.load(Ordering::Relaxed) {
            return Err(io_error("任务已由用户取消。"));
        }
        let entry = entry?;
        let entry_name = entry.file_name().to_string_lossy().to_string();
        if is_ignored_relative_backup_path(Path::new(&entry_name)) {
            continue;
        }
        let entry_path = entry.path();
        let target_path = target_root.join(&entry_name);
        if target_path.exists() {
            let metadata = fs::symlink_metadata(&target_path)?;
            if metadata.is_dir() {
                fs::remove_dir_all(&target_path)
                    .map_err(|error| io_error_with_path("删除目标目录", &target_path, &error))?;
            } else {
                fs::remove_file(&target_path)
                    .map_err(|error| io_error_with_path("删除目标文件", &target_path, &error))?;
            }
        }
        fs::rename(&entry_path, &target_path)
            .map_err(|error| io_error_with_path("切换恢复结果到目标路径", &target_path, &error))?;
        moved_names.push(entry_name);
    }
    Ok(())
}

fn remove_target_entries(target_root: &Path, entry_names: &[String]) -> Result<(), UsbBackupError> {
    for name in entry_names {
        let path = target_root.join(name);
        if !path.exists() {
            continue;
        }
        let metadata = fs::symlink_metadata(&path)?;
        if metadata.is_dir() {
            fs::remove_dir_all(&path)
                .map_err(|error| io_error_with_path("删除已切换目录", &path, &error))?;
        } else {
            fs::remove_file(&path)
                .map_err(|error| io_error_with_path("删除已切换文件", &path, &error))?;
        }
    }
    Ok(())
}

fn backup_target_entries(
    target_root: &Path,
    backup_root: &Path,
    entry_names: &[String],
    handle: &Arc<BackupTaskHandle>,
) -> Result<Vec<String>, UsbBackupError> {
    if entry_names.is_empty() {
        return Ok(Vec::new());
    }
    if backup_root.exists() {
        fs::remove_dir_all(backup_root)?;
    }
    fs::create_dir_all(backup_root)?;
    let mut moved_names = Vec::new();
    for name in entry_names {
        if handle.cancel_flag.load(Ordering::Relaxed) {
            return Err(io_error("任务已由用户取消。"));
        }
        let source_path = target_root.join(name);
        if !source_path.exists() {
            continue;
        }
        let backup_path = backup_root.join(name);
        fs::rename(&source_path, &backup_path)
            .map_err(|error| io_error_with_path("暂存目标盘原有内容", &source_path, &error))?;
        moved_names.push(name.clone());
    }
    Ok(moved_names)
}

fn restore_backup_entries(
    backup_root: &Path,
    target_root: &Path,
    entry_names: &[String],
) -> Result<(), UsbBackupError> {
    for name in entry_names {
        let backup_path = backup_root.join(name);
        if !backup_path.exists() {
            continue;
        }
        let target_path = target_root.join(name);
        fs::rename(&backup_path, &target_path)
            .map_err(|error| io_error_with_path("回滚目标盘原有内容", &target_path, &error))?;
    }
    Ok(())
}

fn collect_target_backup_names(
    stage_root: &Path,
    target_root: &Path,
    clear_target: bool,
) -> Result<Vec<String>, UsbBackupError> {
    let mut names = Vec::new();
    let mut seen = HashSet::new();
    if clear_target {
        for entry in fs::read_dir(target_root)? {
            let entry = entry?;
            if is_ignored_backup_path(&entry.path(), target_root) {
                continue;
            }
            let Some(name) = entry.file_name().to_str().map(|value| value.to_string()) else {
                continue;
            };
            if seen.insert(name.clone()) {
                names.push(name);
            }
        }
        return Ok(names);
    }
    for entry in fs::read_dir(stage_root)? {
        let entry = entry?;
        let Some(name) = entry.file_name().to_str().map(|value| value.to_string()) else {
            continue;
        };
        let target_path = target_root.join(&name);
        if is_ignored_backup_path(&target_path, target_root) {
            continue;
        }
        if target_path.exists() && seen.insert(name.clone()) {
            names.push(name);
        }
    }
    Ok(names)
}

fn copy_object_to_target(
    source_object: &Path,
    target_path: &Path,
    display_path: &str,
    file_size: u64,
    restored_bytes: &mut u64,
    total_bytes: u64,
    restored_index: usize,
    total_files: usize,
    handle: &Arc<BackupTaskHandle>,
) -> Result<(), UsbBackupError> {
    let mut reader = BufReader::new(
        File::open(source_object)
            .map_err(|error| io_error_with_path("打开备份对象文件", source_object, &error))?,
    );
    let mut writer = BufWriter::new(
        File::create(target_path)
            .map_err(|error| io_error_with_path("创建恢复目标文件", target_path, &error))?,
    );
    let mut buffer = [0_u8; 1024 * 128];
    let file_start_bytes = *restored_bytes;
    let total_bytes = total_bytes.max(1);
    let mut copied_bytes = 0_u64;

    loop {
        if handle.cancel_flag.load(Ordering::Relaxed) {
            let _ = fs::remove_file(target_path);
            return Err(io_error("任务已由用户取消。"));
        }
        let read = reader
            .read(&mut buffer)
            .map_err(|error| io_error_with_path("读取备份对象文件", source_object, &error))?;
        if read == 0 {
            break;
        }
        writer
            .write_all(&buffer[..read])
            .map_err(|error| io_error_with_path("写入恢复目标文件", target_path, &error))?;
        copied_bytes = copied_bytes.saturating_add(read as u64);
        let current_bytes = file_start_bytes.saturating_add(copied_bytes);
        let fraction = (current_bytes as f64 / total_bytes as f64).clamp(0.0, 1.0);
        update_task_state(handle, |state| {
            state.progress = 0.12 + (fraction * 0.76);
            state.restored_files = restored_index;
            state.progress_hint_text = format!(
                "正在恢复 rekordbox 数据... {}/{} · {}",
                restored_index, total_files, display_path
            );
        });
    }

    writer
        .flush()
        .map_err(|error| io_error_with_path("刷新恢复目标文件", target_path, &error))?;
    *restored_bytes = file_start_bytes.saturating_add(file_size);
    Ok(())
}

fn store_object(
    repo_root: &Path,
    source_path: &Path,
    handle: &Arc<BackupTaskHandle>,
    processed_bytes: &mut u64,
    total_bytes: u64,
) -> Result<String, UsbBackupError> {
    let temp_id = NEXT_TEMP_ID.fetch_add(1, Ordering::Relaxed);
    let temp_path = repo_tmp_dir(repo_root).join(format!("object_{temp_id:016}.part"));
    let mut reader = BufReader::new(File::open(source_path)?);
    let mut writer = BufWriter::new(File::create(&temp_path)?);
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 1024 * 128];

    loop {
        if handle.cancel_flag.load(Ordering::Relaxed) {
            let _ = fs::remove_file(&temp_path);
            return Err(io_error("任务已由用户取消。"));
        }
        let read = reader.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
        writer.write_all(&buffer[..read])?;
        *processed_bytes = processed_bytes.saturating_add(read as u64);
        let fraction = if total_bytes == 0 {
            1.0
        } else {
            (*processed_bytes as f64 / total_bytes as f64).clamp(0.0, 1.0)
        };
        update_task_state(handle, |state| {
            state.progress = 0.1 + (fraction * 0.82);
            state.progress_hint_text = format!(
                "正在编译 rekordbox 文件... {:.0}% · {}",
                (fraction * 100.0).clamp(0.0, 100.0),
                source_path.display()
            );
        });
    }
    writer.flush()?;
    drop(writer);

    let object_id = hex::encode(hasher.finalize());
    let final_path = object_path(repo_root, &object_id);
    if final_path.exists() {
        fs::remove_file(temp_path)?;
        return Ok(object_id);
    }

    if let Some(parent) = final_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::rename(temp_path, final_path)?;
    Ok(object_id)
}

fn create_backup_snapshot(
    repo_root: &Path,
    source_root: &Path,
    display_name: Option<String>,
    source_volume_name: Option<String>,
    source_filesystem: Option<String>,
    source_capacity_bytes: Option<u64>,
    handle: &Arc<BackupTaskHandle>,
) -> Result<(SnapshotManifest, bool, String), UsbBackupError> {
    ensure_repo_dirs(repo_root)?;
    let mut resumed_from_checkpoint = false;
    let mut checkpoint = if let Some(mut existing) = read_checkpoint(repo_root, source_root)? {
        match sanitize_checkpoint(repo_root, source_root, &mut existing) {
            Ok(()) => {
                resumed_from_checkpoint = true;
                existing.updated_at = Utc::now().to_rfc3339();
                existing
            }
            Err(error) if should_restart_backup_checkpoint(&error) => {
                let _ = remove_checkpoint(repo_root, source_root);
                update_task_state(handle, |state| {
                    state.progress = 0.03;
                    state.progress_hint_text =
                        "检测到旧断点已失效，正在重新扫描并发起完整备份...".to_string();
                    state.resumed_from_checkpoint = false;
                    state.checkpoint_id = None;
                });
                let scanned = scan_source_tree(source_root)?;
                build_new_checkpoint(
                    source_root,
                    display_name,
                    source_volume_name,
                    source_filesystem,
                    source_capacity_bytes,
                    scanned,
                )
            }
            Err(error) => return Err(error),
        }
    } else {
        update_task_state(handle, |state| {
            state.progress = 0.03;
            state.progress_hint_text = "正在扫描备份源目录...".to_string();
        });
        let scanned = scan_source_tree(source_root)?;
        build_new_checkpoint(
            source_root,
            display_name,
            source_volume_name,
            source_filesystem,
            source_capacity_bytes,
            scanned,
        )
    };

    update_task_state(handle, |state| {
        state.total_files = checkpoint.total_files;
        state.total_bytes = checkpoint.total_bytes;
        state.snapshot_id = Some(checkpoint.snapshot_id.clone());
        state.display_name = Some(checkpoint.display_name.clone());
        state.resumed_from_checkpoint = resumed_from_checkpoint;
        state.checkpoint_id = Some(checkpoint.checkpoint_id.clone());
        state.progress = if resumed_from_checkpoint { 0.08 } else { 0.06 };
        state.progress_hint_text = if resumed_from_checkpoint {
            format!(
                "检测到未完成备份，继续处理剩余 {} 个文件...",
                checkpoint.pending_files.len()
            )
        } else {
            format!(
                "已扫描 {} 个文件，准备写入对象仓库...",
                checkpoint.total_files
            )
        };
    });

    write_checkpoint(repo_root, source_root, &checkpoint)?;
    let mut processed_bytes: u64 = checkpoint
        .completed_files
        .iter()
        .map(|item| item.size_bytes)
        .sum();
    while let Some(entry) = checkpoint.pending_files.first().cloned() {
        if handle.cancel_flag.load(Ordering::Relaxed) {
            return Err(io_error("任务已由用户取消。"));
        }
        let object_id = store_object(
            repo_root,
            Path::new(&entry.source_path),
            handle,
            &mut processed_bytes,
            checkpoint.total_bytes,
        )?;
        checkpoint.completed_files.push(SnapshotFileEntry {
            relative_path: entry.relative_path,
            object_id,
            size_bytes: entry.size_bytes,
            modified_at_ms: entry.modified_at_ms,
        });
        checkpoint.pending_files.remove(0);
        checkpoint.updated_at = Utc::now().to_rfc3339();
        write_checkpoint(repo_root, source_root, &checkpoint)?;
    }

    update_task_state(handle, |state| {
        state.progress = 0.96;
        state.snapshot_id = Some(checkpoint.snapshot_id.clone());
        state.display_name = Some(checkpoint.display_name.clone());
        state.progress_hint_text = "正在写入快照清单...".to_string();
    });
    let manifest = checkpoint_to_manifest(checkpoint.clone());
    write_manifest(repo_root, &manifest)?;
    remove_checkpoint(repo_root, source_root)?;
    Ok((manifest, resumed_from_checkpoint, checkpoint.checkpoint_id))
}

fn restore_snapshot(
    repo_root: &Path,
    snapshot_id: &str,
    target_root: &Path,
    clear_target: bool,
    handle: &Arc<BackupTaskHandle>,
) -> Result<SnapshotManifest, UsbBackupError> {
    let manifest = read_manifest(repo_root, snapshot_id)?;
    let stage_root = restore_stage_path(target_root);
    let backup_root = restore_backup_path(target_root);
    update_task_state(handle, |state| {
        state.snapshot_id = Some(manifest.snapshot_id.clone());
        state.display_name = Some(manifest.display_name.clone());
        state.total_files = manifest.total_files;
        state.total_bytes = manifest.total_bytes;
        state.progress = 0.05;
        state.progress_hint_text = "正在准备恢复目标目录...".to_string();
    });
    fs::create_dir_all(target_root)
        .map_err(|error| io_error_with_path("创建恢复目标根目录", target_root, &error))?;
    if stage_root.exists() {
        fs::remove_dir_all(&stage_root)
            .map_err(|error| io_error_with_path("清理旧恢复暂存目录", &stage_root, &error))?;
    }
    fs::create_dir_all(&stage_root)
        .map_err(|error| io_error_with_path("创建恢复暂存目录", &stage_root, &error))?;

    let result = (|| -> Result<SnapshotManifest, UsbBackupError> {
        for directory in &manifest.directories {
            let path = relative_to_target(&stage_root, &directory.relative_path)?;
            fs::create_dir_all(&path)
                .map_err(|error| io_error_with_path("创建恢复目录", &path, &error))?;
        }

        let mut restored_bytes = 0_u64;
        for (index, file_entry) in manifest.files.iter().enumerate() {
            if handle.cancel_flag.load(Ordering::Relaxed) {
                return Err(io_error("任务已由用户取消。"));
            }
            let source_object = object_path(repo_root, &file_entry.object_id);
            if !source_object.exists() {
                return Err(io_error(format!("缺少对象文件: {}", file_entry.object_id)));
            }
            let target_path = relative_to_target(&stage_root, &file_entry.relative_path)?;
            if let Some(parent) = target_path.parent() {
                fs::create_dir_all(parent)
                    .map_err(|error| io_error_with_path("创建恢复目标父目录", parent, &error))?;
            }
            copy_object_to_target(
                &source_object,
                &target_path,
                &file_entry.relative_path,
                file_entry.size_bytes,
                &mut restored_bytes,
                manifest.total_bytes,
                index + 1,
                manifest.total_files,
                handle,
            )?;
            set_file_mtime(
                &target_path,
                unix_ms_to_file_time(file_entry.modified_at_ms),
            )
            .map_err(|error| io_error_with_path("设置恢复目标文件时间", &target_path, &error))?;
        }

        for directory in &manifest.directories {
            let path = relative_to_target(&stage_root, &directory.relative_path)?;
            if path.exists() {
                set_file_mtime(&path, unix_ms_to_file_time(directory.modified_at_ms))
                    .map_err(|error| io_error_with_path("设置恢复目录时间", &path, &error))?;
            }
        }

        let restore_validation = verify_restored_target(&stage_root, &manifest, Some(handle))?;
        let validation_failed =
            !restore_validation.files_present_ok || !restore_validation.rekordbox_layout_ok;
        let validation_message = restore_validation.message.clone();
        update_task_state(handle, |state| {
            state.restore_validation = Some(restore_validation);
            state.progress = 0.99;
            state.progress_hint_text = "正在完成恢复切换...".to_string();
        });
        if validation_failed {
            return Err(io_error(validation_message));
        }

        let mut backup_names = collect_target_backup_names(&stage_root, target_root, clear_target)?;
        backup_names.retain(|name| {
            name != stage_root
                .file_name()
                .expect("stage root file name")
                .to_string_lossy()
                .as_ref()
                && name
                    != backup_root
                        .file_name()
                        .expect("backup root file name")
                        .to_string_lossy()
                        .as_ref()
        });
        let moved_backup_names =
            backup_target_entries(target_root, &backup_root, &backup_names, handle)?;
        let mut moved_stage_names = Vec::new();
        if let Err(error) = move_staged_contents_into_target(
            &stage_root,
            target_root,
            handle,
            &mut moved_stage_names,
        ) {
            let _ = remove_target_entries(target_root, &moved_stage_names);
            let _ = restore_backup_entries(&backup_root, target_root, &moved_backup_names);
            return Err(error);
        }
        if backup_root.exists() {
            fs::remove_dir_all(&backup_root)
                .map_err(|error| io_error_with_path("清理恢复回滚目录", &backup_root, &error))?;
        }
        debug_assert!(moved_stage_names.len() <= manifest.directories.len() + manifest.files.len());
        Ok(manifest.clone())
    })();

    let cleanup_result = if stage_root.exists() {
        fs::remove_dir_all(&stage_root)
            .map_err(|error| io_error_with_path("清理恢复暂存目录", &stage_root, &error))
    } else {
        Ok(())
    };

    let backup_cleanup_result = if result.is_ok() && backup_root.exists() {
        fs::remove_dir_all(&backup_root)
            .map_err(|error| io_error_with_path("清理恢复回滚目录", &backup_root, &error))
    } else {
        Ok(())
    };

    match (result, cleanup_result, backup_cleanup_result) {
        (Ok(manifest), Ok(()), Ok(())) => Ok(manifest),
        (Ok(_), Err(error), _) | (Ok(_), _, Err(error)) => Err(error),
        (Err(error), _, _) => Err(error),
    }
}

fn validate_snapshot(
    repo_root: &Path,
    snapshot_id: &str,
    handle: &Arc<BackupTaskHandle>,
) -> Result<SnapshotManifest, UsbBackupError> {
    let mut manifest = read_manifest(repo_root, snapshot_id)?;
    update_task_state(handle, |state| {
        state.snapshot_id = Some(manifest.snapshot_id.clone());
        state.display_name = Some(manifest.display_name.clone());
        state.total_files = manifest.total_files;
        state.total_bytes = manifest.total_bytes;
        state.progress = 0.05;
        state.progress_hint_text = "正在校验对象仓库...".to_string();
    });
    let total_files = manifest.total_files.max(1);
    for (index, file_entry) in manifest.files.iter().enumerate() {
        if handle.cancel_flag.load(Ordering::Relaxed) {
            return Err(io_error("任务已由用户取消。"));
        }
        let object = object_path(repo_root, &file_entry.object_id);
        if !object.exists() {
            manifest.validate_status = "error".to_string();
            write_manifest(repo_root, &manifest)?;
            return Err(io_error(format!("缺少对象文件: {}", file_entry.object_id)));
        }
        let metadata = fs::metadata(&object)?;
        if metadata.len() != file_entry.size_bytes {
            manifest.validate_status = "error".to_string();
            write_manifest(repo_root, &manifest)?;
            return Err(io_error(format!(
                "对象大小不匹配: {}",
                file_entry.relative_path
            )));
        }
        let actual_hash = hash_file_with_cancel(&object, Some(handle))?;
        if actual_hash != file_entry.object_id {
            manifest.validate_status = "error".to_string();
            write_manifest(repo_root, &manifest)?;
            return Err(io_error(format!(
                "对象哈希不匹配: {}",
                file_entry.relative_path
            )));
        }
        let fraction = ((index + 1) as f64 / total_files as f64).clamp(0.0, 1.0);
        update_task_state(handle, |state| {
            state.progress = 0.08 + (fraction * 0.88);
            state.validated_files = index + 1;
            state.progress_hint_text =
                format!("正在校验对象... {}/{}", index + 1, manifest.total_files);
        });
    }
    manifest.validate_status = "success".to_string();
    write_manifest(repo_root, &manifest)?;
    Ok(manifest)
}

fn list_snapshot_summaries(repo_root: &Path) -> Result<Vec<SnapshotSummary>, UsbBackupError> {
    ensure_repo_dirs(repo_root)?;
    let mut snapshots = Vec::new();
    for entry in fs::read_dir(repo_snapshots_dir(repo_root))? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let file = File::open(path)?;
        let manifest: SnapshotManifest = serde_json::from_reader(BufReader::new(file))?;
        snapshots.push(snapshot_summary(&manifest));
    }
    snapshots.sort_by(|left, right| right.created_at.cmp(&left.created_at));
    Ok(snapshots)
}

fn list_pending_backups(repo_root: &Path) -> Result<Vec<PendingBackupSummary>, UsbBackupError> {
    ensure_repo_dirs(repo_root)?;
    let mut pending = Vec::new();
    for entry in fs::read_dir(repo_tasks_dir(repo_root))? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let file = File::open(path)?;
        let checkpoint: BackupCheckpoint = serde_json::from_reader(BufReader::new(file))?;
        pending.push(pending_backup_summary(&checkpoint));
    }
    pending.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
    Ok(pending)
}

fn collect_referenced_object_ids(repo_root: &Path) -> Result<HashSet<String>, UsbBackupError> {
    ensure_repo_dirs(repo_root)?;
    let mut referenced = HashSet::new();

    for entry in fs::read_dir(repo_snapshots_dir(repo_root))? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let file = File::open(path)?;
        let manifest: SnapshotManifest = serde_json::from_reader(BufReader::new(file))?;
        for file_entry in manifest.files {
            referenced.insert(file_entry.object_id);
        }
    }

    for entry in fs::read_dir(repo_tasks_dir(repo_root))? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let file = File::open(path)?;
        let checkpoint: BackupCheckpoint = serde_json::from_reader(BufReader::new(file))?;
        for file_entry in checkpoint.completed_files {
            referenced.insert(file_entry.object_id);
        }
    }

    Ok(referenced)
}

fn cleanup_unreferenced_objects(repo_root: &Path) -> Result<(usize, u64), UsbBackupError> {
    ensure_repo_dirs(repo_root)?;
    let referenced = collect_referenced_object_ids(repo_root)?;
    let objects_root = repo_objects_dir(repo_root);
    let mut deleted_objects = 0_usize;
    let mut deleted_bytes = 0_u64;

    for entry in fs::read_dir(&objects_root)? {
        let entry = entry?;
        let path = entry.path();
        let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
            continue;
        };
        if name == ".tmp" {
            for tmp_entry in fs::read_dir(&path)? {
                let tmp_entry = tmp_entry?;
                let tmp_path = tmp_entry.path();
                let metadata = fs::metadata(&tmp_path)?;
                if metadata.is_file() {
                    deleted_bytes = deleted_bytes.saturating_add(metadata.len());
                    deleted_objects += 1;
                    fs::remove_file(tmp_path)?;
                }
            }
            continue;
        }
        if !path.is_dir() {
            continue;
        }
        for object_entry in fs::read_dir(&path)? {
            let object_entry = object_entry?;
            let object_path = object_entry.path();
            if !object_path.is_file() {
                continue;
            }
            let Some(suffix) = object_path.file_name().and_then(|value| value.to_str()) else {
                continue;
            };
            let object_id = format!("{name}{suffix}");
            if referenced.contains(&object_id) {
                continue;
            }
            let metadata = fs::metadata(&object_path)?;
            deleted_bytes = deleted_bytes.saturating_add(metadata.len());
            deleted_objects += 1;
            fs::remove_file(object_path)?;
        }
        if fs::read_dir(&path)?.next().is_none() {
            fs::remove_dir(path)?;
        }
    }

    let tmp_root = repo_tmp_dir(repo_root);
    if fs::read_dir(&tmp_root)?.next().is_none() {
        fs::create_dir_all(&tmp_root)?;
    }

    Ok((deleted_objects, deleted_bytes))
}

fn delete_snapshot_and_cleanup(
    repo_root: &Path,
    snapshot_id: &str,
) -> Result<(usize, usize, u64), UsbBackupError> {
    ensure_repo_dirs(repo_root)?;
    let path = snapshot_path(repo_root, snapshot_id);
    if !path.exists() {
        return Err(io_error("未找到指定备份版本。"));
    }
    fs::remove_file(path)?;
    let (deleted_objects, deleted_bytes) = cleanup_unreferenced_objects(repo_root)?;
    Ok((1, deleted_objects, deleted_bytes))
}

fn spawn_task(
    operation: &str,
    worker: impl FnOnce(Arc<BackupTaskHandle>) + Send + 'static,
) -> String {
    let task_id = format!(
        "usb_backup_task_{:03}",
        NEXT_TASK_ID.fetch_add(1, Ordering::Relaxed)
    );
    let handle = Arc::new(BackupTaskHandle {
        cancel_flag: Arc::new(AtomicBool::new(false)),
        state: Mutex::new(BackupTaskState::new(operation)),
    });
    TASKS
        .lock()
        .expect("usb backup task registry poisoned")
        .insert(task_id.clone(), Arc::clone(&handle));
    thread::spawn(move || worker(handle));
    task_id
}

#[pyfunction]
fn health_check() -> PyResult<String> {
    to_json(&HealthCheckResponse {
        ok: true,
        core_version: env!("CARGO_PKG_VERSION"),
        capabilities: vec![
            "health_check",
            "start_backup_task",
            "start_restore_task",
            "start_validate_task",
            "poll_usb_backup_task",
            "stop_usb_backup_task",
            "cleanup_usb_backup_task",
            "list_snapshots",
            "list_pending_backups",
            "delete_snapshot",
            "cleanup_repository",
        ],
    })
}

#[pyfunction]
#[pyo3(signature = (
    repo_root,
    source_root,
    display_name=None,
    source_volume_name=None,
    source_filesystem=None,
    source_capacity_bytes=None,
))]
fn start_backup_task(
    repo_root: String,
    source_root: String,
    display_name: Option<String>,
    source_volume_name: Option<String>,
    source_filesystem: Option<String>,
    source_capacity_bytes: Option<u64>,
) -> PyResult<String> {
    let repo_root = PathBuf::from(repo_root);
    let source_root = PathBuf::from(source_root);
    let resumed_from_checkpoint = read_checkpoint(&repo_root, &source_root)
        .map_err(to_py_error)?
        .is_some();
    let task_id = spawn_task("backup", move |handle| {
        let result = create_backup_snapshot(
            &repo_root,
            &source_root,
            display_name,
            source_volume_name,
            source_filesystem,
            source_capacity_bytes,
            &handle,
        );
        match result {
            Ok((manifest, resumed_from_checkpoint, checkpoint_id)) => {
                update_task_state(&handle, |state| {
                    state.status = "success".to_string();
                    state.progress = 1.0;
                    state.snapshot_id = Some(manifest.snapshot_id.clone());
                    state.display_name = Some(manifest.display_name.clone());
                    state.total_files = manifest.total_files;
                    state.total_bytes = manifest.total_bytes;
                    state.resumed_from_checkpoint = resumed_from_checkpoint;
                    state.checkpoint_id = Some(checkpoint_id.clone());
                    state.progress_hint_text = "备份完成。".to_string();
                })
            }
            Err(_error) if handle.cancel_flag.load(Ordering::Relaxed) => {
                update_task_state(&handle, |state| {
                    state.status = "cancelled".to_string();
                    state.progress_hint_text = "任务已由用户手动停止。".to_string();
                });
            }
            Err(error) => update_task_state(&handle, |state| {
                let message = humanize_usb_backup_error(&error);
                state.status = "error".to_string();
                state.error = Some(message.clone());
                state.progress_hint_text = message;
            }),
        }
    });
    to_json(&StartTaskResponse {
        ok: true,
        task_id,
        resumed_from_checkpoint,
        checkpoint_id: None,
    })
}

#[pyfunction]
#[pyo3(signature = (repo_root, snapshot_id, target_root, clear_target=true))]
fn start_restore_task(
    repo_root: String,
    snapshot_id: String,
    target_root: String,
    clear_target: bool,
) -> PyResult<String> {
    let repo_root = PathBuf::from(repo_root);
    let target_root = PathBuf::from(target_root);
    let task_id = spawn_task("restore", move |handle| {
        let result = restore_snapshot(
            &repo_root,
            &snapshot_id,
            &target_root,
            clear_target,
            &handle,
        );
        match result {
            Ok(manifest) => update_task_state(&handle, |state| {
                state.status = "success".to_string();
                state.progress = 1.0;
                state.snapshot_id = Some(manifest.snapshot_id.clone());
                state.display_name = Some(manifest.display_name.clone());
                state.restored_files = manifest.total_files;
                state.total_files = manifest.total_files;
                state.total_bytes = manifest.total_bytes;
                state.progress_hint_text = "恢复完成。".to_string();
            }),
            Err(_error) if handle.cancel_flag.load(Ordering::Relaxed) => {
                update_task_state(&handle, |state| {
                    state.status = "cancelled".to_string();
                    state.progress_hint_text = "任务已由用户手动停止。".to_string();
                });
            }
            Err(error) => update_task_state(&handle, |state| {
                let message = humanize_usb_backup_error(&error);
                state.status = "error".to_string();
                state.error = Some(message.clone());
                state.progress_hint_text = message;
            }),
        }
    });
    to_json(&StartTaskResponse {
        ok: true,
        task_id,
        resumed_from_checkpoint: false,
        checkpoint_id: None,
    })
}

#[pyfunction]
fn start_validate_task(repo_root: String, snapshot_id: String) -> PyResult<String> {
    let repo_root = PathBuf::from(repo_root);
    let task_id = spawn_task("validate", move |handle| {
        let result = validate_snapshot(&repo_root, &snapshot_id, &handle);
        match result {
            Ok(manifest) => update_task_state(&handle, |state| {
                state.status = "success".to_string();
                state.progress = 1.0;
                state.snapshot_id = Some(manifest.snapshot_id.clone());
                state.display_name = Some(manifest.display_name.clone());
                state.validated_files = manifest.total_files;
                state.total_files = manifest.total_files;
                state.total_bytes = manifest.total_bytes;
                state.progress_hint_text = "校验完成。".to_string();
            }),
            Err(_error) if handle.cancel_flag.load(Ordering::Relaxed) => {
                update_task_state(&handle, |state| {
                    state.status = "cancelled".to_string();
                    state.progress_hint_text = "任务已由用户手动停止。".to_string();
                });
            }
            Err(error) => update_task_state(&handle, |state| {
                let message = humanize_usb_backup_error(&error);
                state.status = "error".to_string();
                state.error = Some(message.clone());
                state.progress_hint_text = message;
            }),
        }
    });
    to_json(&StartTaskResponse {
        ok: true,
        task_id,
        resumed_from_checkpoint: false,
        checkpoint_id: None,
    })
}

#[pyfunction]
fn poll_usb_backup_task(task_id: String) -> PyResult<String> {
    let tasks = TASKS
        .lock()
        .map_err(|_| to_py_error("备份任务状态异常，请重新操作。"))?;
    let handle = tasks
        .get(&task_id)
        .ok_or_else(|| to_py_error(format!("未找到任务: {task_id}")))?;
    let state = handle
        .state
        .lock()
        .map_err(|_| to_py_error("备份任务状态异常，请重新操作。"))?;
    to_json(&PollTaskResponse {
        ok: true,
        task_id,
        operation: state.operation.clone(),
        status: state.status.clone(),
        progress: state.progress,
        progress_hint_text: state.progress_hint_text.clone(),
        snapshot_id: state.snapshot_id.clone(),
        display_name: state.display_name.clone(),
        total_files: state.total_files,
        total_bytes: state.total_bytes,
        restored_files: state.restored_files,
        validated_files: state.validated_files,
        error: state.error.clone(),
        resumed_from_checkpoint: state.resumed_from_checkpoint,
        checkpoint_id: state.checkpoint_id.clone(),
        restore_validation: state.restore_validation.clone(),
    })
}

#[pyfunction]
fn stop_usb_backup_task(task_id: String) -> PyResult<String> {
    let tasks = TASKS
        .lock()
        .map_err(|_| to_py_error("备份任务状态异常，请重新操作。"))?;
    let handle = tasks
        .get(&task_id)
        .ok_or_else(|| to_py_error(format!("未找到任务: {task_id}")))?;
    handle.cancel_flag.store(true, Ordering::Relaxed);
    to_json(&StopTaskResponse {
        ok: true,
        accepted: true,
        task_id,
    })
}

#[pyfunction]
fn cleanup_usb_backup_task(task_id: String) -> PyResult<String> {
    let mut tasks = TASKS
        .lock()
        .map_err(|_| to_py_error("备份任务状态异常，请重新操作。"))?;
    let handle = tasks
        .get(&task_id)
        .cloned()
        .ok_or_else(|| to_py_error(format!("未找到任务: {task_id}")))?;
    let state = handle
        .state
        .lock()
        .map_err(|_| to_py_error("备份任务状态异常，请重新操作。"))?;
    ensure_task_is_terminal(&state.status)?;
    drop(state);
    tasks.remove(&task_id);
    to_json(&CleanupTaskResponse {
        ok: true,
        removed: true,
        task_id,
    })
}

#[pyfunction]
fn list_snapshots(repo_root: String) -> PyResult<String> {
    let repo_root = PathBuf::from(repo_root);
    let snapshots = list_snapshot_summaries(&repo_root).map_err(to_py_error)?;
    to_json(&SnapshotListResponse {
        ok: true,
        snapshots,
    })
}

#[pyfunction]
fn list_pending_backups_py(repo_root: String) -> PyResult<String> {
    let repo_root = PathBuf::from(repo_root);
    let pending_backups = list_pending_backups(&repo_root).map_err(to_py_error)?;
    to_json(&PendingBackupListResponse {
        ok: true,
        pending_backups,
    })
}

#[pyfunction]
fn delete_snapshot(repo_root: String, snapshot_id: String) -> PyResult<String> {
    let repo_root = PathBuf::from(repo_root);
    let (deleted_snapshots, deleted_objects, deleted_bytes) =
        delete_snapshot_and_cleanup(&repo_root, &snapshot_id).map_err(to_py_error)?;
    to_json(&DeleteSnapshotResponse {
        ok: true,
        snapshot_id,
        deleted_snapshots,
        deleted_objects,
        deleted_bytes,
    })
}

#[pyfunction]
fn cleanup_repository(repo_root: String) -> PyResult<String> {
    let repo_root = PathBuf::from(repo_root);
    let (deleted_objects, deleted_bytes) =
        cleanup_unreferenced_objects(&repo_root).map_err(to_py_error)?;
    to_json(&CleanupRepositoryResponse {
        ok: true,
        deleted_objects,
        deleted_bytes,
    })
}

#[pymodule]
fn dj_usb_backup_core(_py: Python<'_>, module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_function(wrap_pyfunction!(health_check, module)?)?;
    module.add_function(wrap_pyfunction!(start_backup_task, module)?)?;
    module.add_function(wrap_pyfunction!(start_restore_task, module)?)?;
    module.add_function(wrap_pyfunction!(start_validate_task, module)?)?;
    module.add_function(wrap_pyfunction!(poll_usb_backup_task, module)?)?;
    module.add_function(wrap_pyfunction!(stop_usb_backup_task, module)?)?;
    module.add_function(wrap_pyfunction!(cleanup_usb_backup_task, module)?)?;
    module.add_function(wrap_pyfunction!(list_snapshots, module)?)?;
    module.add_function(wrap_pyfunction!(list_pending_backups_py, module)?)?;
    module.add_function(wrap_pyfunction!(delete_snapshot, module)?)?;
    module.add_function(wrap_pyfunction!(cleanup_repository, module)?)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        cleanup_unreferenced_objects, cleanup_usb_backup_task, create_backup_snapshot,
        delete_snapshot_and_cleanup, hash_file, list_pending_backups, list_snapshot_summaries,
        object_path, restore_snapshot, scan_source_tree, summarize_rekordbox_entries,
        validate_snapshot, verify_restored_target, write_checkpoint, write_manifest,
        BackupCheckpoint, PendingCheckpointFileEntry, SnapshotDirectoryEntry, TASKS,
    };
    use sha2::Digest;
    use std::fs;
    use std::sync::atomic::AtomicBool;
    use std::sync::{Arc, Mutex};
    use tempfile::tempdir;

    use super::{BackupTaskHandle, BackupTaskState, SnapshotFileEntry, SnapshotManifest};

    fn empty_rekordbox_summary() -> super::RekordboxSummary {
        let directories: Vec<SnapshotDirectoryEntry> = Vec::new();
        let files: Vec<(String, u64)> = Vec::new();
        summarize_rekordbox_entries(directories.as_slice(), files.as_slice())
    }

    fn test_handle() -> Arc<BackupTaskHandle> {
        Arc::new(BackupTaskHandle {
            cancel_flag: Arc::new(AtomicBool::new(false)),
            state: Mutex::new(BackupTaskState::new("validate")),
        })
    }

    #[test]
    fn scan_source_tree_detects_rekordbox_layout() {
        let dir = tempdir().expect("tempdir");
        fs::create_dir_all(dir.path().join("PIONEER")).expect("create pioneer");
        fs::write(dir.path().join("demo.txt"), b"demo").expect("write file");

        let scanned = scan_source_tree(dir.path()).expect("scan");
        assert!(scanned.rekordbox_detected);
        assert_eq!(scanned.files.len(), 1);
    }

    #[test]
    fn scan_source_tree_ignores_system_artifacts() {
        let dir = tempdir().expect("tempdir");
        fs::create_dir_all(dir.path().join("PIONEER")).expect("create pioneer");
        fs::create_dir_all(dir.path().join(".Spotlight-V100")).expect("spotlight");
        fs::create_dir_all(dir.path().join("$RECYCLE.BIN")).expect("recycle bin");
        fs::write(dir.path().join("demo.txt"), b"demo").expect("write file");
        fs::write(dir.path().join(".DS_Store"), b"ds").expect("write ds store");
        fs::write(dir.path().join("._demo.txt"), b"apple double").expect("write apple double");

        let scanned = scan_source_tree(dir.path()).expect("scan");

        assert_eq!(scanned.files.len(), 1);
        assert_eq!(scanned.files[0].relative_path, "demo.txt");
        assert!(scanned
            .directories
            .iter()
            .all(|entry| !entry.relative_path.starts_with(".Spotlight-V100")));
    }

    #[test]
    fn list_snapshot_summaries_reads_snapshot_files() {
        let dir = tempdir().expect("tempdir");
        fs::create_dir_all(dir.path().join("snapshots")).expect("snapshots");
        fs::create_dir_all(dir.path().join("objects")).expect("objects");
        let manifest = SnapshotManifest {
            snapshot_id: "snapshot_test".to_string(),
            display_name: "测试备份".to_string(),
            created_at: "2026-04-07T10:00:00Z".to_string(),
            source_root: "/Volumes/Test".to_string(),
            source_volume_name: "Test".to_string(),
            source_filesystem: Some("exfat".to_string()),
            source_capacity_bytes: Some(1024),
            rekordbox_detected: true,
            validate_status: "success".to_string(),
            rekordbox_summary: empty_rekordbox_summary(),
            total_files: 1,
            total_directories: 0,
            total_bytes: 4,
            directories: Vec::new(),
            files: Vec::new(),
        };
        write_manifest(dir.path(), &manifest).expect("write manifest");
        let summaries = list_snapshot_summaries(dir.path()).expect("list");
        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].display_name, "测试备份");
    }

    #[test]
    fn validate_snapshot_detects_missing_object() {
        let dir = tempdir().expect("tempdir");
        fs::create_dir_all(dir.path().join("snapshots")).expect("snapshots");
        fs::create_dir_all(dir.path().join("objects")).expect("objects");
        let manifest = SnapshotManifest {
            snapshot_id: "snapshot_test".to_string(),
            display_name: "测试备份".to_string(),
            created_at: "2026-04-07T10:00:00Z".to_string(),
            source_root: "/Volumes/Test".to_string(),
            source_volume_name: "Test".to_string(),
            source_filesystem: Some("exfat".to_string()),
            source_capacity_bytes: Some(1024),
            rekordbox_detected: true,
            validate_status: "success".to_string(),
            rekordbox_summary: empty_rekordbox_summary(),
            total_files: 1,
            total_directories: 0,
            total_bytes: 4,
            directories: Vec::new(),
            files: vec![SnapshotFileEntry {
                relative_path: "demo.txt".to_string(),
                object_id: "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
                    .to_string(),
                size_bytes: 4,
                modified_at_ms: 0,
            }],
        };
        write_manifest(dir.path(), &manifest).expect("write manifest");
        let result = validate_snapshot(dir.path(), "snapshot_test", &test_handle());
        assert!(result.is_err());
        assert!(!object_path(dir.path(), &manifest.files[0].object_id).exists());
    }

    #[test]
    fn create_backup_snapshot_resumes_from_checkpoint() {
        let dir = tempdir().expect("tempdir");
        fs::create_dir_all(dir.path().join("snapshots")).expect("snapshots");
        fs::create_dir_all(dir.path().join("objects")).expect("objects");
        fs::create_dir_all(dir.path().join("tasks")).expect("tasks");
        let source_root = dir.path().join("USB");
        fs::create_dir_all(source_root.join("PIONEER")).expect("pioneer");
        let first = source_root.join("A.mp3");
        let second = source_root.join("B.mp3");
        fs::write(&first, b"first-demo").expect("write first");
        fs::write(&second, b"second-demo").expect("write second");
        let first_metadata = fs::metadata(&first).expect("first metadata");
        let second_metadata = fs::metadata(&second).expect("second metadata");
        let pioneer_metadata = fs::metadata(source_root.join("PIONEER")).expect("dir metadata");
        let first_mtime =
            super::system_time_to_unix_ms(first_metadata.modified().expect("first modified"));
        let second_mtime =
            super::system_time_to_unix_ms(second_metadata.modified().expect("second modified"));
        let pioneer_mtime =
            super::system_time_to_unix_ms(pioneer_metadata.modified().expect("dir modified"));

        let first_hash = hash_file(&first).expect("hash first");
        let first_object = object_path(dir.path(), &first_hash);
        fs::create_dir_all(first_object.parent().expect("object parent")).expect("mkdir object");
        fs::copy(&first, &first_object).expect("copy object");

        let checkpoint = BackupCheckpoint {
            checkpoint_id: "checkpoint_test".to_string(),
            snapshot_id: "snapshot_resume".to_string(),
            display_name: "断点续传测试".to_string(),
            created_at: "2026-04-07T10:00:00Z".to_string(),
            updated_at: "2026-04-07T10:05:00Z".to_string(),
            source_root: source_root.to_string_lossy().to_string(),
            source_volume_name: "PIONEER".to_string(),
            source_filesystem: Some("exfat".to_string()),
            source_capacity_bytes: Some(1024),
            rekordbox_detected: true,
            rekordbox_summary: empty_rekordbox_summary(),
            total_files: 2,
            total_directories: 1,
            total_bytes: first_metadata.len() + second_metadata.len(),
            directories: vec![SnapshotDirectoryEntry {
                relative_path: "PIONEER".to_string(),
                modified_at_ms: pioneer_mtime,
            }],
            completed_files: vec![SnapshotFileEntry {
                relative_path: "A.mp3".to_string(),
                object_id: first_hash,
                size_bytes: first_metadata.len(),
                modified_at_ms: first_mtime,
            }],
            pending_files: vec![PendingCheckpointFileEntry {
                source_path: second.to_string_lossy().to_string(),
                relative_path: "B.mp3".to_string(),
                size_bytes: second_metadata.len(),
                modified_at_ms: second_mtime,
            }],
        };
        write_checkpoint(dir.path(), &source_root, &checkpoint).expect("write checkpoint");
        let pending = list_pending_backups(dir.path()).expect("list pending");
        assert_eq!(pending.len(), 1);

        let (manifest, resumed, checkpoint_id) = create_backup_snapshot(
            dir.path(),
            &source_root,
            None,
            Some("PIONEER".to_string()),
            Some("exfat".to_string()),
            Some(1024),
            &test_handle(),
        )
        .expect("resume backup");
        assert!(resumed);
        assert_eq!(checkpoint_id, "checkpoint_test");
        assert_eq!(manifest.total_files, 2);
        assert_eq!(manifest.files.len(), 2);
        assert!(list_pending_backups(dir.path())
            .expect("pending after")
            .is_empty());
    }

    #[test]
    fn create_backup_snapshot_tolerates_new_source_files_during_resume() {
        let dir = tempdir().expect("tempdir");
        fs::create_dir_all(dir.path().join("snapshots")).expect("snapshots");
        fs::create_dir_all(dir.path().join("objects")).expect("objects");
        fs::create_dir_all(dir.path().join("tasks")).expect("tasks");
        let source_root = dir.path().join("USB");
        fs::create_dir_all(source_root.join("PIONEER")).expect("pioneer");
        let first = source_root.join("A.mp3");
        fs::write(&first, b"first-demo").expect("write first");
        let first_metadata = fs::metadata(&first).expect("first metadata");
        let first_mtime =
            super::system_time_to_unix_ms(first_metadata.modified().expect("first modified"));

        let first_hash = hash_file(&first).expect("hash first");
        let first_object = object_path(dir.path(), &first_hash);
        fs::create_dir_all(first_object.parent().expect("object parent")).expect("mkdir object");
        fs::copy(&first, &first_object).expect("copy object");

        let checkpoint = BackupCheckpoint {
            checkpoint_id: "checkpoint_test".to_string(),
            snapshot_id: "snapshot_resume".to_string(),
            display_name: "断点续传测试".to_string(),
            created_at: "2026-04-07T10:00:00Z".to_string(),
            updated_at: "2026-04-07T10:05:00Z".to_string(),
            source_root: source_root.to_string_lossy().to_string(),
            source_volume_name: "PIONEER".to_string(),
            source_filesystem: Some("exfat".to_string()),
            source_capacity_bytes: Some(1024),
            rekordbox_detected: true,
            rekordbox_summary: empty_rekordbox_summary(),
            total_files: 1,
            total_directories: 1,
            total_bytes: first_metadata.len(),
            directories: vec![SnapshotDirectoryEntry {
                relative_path: "PIONEER".to_string(),
                modified_at_ms: 0,
            }],
            completed_files: vec![SnapshotFileEntry {
                relative_path: "A.mp3".to_string(),
                object_id: first_hash,
                size_bytes: first_metadata.len(),
                modified_at_ms: first_mtime,
            }],
            pending_files: Vec::new(),
        };
        write_checkpoint(dir.path(), &source_root, &checkpoint).expect("write checkpoint");

        fs::write(source_root.join("NEW.mp3"), b"new-demo").expect("write new file");

        let (manifest, resumed, _checkpoint_id) = create_backup_snapshot(
            dir.path(),
            &source_root,
            None,
            Some("PIONEER".to_string()),
            Some("exfat".to_string()),
            Some(1024),
            &test_handle(),
        )
        .expect("resume backup");

        assert!(resumed);
        assert_eq!(manifest.total_files, 1);
        assert_eq!(manifest.files.len(), 1);
    }

    #[test]
    fn create_backup_snapshot_restarts_when_checkpoint_source_changed() {
        let dir = tempdir().expect("tempdir");
        fs::create_dir_all(dir.path().join("snapshots")).expect("snapshots");
        fs::create_dir_all(dir.path().join("objects")).expect("objects");
        fs::create_dir_all(dir.path().join("tasks")).expect("tasks");
        let source_root = dir.path().join("USB");
        fs::create_dir_all(source_root.join("PIONEER")).expect("pioneer");
        let first = source_root.join("A.mp3");
        let second = source_root.join("B.mp3");
        fs::write(&first, b"first-demo").expect("write first");
        fs::write(&second, b"second-demo").expect("write second");
        let first_metadata = fs::metadata(&first).expect("first metadata");
        let second_metadata = fs::metadata(&second).expect("second metadata");
        let first_mtime =
            super::system_time_to_unix_ms(first_metadata.modified().expect("first modified"));
        let second_mtime =
            super::system_time_to_unix_ms(second_metadata.modified().expect("second modified"));

        let checkpoint = BackupCheckpoint {
            checkpoint_id: "checkpoint_test".to_string(),
            snapshot_id: "snapshot_resume".to_string(),
            display_name: "断点续传测试".to_string(),
            created_at: "2026-04-07T10:00:00Z".to_string(),
            updated_at: "2026-04-07T10:05:00Z".to_string(),
            source_root: source_root.to_string_lossy().to_string(),
            source_volume_name: "PIONEER".to_string(),
            source_filesystem: Some("exfat".to_string()),
            source_capacity_bytes: Some(1024),
            rekordbox_detected: true,
            rekordbox_summary: empty_rekordbox_summary(),
            total_files: 2,
            total_directories: 1,
            total_bytes: first_metadata.len() + second_metadata.len(),
            directories: vec![SnapshotDirectoryEntry {
                relative_path: "PIONEER".to_string(),
                modified_at_ms: 0,
            }],
            completed_files: vec![SnapshotFileEntry {
                relative_path: "A.mp3".to_string(),
                object_id: "x".repeat(64),
                size_bytes: first_metadata.len(),
                modified_at_ms: first_mtime,
            }],
            pending_files: vec![PendingCheckpointFileEntry {
                source_path: second.to_string_lossy().to_string(),
                relative_path: "B.mp3".to_string(),
                size_bytes: second_metadata.len(),
                modified_at_ms: second_mtime,
            }],
        };
        write_checkpoint(dir.path(), &source_root, &checkpoint).expect("write checkpoint");

        fs::write(&first, b"first-demo-updated").expect("modify first");

        let (manifest, resumed, _checkpoint_id) = create_backup_snapshot(
            dir.path(),
            &source_root,
            None,
            Some("PIONEER".to_string()),
            Some("exfat".to_string()),
            Some(1024),
            &test_handle(),
        )
        .expect("restart backup");

        assert!(!resumed);
        assert_eq!(manifest.total_files, 2);
        assert_eq!(manifest.files.len(), 2);
        assert!(list_pending_backups(dir.path())
            .expect("pending after")
            .is_empty());
    }

    #[test]
    fn delete_snapshot_removes_unreferenced_objects_only() {
        let dir = tempdir().expect("tempdir");
        fs::create_dir_all(dir.path().join("snapshots")).expect("snapshots");
        fs::create_dir_all(dir.path().join("objects")).expect("objects");
        fs::create_dir_all(dir.path().join("tasks")).expect("tasks");

        let shared_id = "aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44";
        let unique_id = "bb11bb22cc33dd44ee55ff66aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44";
        let shared_path = object_path(dir.path(), shared_id);
        let unique_path = object_path(dir.path(), unique_id);
        fs::create_dir_all(shared_path.parent().expect("shared parent")).expect("shared dir");
        fs::create_dir_all(unique_path.parent().expect("unique parent")).expect("unique dir");
        fs::write(&shared_path, b"shared").expect("shared object");
        fs::write(&unique_path, b"unique").expect("unique object");

        let manifest_a = SnapshotManifest {
            snapshot_id: "snapshot_a".to_string(),
            display_name: "A".to_string(),
            created_at: "2026-04-07T10:00:00Z".to_string(),
            source_root: "/Volumes/A".to_string(),
            source_volume_name: "A".to_string(),
            source_filesystem: Some("exfat".to_string()),
            source_capacity_bytes: Some(1024),
            rekordbox_detected: true,
            validate_status: "success".to_string(),
            rekordbox_summary: empty_rekordbox_summary(),
            total_files: 1,
            total_directories: 0,
            total_bytes: 6,
            directories: Vec::new(),
            files: vec![SnapshotFileEntry {
                relative_path: "shared.mp3".to_string(),
                object_id: shared_id.to_string(),
                size_bytes: 6,
                modified_at_ms: 0,
            }],
        };
        let manifest_b = SnapshotManifest {
            snapshot_id: "snapshot_b".to_string(),
            display_name: "B".to_string(),
            created_at: "2026-04-07T11:00:00Z".to_string(),
            source_root: "/Volumes/B".to_string(),
            source_volume_name: "B".to_string(),
            source_filesystem: Some("exfat".to_string()),
            source_capacity_bytes: Some(1024),
            rekordbox_detected: true,
            validate_status: "success".to_string(),
            rekordbox_summary: empty_rekordbox_summary(),
            total_files: 2,
            total_directories: 0,
            total_bytes: 12,
            directories: Vec::new(),
            files: vec![
                SnapshotFileEntry {
                    relative_path: "shared.mp3".to_string(),
                    object_id: shared_id.to_string(),
                    size_bytes: 6,
                    modified_at_ms: 0,
                },
                SnapshotFileEntry {
                    relative_path: "unique.mp3".to_string(),
                    object_id: unique_id.to_string(),
                    size_bytes: 6,
                    modified_at_ms: 0,
                },
            ],
        };
        write_manifest(dir.path(), &manifest_a).expect("write a");
        write_manifest(dir.path(), &manifest_b).expect("write b");

        let (deleted_snapshots, deleted_objects, _deleted_bytes) =
            delete_snapshot_and_cleanup(dir.path(), "snapshot_b").expect("delete snapshot b");
        assert_eq!(deleted_snapshots, 1);
        assert_eq!(deleted_objects, 1);
        assert!(shared_path.exists());
        assert!(!unique_path.exists());

        let (cleanup_objects, _cleanup_bytes) =
            cleanup_unreferenced_objects(dir.path()).expect("cleanup");
        assert_eq!(cleanup_objects, 0);
        assert!(shared_path.exists());
    }

    #[test]
    fn verify_restored_target_reports_rekordbox_summary() {
        let dir = tempdir().expect("tempdir");
        let target = dir.path().join("USB");
        fs::create_dir_all(target.join("PIONEER")).expect("pioneer");
        fs::create_dir_all(target.join("Contents")).expect("contents");
        fs::write(target.join("Contents/demo.mp3"), b"music").expect("music");
        fs::write(target.join("PIONEER/exportLibrary.db"), b"db").expect("db");
        let demo_hash = hash_file(&target.join("Contents/demo.mp3")).expect("hash demo");
        let db_hash = hash_file(&target.join("PIONEER/exportLibrary.db")).expect("hash db");

        let manifest = SnapshotManifest {
            snapshot_id: "snapshot_test".to_string(),
            display_name: "测试备份".to_string(),
            created_at: "2026-04-07T10:00:00Z".to_string(),
            source_root: "/Volumes/Test".to_string(),
            source_volume_name: "Test".to_string(),
            source_filesystem: Some("exfat".to_string()),
            source_capacity_bytes: Some(1024),
            rekordbox_detected: true,
            validate_status: "success".to_string(),
            rekordbox_summary: empty_rekordbox_summary(),
            total_files: 2,
            total_directories: 2,
            total_bytes: 7,
            directories: vec![
                SnapshotDirectoryEntry {
                    relative_path: "PIONEER".to_string(),
                    modified_at_ms: 0,
                },
                SnapshotDirectoryEntry {
                    relative_path: "Contents".to_string(),
                    modified_at_ms: 0,
                },
            ],
            files: vec![
                SnapshotFileEntry {
                    relative_path: "Contents/demo.mp3".to_string(),
                    object_id: demo_hash,
                    size_bytes: 5,
                    modified_at_ms: 0,
                },
                SnapshotFileEntry {
                    relative_path: "PIONEER/exportLibrary.db".to_string(),
                    object_id: db_hash,
                    size_bytes: 2,
                    modified_at_ms: 0,
                },
            ],
        };

        let validation = verify_restored_target(&target, &manifest, None).expect("verify restore");
        assert!(validation.files_present_ok);
        assert!(validation.rekordbox_layout_ok);
        assert!(validation.rekordbox_summary.has_export_library_db);
        assert_eq!(validation.rekordbox_summary.audio_file_count, 1);
    }

    #[test]
    fn restore_snapshot_keeps_existing_target_when_object_missing() {
        let dir = tempdir().expect("tempdir");
        fs::create_dir_all(dir.path().join("snapshots")).expect("snapshots");
        fs::create_dir_all(dir.path().join("objects")).expect("objects");
        let target = dir.path().join("USB");
        fs::create_dir_all(&target).expect("target dir");
        fs::write(target.join("keep.txt"), b"keep").expect("keep file");

        let manifest = SnapshotManifest {
            snapshot_id: "snapshot_test".to_string(),
            display_name: "测试备份".to_string(),
            created_at: "2026-04-07T10:00:00Z".to_string(),
            source_root: "/Volumes/Test".to_string(),
            source_volume_name: "Test".to_string(),
            source_filesystem: Some("exfat".to_string()),
            source_capacity_bytes: Some(1024),
            rekordbox_detected: false,
            validate_status: "success".to_string(),
            rekordbox_summary: empty_rekordbox_summary(),
            total_files: 1,
            total_directories: 0,
            total_bytes: 5,
            directories: Vec::new(),
            files: vec![SnapshotFileEntry {
                relative_path: "missing.mp3".to_string(),
                object_id: "abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234"
                    .to_string(),
                size_bytes: 5,
                modified_at_ms: 0,
            }],
        };
        write_manifest(dir.path(), &manifest).expect("write manifest");

        let error =
            match restore_snapshot(dir.path(), "snapshot_test", &target, true, &test_handle()) {
                Ok(_) => panic!("restore should fail"),
                Err(error) => error,
            };
        assert!(error.to_string().contains("缺少对象文件"));
        assert!(target.join("keep.txt").exists());
        assert!(!target.join("missing.mp3").exists());
    }

    #[test]
    fn restore_snapshot_keeps_existing_target_when_object_is_corrupted() {
        let dir = tempdir().expect("tempdir");
        fs::create_dir_all(dir.path().join("snapshots")).expect("snapshots");
        fs::create_dir_all(dir.path().join("objects")).expect("objects");
        let target = dir.path().join("USB");
        fs::create_dir_all(&target).expect("target dir");
        fs::write(target.join("keep.txt"), b"keep").expect("keep file");

        let object_id = "aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44";
        let object = object_path(dir.path(), object_id);
        fs::create_dir_all(object.parent().expect("object parent")).expect("object dir");
        fs::write(&object, b"wrong").expect("corrupted object");

        let manifest = SnapshotManifest {
            snapshot_id: "snapshot_test".to_string(),
            display_name: "测试备份".to_string(),
            created_at: "2026-04-07T10:00:00Z".to_string(),
            source_root: "/Volumes/Test".to_string(),
            source_volume_name: "Test".to_string(),
            source_filesystem: Some("exfat".to_string()),
            source_capacity_bytes: Some(1024),
            rekordbox_detected: false,
            validate_status: "success".to_string(),
            rekordbox_summary: empty_rekordbox_summary(),
            total_files: 1,
            total_directories: 0,
            total_bytes: 5,
            directories: Vec::new(),
            files: vec![SnapshotFileEntry {
                relative_path: "bad.mp3".to_string(),
                object_id: object_id.to_string(),
                size_bytes: 5,
                modified_at_ms: 0,
            }],
        };
        write_manifest(dir.path(), &manifest).expect("write manifest");

        let error =
            match restore_snapshot(dir.path(), "snapshot_test", &target, true, &test_handle()) {
                Ok(_) => panic!("restore should fail"),
                Err(error) => error,
            };
        assert!(error.to_string().contains("校验失败") || error.to_string().contains("大小不匹配"));
        assert!(target.join("keep.txt").exists());
        assert!(!target.join("bad.mp3").exists());
    }

    #[test]
    fn restore_snapshot_ignores_target_system_artifacts_during_switch() {
        let dir = tempdir().expect("tempdir");
        fs::create_dir_all(dir.path().join("snapshots")).expect("snapshots");
        fs::create_dir_all(dir.path().join("objects")).expect("objects");
        let target = dir.path().join("USB");
        fs::create_dir_all(target.join(".Spotlight-V100")).expect("spotlight");
        fs::create_dir_all(target.join(".Trash-1000")).expect("trash");
        fs::write(target.join("keep.txt"), b"keep").expect("keep file");

        let content = b"demo";
        let real_hash = hex::encode(sha2::Sha256::digest(content));
        let object = object_path(dir.path(), &real_hash);
        fs::create_dir_all(object.parent().expect("object parent")).expect("object dir");
        fs::write(&object, content).expect("object data");

        let manifest = SnapshotManifest {
            snapshot_id: "snapshot_test".to_string(),
            display_name: "测试备份".to_string(),
            created_at: "2026-04-07T10:00:00Z".to_string(),
            source_root: "/Volumes/Test".to_string(),
            source_volume_name: "Test".to_string(),
            source_filesystem: Some("exfat".to_string()),
            source_capacity_bytes: Some(1024),
            rekordbox_detected: false,
            validate_status: "success".to_string(),
            rekordbox_summary: empty_rekordbox_summary(),
            total_files: 1,
            total_directories: 0,
            total_bytes: 4,
            directories: Vec::new(),
            files: vec![SnapshotFileEntry {
                relative_path: "demo.txt".to_string(),
                object_id: real_hash,
                size_bytes: 4,
                modified_at_ms: 0,
            }],
        };
        write_manifest(dir.path(), &manifest).expect("write manifest");

        let restored = restore_snapshot(dir.path(), "snapshot_test", &target, true, &test_handle())
            .expect("restore snapshot");

        assert_eq!(restored.total_files, 1);
        assert!(target.join("demo.txt").exists());
        assert!(target.join(".Spotlight-V100").exists());
        assert!(target.join(".Trash-1000").exists());
        assert!(!target.join("keep.txt").exists());
    }

    #[test]
    fn move_staged_contents_into_target_ignores_appledouble_artifacts() {
        let dir = tempdir().expect("tempdir");
        let stage_root = dir.path().join("stage");
        let target_root = dir.path().join("target");
        fs::create_dir_all(&stage_root).expect("stage root");
        fs::create_dir_all(&target_root).expect("target root");
        fs::write(stage_root.join("demo.txt"), b"demo").expect("demo file");
        fs::write(stage_root.join("._Contents"), b"apple double").expect("apple double");

        let mut moved_names = Vec::new();
        super::move_staged_contents_into_target(
            &stage_root,
            &target_root,
            &test_handle(),
            &mut moved_names,
        )
        .expect("move staged contents");

        assert_eq!(moved_names, vec!["demo.txt".to_string()]);
        assert!(target_root.join("demo.txt").exists());
        assert!(!target_root.join("._Contents").exists());
        assert!(stage_root.join("._Contents").exists());
    }

    #[test]
    fn cleanup_usb_backup_task_removes_terminal_task() {
        let task_id = "usb_backup_task_test_success".to_string();
        TASKS.lock().expect("lock tasks").insert(
            task_id.clone(),
            Arc::new(BackupTaskHandle {
                cancel_flag: Arc::new(AtomicBool::new(false)),
                state: Mutex::new(BackupTaskState {
                    operation: "backup".to_string(),
                    status: "success".to_string(),
                    progress: 1.0,
                    progress_hint_text: "done".to_string(),
                    snapshot_id: None,
                    display_name: None,
                    total_files: 0,
                    total_bytes: 0,
                    restored_files: 0,
                    validated_files: 0,
                    error: None,
                    resumed_from_checkpoint: false,
                    checkpoint_id: None,
                    restore_validation: None,
                }),
            }),
        );

        let response = cleanup_usb_backup_task(task_id.clone()).expect("cleanup task");
        assert!(response.contains("\"removed\":true"));
        assert!(!TASKS
            .lock()
            .expect("lock tasks after cleanup")
            .contains_key(&task_id));
    }

    #[test]
    fn cleanup_usb_backup_task_rejects_running_task() {
        let task_id = "usb_backup_task_test_running".to_string();
        TASKS.lock().expect("lock tasks").insert(
            task_id.clone(),
            Arc::new(BackupTaskHandle {
                cancel_flag: Arc::new(AtomicBool::new(false)),
                state: Mutex::new(BackupTaskState::new("backup")),
            }),
        );

        let error = cleanup_usb_backup_task(task_id.clone()).expect_err("reject running task");
        assert!(error.to_string().contains("暂不允许清理"));
        assert!(TASKS
            .lock()
            .expect("lock tasks after failure")
            .contains_key(&task_id));
        TASKS
            .lock()
            .expect("lock tasks for cleanup")
            .remove(&task_id);
    }
}
