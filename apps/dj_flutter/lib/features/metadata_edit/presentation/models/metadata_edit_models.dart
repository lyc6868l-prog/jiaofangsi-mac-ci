import 'package:flutter/foundation.dart';

enum MetadataEditPanelKind { cover, filename }

enum MetadataEditStatus {
  idle,
  targetReady,
  configLocked,
  running,
  success,
  cancelled,
  error,
}

enum MetadataEditTaskType { coverInjection, filenameInjection }

enum MetadataEditItemStatus { ok, skip, need, fail }

extension MetadataEditStatusValue on MetadataEditStatus {
  String get value => switch (this) {
    MetadataEditStatus.idle => 'idle',
    MetadataEditStatus.targetReady => 'target_ready',
    MetadataEditStatus.configLocked => 'config_locked',
    MetadataEditStatus.running => 'running',
    MetadataEditStatus.success => 'success',
    MetadataEditStatus.cancelled => 'cancelled',
    MetadataEditStatus.error => 'error',
  };
}

MetadataEditStatus metadataEditStatusFromValue(String value) {
  return switch (value) {
    'idle' => MetadataEditStatus.idle,
    'target_ready' => MetadataEditStatus.targetReady,
    'config_locked' => MetadataEditStatus.configLocked,
    'running' => MetadataEditStatus.running,
    'success' => MetadataEditStatus.success,
    'cancelled' => MetadataEditStatus.cancelled,
    'error' => MetadataEditStatus.error,
    _ => throw ArgumentError.value(value, 'value', '未知 status'),
  };
}

MetadataEditTaskType metadataEditTaskTypeFromValue(String value) {
  return switch (value) {
    'cover_injection' => MetadataEditTaskType.coverInjection,
    'filename_injection' => MetadataEditTaskType.filenameInjection,
    _ => throw ArgumentError.value(value, 'value', '未知 task_type'),
  };
}

MetadataEditItemStatus metadataEditItemStatusFromValue(String value) {
  return switch (value) {
    'ok' => MetadataEditItemStatus.ok,
    'skip' => MetadataEditItemStatus.skip,
    'need' => MetadataEditItemStatus.need,
    'fail' => MetadataEditItemStatus.fail,
    _ => throw ArgumentError.value(value, 'value', '未知 item status'),
  };
}

@immutable
class MetadataEditFileItem {
  const MetadataEditFileItem({required this.path, required this.name});

  final String path;
  final String name;
}

@immutable
class MetadataEditTaskSnapshot {
  const MetadataEditTaskSnapshot({
    required this.taskId,
    required this.taskType,
    required this.status,
    required this.progress,
    required this.hintText,
    required this.fileCount,
    required this.successCount,
    required this.skippedCount,
    required this.needCount,
    required this.failedCount,
  });

  final String taskId;
  final MetadataEditTaskType taskType;
  final MetadataEditStatus status;
  final double progress;
  final String hintText;
  final int fileCount;
  final int successCount;
  final int skippedCount;
  final int needCount;
  final int failedCount;

  factory MetadataEditTaskSnapshot.fromJson(Map<String, Object?> json) {
    return MetadataEditTaskSnapshot(
      taskId: json['task_id'] as String? ?? '',
      taskType: metadataEditTaskTypeFromValue(
        json['task_type'] as String? ?? 'filename_injection',
      ),
      status: metadataEditStatusFromValue(json['status'] as String? ?? 'idle'),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      hintText: json['progress_hint_text'] as String? ?? '等待任务载入...',
      fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      skippedCount: (json['skipped_count'] as num?)?.toInt() ?? 0,
      needCount: (json['need_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
    );
  }

  static const MetadataEditTaskSnapshot idleCover = MetadataEditTaskSnapshot(
    taskId: '',
    taskType: MetadataEditTaskType.coverInjection,
    status: MetadataEditStatus.idle,
    progress: 0,
    hintText: '等待任务载入...',
    fileCount: 0,
    successCount: 0,
    skippedCount: 0,
    needCount: 0,
    failedCount: 0,
  );

  static const MetadataEditTaskSnapshot idleFilename = MetadataEditTaskSnapshot(
    taskId: '',
    taskType: MetadataEditTaskType.filenameInjection,
    status: MetadataEditStatus.idle,
    progress: 0,
    hintText: '等待任务载入...',
    fileCount: 0,
    successCount: 0,
    skippedCount: 0,
    needCount: 0,
    failedCount: 0,
  );
}

@immutable
class MetadataEditResultItem {
  const MetadataEditResultItem({
    required this.status,
    required this.inputPath,
    required this.outputPath,
    required this.changed,
    required this.backupPath,
    required this.message,
  });

  final MetadataEditItemStatus status;
  final String inputPath;
  final String outputPath;
  final bool changed;
  final String? backupPath;
  final String message;

  factory MetadataEditResultItem.fromJson(Map<String, Object?> json) {
    return MetadataEditResultItem(
      status: metadataEditItemStatusFromValue(
        json['status'] as String? ?? 'fail',
      ),
      inputPath: json['input_path'] as String? ?? '',
      outputPath: json['output_path'] as String? ?? '',
      changed: json['changed'] as bool? ?? false,
      backupPath: json['backup_path'] as String?,
      message: json['message'] as String? ?? '',
    );
  }
}

@immutable
class MetadataEditResult {
  const MetadataEditResult({
    required this.taskId,
    required this.status,
    required this.results,
    required this.successCount,
    required this.skippedCount,
    required this.needCount,
    required this.failedCount,
    required this.logLines,
  });

  final String taskId;
  final MetadataEditStatus status;
  final List<MetadataEditResultItem> results;
  final int successCount;
  final int skippedCount;
  final int needCount;
  final int failedCount;
  final List<String> logLines;

  factory MetadataEditResult.fromJson(Map<String, Object?> json) {
    final List<Object?> rawResults =
        json['results'] as List<Object?>? ?? <Object?>[];
    final List<Object?> rawLogs =
        json['log_lines'] as List<Object?>? ?? <Object?>[];
    return MetadataEditResult(
      taskId: json['task_id'] as String? ?? '',
      status: metadataEditStatusFromValue(json['status'] as String? ?? 'idle'),
      results: rawResults
          .whereType<Map<String, Object?>>()
          .map(MetadataEditResultItem.fromJson)
          .toList(),
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      skippedCount: (json['skipped_count'] as num?)?.toInt() ?? 0,
      needCount: (json['need_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      logLines: rawLogs.whereType<String>().toList(),
    );
  }
}

@immutable
class MetadataEditCompletedTaskRecord {
  const MetadataEditCompletedTaskRecord({
    required this.panel,
    required this.taskId,
    required this.status,
    required this.finishedAt,
    required this.inputFiles,
    required this.successCount,
    required this.skippedCount,
    required this.needCount,
    required this.failedCount,
    required this.results,
    required this.message,
  });

  final MetadataEditPanelKind panel;
  final String taskId;
  final MetadataEditStatus status;
  final DateTime finishedAt;
  final List<MetadataEditFileItem> inputFiles;
  final int successCount;
  final int skippedCount;
  final int needCount;
  final int failedCount;
  final List<MetadataEditResultItem> results;
  final String? message;

  bool get hasFailures => failedCount > 0 || status == MetadataEditStatus.error;
}

@immutable
class MetadataEditTaskEvent {
  const MetadataEditTaskEvent({
    required this.event,
    required this.taskId,
    required this.snapshot,
  });

  final String event;
  final String taskId;
  final MetadataEditTaskSnapshot snapshot;

  factory MetadataEditTaskEvent.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> data =
        json['data'] as Map<String, Object?>? ?? <String, Object?>{};
    return MetadataEditTaskEvent(
      event: json['event'] as String? ?? '',
      taskId: json['task_id'] as String? ?? '',
      snapshot: MetadataEditTaskSnapshot.fromJson(<String, Object?>{
        ...data,
        'task_id': json['task_id'],
      }),
    );
  }
}

class MetadataEditBridgeException implements Exception {
  MetadataEditBridgeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

abstract interface class MetadataEditTaskBridge {
  Future<void> ensureStarted();
  Future<List<String>> loadTargets(List<String> filePaths);
  Future<void> lockConfig(Map<String, Object?> config);
  Future<MetadataEditTaskSnapshot> startCoverInjectionTask();
  Future<MetadataEditTaskSnapshot> startFilenameInjectionTask();
  Future<MetadataEditTaskSnapshot> stopTask(String taskId);
  Future<List<MetadataEditTaskEvent>> subscribeTaskEvents({String? taskId});
  Future<MetadataEditResult> fetchMetadataEditResult(String taskId);
  Future<List<String>> loadTemplates();
  Future<List<String>> saveTemplate(String template);
  Future<List<String>> deleteTemplate(String template);
  Future<void> close();
}
