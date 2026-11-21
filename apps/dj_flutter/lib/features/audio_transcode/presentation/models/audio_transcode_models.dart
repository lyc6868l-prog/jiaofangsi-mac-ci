import 'package:flutter/foundation.dart';

@immutable
class AudioTranscodeFileItem {
  final String path;
  final String name;

  const AudioTranscodeFileItem({required this.path, required this.name});
}

enum AudioTranscodeOutputFormat { mp3, wav, aiff, flac }

enum AudioTranscodeOutputLocation { sourceSubdir, custom }

extension AudioTranscodeOutputLocationValue on AudioTranscodeOutputLocation {
  String get value => switch (this) {
    AudioTranscodeOutputLocation.sourceSubdir => 'source_subdir',
    AudioTranscodeOutputLocation.custom => 'custom',
  };
}

extension AudioTranscodeOutputFormatValue on AudioTranscodeOutputFormat {
  String get value => switch (this) {
    AudioTranscodeOutputFormat.mp3 => 'mp3',
    AudioTranscodeOutputFormat.wav => 'wav',
    AudioTranscodeOutputFormat.aiff => 'aiff',
    AudioTranscodeOutputFormat.flac => 'flac',
  };

  String get label => switch (this) {
    AudioTranscodeOutputFormat.mp3 => 'MP3',
    AudioTranscodeOutputFormat.wav => 'WAV',
    AudioTranscodeOutputFormat.aiff => 'AIFF',
    AudioTranscodeOutputFormat.flac => 'FLAC',
  };
}

AudioTranscodeOutputFormat audioTranscodeOutputFormatFromValue(String value) {
  return switch (value) {
    'mp3' => AudioTranscodeOutputFormat.mp3,
    'wav' => AudioTranscodeOutputFormat.wav,
    'aiff' => AudioTranscodeOutputFormat.aiff,
    'flac' => AudioTranscodeOutputFormat.flac,
    _ => throw ArgumentError.value(value, 'value', '未知 output format'),
  };
}

enum AudioTranscodeStatus {
  idle,
  targetReady,
  configLocked,
  planReady,
  running,
  success,
  cancelled,
  error,
}

extension AudioTranscodeStatusValue on AudioTranscodeStatus {
  String get value => switch (this) {
    AudioTranscodeStatus.idle => 'idle',
    AudioTranscodeStatus.targetReady => 'target_ready',
    AudioTranscodeStatus.configLocked => 'config_locked',
    AudioTranscodeStatus.planReady => 'plan_ready',
    AudioTranscodeStatus.running => 'running',
    AudioTranscodeStatus.success => 'success',
    AudioTranscodeStatus.cancelled => 'cancelled',
    AudioTranscodeStatus.error => 'error',
  };

  String get label => switch (this) {
    AudioTranscodeStatus.idle => '待命',
    AudioTranscodeStatus.targetReady => '目标就绪',
    AudioTranscodeStatus.configLocked => '配置已锁定',
    AudioTranscodeStatus.planReady => '方案就绪',
    AudioTranscodeStatus.running => '转码中',
    AudioTranscodeStatus.success => '已完成',
    AudioTranscodeStatus.cancelled => '已取消',
    AudioTranscodeStatus.error => '出错',
  };
}

AudioTranscodeStatus audioTranscodeStatusFromValue(String value) {
  return switch (value) {
    'idle' => AudioTranscodeStatus.idle,
    'target_ready' => AudioTranscodeStatus.targetReady,
    'config_locked' => AudioTranscodeStatus.configLocked,
    'plan_ready' => AudioTranscodeStatus.planReady,
    'running' => AudioTranscodeStatus.running,
    'success' => AudioTranscodeStatus.success,
    'cancelled' => AudioTranscodeStatus.cancelled,
    'error' => AudioTranscodeStatus.error,
    _ => throw ArgumentError.value(value, 'value', '未知 status'),
  };
}

@immutable
class AudioTranscodeTaskSnapshot {
  final String taskId;
  final AudioTranscodeStatus status;
  final double progress;
  final String hintText;
  final int inputCount;
  final int plannedCount;
  final int successCount;
  final int failedCount;
  final String? error;
  final String? currentFilePath;
  final String? outputDirectory;

  const AudioTranscodeTaskSnapshot({
    required this.taskId,
    required this.status,
    required this.progress,
    required this.hintText,
    required this.inputCount,
    required this.plannedCount,
    required this.successCount,
    required this.failedCount,
    this.error,
    this.currentFilePath,
    this.outputDirectory,
  });

  factory AudioTranscodeTaskSnapshot.fromJson(Map<String, Object?> json) {
    final double rawProgress = (json['progress'] as num?)?.toDouble() ?? 0;
    return AudioTranscodeTaskSnapshot(
      taskId: json['task_id'] as String,
      status: audioTranscodeStatusFromValue(json['status'] as String),
      progress: rawProgress > 1 ? (rawProgress / 100).clamp(0, 1) : rawProgress,
      hintText: json['progress_hint_text'] as String? ?? '等待任务载入...',
      inputCount: (json['file_count'] as num?)?.toInt() ?? 0,
      plannedCount: (json['file_count'] as num?)?.toInt() ?? 0,
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      error: json['error'] as String?,
      currentFilePath: json['current_file_path'] as String?,
      outputDirectory:
          json['output_dir'] as String? ?? json['output_directory'] as String?,
    );
  }
}

@immutable
class AudioTranscodeTaskEvent {
  final String event;
  final String taskId;
  final AudioTranscodeTaskSnapshot snapshot;

  const AudioTranscodeTaskEvent({
    required this.event,
    required this.taskId,
    required this.snapshot,
  });

  factory AudioTranscodeTaskEvent.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> data =
        json['data'] as Map<String, Object?>? ?? <String, Object?>{};
    return AudioTranscodeTaskEvent(
      event: json['event'] as String,
      taskId: json['task_id'] as String,
      snapshot: AudioTranscodeTaskSnapshot.fromJson(<String, Object?>{
        ...data,
        'task_id': json['task_id'],
      }),
    );
  }
}

@immutable
class AudioTranscodeResultItem {
  final String inputPath;
  final String? outputPath;
  final AudioTranscodeOutputFormat outputFormat;
  final String stateLabel;
  final bool success;
  final String? error;

  const AudioTranscodeResultItem({
    required this.inputPath,
    required this.outputPath,
    required this.outputFormat,
    required this.stateLabel,
    required this.success,
    required this.error,
  });

  factory AudioTranscodeResultItem.fromJson(Map<String, Object?> json) {
    return AudioTranscodeResultItem(
      inputPath: json['input_path'] as String,
      outputPath: json['output_path'] as String?,
      outputFormat: audioTranscodeOutputFormatFromValue(
        json['format'] as String? ?? 'mp3',
      ),
      stateLabel: (json['success'] as bool? ?? false) ? '已完成' : '失败',
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }
}

@immutable
class AudioTranscodeResult {
  final String taskId;
  final AudioTranscodeStatus status;
  final int successCount;
  final int failedCount;
  final List<AudioTranscodeResultItem> results;

  const AudioTranscodeResult({
    required this.taskId,
    required this.status,
    required this.successCount,
    required this.failedCount,
    required this.results,
  });

  factory AudioTranscodeResult.fromJson(Map<String, Object?> json) {
    final List<Object?> rawResults =
        json['results'] as List<Object?>? ?? <Object?>[];
    return AudioTranscodeResult(
      taskId: json['task_id'] as String,
      status: audioTranscodeStatusFromValue(json['status'] as String),
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      results: rawResults
          .whereType<Map<String, Object?>>()
          .map(AudioTranscodeResultItem.fromJson)
          .toList(),
    );
  }
}

@immutable
class AudioTranscodeCompletedTaskRecord {
  final String taskId;
  final AudioTranscodeStatus status;
  final DateTime finishedAt;
  final String outputDirectory;
  final List<AudioTranscodeFileItem> inputFiles;
  final int successCount;
  final int failedCount;
  final List<AudioTranscodeResultItem> results;
  final String? message;

  const AudioTranscodeCompletedTaskRecord({
    required this.taskId,
    required this.status,
    required this.finishedAt,
    required this.outputDirectory,
    required this.inputFiles,
    required this.successCount,
    required this.failedCount,
    required this.results,
    required this.message,
  });

  bool get hasFailures => failedCount > 0;
}

class AudioTranscodeBridgeException implements Exception {
  final String code;
  final String message;

  const AudioTranscodeBridgeException(this.code, this.message);

  @override
  String toString() => message;
}

abstract class AudioTranscodeTaskBridge {
  Future<void> ensureStarted();
  Future<List<String>> loadTargets(List<String> filePaths);
  Future<void> lockConfig(Map<String, Object?> config);
  Future<AudioTranscodeTaskSnapshot> startAudioTranscodeTask();
  Future<AudioTranscodeTaskSnapshot> stopTask(String taskId);
  Future<List<AudioTranscodeTaskEvent>> subscribeTaskEvents({String? taskId});
  Future<AudioTranscodeResult> fetchTranscodeResult(String taskId);
  Future<void> close();
}
