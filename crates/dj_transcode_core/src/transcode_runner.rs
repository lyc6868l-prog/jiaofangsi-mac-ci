use std::collections::VecDeque;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::time::Duration;

use crate::audio_probe::{probe_audio_file, AudioProbeResult};
use crate::ffmpeg_builder::build_ffmpeg_command;
use crate::progress_parser::{parse_ffmpeg_progress_line, TranscodeProgress};
use crate::transcode_task::{TranscodeCompletion, TranscodeError, TranscodeTask};

pub fn run_transcode_task<F>(
    task: &TranscodeTask,
    ffmpeg_path: &Path,
    ffprobe_path: &Path,
    cancel_flag: &AtomicBool,
    mut on_progress: F,
) -> Result<TranscodeCompletion, TranscodeError>
where
    F: FnMut(TranscodeProgress),
{
    if cancel_flag.load(Ordering::Relaxed) {
        return Err(TranscodeError::Cancelled(task.id.clone()));
    }

    fs::create_dir_all(&task.output_dir)?;
    let probe = probe_audio_file(&task.input_path, ffprobe_path)?;
    let command_spec = build_ffmpeg_command(
        ffmpeg_path,
        &task.input_path,
        &task.output_dir,
        &task.preset,
    )?;

    let mut child = Command::new(&command_spec.program)
        .args(&command_spec.args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| TranscodeError::SpawnFailed(error.to_string()))?;

    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| TranscodeError::SpawnFailed("missing stderr pipe".to_string()))?;
    let (stderr_tx, stderr_rx) = mpsc::channel::<Result<String, std::io::Error>>();
    std::thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines() {
            if stderr_tx.send(line).is_err() {
                break;
            }
        }
    });
    let mut stderr_tail = VecDeque::with_capacity(20);
    let status = loop {
        if cancel_flag.load(Ordering::Relaxed) {
            let _ = child.kill();
            let _ = child.wait();
            let _ = fs::remove_file(&command_spec.output_path);
            return Err(TranscodeError::Cancelled(task.id.clone()));
        }

        match stderr_rx.recv_timeout(Duration::from_millis(100)) {
            Ok(Ok(line)) => {
                if stderr_tail.len() == 20 {
                    stderr_tail.pop_front();
                }
                stderr_tail.push_back(line.clone());

                if let Some(progress) = parse_ffmpeg_progress_line(
                    &line,
                    probe.duration_secs.filter(|value| *value > 0.0),
                ) {
                    on_progress(progress);
                }
            }
            Ok(Err(error)) => return Err(TranscodeError::Io(error)),
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if let Some(status) = child.try_wait()? {
                    break status;
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                if let Some(status) = child.try_wait()? {
                    break status;
                }
                std::thread::sleep(Duration::from_millis(50));
            }
        }
    };
    if cancel_flag.load(Ordering::Relaxed) {
        return Err(TranscodeError::Cancelled(task.id.clone()));
    }
    if !status.success() {
        let _ = fs::remove_file(&command_spec.output_path);
        return Err(TranscodeError::NonZeroExit {
            code: status.code(),
            stderr_tail: stderr_tail.into_iter().collect::<Vec<_>>().join("\n"),
        });
    }

    probe_audio_file(&command_spec.output_path, ffprobe_path)?;

    Ok(TranscodeCompletion {
        id: task.id.clone(),
        input_path: task.input_path.clone(),
        output_path: command_spec.output_path,
        probe,
    })
}

pub fn completed_progress(probe: &AudioProbeResult) -> TranscodeProgress {
    let elapsed_secs = probe.duration_secs.unwrap_or(0.0);
    TranscodeProgress {
        elapsed_secs,
        total_secs: probe.duration_secs,
        percent: 100.0,
        raw_line: "completed".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::{completed_progress, run_transcode_task};
    use std::fs;
    use std::path::PathBuf;
    use std::process::Command;
    use std::sync::atomic::AtomicBool;

    use tempfile::tempdir;

    use crate::transcode_preset::{Mp3Preset, TranscodePreset};
    use crate::transcode_task::{TranscodeError, TranscodeTask};

    fn write_executable(path: &PathBuf, content: &str) {
        fs::write(path, content).expect("write helper script");
        let status = Command::new("chmod")
            .arg("+x")
            .arg(path)
            .status()
            .expect("chmod helper script");
        assert!(status.success());
    }

    fn build_task(root: &std::path::Path) -> TranscodeTask {
        let input_path = root.join("input.wav");
        fs::write(&input_path, b"fake audio").expect("write input file");
        TranscodeTask {
            id: "task-001".to_string(),
            input_path,
            output_dir: root.join("out"),
            preset: TranscodePreset::Mp3(Mp3Preset::default()),
        }
    }

    #[test]
    fn completed_progress_marks_task_as_finished() {
        let probe = crate::audio_probe::AudioProbeResult {
            format_name: Some("wav".to_string()),
            duration_secs: Some(12.5),
            bit_rate_kbps: Some(320.0),
            codec_name: Some("pcm_s16le".to_string()),
            sample_rate_hz: Some(44_100),
            channels: Some(2),
        };

        let progress = completed_progress(&probe);
        assert_eq!(progress.elapsed_secs, 12.5);
        assert_eq!(progress.total_secs, Some(12.5));
        assert_eq!(progress.percent, 100.0);
        assert_eq!(progress.raw_line, "completed");
    }

    #[test]
    fn run_transcode_task_returns_cancelled_before_work_starts() {
        let dir = tempdir().expect("create temp dir");
        let task = build_task(dir.path());
        let cancel_flag = AtomicBool::new(true);
        let result = run_transcode_task(
            &task,
            std::path::Path::new("/missing/ffmpeg"),
            std::path::Path::new("/missing/ffprobe"),
            &cancel_flag,
            |_| {},
        );

        assert!(matches!(result, Err(TranscodeError::Cancelled(task_id)) if task_id == task.id));
    }

    #[test]
    fn run_transcode_task_returns_non_zero_exit_with_stderr_tail() {
        let dir = tempdir().expect("create temp dir");
        let ffprobe_path = dir.path().join("fake_ffprobe.sh");
        let ffmpeg_path = dir.path().join("fake_ffmpeg.sh");
        write_executable(
            &ffprobe_path,
            "#!/bin/sh\ncat <<'EOF'\n{\"streams\":[{\"codec_type\":\"audio\",\"codec_name\":\"pcm_s16le\",\"channels\":2,\"sample_rate\":\"44100\",\"bit_rate\":\"320000\"}],\"format\":{\"format_name\":\"wav\",\"duration\":\"30.0\",\"bit_rate\":\"320000\"}}\nEOF\n",
        );
        write_executable(
            &ffmpeg_path,
            "#!/bin/sh\necho 'size=     512kB time=00:00:10.00 bitrate= 139.8kbits/s speed=4.4x' 1>&2\necho 'mock ffmpeg failure' 1>&2\nexit 7\n",
        );
        let task = build_task(dir.path());
        let cancel_flag = AtomicBool::new(false);
        let mut updates = Vec::new();

        let result = run_transcode_task(
            &task,
            ffmpeg_path.as_path(),
            ffprobe_path.as_path(),
            &cancel_flag,
            |progress| updates.push(progress),
        );

        assert_eq!(updates.len(), 1);
        assert_eq!(updates[0].elapsed_secs, 10.0);
        assert_eq!(updates[0].percent, 33.33333333333333);
        assert!(matches!(
            result,
            Err(TranscodeError::NonZeroExit { code: Some(7), stderr_tail })
            if stderr_tail.contains("mock ffmpeg failure")
        ));
    }
}
