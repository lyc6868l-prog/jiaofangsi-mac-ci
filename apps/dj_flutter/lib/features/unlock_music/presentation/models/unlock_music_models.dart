import 'package:flutter/foundation.dart';

@immutable
class UnlockMusicFileItem {
  final String path;
  final String name;

  const UnlockMusicFileItem({required this.path, required this.name});
}

@immutable
class UnlockMusicLoadResult {
  final List<String> filePaths;
  final List<String> addedPaths;
  final List<String> skippedPaths;

  const UnlockMusicLoadResult({
    required this.filePaths,
    required this.addedPaths,
    required this.skippedPaths,
  });

  factory UnlockMusicLoadResult.fromJson(Map<String, Object?> json) {
    final List<Object?> rawFilePaths =
        json['file_paths'] as List<Object?>? ?? <Object?>[];
    final List<Object?> rawAddedPaths =
        json['added_paths'] as List<Object?>? ?? <Object?>[];
    final List<Object?> rawSkippedPaths =
        json['skipped_paths'] as List<Object?>? ?? <Object?>[];
    return UnlockMusicLoadResult(
      filePaths: rawFilePaths.whereType<String>().toList(),
      addedPaths: rawAddedPaths.whereType<String>().toList(),
      skippedPaths: rawSkippedPaths.whereType<String>().toList(),
    );
  }
}

enum UnlockMusicStatus {
  idle,
  targetReady,
  configLocked,
  running,
  success,
  cancelled,
  error,
}

extension UnlockMusicStatusValue on UnlockMusicStatus {
  String get value => switch (this) {
    UnlockMusicStatus.idle => 'idle',
    UnlockMusicStatus.targetReady => 'target_ready',
    UnlockMusicStatus.configLocked => 'config_locked',
    UnlockMusicStatus.running => 'running',
    UnlockMusicStatus.success => 'success',
    UnlockMusicStatus.cancelled => 'cancelled',
    UnlockMusicStatus.error => 'error',
  };
}

UnlockMusicStatus unlockMusicStatusFromValue(String value) {
  return switch (value) {
    'idle' => UnlockMusicStatus.idle,
    'target_ready' => UnlockMusicStatus.targetReady,
    'config_locked' => UnlockMusicStatus.configLocked,
    'running' => UnlockMusicStatus.running,
    'success' => UnlockMusicStatus.success,
    'cancelled' => UnlockMusicStatus.cancelled,
    'error' => UnlockMusicStatus.error,
    _ => throw ArgumentError.value(value, 'value', '未知 status'),
  };
}

@immutable
class UnlockMusicTaskSnapshot {
  final String taskId;
  final UnlockMusicStatus status;
  final double progress;
  final String progressHintText;
  final int fileCount;
  final int successCount;
  final int failedCount;

  const UnlockMusicTaskSnapshot({
    required this.taskId,
    required this.status,
    required this.progress,
    required this.progressHintText,
    required this.fileCount,
    required this.successCount,
    required this.failedCount,
  });

  factory UnlockMusicTaskSnapshot.fromJson(Map<String, Object?> json) {
    return UnlockMusicTaskSnapshot(
      taskId: json['task_id'] as String,
      status: unlockMusicStatusFromValue(json['status'] as String),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      progressHintText: json['progress_hint_text'] as String? ?? '等待任务载入...',
      fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class UnlockMusicTaskEvent {
  final String event;
  final String taskId;
  final UnlockMusicTaskSnapshot snapshot;

  const UnlockMusicTaskEvent({
    required this.event,
    required this.taskId,
    required this.snapshot,
  });

  factory UnlockMusicTaskEvent.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> data =
        json['data'] as Map<String, Object?>? ?? <String, Object?>{};
    return UnlockMusicTaskEvent(
      event: json['event'] as String,
      taskId: json['task_id'] as String,
      snapshot: UnlockMusicTaskSnapshot.fromJson(<String, Object?>{
        ...data,
        'task_id': json['task_id'],
      }),
    );
  }
}

@immutable
class UnlockMusicResultItem {
  final String inputPath;
  final String? outputPath;
  final bool success;
  final String? format;
  final String? error;

  const UnlockMusicResultItem({
    required this.inputPath,
    required this.outputPath,
    required this.success,
    required this.format,
    required this.error,
  });

  factory UnlockMusicResultItem.fromJson(Map<String, Object?> json) {
    return UnlockMusicResultItem(
      inputPath: json['input_path'] as String,
      outputPath: json['output_path'] as String?,
      success: json['success'] as bool? ?? false,
      format: json['format'] as String?,
      error: json['error'] as String?,
    );
  }
}

@immutable
class UnlockMusicResult {
  final String taskId;
  final UnlockMusicStatus status;
  final int successCount;
  final int failedCount;
  final List<UnlockMusicResultItem> results;

  const UnlockMusicResult({
    required this.taskId,
    required this.status,
    required this.successCount,
    required this.failedCount,
    required this.results,
  });

  factory UnlockMusicResult.fromJson(Map<String, Object?> json) {
    final List<Object?> rawResults =
        json['results'] as List<Object?>? ?? <Object?>[];
    return UnlockMusicResult(
      taskId: json['task_id'] as String,
      status: unlockMusicStatusFromValue(json['status'] as String),
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      results: rawResults
          .whereType<Map<String, Object?>>()
          .map(UnlockMusicResultItem.fromJson)
          .toList(),
    );
  }
}

@immutable
class UnlockMusicCompletedTaskRecord {
  final String taskId;
  final UnlockMusicStatus status;
  final DateTime finishedAt;
  final String outputDirectory;
  final List<UnlockMusicFileItem> inputFiles;
  final int successCount;
  final int failedCount;
  final List<UnlockMusicResultItem> results;
  final String? message;

  const UnlockMusicCompletedTaskRecord({
    required this.taskId,
    required this.status,
    required this.finishedAt,
    required this.outputDirectory,
    required this.inputFiles,
    required this.successCount,
    required this.failedCount,
    required this.results,
    this.message,
  });

  bool get hasFailures => failedCount > 0 || status == UnlockMusicStatus.error;

  bool get isAllSuccess =>
      status == UnlockMusicStatus.success && failedCount == 0;
}

class UnlockMusicBridgeException implements Exception {
  final String code;
  final String message;

  const UnlockMusicBridgeException(this.code, this.message);

  @override
  String toString() => message;
}

abstract class UnlockMusicTaskBridge {
  Future<void> ensureStarted();
  Future<UnlockMusicLoadResult> loadTargets(
    List<String> filePaths, {
    bool append = false,
  });
  Future<UnlockMusicLoadResult> removeTarget(String filePath);
  Future<UnlockMusicLoadResult> clearTargets();
  Future<void> lockConfig(Map<String, Object?> config);
  Future<UnlockMusicTaskSnapshot> startUnlockTask();
  Future<UnlockMusicTaskSnapshot> stopTask(String taskId);
  Future<List<UnlockMusicTaskEvent>> subscribeTaskEvents({String? taskId});
  Future<UnlockMusicResult> fetchUnlockResult(String taskId);
  Future<void> close();
}
