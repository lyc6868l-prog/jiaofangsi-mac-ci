use std::collections::HashSet;
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;

use crate::audio_probe::probe_audio_file;
use crate::transcode_task::TranscodeError;

const AUDIO_SUFFIXES: &[&str] = &[
    ".mp3", ".wav", ".aiff", ".aif", ".flac", ".m4a", ".mp4", ".ogg", ".opus", ".aac", ".wma",
    ".dff",
];
const COVER_SUPPORTED_SUFFIXES: &[&str] = &[".mp3", ".flac", ".m4a", ".mp4", ".aiff", ".aif"];
const COVER_NEED_TRANSCODE_SUFFIXES: &[&str] = &[".wav", ".ogg", ".opus"];
const IMAGE_SUFFIXES: &[&str] = &[".jpg", ".jpeg", ".png", ".webp"];

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct ScanAudioTargetsResult {
    pub ok: bool,
    pub files: Vec<String>,
    pub file_count: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct MetadataEditResult {
    pub ok: bool,
    pub status: String,
    pub input_path: String,
    pub output_path: String,
    pub changed: bool,
    pub backup_path: Option<String>,
    pub message: String,
}

pub fn scan_audio_targets(
    input_paths: &[String],
) -> Result<ScanAudioTargetsResult, TranscodeError> {
    let mut files = Vec::new();
    let mut seen = HashSet::new();
    for raw_path in input_paths {
        collect_audio_targets(Path::new(raw_path), &mut files, &mut seen)?;
    }
    files.sort();
    Ok(ScanAudioTargetsResult {
        ok: true,
        file_count: files.len(),
        files,
    })
}

pub fn inject_filename_text(
    input_path: &Path,
    append_text: &str,
    ffprobe_path: &Path,
) -> Result<MetadataEditResult, TranscodeError> {
    if !input_path.exists() {
        return Err(TranscodeError::InvalidInput(format!(
            "input file does not exist: {}",
            input_path.display()
        )));
    }
    let append_text = sanitize_append_text(append_text);
    if append_text.is_empty() {
        return Err(TranscodeError::InvalidInput(
            "append_text is empty".to_string(),
        ));
    }
    probe_audio_file(input_path, ffprobe_path)?;
    let stem = input_path
        .file_stem()
        .and_then(OsStr::to_str)
        .ok_or_else(|| TranscodeError::InvalidInput("unable to resolve file stem".to_string()))?;
    if stem.ends_with(&append_text) {
        let input = input_path.to_string_lossy().to_string();
        return Ok(MetadataEditResult {
            ok: true,
            status: "skip".to_string(),
            input_path: input.clone(),
            output_path: input,
            changed: false,
            backup_path: None,
            message: "文件名已包含注入文本，已跳过。".to_string(),
        });
    }

    let parent = input_path.parent().ok_or_else(|| {
        TranscodeError::InvalidInput(format!(
            "unable to resolve parent directory: {}",
            input_path.display()
        ))
    })?;
    let extension = input_path.extension().and_then(OsStr::to_str).unwrap_or("");
    let base_stem = sanitize_file_stem(&format!("{stem}{append_text}"));
    let mut candidate = build_sibling_path(parent, &base_stem, extension, None);
    let mut index = 1usize;
    while candidate.exists() {
        candidate = build_sibling_path(parent, &base_stem, extension, Some(index));
        index += 1;
    }

    fs::rename(input_path, &candidate)?;
    Ok(MetadataEditResult {
        ok: true,
        status: "ok".to_string(),
        input_path: input_path.to_string_lossy().to_string(),
        output_path: candidate.to_string_lossy().to_string(),
        changed: true,
        backup_path: None,
        message: "文件名注入完成。".to_string(),
    })
}

pub fn inject_cover_art(
    input_path: &Path,
    cover_image_path: &Path,
    ffmpeg_path: &Path,
    ffprobe_path: &Path,
) -> Result<MetadataEditResult, TranscodeError> {
    if !input_path.exists() {
        return Err(TranscodeError::InvalidInput(format!(
            "input file does not exist: {}",
            input_path.display()
        )));
    }
    if !cover_image_path.exists() {
        return Err(TranscodeError::InvalidInput(format!(
            "cover image does not exist: {}",
            cover_image_path.display()
        )));
    }
    probe_audio_file(input_path, ffprobe_path)?;
    let input_ext = normalized_suffix(input_path);
    if COVER_NEED_TRANSCODE_SUFFIXES.contains(&input_ext.as_str()) {
        let input = input_path.to_string_lossy().to_string();
        return Ok(MetadataEditResult {
            ok: true,
            status: "need".to_string(),
            input_path: input.clone(),
            output_path: input,
            changed: false,
            backup_path: None,
            message: "当前格式不支持稳定写入封面，建议先转码。".to_string(),
        });
    }
    if !COVER_SUPPORTED_SUFFIXES.contains(&input_ext.as_str()) {
        if AUDIO_SUFFIXES.contains(&input_ext.as_str()) {
            let input = input_path.to_string_lossy().to_string();
            return Ok(MetadataEditResult {
                ok: true,
                status: "need".to_string(),
                input_path: input.clone(),
                output_path: input,
                changed: false,
                backup_path: None,
                message: "当前格式暂不支持直接写入封面，建议先转码。".to_string(),
            });
        }
        return Err(TranscodeError::InvalidInput(format!(
            "cover injection is not supported for {}",
            input_path.display()
        )));
    }
    let image_ext = normalized_suffix(cover_image_path);
    if !IMAGE_SUFFIXES.contains(&image_ext.as_str()) {
        return Err(TranscodeError::InvalidInput(format!(
            "unsupported image format: {}",
            cover_image_path.display()
        )));
    }

    let requested_cover_hash = probe_first_video_data_hash(ffprobe_path, cover_image_path)?;
    let current_cover_hash = probe_first_video_data_hash(ffprobe_path, input_path)?;
    if requested_cover_hash.is_some() && requested_cover_hash == current_cover_hash {
        let input = input_path.to_string_lossy().to_string();
        return Ok(MetadataEditResult {
            ok: true,
            status: "skip".to_string(),
            input_path: input.clone(),
            output_path: input,
            changed: false,
            backup_path: None,
            message: "检测到相同封面，已跳过。".to_string(),
        });
    }

    let parent = input_path.parent().ok_or_else(|| {
        TranscodeError::InvalidInput(format!(
            "unable to resolve parent directory: {}",
            input_path.display()
        ))
    })?;
    let ext = input_path.extension().and_then(OsStr::to_str).unwrap_or("");
    let stem = input_path
        .file_stem()
        .and_then(OsStr::to_str)
        .unwrap_or("metadata_edit_output");
    let temp_output_path = build_temp_path(parent, &format!("{stem}_metadata_edit_output"), ext);
    let backup_path = build_temp_path(parent, &format!("{stem}_metadata_edit_backup"), ext);
    fs::copy(input_path, &backup_path)?;

    let injection_result =
        run_cover_injection(ffmpeg_path, input_path, cover_image_path, &temp_output_path);
    let verify_result = injection_result.and_then(|()| {
        if !has_embedded_cover_stream(ffprobe_path, &temp_output_path)? {
            return Err(TranscodeError::InvalidInput(
                "embedded cover stream missing after write".to_string(),
            ));
        }
        let injected_cover_hash = probe_first_video_data_hash(ffprobe_path, &temp_output_path)?;
        match (
            requested_cover_hash.as_deref(),
            injected_cover_hash.as_deref(),
        ) {
            (Some(expected), Some(actual)) if expected == actual => Ok(()),
            (Some(_), Some(_)) => Err(TranscodeError::InvalidInput(
                "embedded cover verification failed".to_string(),
            )),
            _ => Err(TranscodeError::InvalidInput(
                "embedded cover missing after write".to_string(),
            )),
        }
    });

    let result = match verify_result {
        Ok(()) => {
            if let Err(error) = replace_existing_file(&temp_output_path, input_path) {
                let _ = restore_original_file(&backup_path, input_path);
                let _ = fs::remove_file(&temp_output_path);
                return Err(TranscodeError::Io(error));
            }
            if !has_embedded_cover_stream(ffprobe_path, input_path)? {
                let _ = restore_original_file(&backup_path, input_path);
                return Err(TranscodeError::InvalidInput(
                    "final cover stream verification failed".to_string(),
                ));
            }
            let final_cover_hash = probe_first_video_data_hash(ffprobe_path, input_path)?;
            if requested_cover_hash.is_some() && requested_cover_hash != final_cover_hash {
                let _ = restore_original_file(&backup_path, input_path);
                return Err(TranscodeError::InvalidInput(
                    "final cover verification failed".to_string(),
                ));
            }
            let _ = fs::remove_file(&backup_path);
            Ok(MetadataEditResult {
                ok: true,
                status: "ok".to_string(),
                input_path: input_path.to_string_lossy().to_string(),
                output_path: input_path.to_string_lossy().to_string(),
                changed: true,
                backup_path: None,
                message: "封面注入完成。".to_string(),
            })
        }
        Err(error) => {
            let _ = fs::remove_file(&temp_output_path);
            let _ = restore_original_file(&backup_path, input_path);
            Err(error)
        }
    };
    result
}

fn collect_audio_targets(
    path: &Path,
    output: &mut Vec<String>,
    seen: &mut HashSet<String>,
) -> Result<(), TranscodeError> {
    let path = path.expanduser_fallback()?.canonicalize()?;
    if path.is_dir() {
        for entry in fs::read_dir(&path)? {
            let entry = entry?;
            collect_audio_targets(&entry.path(), output, seen)?;
        }
        return Ok(());
    }
    if !path.is_file() {
        return Ok(());
    }
    let suffix = normalized_suffix(&path);
    if !AUDIO_SUFFIXES.contains(&suffix.as_str()) {
        return Ok(());
    }
    let value = path.to_string_lossy().to_string();
    if seen.insert(value.clone()) {
        output.push(value);
    }
    Ok(())
}

fn run_cover_injection(
    ffmpeg_path: &Path,
    input_path: &Path,
    cover_image_path: &Path,
    output_path: &Path,
) -> Result<(), TranscodeError> {
    let args = vec![
        "-hide_banner".to_string(),
        "-loglevel".to_string(),
        "error".to_string(),
        "-y".to_string(),
        "-i".to_string(),
        input_path.to_string_lossy().to_string(),
        "-i".to_string(),
        cover_image_path.to_string_lossy().to_string(),
        "-map_metadata".to_string(),
        "0".to_string(),
        "-map".to_string(),
        "0:a".to_string(),
        "-map".to_string(),
        "1:v:0".to_string(),
        "-c".to_string(),
        "copy".to_string(),
        "-disposition:v:0".to_string(),
        "attached_pic".to_string(),
        "-metadata:s:v".to_string(),
        "title=Album cover".to_string(),
        "-metadata:s:v".to_string(),
        "comment=Cover (front)".to_string(),
        output_path.to_string_lossy().to_string(),
    ];
    let output = Command::new(ffmpeg_path)
        .args(&args)
        .output()
        .map_err(|error| TranscodeError::SpawnFailed(error.to_string()))?;
    if output.status.success() {
        return Ok(());
    }
    Err(TranscodeError::SpawnFailed(
        String::from_utf8_lossy(&output.stderr).trim().to_string(),
    ))
}

fn has_embedded_cover_stream(
    ffprobe_path: &Path,
    input_path: &Path,
) -> Result<bool, TranscodeError> {
    let output = Command::new(ffprobe_path)
        .args([
            "-v",
            "quiet",
            "-print_format",
            "json",
            "-select_streams",
            "v:0",
            "-show_streams",
            &input_path.to_string_lossy(),
        ])
        .output()
        .map_err(|error| TranscodeError::ProbeFailed(error.to_string()))?;
    if !output.status.success() {
        return Err(TranscodeError::ProbeFailed(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }
    let payload: serde_json::Value = serde_json::from_slice(&output.stdout)?;
    let Some(streams) = payload.get("streams").and_then(|value| value.as_array()) else {
        return Ok(false);
    };
    Ok(streams.iter().any(|stream| {
        let codec_type = stream.get("codec_type").and_then(|value| value.as_str());
        let attached_pic = stream
            .get("disposition")
            .and_then(|value| value.get("attached_pic"))
            .and_then(|value| value.as_i64())
            .unwrap_or_default();
        codec_type == Some("video") || attached_pic == 1
    }))
}

fn probe_first_video_data_hash(
    ffprobe_path: &Path,
    input_path: &Path,
) -> Result<Option<String>, TranscodeError> {
    let output = Command::new(ffprobe_path)
        .args([
            "-v",
            "quiet",
            "-print_format",
            "json",
            "-select_streams",
            "v:0",
            "-show_packets",
            "-show_data_hash",
            "sha256",
            &input_path.to_string_lossy(),
        ])
        .output()
        .map_err(|error| TranscodeError::ProbeFailed(error.to_string()))?;
    if !output.status.success() {
        return Err(TranscodeError::ProbeFailed(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }
    let payload: serde_json::Value = serde_json::from_slice(&output.stdout)?;
    let Some(packets) = payload.get("packets").and_then(|value| value.as_array()) else {
        return Ok(None);
    };
    Ok(packets.iter().find_map(|packet| {
        let codec_type = packet.get("codec_type").and_then(|value| value.as_str());
        if codec_type != Some("video") {
            return None;
        }
        packet
            .get("data_hash")
            .and_then(|value| value.as_str())
            .map(ToString::to_string)
    }))
}

fn sanitize_append_text(value: &str) -> String {
    value
        .chars()
        .filter(|ch| !matches!(ch, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|'))
        .filter(|ch| !ch.is_control())
        .collect::<String>()
        .trim()
        .to_string()
}

fn sanitize_file_stem(value: &str) -> String {
    let sanitized = value
        .chars()
        .map(|ch| match ch {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            _ if ch.is_control() => '_',
            _ => ch,
        })
        .collect::<String>()
        .trim()
        .to_string();
    if sanitized.is_empty() {
        "metadata_edit".to_string()
    } else {
        sanitized
    }
}

fn build_sibling_path(parent: &Path, stem: &str, extension: &str, index: Option<usize>) -> PathBuf {
    let file_name = match index {
        Some(index) if extension.is_empty() => format!("{stem} ({index})"),
        Some(index) => format!("{stem} ({index}).{extension}"),
        None if extension.is_empty() => stem.to_string(),
        None => format!("{stem}.{extension}"),
    };
    parent.join(file_name)
}

fn build_temp_path(parent: &Path, stem: &str, extension: &str) -> PathBuf {
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let process_id = std::process::id();
    let clean_stem = sanitize_file_stem(stem);
    let clean_extension = extension.trim_start_matches('.');
    if clean_extension.is_empty() {
        parent.join(format!("{clean_stem}_{process_id}_{unique}"))
    } else {
        parent.join(format!(
            "{clean_stem}_{process_id}_{unique}.{clean_extension}"
        ))
    }
}

fn replace_existing_file(source_path: &Path, target_path: &Path) -> std::io::Result<()> {
    if !target_path.exists() {
        return fs::rename(source_path, target_path);
    }
    let target_metadata = fs::metadata(target_path)?;
    let mut target_permissions = target_metadata.permissions();
    if target_permissions.readonly() {
        target_permissions.set_readonly(false);
        fs::set_permissions(target_path, target_permissions)?;
    }
    fs::remove_file(target_path)?;
    fs::rename(source_path, target_path)
}

fn restore_original_file(backup_path: &Path, target_path: &Path) -> std::io::Result<()> {
    if !backup_path.exists() {
        return Ok(());
    }
    if target_path.exists() {
        let target_metadata = fs::metadata(target_path)?;
        let mut target_permissions = target_metadata.permissions();
        if target_permissions.readonly() {
            target_permissions.set_readonly(false);
            fs::set_permissions(target_path, target_permissions)?;
        }
        fs::remove_file(target_path)?;
    }
    fs::rename(backup_path, target_path)
}

fn normalized_suffix(path: &Path) -> String {
    path.extension()
        .and_then(OsStr::to_str)
        .map(|value| format!(".{}", value.to_ascii_lowercase()))
        .unwrap_or_default()
}

trait ExpandUserFallback {
    fn expanduser_fallback(&self) -> Result<PathBuf, TranscodeError>;
}

impl ExpandUserFallback for Path {
    fn expanduser_fallback(&self) -> Result<PathBuf, TranscodeError> {
        let raw = self.to_string_lossy();
        if raw == "~" {
            let home = std::env::var("HOME")
                .map(PathBuf::from)
                .map_err(|_| TranscodeError::InvalidInput("HOME is not set".to_string()))?;
            return Ok(home);
        }
        if let Some(stripped) = raw.strip_prefix("~/") {
            let home = std::env::var("HOME")
                .map(PathBuf::from)
                .map_err(|_| TranscodeError::InvalidInput("HOME is not set".to_string()))?;
            return Ok(home.join(stripped));
        }
        Ok(self.to_path_buf())
    }
}

#[cfg(test)]
mod tests {
    use super::{
        inject_cover_art, inject_filename_text, replace_existing_file, sanitize_append_text,
        scan_audio_targets,
    };
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[cfg(unix)]
    use std::os::unix::fs::PermissionsExt;

    fn temp_dir(label: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("dj_metadata_edit_{label}_{unique}"));
        fs::create_dir_all(&dir).expect("temp dir should create");
        dir
    }

    #[cfg(unix)]
    fn fake_ffprobe(dir: &Path) -> PathBuf {
        let script = dir.join("fake_ffprobe.sh");
        fs::write(
            &script,
            "#!/bin/sh\nprintf '{\"streams\":[{\"codec_type\":\"audio\",\"codec_name\":\"mp3\",\"channels\":2,\"sample_rate\":\"44100\"}],\"format\":{\"format_name\":\"mp3\",\"duration\":\"1.0\",\"bit_rate\":\"320000\"}}'\n",
        )
        .expect("fake ffprobe should write");
        let mut permissions = fs::metadata(&script)
            .expect("metadata should exist")
            .permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&script, permissions).expect("permissions should update");
        script
    }

    #[cfg(windows)]
    fn fake_ffprobe(dir: &Path) -> PathBuf {
        let script = dir.join("fake_ffprobe.cmd");
        fs::write(
            &script,
            "@echo off\r\n< nul set /p = {\"streams\":[{\"codec_type\":\"audio\",\"codec_name\":\"mp3\",\"channels\":2,\"sample_rate\":\"44100\"}],\"format\":{\"format_name\":\"mp3\",\"duration\":\"1.0\",\"bit_rate\":\"320000\"}}\r\n",
        )
        .expect("fake ffprobe should write");
        script
    }

    #[test]
    fn scans_audio_targets_recursively() {
        let dir = temp_dir("scan");
        let nested = dir.join("nested");
        fs::create_dir_all(&nested).expect("nested dir should create");
        fs::write(dir.join("a.mp3"), b"a").expect("mp3 should write");
        fs::write(nested.join("b.flac"), b"b").expect("flac should write");
        fs::write(nested.join("c.txt"), b"c").expect("txt should write");

        let result =
            scan_audio_targets(&[dir.to_string_lossy().to_string()]).expect("scan should work");
        assert_eq!(result.file_count, 2);

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn inject_filename_text_is_idempotent() {
        let dir = temp_dir("idempotent");
        let ffprobe = fake_ffprobe(&dir);
        let input = dir.join("夜曲remix版.mp3");
        fs::write(&input, b"a").expect("file should write");

        let result = inject_filename_text(&input, "remix版", &ffprobe).expect("rename should work");
        assert_eq!(result.status, "skip");
        assert_eq!(result.output_path, input.to_string_lossy());

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn inject_filename_text_resolves_conflict() {
        let dir = temp_dir("conflict");
        let ffprobe = fake_ffprobe(&dir);
        let input = dir.join("夜曲.mp3");
        let conflict = dir.join("夜曲remix版.mp3");
        fs::write(&input, b"a").expect("input should write");
        fs::write(&conflict, b"b").expect("conflict should write");

        let result = inject_filename_text(&input, "remix版", &ffprobe).expect("rename should work");
        assert_eq!(result.status, "ok");
        assert!(result.output_path.ends_with("夜曲remix版 (1).mp3"));

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn replace_existing_file_overwrites_existing_target() {
        let dir = temp_dir("replace_existing");
        let source = dir.join("source.mp3");
        let target = dir.join("target.mp3");
        fs::write(&source, b"new").expect("source should write");
        fs::write(&target, b"old").expect("target should write");

        replace_existing_file(&source, &target).expect("replace should work");

        assert!(!source.exists());
        assert_eq!(fs::read(&target).expect("target should read"), b"new");

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn inject_cover_art_marks_unsupported_audio_as_need() {
        let dir = temp_dir("cover_need");
        let ffprobe = fake_ffprobe(&dir);
        let input = dir.join("sample.wma");
        let cover = dir.join("cover.jpg");
        fs::write(&input, b"audio").expect("input should write");
        fs::write(&cover, b"image").expect("cover should write");

        let result = inject_cover_art(&input, &cover, Path::new("ffmpeg"), &ffprobe)
            .expect("cover injection should return need");
        assert_eq!(result.status, "need");
        assert!(!result.changed);

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn sanitize_append_text_filters_illegal_chars() {
        assert_eq!(sanitize_append_text(" remix:版? "), "remix版");
    }
}
