import 'package:flutter/foundation.dart';

@immutable
class FileItem {
  final String path;
  final String name;
  final String? size;

  const FileItem({required this.path, required this.name, this.size});

  factory FileItem.fromJson(Map<String, Object?> json) {
    return FileItem(
      path: json['path'] as String,
      name: json['name'] as String,
      size: json['size'] as String?,
    );
  }

  Map<String, Object?> toJson() => {'path': path, 'name': name, 'size': size};
}

@immutable
class DuplicateGroup {
  final String groupName;
  final List<DuplicateEntry> entries;

  const DuplicateGroup({required this.groupName, required this.entries});

  factory DuplicateGroup.fromJson(Map<String, Object?> json) {
    final List<Object?> rawEntries =
        json['entries'] as List<Object?>? ?? <Object?>[];
    return DuplicateGroup(
      groupName: json['group_name'] as String,
      entries: rawEntries
          .whereType<Map<String, Object?>>()
          .map(DuplicateEntry.fromJson)
          .toList(),
    );
  }

  DuplicateGroup copyWith({String? groupName, List<DuplicateEntry>? entries}) {
    return DuplicateGroup(
      groupName: groupName ?? this.groupName,
      entries: entries ?? this.entries,
    );
  }
}

@immutable
class DuplicateEntry {
  final FileItem file;
  final bool isAutoKeep;
  final bool isSelectedToDelete;

  const DuplicateEntry({
    required this.file,
    this.isAutoKeep = false,
    this.isSelectedToDelete = false,
  });

  factory DuplicateEntry.fromJson(Map<String, Object?> json) {
    return DuplicateEntry(
      file: FileItem.fromJson(json),
      isAutoKeep: json['is_auto_keep'] as bool? ?? false,
      isSelectedToDelete: json['is_selected_to_delete'] as bool? ?? false,
    );
  }

  DuplicateEntry copyWith({bool? isSelectedToDelete}) {
    return DuplicateEntry(
      file: file,
      isAutoKeep: isAutoKeep,
      isSelectedToDelete: isSelectedToDelete ?? this.isSelectedToDelete,
    );
  }
}

enum CleanupDupStatus {
  idle,
  targetReady,
  configLocked,
  running,
  reviewReady,
  executing,
  success,
  cancelled,
  error,
}

enum CleanupDupPanelKind { titleClean, duplicateSearch }

enum CleanupDupTaskType { titleClean, duplicateCheck }

enum CleanupDupErrorCode {
  invalidModule,
  invalidConfig,
  emptyTargets,
  targetNotFound,
  taskNotFound,
  taskAlreadyRunning,
  taskNotReviewReady,
  deleteSelectionEmpty,
  fileDeleteFailed,
  internalError,
}

extension CleanupDupErrorCodeValue on CleanupDupErrorCode {
  String get value => switch (this) {
    CleanupDupErrorCode.invalidModule => 'INVALID_MODULE',
    CleanupDupErrorCode.invalidConfig => 'INVALID_CONFIG',
    CleanupDupErrorCode.emptyTargets => 'EMPTY_TARGETS',
    CleanupDupErrorCode.targetNotFound => 'TARGET_NOT_FOUND',
    CleanupDupErrorCode.taskNotFound => 'TASK_NOT_FOUND',
    CleanupDupErrorCode.taskAlreadyRunning => 'TASK_ALREADY_RUNNING',
    CleanupDupErrorCode.taskNotReviewReady => 'TASK_NOT_REVIEW_READY',
    CleanupDupErrorCode.deleteSelectionEmpty => 'DELETE_SELECTION_EMPTY',
    CleanupDupErrorCode.fileDeleteFailed => 'FILE_DELETE_FAILED',
    CleanupDupErrorCode.internalError => 'INTERNAL_ERROR',
  };
}

extension CleanupDupPanelKindValue on CleanupDupPanelKind {
  String get value => switch (this) {
    CleanupDupPanelKind.titleClean => 'title_clean',
    CleanupDupPanelKind.duplicateSearch => 'duplicate_search',
  };
}

extension CleanupDupTaskTypeValue on CleanupDupTaskType {
  String get value => switch (this) {
    CleanupDupTaskType.titleClean => 'title_clean',
    CleanupDupTaskType.duplicateCheck => 'duplicate_check',
  };
}

extension CleanupDupStatusValue on CleanupDupStatus {
  String get value => switch (this) {
    CleanupDupStatus.idle => 'idle',
    CleanupDupStatus.targetReady => 'target_ready',
    CleanupDupStatus.configLocked => 'config_locked',
    CleanupDupStatus.running => 'running',
    CleanupDupStatus.reviewReady => 'review_ready',
    CleanupDupStatus.executing => 'executing',
    CleanupDupStatus.success => 'success',
    CleanupDupStatus.cancelled => 'cancelled',
    CleanupDupStatus.error => 'error',
  };
}

CleanupDupPanelKind cleanupDupPanelKindFromValue(String value) {
  return switch (value) {
    'title_clean' => CleanupDupPanelKind.titleClean,
    'duplicate_search' => CleanupDupPanelKind.duplicateSearch,
    _ => throw ArgumentError.value(value, 'value', '未知 panel'),
  };
}

CleanupDupTaskType cleanupDupTaskTypeFromValue(String value) {
  return switch (value) {
    'title_clean' => CleanupDupTaskType.titleClean,
    'duplicate_check' => CleanupDupTaskType.duplicateCheck,
    _ => throw ArgumentError.value(value, 'value', '未知 task_type'),
  };
}

CleanupDupStatus cleanupDupStatusFromValue(String value) {
  return switch (value) {
    'idle' => CleanupDupStatus.idle,
    'target_ready' => CleanupDupStatus.targetReady,
    'config_locked' => CleanupDupStatus.configLocked,
    'running' => CleanupDupStatus.running,
    'review_ready' => CleanupDupStatus.reviewReady,
    'executing' => CleanupDupStatus.executing,
    'success' => CleanupDupStatus.success,
    'cancelled' => CleanupDupStatus.cancelled,
    'error' => CleanupDupStatus.error,
    _ => throw ArgumentError.value(value, 'value', '未知 status'),
  };
}

@immutable
class CleanupDupApiError {
  final String code;
  final String message;

  const CleanupDupApiError({required this.code, required this.message});

  Map<String, Object?> toJson() => {'code': code, 'message': message};
}

@immutable
class CleanupDupApiEnvelope<T> {
  final bool ok;
  final T? data;
  final CleanupDupApiError? error;

  const CleanupDupApiEnvelope({required this.ok, this.data, this.error});

  Map<String, Object?> toJson(Object? Function(T value)? encodeData) => {
    'ok': ok,
    'data': data == null ? null : encodeData?.call(data as T) ?? data,
    'error': error?.toJson(),
  };
}

@immutable
class CleanupDupTaskSnapshot {
  final String taskId;
  final CleanupDupPanelKind panel;
  final CleanupDupTaskType taskType;
  final CleanupDupStatus status;
  final double progress;
  final String progressHintText;
  final int fileCount;
  final int duplicateCount;

  const CleanupDupTaskSnapshot({
    required this.taskId,
    required this.panel,
    required this.taskType,
    required this.status,
    required this.progress,
    required this.progressHintText,
    required this.fileCount,
    required this.duplicateCount,
  });

  factory CleanupDupTaskSnapshot.fromJson(Map<String, Object?> json) {
    return CleanupDupTaskSnapshot(
      taskId: json['task_id'] as String,
      panel: cleanupDupPanelKindFromValue(json['panel'] as String),
      taskType: cleanupDupTaskTypeFromValue(json['task_type'] as String),
      status: cleanupDupStatusFromValue(json['status'] as String),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      progressHintText: json['progress_hint_text'] as String? ?? '等待任务载入...',
      fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
      duplicateCount: (json['duplicate_count'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class CleanupDupReviewResult {
  final String taskId;
  final CleanupDupPanelKind panel;
  final CleanupDupStatus status;
  final int duplicateCount;
  final List<DuplicateGroup> groups;

  const CleanupDupReviewResult({
    required this.taskId,
    required this.panel,
    required this.status,
    required this.duplicateCount,
    required this.groups,
  });

  factory CleanupDupReviewResult.fromJson(Map<String, Object?> json) {
    final List<Object?> rawGroups =
        json['groups'] as List<Object?>? ?? <Object?>[];
    return CleanupDupReviewResult(
      taskId: json['task_id'] as String,
      panel: cleanupDupPanelKindFromValue(json['panel'] as String),
      status: cleanupDupStatusFromValue(json['status'] as String),
      duplicateCount: (json['duplicate_count'] as num?)?.toInt() ?? 0,
      groups: rawGroups
          .whereType<Map<String, Object?>>()
          .map(DuplicateGroup.fromJson)
          .toList(),
    );
  }
}

@immutable
class CleanupDupDeleteResult {
  final String taskId;
  final int deletedCount;
  final bool moveToRecycleBin;
  final CleanupDupStatus status;

  const CleanupDupDeleteResult({
    required this.taskId,
    required this.deletedCount,
    required this.moveToRecycleBin,
    required this.status,
  });

  factory CleanupDupDeleteResult.fromJson(Map<String, Object?> json) {
    return CleanupDupDeleteResult(
      taskId: json['task_id'] as String,
      deletedCount: (json['deleted_count'] as num?)?.toInt() ?? 0,
      moveToRecycleBin: json['move_to_recycle_bin'] as bool? ?? true,
      status: cleanupDupStatusFromValue(json['status'] as String),
    );
  }
}

@immutable
class CleanupDupTaskEvent {
  final String event;
  final String taskId;
  final CleanupDupTaskSnapshot snapshot;

  const CleanupDupTaskEvent({
    required this.event,
    required this.taskId,
    required this.snapshot,
  });

  factory CleanupDupTaskEvent.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> data =
        json['data'] as Map<String, Object?>? ?? <String, Object?>{};
    return CleanupDupTaskEvent(
      event: json['event'] as String,
      taskId: json['task_id'] as String,
      snapshot: CleanupDupTaskSnapshot.fromJson(<String, Object?>{
        ...data,
        'task_id': json['task_id'],
      }),
    );
  }
}

@immutable
class CleanupDupCompletedTaskRecord {
  final String taskId;
  final CleanupDupPanelKind panel;
  final CleanupDupStatus status;
  final DateTime finishedAt;
  final List<FileItem> inputFiles;
  final int processedCount;
  final String? message;

  const CleanupDupCompletedTaskRecord({
    required this.taskId,
    required this.panel,
    required this.status,
    required this.finishedAt,
    required this.inputFiles,
    required this.processedCount,
    this.message,
  });

  bool get hasFailures => status == CleanupDupStatus.error;
  bool get isAllSuccess => status == CleanupDupStatus.success;
}

class CleanupDupBridgeException implements Exception {
  final String code;
  final String message;

  const CleanupDupBridgeException(this.code, this.message);

  @override
  String toString() => message;
}

abstract class CleanupDupTaskBridge {
  Future<void> ensureStarted();
  Future<List<String>> loadTargets(
    CleanupDupPanelKind panel,
    List<String> filePaths,
  );
  Future<void> lockConfig(
    CleanupDupPanelKind panel,
    Map<String, Object?> config,
  );
  Future<CleanupDupTaskSnapshot> startTitleCleanTask();
  Future<CleanupDupTaskSnapshot> startDuplicateCheckTask();
  Future<CleanupDupTaskSnapshot> stopTask(String taskId);
  Future<CleanupDupReviewResult> fetchReviewResult(String taskId);
  Future<CleanupDupDeleteResult> executeDelete({
    required String taskId,
    required bool moveToRecycleBin,
    required List<FileItem> selectedFiles,
  });
  Future<List<CleanupDupTaskEvent>> subscribeTaskEvents({String? taskId});
  Future<void> close();
}
