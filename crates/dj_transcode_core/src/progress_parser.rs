use regex::Regex;
use serde::{Deserialize, Serialize};
use std::sync::LazyLock;

static TIME_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"time=\s*(\d+(?::\d+){0,3}(?:\.\d+)?)").expect("valid time regex")
});

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TranscodeProgress {
    pub elapsed_secs: f64,
    pub total_secs: Option<f64>,
    pub percent: f64,
    pub raw_line: String,
}

pub fn parse_ffmpeg_timestamp(value: &str) -> Option<f64> {
    let parts: Vec<&str> = value.trim().split(':').collect();
    match parts.as_slice() {
        [seconds] => seconds.parse::<f64>().ok(),
        [minutes, seconds] => {
            let minutes = minutes.parse::<f64>().ok()?;
            let seconds = seconds.parse::<f64>().ok()?;
            Some((minutes * 60.0) + seconds)
        }
        [hours, minutes, seconds] => {
            let hours = hours.parse::<f64>().ok()?;
            let minutes = minutes.parse::<f64>().ok()?;
            let seconds = seconds.parse::<f64>().ok()?;
            Some((hours * 3600.0) + (minutes * 60.0) + seconds)
        }
        _ => None,
    }
}

pub fn parse_ffmpeg_progress_line(
    line: &str,
    total_duration_secs: Option<f64>,
) -> Option<TranscodeProgress> {
    let captures = TIME_REGEX.captures(line)?;
    let elapsed_text = captures.get(1)?.as_str();
    let elapsed_secs = parse_ffmpeg_timestamp(elapsed_text)?;
    let percent = total_duration_secs
        .filter(|duration| *duration > 0.0)
        .map(|duration| ((elapsed_secs / duration) * 100.0).clamp(0.0, 100.0))
        .unwrap_or(0.0);

    Some(TranscodeProgress {
        elapsed_secs,
        total_secs: total_duration_secs,
        percent,
        raw_line: line.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::{parse_ffmpeg_progress_line, parse_ffmpeg_timestamp};

    #[test]
    fn parses_timestamps() {
        assert_eq!(parse_ffmpeg_timestamp("00:00:12.50"), Some(12.5));
        assert_eq!(parse_ffmpeg_timestamp("01:02:03.00"), Some(3723.0));
        assert_eq!(parse_ffmpeg_timestamp("75.0"), Some(75.0));
        assert_eq!(parse_ffmpeg_timestamp("invalid"), None);
    }

    #[test]
    fn parses_progress_line_with_percentage() {
        let update = parse_ffmpeg_progress_line(
            "size=     512kB time=00:00:30.00 bitrate= 139.8kbits/s speed=4.4x",
            Some(120.0),
        )
        .expect("progress should parse");
        assert_eq!(update.elapsed_secs, 30.0);
        assert_eq!(update.percent, 25.0);
    }
}
