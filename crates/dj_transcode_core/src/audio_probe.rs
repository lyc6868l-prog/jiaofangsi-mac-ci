use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{Deserialize, Serialize};

use crate::transcode_task::TranscodeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioProbeConfig {
    pub ffprobe_path: PathBuf,
}

impl Default for AudioProbeConfig {
    fn default() -> Self {
        Self {
            ffprobe_path: PathBuf::from("ffprobe"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct AudioProbeResult {
    pub format_name: Option<String>,
    pub duration_secs: Option<f64>,
    pub bit_rate_kbps: Option<f64>,
    pub codec_name: Option<String>,
    pub sample_rate_hz: Option<u32>,
    pub channels: Option<u16>,
}

#[derive(Debug, Deserialize)]
struct FfprobeOutput {
    #[serde(default)]
    streams: Vec<FfprobeStream>,
    format: FfprobeFormat,
}

#[derive(Debug, Deserialize)]
struct FfprobeStream {
    codec_type: String,
    codec_name: Option<String>,
    channels: Option<u16>,
    bit_rate: Option<String>,
    sample_rate: Option<String>,
}

#[derive(Debug, Deserialize)]
struct FfprobeFormat {
    format_name: Option<String>,
    duration: Option<String>,
    bit_rate: Option<String>,
}

pub fn probe_audio_file(
    input_path: &Path,
    ffprobe_path: &Path,
) -> Result<AudioProbeResult, TranscodeError> {
    if !input_path.exists() {
        return Err(TranscodeError::InvalidInput(format!(
            "input file does not exist: {}",
            input_path.display()
        )));
    }
    if !input_path.is_file() {
        return Err(TranscodeError::InvalidInput(format!(
            "input path is not a file: {}",
            input_path.display()
        )));
    }

    let output = Command::new(ffprobe_path)
        .arg("-v")
        .arg("error")
        .arg("-print_format")
        .arg("json")
        .arg("-show_format")
        .arg("-show_streams")
        .arg(input_path)
        .output()
        .map_err(|error| TranscodeError::ProbeFailed(error.to_string()))?;

    if !output.status.success() {
        return Err(TranscodeError::ProbeFailed(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ));
    }

    let probe: FfprobeOutput = serde_json::from_slice(&output.stdout)?;
    let audio_stream = probe
        .streams
        .into_iter()
        .find(|stream| stream.codec_type == "audio");
    let Some(audio_stream) = audio_stream else {
        return Err(TranscodeError::ProbeFailed(
            "ffprobe did not report an audio stream".to_string(),
        ));
    };

    Ok(AudioProbeResult {
        format_name: probe.format.format_name,
        duration_secs: parse_f64(probe.format.duration.as_deref()),
        bit_rate_kbps: parse_bitrate_kbps(audio_stream.bit_rate.as_deref())
            .or_else(|| parse_bitrate_kbps(probe.format.bit_rate.as_deref())),
        codec_name: audio_stream.codec_name,
        sample_rate_hz: parse_u32(audio_stream.sample_rate.as_deref()),
        channels: audio_stream.channels,
    })
}

fn parse_u32(value: Option<&str>) -> Option<u32> {
    value?.trim().parse::<u32>().ok()
}

fn parse_f64(value: Option<&str>) -> Option<f64> {
    value?.trim().parse::<f64>().ok()
}

fn parse_bitrate_kbps(value: Option<&str>) -> Option<f64> {
    let raw = value?.trim();
    if raw.is_empty() || raw.eq_ignore_ascii_case("n/a") {
        return None;
    }
    let numeric = raw.parse::<f64>().ok()?;
    if numeric <= 0.0 {
        return None;
    }
    Some(numeric / 1000.0)
}

#[cfg(test)]
mod tests {
    use super::{parse_bitrate_kbps, parse_f64, parse_u32};

    #[test]
    fn parses_probe_scalars() {
        assert_eq!(parse_u32(Some("44100")), Some(44_100));
        assert_eq!(parse_f64(Some("120.5")), Some(120.5));
        assert_eq!(parse_bitrate_kbps(Some("320000")), Some(320.0));
        assert_eq!(parse_bitrate_kbps(Some("n/a")), None);
    }
}
