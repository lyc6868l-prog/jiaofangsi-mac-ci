use std::path::{Path, PathBuf};

use crate::transcode_preset::{AudioChannelMode, TranscodePreset};
use crate::transcode_task::TranscodeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FfmpegCommandSpec {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub output_path: PathBuf,
}

pub fn build_output_path(
    input_path: &Path,
    output_dir: &Path,
    preset: &TranscodePreset,
) -> Result<PathBuf, TranscodeError> {
    let stem = input_path
        .file_stem()
        .and_then(|value| value.to_str())
        .ok_or_else(|| {
            TranscodeError::InvalidInput(format!(
                "unable to derive file stem from {}",
                input_path.display()
            ))
        })?;
    let sanitized = sanitize_output_stem(stem);
    Ok(next_available_output_path(
        output_dir,
        &sanitized,
        preset.extension(),
    ))
}

pub fn build_ffmpeg_command(
    ffmpeg_path: &Path,
    input_path: &Path,
    output_dir: &Path,
    preset: &TranscodePreset,
) -> Result<FfmpegCommandSpec, TranscodeError> {
    let output_path = build_output_path(input_path, output_dir, preset)?;
    let mut args = vec![
        "-hide_banner".to_string(),
        "-y".to_string(),
        "-i".to_string(),
        input_path.to_string_lossy().to_string(),
        "-vn".to_string(),
    ];

    match preset {
        TranscodePreset::Mp3(config) => {
            args.push("-c:a".to_string());
            args.push("libmp3lame".to_string());
            args.push("-b:a".to_string());
            args.push(format!("{}k", config.bitrate_kbps));
            push_channels(&mut args, config.channels);
            push_sample_rate(&mut args, config.sample_rate_hz);
        }
        TranscodePreset::Wav(config) => {
            args.push("-c:a".to_string());
            args.push(config.codec.ffmpeg_codec().to_string());
            push_channels(&mut args, config.channels);
            push_sample_rate(&mut args, config.sample_rate_hz);
        }
        TranscodePreset::Aiff(config) => {
            args.push("-c:a".to_string());
            args.push("pcm_s16be".to_string());
            push_channels(&mut args, config.channels);
            push_sample_rate(&mut args, config.sample_rate_hz);
        }
        TranscodePreset::Flac(config) => {
            if config.compression_level > 12 {
                return Err(TranscodeError::InvalidPreset(
                    "flac compression_level must be between 0 and 12".to_string(),
                ));
            }
            args.push("-c:a".to_string());
            args.push("flac".to_string());
            args.push("-compression_level".to_string());
            args.push(config.compression_level.to_string());
            push_channels(&mut args, config.channels);
            push_sample_rate(&mut args, config.sample_rate_hz);
        }
    }

    args.push(output_path.to_string_lossy().to_string());

    Ok(FfmpegCommandSpec {
        program: ffmpeg_path.to_path_buf(),
        args,
        output_path,
    })
}

fn push_sample_rate(args: &mut Vec<String>, sample_rate_hz: Option<u32>) {
    if let Some(sample_rate_hz) = sample_rate_hz {
        args.push("-ar".to_string());
        args.push(sample_rate_hz.to_string());
    }
}

fn push_channels(args: &mut Vec<String>, channels: AudioChannelMode) {
    match channels {
        AudioChannelMode::Original => {}
        AudioChannelMode::Mono => {
            args.push("-ac".to_string());
            args.push("1".to_string());
        }
        AudioChannelMode::Stereo => {
            args.push("-ac".to_string());
            args.push("2".to_string());
        }
    }
}

fn sanitize_output_stem(stem: &str) -> String {
    let sanitized = stem
        .chars()
        .map(|ch| match ch {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            _ => ch,
        })
        .collect::<String>()
        .trim()
        .to_string();
    if sanitized.is_empty() {
        "transcoded_audio".to_string()
    } else {
        sanitized
    }
}

fn next_available_output_path(output_dir: &Path, stem: &str, extension: &str) -> PathBuf {
    let candidate = output_dir.join(format!("{stem}.{extension}"));
    if !candidate.exists() {
        return candidate;
    }
    let mut index = 1_u32;
    loop {
        let candidate = output_dir.join(format!("{stem}_{index:02}.{extension}"));
        if !candidate.exists() {
            return candidate;
        }
        index = index.saturating_add(1);
    }
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use crate::transcode_preset::{
        AudioChannelMode, FlacPreset, Mp3Preset, TranscodePreset, WavCodec, WavPreset,
    };

    use super::{build_ffmpeg_command, build_output_path};

    #[test]
    fn builds_mp3_command() {
        let spec = build_ffmpeg_command(
            Path::new("ffmpeg"),
            Path::new("/music/source.wav"),
            Path::new("/out"),
            &TranscodePreset::Mp3(Mp3Preset {
                bitrate_kbps: 320,
                sample_rate_hz: Some(44_100),
                channels: AudioChannelMode::Stereo,
            }),
        )
        .expect("mp3 command should build");
        assert!(spec.args.contains(&"libmp3lame".to_string()));
        assert!(spec.args.contains(&"320k".to_string()));
        assert!(spec.args.contains(&"44100".to_string()));
        assert!(spec.args.contains(&"2".to_string()));
    }

    #[test]
    fn builds_wav_command() {
        let spec = build_ffmpeg_command(
            Path::new("ffmpeg"),
            Path::new("/music/source.flac"),
            Path::new("/out"),
            &TranscodePreset::Wav(WavPreset {
                codec: WavCodec::PcmS16Le,
                sample_rate_hz: Some(48_000),
                channels: AudioChannelMode::Original,
            }),
        )
        .expect("wav command should build");
        assert!(spec.args.contains(&"pcm_s16le".to_string()));
        assert!(spec.args.contains(&"48000".to_string()));
    }

    #[test]
    fn builds_flac_command() {
        let spec = build_ffmpeg_command(
            Path::new("ffmpeg"),
            Path::new("/music/source.mp3"),
            Path::new("/out"),
            &TranscodePreset::Flac(FlacPreset {
                compression_level: 8,
                sample_rate_hz: None,
                channels: AudioChannelMode::Mono,
            }),
        )
        .expect("flac command should build");
        assert!(spec.args.contains(&"flac".to_string()));
        assert!(spec.args.contains(&"8".to_string()));
        assert!(spec.args.contains(&"1".to_string()));
    }

    #[test]
    fn builds_sanitized_output_path() {
        let output = build_output_path(
            Path::new("/music/bad:name?.wav"),
            Path::new("/out"),
            &TranscodePreset::Mp3(Mp3Preset::default()),
        )
        .expect("output path should build");
        assert_eq!(output, Path::new("/out/bad_name_.mp3"));
    }
}
