use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::audio_probe::AudioProbeResult;
use crate::transcode_preset::TranscodePreset;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TranscodeTaskStatus {
    Pending,
    Queued,
    Running,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TranscodeTask {
    pub id: String,
    pub input_path: PathBuf,
    pub output_dir: PathBuf,
    pub preset: TranscodePreset,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TranscodeTaskSnapshot {
    pub id: String,
    pub status: TranscodeTaskStatus,
    pub progress: f64,
    pub message: String,
    pub input_path: PathBuf,
    pub output_path: Option<PathBuf>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TranscodeCompletion {
    pub id: String,
    pub input_path: PathBuf,
    pub output_path: PathBuf,
    pub probe: AudioProbeResult,
}

#[derive(Debug, Error)]
pub enum TranscodeError {
    #[error("invalid input: {0}")]
    InvalidInput(String),
    #[error("probe failed: {0}")]
    ProbeFailed(String),
    #[error("ffmpeg spawn failed: {0}")]
    SpawnFailed(String),
    #[error("task not found: {0}")]
    TaskNotFound(String),
    #[error("queue is closed")]
    QueueClosed,
    #[error("transcode cancelled: {0}")]
    Cancelled(String),
    #[error("invalid preset: {0}")]
    InvalidPreset(String),
    #[error("ffmpeg exited with code {code:?}: {stderr_tail}")]
    NonZeroExit {
        code: Option<i32>,
        stderr_tail: String,
    },
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
}

impl TranscodeError {
    pub fn user_message(&self) -> String {
        match self {
            Self::InvalidInput(message) => {
                if message.contains("does not exist") {
                    "文件不存在，请检查源文件路径是否有效。".to_string()
                } else if message.contains("not a file") {
                    "当前路径不是有效文件，请重新选择音频文件。".to_string()
                } else if message.contains("file stem") {
                    "输出文件名生成失败，请检查源文件名是否异常。".to_string()
                } else {
                    "输入文件异常，请检查源文件是否完整。".to_string()
                }
            }
            Self::ProbeFailed(message) => {
                let lower = message.to_lowercase();
                if lower.contains("no such file") || lower.contains("not found") {
                    "文件读取失败，请确认源文件仍然存在。".to_string()
                } else if lower.contains("invalid data")
                    || lower.contains("moov atom not found")
                    || lower.contains("error reading")
                    || lower.contains("failed to read")
                {
                    "音频探测失败，文件格式异常或文件已损坏。".to_string()
                } else if lower.contains("invalid argument")
                    || lower.contains("permission denied")
                    || lower.contains("exec format error")
                {
                    "音频探测失败，ffprobe 调用异常。".to_string()
                } else if lower.contains("audio stream") {
                    "当前文件无法识别，请检查源文件是否为有效音频。".to_string()
                } else {
                    "音频探测失败，请检查源文件是否完整或格式是否异常。".to_string()
                }
            }
            Self::SpawnFailed(_) => "转码器启动失败，请检查 ffmpeg 是否可用。".to_string(),
            Self::TaskNotFound(_) => "未找到对应的转码任务。".to_string(),
            Self::QueueClosed => "转码任务队列已关闭，请重新启动任务。".to_string(),
            Self::Cancelled(_) => "任务已由用户手动停止。".to_string(),
            Self::InvalidPreset(_) => "转码参数无效，请检查输出格式设置。".to_string(),
            Self::NonZeroExit { stderr_tail, .. } => {
                let lower = stderr_tail.to_lowercase();
                if lower.contains("invalid data") || lower.contains("error while decoding") {
                    "转码失败，源文件内容异常或已损坏。".to_string()
                } else if lower.contains("permission denied") {
                    "转码失败，无法写入输出目录。".to_string()
                } else if lower.contains("no space left") {
                    "转码失败，磁盘空间不足。".to_string()
                } else {
                    "转码失败，请检查源文件和输出目录后重试。".to_string()
                }
            }
            Self::Io(_) => "文件读写失败，请检查文件权限和磁盘状态。".to_string(),
            Self::Json(_) => "音频信息解析失败，请检查源文件格式是否正常。".to_string(),
        }
    }
}
