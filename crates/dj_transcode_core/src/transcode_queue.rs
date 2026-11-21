use std::collections::{HashMap, VecDeque};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::Arc;
use std::thread;

use crate::progress_parser::TranscodeProgress;
use crate::transcode_runner::{completed_progress, run_transcode_task};
use crate::transcode_task::{
    TranscodeCompletion, TranscodeError, TranscodeTask, TranscodeTaskSnapshot, TranscodeTaskStatus,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TranscodeToolchain {
    pub ffmpeg_path: PathBuf,
    pub ffprobe_path: PathBuf,
}

impl Default for TranscodeToolchain {
    fn default() -> Self {
        Self {
            ffmpeg_path: PathBuf::from("ffmpeg"),
            ffprobe_path: PathBuf::from("ffprobe"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TranscodeQueueConfig {
    pub max_concurrency: usize,
    pub toolchain: TranscodeToolchain,
}

impl Default for TranscodeQueueConfig {
    fn default() -> Self {
        Self {
            max_concurrency: 2,
            toolchain: TranscodeToolchain::default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum TranscodeQueueEvent {
    Queued(TranscodeTaskSnapshot),
    Started(TranscodeTaskSnapshot),
    Progress(TranscodeTaskSnapshot),
    Completed(TranscodeTaskSnapshot),
    Cancelled(TranscodeTaskSnapshot),
    Failed(TranscodeTaskSnapshot),
}

enum WorkerMessage {
    Progress {
        task_id: String,
        progress: TranscodeProgress,
    },
    Finished {
        task_id: String,
        result: Result<TranscodeCompletion, TranscodeError>,
    },
}

struct RunningTask {
    cancel_flag: Arc<AtomicBool>,
    snapshot: TranscodeTaskSnapshot,
}

type QueueRunner = Arc<
    dyn Fn(TranscodeTask, TranscodeToolchain, Arc<AtomicBool>, Sender<WorkerMessage>) + Send + Sync,
>;

pub struct TranscodeQueue {
    state: QueueState,
    worker_tx: Sender<WorkerMessage>,
    worker_rx: Receiver<WorkerMessage>,
    runner: QueueRunner,
    toolchain: TranscodeToolchain,
}

struct QueueState {
    max_concurrency: usize,
    pending: VecDeque<TranscodeTask>,
    running: HashMap<String, RunningTask>,
    queued_events: VecDeque<TranscodeQueueEvent>,
}

impl TranscodeQueue {
    pub fn new(config: TranscodeQueueConfig) -> Self {
        Self::new_with_runner(config, default_runner())
    }

    fn new_with_runner(config: TranscodeQueueConfig, runner: QueueRunner) -> Self {
        let (worker_tx, worker_rx) = mpsc::channel();
        Self {
            state: QueueState {
                max_concurrency: config.max_concurrency.max(1),
                pending: VecDeque::new(),
                running: HashMap::new(),
                queued_events: VecDeque::new(),
            },
            worker_tx,
            worker_rx,
            runner,
            toolchain: config.toolchain,
        }
    }

    pub fn enqueue(&mut self, task: TranscodeTask) -> Result<(), TranscodeError> {
        if self.state.running.contains_key(&task.id)
            || self.state.pending.iter().any(|queued| queued.id == task.id)
        {
            return Err(TranscodeError::InvalidInput(format!(
                "duplicate task id: {}",
                task.id
            )));
        }

        let snapshot = queued_snapshot(&task, TranscodeTaskStatus::Queued, 0.0, "task queued");
        self.state
            .queued_events
            .push_back(TranscodeQueueEvent::Queued(snapshot));
        self.state.pending.push_back(task);
        self.spawn_available();
        Ok(())
    }

    pub fn set_max_concurrency(&mut self, value: usize) -> Result<(), TranscodeError> {
        if value == 0 {
            return Err(TranscodeError::InvalidInput(
                "max_concurrency must be at least 1".to_string(),
            ));
        }
        self.state.max_concurrency = value;
        self.spawn_available();
        Ok(())
    }

    pub fn cancel(&mut self, task_id: &str) -> Result<(), TranscodeError> {
        if let Some(index) = self
            .state
            .pending
            .iter()
            .position(|task| task.id == task_id)
        {
            let task = self
                .state
                .pending
                .remove(index)
                .expect("pending index is valid");
            let snapshot = queued_snapshot(
                &task,
                TranscodeTaskStatus::Cancelled,
                0.0,
                "task cancelled before execution",
            );
            self.state
                .queued_events
                .push_back(TranscodeQueueEvent::Cancelled(snapshot));
            return Ok(());
        }

        if let Some(running) = self.state.running.get(task_id) {
            running.cancel_flag.store(true, Ordering::Relaxed);
            return Ok(());
        }

        Err(TranscodeError::TaskNotFound(task_id.to_string()))
    }

    pub fn poll_events(&mut self) -> Vec<TranscodeQueueEvent> {
        let mut events = Vec::new();
        while let Some(event) = self.state.queued_events.pop_front() {
            events.push(event);
        }

        loop {
            match self.worker_rx.try_recv() {
                Ok(message) => self.handle_worker_message(message, &mut events),
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => break,
            }
        }

        self.spawn_available();
        while let Some(event) = self.state.queued_events.pop_front() {
            events.push(event);
        }
        events
    }

    fn handle_worker_message(
        &mut self,
        message: WorkerMessage,
        events: &mut Vec<TranscodeQueueEvent>,
    ) {
        match message {
            WorkerMessage::Progress { task_id, progress } => {
                if let Some(running) = self.state.running.get_mut(&task_id) {
                    running.snapshot.progress = progress.percent;
                    running.snapshot.message = format!(
                        "elapsed {:.2}s / {}",
                        progress.elapsed_secs,
                        progress
                            .total_secs
                            .map(|value| format!("{value:.2}s"))
                            .unwrap_or_else(|| "unknown".to_string())
                    );
                    events.push(TranscodeQueueEvent::Progress(running.snapshot.clone()));
                }
            }
            WorkerMessage::Finished { task_id, result } => {
                let Some(mut running) = self.state.running.remove(&task_id) else {
                    return;
                };
                match result {
                    Ok(completion) => {
                        let progress = completed_progress(&completion.probe);
                        running.snapshot.status = TranscodeTaskStatus::Completed;
                        running.snapshot.progress = progress.percent;
                        running.snapshot.message = "task completed".to_string();
                        running.snapshot.output_path = Some(completion.output_path);
                        running.snapshot.error = None;
                        events.push(TranscodeQueueEvent::Completed(running.snapshot));
                    }
                    Err(TranscodeError::Cancelled(_)) => {
                        running.snapshot.status = TranscodeTaskStatus::Cancelled;
                        running.snapshot.message = "task cancelled".to_string();
                        running.snapshot.error = None;
                        events.push(TranscodeQueueEvent::Cancelled(running.snapshot));
                    }
                    Err(error) => {
                        running.snapshot.status = TranscodeTaskStatus::Failed;
                        running.snapshot.message = "task failed".to_string();
                        running.snapshot.error = Some(error.to_string());
                        events.push(TranscodeQueueEvent::Failed(running.snapshot));
                    }
                }
            }
        }
    }

    fn spawn_available(&mut self) {
        while self.state.running.len() < self.state.max_concurrency {
            let Some(task) = self.state.pending.pop_front() else {
                break;
            };
            let snapshot =
                queued_snapshot(&task, TranscodeTaskStatus::Running, 0.0, "task started");
            self.state
                .queued_events
                .push_back(TranscodeQueueEvent::Started(snapshot.clone()));
            let cancel_flag = Arc::new(AtomicBool::new(false));
            let worker_sender = self.worker_tx.clone();
            let runner = Arc::clone(&self.runner);
            let toolchain = self.toolchain.clone();
            let task_clone = task.clone();
            let cancel_flag_clone = Arc::clone(&cancel_flag);
            thread::spawn(move || {
                runner(task_clone, toolchain, cancel_flag_clone, worker_sender);
            });
            self.state.running.insert(
                task.id.clone(),
                RunningTask {
                    cancel_flag,
                    snapshot,
                },
            );
        }
    }
}

fn queued_snapshot(
    task: &TranscodeTask,
    status: TranscodeTaskStatus,
    progress: f64,
    message: &str,
) -> TranscodeTaskSnapshot {
    TranscodeTaskSnapshot {
        id: task.id.clone(),
        status,
        progress,
        message: message.to_string(),
        input_path: task.input_path.clone(),
        output_path: None,
        error: None,
    }
}

fn default_runner() -> QueueRunner {
    Arc::new(
        |task: TranscodeTask,
         toolchain: TranscodeToolchain,
         cancel_flag: Arc<AtomicBool>,
         sender: Sender<WorkerMessage>| {
            let task_id = task.id.clone();
            let result = run_transcode_task(
                &task,
                &toolchain.ffmpeg_path,
                &toolchain.ffprobe_path,
                cancel_flag.as_ref(),
                |progress| {
                    let _ = sender.send(WorkerMessage::Progress {
                        task_id: task_id.clone(),
                        progress,
                    });
                },
            );
            let _ = sender.send(WorkerMessage::Finished { task_id, result });
        },
    )
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::mpsc::Sender;
    use std::sync::Arc;
    use std::thread;
    use std::time::Duration;

    use crate::transcode_preset::{Mp3Preset, TranscodePreset};
    use crate::transcode_task::{
        TranscodeCompletion, TranscodeError, TranscodeTask, TranscodeTaskStatus,
    };

    use super::{
        QueueRunner, TranscodeQueue, TranscodeQueueConfig, TranscodeQueueEvent, TranscodeToolchain,
        WorkerMessage,
    };
    use crate::audio_probe::AudioProbeResult;
    use std::path::PathBuf;

    fn task(id: &str) -> TranscodeTask {
        TranscodeTask {
            id: id.to_string(),
            input_path: PathBuf::from(format!("/tmp/{id}.wav")),
            output_dir: PathBuf::from("/tmp/out"),
            preset: TranscodePreset::Mp3(Mp3Preset::default()),
        }
    }

    fn fake_runner(started: Arc<AtomicUsize>) -> QueueRunner {
        Arc::new(
            move |task: TranscodeTask,
                  _toolchain: TranscodeToolchain,
                  cancel_flag: Arc<AtomicBool>,
                  sender: Sender<WorkerMessage>| {
                started.fetch_add(1, Ordering::SeqCst);
                let _ = sender.send(WorkerMessage::Progress {
                    task_id: task.id.clone(),
                    progress: crate::progress_parser::TranscodeProgress {
                        elapsed_secs: 1.0,
                        total_secs: Some(4.0),
                        percent: 25.0,
                        raw_line: "time=00:00:01.00".to_string(),
                    },
                });
                thread::sleep(Duration::from_millis(60));
                let result = if cancel_flag.load(Ordering::Relaxed) {
                    Err(TranscodeError::Cancelled(task.id.clone()))
                } else {
                    Ok(TranscodeCompletion {
                        id: task.id.clone(),
                        input_path: task.input_path.clone(),
                        output_path: task.output_dir.join(format!("{}.mp3", task.id)),
                        probe: AudioProbeResult {
                            format_name: Some("wav".to_string()),
                            duration_secs: Some(4.0),
                            bit_rate_kbps: Some(1411.0),
                            codec_name: Some("pcm_s16le".to_string()),
                            sample_rate_hz: Some(44_100),
                            channels: Some(2),
                        },
                    })
                };
                let _ = sender.send(WorkerMessage::Finished {
                    task_id: task.id,
                    result,
                });
            },
        )
    }

    #[test]
    fn queue_respects_concurrency_limit() {
        let started = Arc::new(AtomicUsize::new(0));
        let runner = fake_runner(Arc::clone(&started));
        let mut queue = TranscodeQueue::new_with_runner(
            TranscodeQueueConfig {
                max_concurrency: 1,
                toolchain: TranscodeToolchain::default(),
            },
            runner,
        );

        queue.enqueue(task("task_a")).expect("enqueue task_a");
        queue.enqueue(task("task_b")).expect("enqueue task_b");
        let first_events = queue.poll_events();
        assert!(first_events.iter().any(|event| matches!(event, TranscodeQueueEvent::Started(snapshot) if snapshot.id == "task_a")));
        assert!(!first_events.iter().any(|event| matches!(event, TranscodeQueueEvent::Started(snapshot) if snapshot.id == "task_b")));

        thread::sleep(Duration::from_millis(100));
        let second_events = queue.poll_events();
        assert!(second_events.iter().any(|event| matches!(event, TranscodeQueueEvent::Completed(snapshot) if snapshot.id == "task_a")));
        assert!(second_events.iter().any(|event| matches!(event, TranscodeQueueEvent::Started(snapshot) if snapshot.id == "task_b")));
        for _ in 0..5 {
            if started.load(Ordering::SeqCst) == 2 {
                break;
            }
            thread::sleep(Duration::from_millis(20));
        }
        assert_eq!(started.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn queue_cancels_pending_task_immediately() {
        let mut queue = TranscodeQueue::new_with_runner(
            TranscodeQueueConfig {
                max_concurrency: 1,
                toolchain: TranscodeToolchain::default(),
            },
            fake_runner(Arc::new(AtomicUsize::new(0))),
        );

        queue.enqueue(task("task_a")).expect("enqueue task_a");
        queue.enqueue(task("task_b")).expect("enqueue task_b");
        let _ = queue.poll_events();
        queue.cancel("task_b").expect("cancel pending task");
        let events = queue.poll_events();
        assert!(events.iter().any(|event| matches!(event, TranscodeQueueEvent::Cancelled(snapshot) if snapshot.id == "task_b" && snapshot.status == TranscodeTaskStatus::Cancelled)));
    }
}
