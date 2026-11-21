import 'package:flutter/foundation.dart';

@immutable
class PinyinGeneratorFileItem {
  final String path;
  final String name;

  const PinyinGeneratorFileItem({required this.path, required this.name});
}

enum PinyinGeneratorWriteMode { overwrite, append }

extension PinyinGeneratorWriteModeValue on PinyinGeneratorWriteMode {
  String get value => switch (this) {
    PinyinGeneratorWriteMode.overwrite => 'overwrite',
    PinyinGeneratorWriteMode.append => 'append',
  };

  String get label => switch (this) {
    PinyinGeneratorWriteMode.overwrite => '覆盖写入',
    PinyinGeneratorWriteMode.append => '追加写入',
  };
}

PinyinGeneratorWriteMode pinyinGeneratorWriteModeFromValue(String value) {
  return switch (value) {
    'overwrite' => PinyinGeneratorWriteMode.overwrite,
    'append' => PinyinGeneratorWriteMode.append,
    _ => throw ArgumentError.value(value, 'value', '未知 write mode'),
  };
}

enum PinyinGeneratorStatus {
  idle,
  targetReady,
  configLocked,
  planReady,
  running,
  success,
  cancelled,
  error,
}

extension PinyinGeneratorStatusValue on PinyinGeneratorStatus {
  String get value => switch (this) {
    PinyinGeneratorStatus.idle => 'idle',
    PinyinGeneratorStatus.targetReady => 'target_ready',
    PinyinGeneratorStatus.configLocked => 'config_locked',
    PinyinGeneratorStatus.planReady => 'plan_ready',
    PinyinGeneratorStatus.running => 'running',
    PinyinGeneratorStatus.success => 'success',
    PinyinGeneratorStatus.cancelled => 'cancelled',
    PinyinGeneratorStatus.error => 'error',
  };

  String get label => switch (this) {
    PinyinGeneratorStatus.idle => '待命',
    PinyinGeneratorStatus.targetReady => '目标就绪',
    PinyinGeneratorStatus.configLocked => '配置已锁定',
    PinyinGeneratorStatus.planReady => '方案就绪',
    PinyinGeneratorStatus.running => '写入中',
    PinyinGeneratorStatus.success => '已完成',
    PinyinGeneratorStatus.cancelled => '已取消',
    PinyinGeneratorStatus.error => '出错',
  };
}

PinyinGeneratorStatus pinyinGeneratorStatusFromValue(String value) {
  return switch (value) {
    'idle' => PinyinGeneratorStatus.idle,
    'target_ready' => PinyinGeneratorStatus.targetReady,
    'config_locked' => PinyinGeneratorStatus.configLocked,
    'plan_ready' => PinyinGeneratorStatus.planReady,
    'running' => PinyinGeneratorStatus.running,
    'success' => PinyinGeneratorStatus.success,
    'cancelled' => PinyinGeneratorStatus.cancelled,
    'error' => PinyinGeneratorStatus.error,
    _ => throw ArgumentError.value(value, 'value', '未知 status'),
  };
}

@immutable
class PinyinGeneratorLoadResult {
  final List<String> filePaths;
  final String? warningMessage;
  final int skippedWavCount;

  const PinyinGeneratorLoadResult({
    required this.filePaths,
    required this.warningMessage,
    required this.skippedWavCount,
  });

  factory PinyinGeneratorLoadResult.fromJson(Map<String, Object?> json) {
    final List<Object?> rawPaths =
        json['file_paths'] as List<Object?>? ?? <Object?>[];
    return PinyinGeneratorLoadResult(
      filePaths: rawPaths.whereType<String>().toList(),
      warningMessage: json['warning_message'] as String?,
      skippedWavCount: (json['skipped_wav_count'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class PinyinGeneratorTaskSnapshot {
  final String taskId;
  final PinyinGeneratorStatus status;
  final double progress;
  final String hintText;
  final int inputCount;
  final int successCount;
  final int skippedCount;
  final int failedCount;

  const PinyinGeneratorTaskSnapshot({
    required this.taskId,
    required this.status,
    required this.progress,
    required this.hintText,
    required this.inputCount,
    required this.successCount,
    required this.skippedCount,
    required this.failedCount,
  });

  factory PinyinGeneratorTaskSnapshot.fromJson(Map<String, Object?> json) {
    final double rawProgress = (json['progress'] as num?)?.toDouble() ?? 0;
    return PinyinGeneratorTaskSnapshot(
      taskId: json['task_id'] as String,
      status: pinyinGeneratorStatusFromValue(json['status'] as String),
      progress: rawProgress > 1 ? (rawProgress / 100).clamp(0, 1) : rawProgress,
      hintText: json['progress_hint_text'] as String? ?? '等待首拼任务载入...',
      inputCount: (json['file_count'] as num?)?.toInt() ?? 0,
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      skippedCount: (json['skipped_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class PinyinGeneratorTaskEvent {
  final String event;
  final String taskId;
  final PinyinGeneratorTaskSnapshot snapshot;

  const PinyinGeneratorTaskEvent({
    required this.event,
    required this.taskId,
    required this.snapshot,
  });

  factory PinyinGeneratorTaskEvent.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> data =
        json['data'] as Map<String, Object?>? ?? <String, Object?>{};
    return PinyinGeneratorTaskEvent(
      event: json['event'] as String,
      taskId: json['task_id'] as String,
      snapshot: PinyinGeneratorTaskSnapshot.fromJson(<String, Object?>{
        ...data,
        'task_id': json['task_id'],
      }),
    );
  }
}

enum PinyinGeneratorItemStatus { success, skipped, failed }

extension PinyinGeneratorItemStatusValue on PinyinGeneratorItemStatus {
  String get value => switch (this) {
    PinyinGeneratorItemStatus.success => 'success',
    PinyinGeneratorItemStatus.skipped => 'skipped',
    PinyinGeneratorItemStatus.failed => 'failed',
  };

  String get label => switch (this) {
    PinyinGeneratorItemStatus.success => '成功',
    PinyinGeneratorItemStatus.skipped => '跳过',
    PinyinGeneratorItemStatus.failed => '失败',
  };
}

PinyinGeneratorItemStatus pinyinGeneratorItemStatusFromValue(String value) {
  return switch (value) {
    'success' => PinyinGeneratorItemStatus.success,
    'skipped' => PinyinGeneratorItemStatus.skipped,
    'failed' => PinyinGeneratorItemStatus.failed,
    _ => throw ArgumentError.value(value, 'value', '未知 item status'),
  };
}

@immutable
class PinyinGeneratorResultItem {
  final String inputPath;
  final String inputName;
  final String titleSource;
  final String sourceTitle;
  final bool containsChinese;
  final String? generatedInitials;
  final String? albumBefore;
  final String? albumAfter;
  final PinyinGeneratorItemStatus status;
  final String message;

  const PinyinGeneratorResultItem({
    required this.inputPath,
    required this.inputName,
    required this.titleSource,
    required this.sourceTitle,
    required this.containsChinese,
    required this.generatedInitials,
    required this.albumBefore,
    required this.albumAfter,
    required this.status,
    required this.message,
  });

  factory PinyinGeneratorResultItem.fromJson(Map<String, Object?> json) {
    return PinyinGeneratorResultItem(
      inputPath: json['input_path'] as String,
      inputName: json['input_name'] as String? ?? '',
      titleSource: json['title_source'] as String? ?? 'filename',
      sourceTitle: json['source_title'] as String? ?? '',
      containsChinese: json['contains_chinese'] as bool? ?? false,
      generatedInitials: json['generated_initials'] as String?,
      albumBefore: json['album_before'] as String?,
      albumAfter: json['album_after'] as String?,
      status: pinyinGeneratorItemStatusFromValue(
        json['status'] as String? ?? 'failed',
      ),
      message: json['message'] as String? ?? '',
    );
  }
}

@immutable
class PinyinGeneratorResult {
  final String taskId;
  final PinyinGeneratorStatus status;
  final int successCount;
  final int skippedCount;
  final int failedCount;
  final List<PinyinGeneratorResultItem> results;

  const PinyinGeneratorResult({
    required this.taskId,
    required this.status,
    required this.successCount,
    required this.skippedCount,
    required this.failedCount,
    required this.results,
  });

  factory PinyinGeneratorResult.fromJson(Map<String, Object?> json) {
    final List<Object?> rawResults =
        json['results'] as List<Object?>? ?? <Object?>[];
    return PinyinGeneratorResult(
      taskId: json['task_id'] as String,
      status: pinyinGeneratorStatusFromValue(json['status'] as String),
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      skippedCount: (json['skipped_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      results: rawResults
          .whereType<Map<String, Object?>>()
          .map(PinyinGeneratorResultItem.fromJson)
          .toList(),
    );
  }
}

@immutable
class PinyinGeneratorCompletedTaskRecord {
  final String taskId;
  final PinyinGeneratorStatus status;
  final DateTime finishedAt;
  final List<PinyinGeneratorFileItem> inputFiles;
  final int successCount;
  final int skippedCount;
  final int failedCount;
  final List<PinyinGeneratorResultItem> results;
  final String? message;
  final String locationSummary;

  const PinyinGeneratorCompletedTaskRecord({
    required this.taskId,
    required this.status,
    required this.finishedAt,
    required this.inputFiles,
    required this.successCount,
    required this.skippedCount,
    required this.failedCount,
    required this.results,
    required this.message,
    required this.locationSummary,
  });

  bool get hasFailures =>
      failedCount > 0 || status == PinyinGeneratorStatus.error;
}

class PinyinGeneratorBridgeException implements Exception {
  final String code;
  final String message;

  const PinyinGeneratorBridgeException(this.code, this.message);

  @override
  String toString() => message;
}

abstract class PinyinGeneratorTaskBridge {
  Future<void> ensureStarted();
  Future<PinyinGeneratorLoadResult> loadTargets(List<String> filePaths);
  Future<void> lockConfig(Map<String, Object?> config);
  Future<PinyinGeneratorTaskSnapshot> startPinyinGeneratorTask();
  Future<PinyinGeneratorTaskSnapshot> stopTask(String taskId);
  Future<List<PinyinGeneratorTaskEvent>> subscribeTaskEvents({String? taskId});
  Future<PinyinGeneratorResult> fetchPinyinGeneratorResult(String taskId);
  Future<void> close();
}
