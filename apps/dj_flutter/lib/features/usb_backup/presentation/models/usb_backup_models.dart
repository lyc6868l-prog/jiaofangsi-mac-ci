import 'package:flutter/foundation.dart';

@immutable
class UsbBackupVolume {
  const UsbBackupVolume({
    required this.path,
    required this.volumeName,
    required this.filesystem,
    required this.normalizedFilesystem,
    required this.totalBytes,
    required this.freeBytes,
    required this.busProtocol,
    required this.serialNumber,
    required this.rekordboxDetected,
    required this.isCdjSupportedFs,
    required this.requiresFormatBeforeRestore,
    this.diskIdentifier,
    this.wholeDiskIdentifier,
  });

  final String path;
  final String volumeName;
  final String? filesystem;
  final String? normalizedFilesystem;
  final int totalBytes;
  final int freeBytes;
  final String? busProtocol;
  final String? serialNumber;
  final bool rekordboxDetected;
  final bool isCdjSupportedFs;
  final bool requiresFormatBeforeRestore;
  final String? diskIdentifier;
  final String? wholeDiskIdentifier;

  factory UsbBackupVolume.fromJson(Map<String, Object?> json) {
    return UsbBackupVolume(
      path: json['path'] as String? ?? '',
      volumeName: json['volume_name'] as String? ?? '',
      filesystem: json['filesystem'] as String?,
      normalizedFilesystem: json['normalized_filesystem'] as String?,
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      freeBytes: (json['free_bytes'] as num?)?.toInt() ?? 0,
      busProtocol: json['bus_protocol'] as String?,
      serialNumber: json['serial_number'] as String?,
      rekordboxDetected: json['rekordbox_detected'] as bool? ?? false,
      isCdjSupportedFs: json['is_cdj_supported_fs'] as bool? ?? false,
      requiresFormatBeforeRestore:
          json['requires_format_before_restore'] as bool? ?? true,
      diskIdentifier: json['disk_identifier'] as String?,
      wholeDiskIdentifier: json['whole_disk_identifier'] as String?,
    );
  }
}

@immutable
class UsbBackupDialogData {
  const UsbBackupDialogData({required this.title, required this.message});

  final String title;
  final String message;
}

@immutable
class UsbBackupCleanupResult {
  const UsbBackupCleanupResult({
    required this.deletedSnapshots,
    required this.deletedObjects,
    required this.deletedBytes,
    required this.snapshotId,
  });

  final int deletedSnapshots;
  final int deletedObjects;
  final int deletedBytes;
  final String? snapshotId;

  factory UsbBackupCleanupResult.fromJson(Map<String, Object?> json) {
    return UsbBackupCleanupResult(
      deletedSnapshots: (json['deleted_snapshots'] as num?)?.toInt() ?? 0,
      deletedObjects: (json['deleted_objects'] as num?)?.toInt() ?? 0,
      deletedBytes: (json['deleted_bytes'] as num?)?.toInt() ?? 0,
      snapshotId: json['snapshot_id'] as String?,
    );
  }
}

@immutable
class UsbBackupRekordboxSummary {
  const UsbBackupRekordboxSummary({
    required this.hasPioneerDir,
    required this.hasDotPioneerDir,
    required this.hasContentsDir,
    required this.hasExportLibraryDb,
    required this.audioFileCount,
    required this.artworkFileCount,
    required this.analysisFileCount,
    required this.playlistSyncCount,
    required this.databaseFileCount,
    required this.musicBytes,
  });

  final bool hasPioneerDir;
  final bool hasDotPioneerDir;
  final bool hasContentsDir;
  final bool hasExportLibraryDb;
  final int audioFileCount;
  final int artworkFileCount;
  final int analysisFileCount;
  final int playlistSyncCount;
  final int databaseFileCount;
  final int musicBytes;

  factory UsbBackupRekordboxSummary.fromJson(Map<String, Object?> json) {
    return UsbBackupRekordboxSummary(
      hasPioneerDir: json['has_pioneer_dir'] as bool? ?? false,
      hasDotPioneerDir: json['has_dot_pioneer_dir'] as bool? ?? false,
      hasContentsDir: json['has_contents_dir'] as bool? ?? false,
      hasExportLibraryDb: json['has_export_library_db'] as bool? ?? false,
      audioFileCount: (json['audio_file_count'] as num?)?.toInt() ?? 0,
      artworkFileCount: (json['artwork_file_count'] as num?)?.toInt() ?? 0,
      analysisFileCount: (json['analysis_file_count'] as num?)?.toInt() ?? 0,
      playlistSyncCount: (json['playlist_sync_count'] as num?)?.toInt() ?? 0,
      databaseFileCount: (json['database_file_count'] as num?)?.toInt() ?? 0,
      musicBytes: (json['music_bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class UsbBackupRestoreValidation {
  const UsbBackupRestoreValidation({
    required this.checkedAt,
    required this.targetRoot,
    required this.filesPresentOk,
    required this.rekordboxLayoutOk,
    required this.missingFiles,
    required this.mismatchedFiles,
    required this.message,
    required this.rekordboxSummary,
  });

  final String checkedAt;
  final String targetRoot;
  final bool filesPresentOk;
  final bool rekordboxLayoutOk;
  final int missingFiles;
  final int mismatchedFiles;
  final String message;
  final UsbBackupRekordboxSummary rekordboxSummary;

  factory UsbBackupRestoreValidation.fromJson(Map<String, Object?> json) {
    return UsbBackupRestoreValidation(
      checkedAt: json['checked_at'] as String? ?? '',
      targetRoot: json['target_root'] as String? ?? '',
      filesPresentOk: json['files_present_ok'] as bool? ?? false,
      rekordboxLayoutOk: json['rekordbox_layout_ok'] as bool? ?? false,
      missingFiles: (json['missing_files'] as num?)?.toInt() ?? 0,
      mismatchedFiles: (json['mismatched_files'] as num?)?.toInt() ?? 0,
      message: json['message'] as String? ?? '',
      rekordboxSummary: UsbBackupRekordboxSummary.fromJson(
        json['rekordbox_summary'] as Map<String, Object?>? ??
            const <String, Object?>{},
      ),
    );
  }
}

@immutable
class UsbBackupVersion {
  const UsbBackupVersion({
    required this.snapshotId,
    required this.displayName,
    required this.createdAt,
    required this.sourceVolumeName,
    required this.sourceFilesystem,
    required this.sourceCapacityBytes,
    required this.rekordboxDetected,
    required this.validateStatus,
    required this.totalFiles,
    required this.totalDirectories,
    required this.totalBytes,
    required this.canRestore,
    required this.disabledReason,
    required this.recommended,
    required this.rekordboxSummary,
  });

  final String snapshotId;
  final String displayName;
  final String createdAt;
  final String sourceVolumeName;
  final String? sourceFilesystem;
  final int? sourceCapacityBytes;
  final bool rekordboxDetected;
  final String validateStatus;
  final int totalFiles;
  final int totalDirectories;
  final int totalBytes;
  final bool canRestore;
  final String? disabledReason;
  final bool recommended;
  final UsbBackupRekordboxSummary? rekordboxSummary;

  factory UsbBackupVersion.fromJson(Map<String, Object?> json) {
    return UsbBackupVersion(
      snapshotId: json['snapshot_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      sourceVolumeName: json['source_volume_name'] as String? ?? '',
      sourceFilesystem: json['source_filesystem'] as String?,
      sourceCapacityBytes: (json['source_capacity_bytes'] as num?)?.toInt(),
      rekordboxDetected: json['rekordbox_detected'] as bool? ?? false,
      validateStatus: json['validate_status'] as String? ?? 'unknown',
      totalFiles: (json['total_files'] as num?)?.toInt() ?? 0,
      totalDirectories: (json['total_directories'] as num?)?.toInt() ?? 0,
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      canRestore: json['can_restore'] as bool? ?? true,
      disabledReason: json['disabled_reason'] as String?,
      recommended: json['recommended'] as bool? ?? false,
      rekordboxSummary: json['rekordbox_summary'] is Map<String, Object?>
          ? UsbBackupRekordboxSummary.fromJson(
              json['rekordbox_summary'] as Map<String, Object?>,
            )
          : null,
    );
  }
}

@immutable
class UsbBackupVersionListResult {
  const UsbBackupVersionListResult({
    required this.repoRoot,
    required this.versions,
    required this.latestVersions,
    required this.pendingBackups,
    required this.targetVolume,
    required this.canRestoreAny,
  });

  final String repoRoot;
  final List<UsbBackupVersion> versions;
  final List<UsbBackupVersion> latestVersions;
  final List<UsbBackupPendingBackup> pendingBackups;
  final UsbBackupVolume? targetVolume;
  final bool canRestoreAny;

  factory UsbBackupVersionListResult.fromJson(Map<String, Object?> json) {
    final List<Object?> rawVersions =
        json['versions'] as List<Object?>? ?? <Object?>[];
    final List<Object?> rawLatest =
        json['latest_versions'] as List<Object?>? ?? <Object?>[];
    return UsbBackupVersionListResult(
      repoRoot: json['repo_root'] as String? ?? '',
      versions: rawVersions
          .whereType<Map<String, Object?>>()
          .map(UsbBackupVersion.fromJson)
          .toList(),
      latestVersions: rawLatest
          .whereType<Map<String, Object?>>()
          .map(UsbBackupVersion.fromJson)
          .toList(),
      pendingBackups: (json['pending_backups'] as List<Object?>? ?? <Object?>[])
          .whereType<Map<String, Object?>>()
          .map(UsbBackupPendingBackup.fromJson)
          .toList(),
      targetVolume: json['target_volume'] is Map<String, Object?>
          ? UsbBackupVolume.fromJson(
              json['target_volume'] as Map<String, Object?>,
            )
          : null,
      canRestoreAny: json['can_restore_any'] as bool? ?? false,
    );
  }
}

@immutable
class UsbBackupPendingBackup {
  const UsbBackupPendingBackup({
    required this.checkpointId,
    required this.snapshotId,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    required this.sourceRoot,
    required this.sourceVolumeName,
    required this.totalFiles,
    required this.completedFiles,
    required this.totalBytes,
    required this.completedBytes,
    required this.rekordboxDetected,
    required this.rekordboxSummary,
  });

  final String checkpointId;
  final String snapshotId;
  final String displayName;
  final String createdAt;
  final String updatedAt;
  final String sourceRoot;
  final String sourceVolumeName;
  final int totalFiles;
  final int completedFiles;
  final int totalBytes;
  final int completedBytes;
  final bool rekordboxDetected;
  final UsbBackupRekordboxSummary? rekordboxSummary;

  double get progressFraction =>
      totalFiles <= 0 ? 0 : (completedFiles / totalFiles).clamp(0, 1);

  factory UsbBackupPendingBackup.fromJson(Map<String, Object?> json) {
    return UsbBackupPendingBackup(
      checkpointId: json['checkpoint_id'] as String? ?? '',
      snapshotId: json['snapshot_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
      sourceRoot: json['source_root'] as String? ?? '',
      sourceVolumeName: json['source_volume_name'] as String? ?? '',
      totalFiles: (json['total_files'] as num?)?.toInt() ?? 0,
      completedFiles: (json['completed_files'] as num?)?.toInt() ?? 0,
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      completedBytes: (json['completed_bytes'] as num?)?.toInt() ?? 0,
      rekordboxDetected: json['rekordbox_detected'] as bool? ?? false,
      rekordboxSummary: json['rekordbox_summary'] is Map<String, Object?>
          ? UsbBackupRekordboxSummary.fromJson(
              json['rekordbox_summary'] as Map<String, Object?>,
            )
          : null,
    );
  }
}

enum UsbBackupTaskStatus { idle, running, success, cancelled, error }

UsbBackupTaskStatus usbBackupTaskStatusFromValue(String value) {
  return switch (value) {
    'running' => UsbBackupTaskStatus.running,
    'success' => UsbBackupTaskStatus.success,
    'cancelled' => UsbBackupTaskStatus.cancelled,
    'error' => UsbBackupTaskStatus.error,
    _ => UsbBackupTaskStatus.idle,
  };
}

extension UsbBackupTaskStatusLabel on UsbBackupTaskStatus {
  String get label => switch (this) {
    UsbBackupTaskStatus.idle => '待命',
    UsbBackupTaskStatus.running => '进行中',
    UsbBackupTaskStatus.success => '已完成',
    UsbBackupTaskStatus.cancelled => '已取消',
    UsbBackupTaskStatus.error => '失败',
  };
}

@immutable
class UsbBackupTaskSnapshot {
  const UsbBackupTaskSnapshot({
    required this.taskId,
    required this.taskType,
    required this.status,
    required this.progress,
    required this.progressHintText,
    required this.displayName,
    required this.snapshotId,
    required this.totalFiles,
    required this.totalBytes,
    required this.restoredFiles,
    required this.validatedFiles,
    required this.errorMessage,
    required this.resumedFromCheckpoint,
    required this.checkpointId,
    required this.restoreValidation,
  });

  final String taskId;
  final String taskType;
  final UsbBackupTaskStatus status;
  final double progress;
  final String progressHintText;
  final String? displayName;
  final String? snapshotId;
  final int totalFiles;
  final int totalBytes;
  final int restoredFiles;
  final int validatedFiles;
  final String? errorMessage;
  final bool resumedFromCheckpoint;
  final String? checkpointId;
  final UsbBackupRestoreValidation? restoreValidation;

  const UsbBackupTaskSnapshot.idle()
    : taskId = '',
      taskType = '',
      status = UsbBackupTaskStatus.idle,
      progress = 0,
      progressHintText = '等待选择 U 盘并创建备份。',
      displayName = null,
      snapshotId = null,
      totalFiles = 0,
      totalBytes = 0,
      restoredFiles = 0,
      validatedFiles = 0,
      errorMessage = null,
      resumedFromCheckpoint = false,
      checkpointId = null,
      restoreValidation = null;

  factory UsbBackupTaskSnapshot.fromJson(Map<String, Object?> json) {
    final double rawProgress = (json['progress'] as num?)?.toDouble() ?? 0;
    return UsbBackupTaskSnapshot(
      taskId: json['task_id'] as String? ?? '',
      taskType: json['task_type'] as String? ?? '',
      status: usbBackupTaskStatusFromValue(json['status'] as String? ?? 'idle'),
      progress: rawProgress > 1 ? (rawProgress / 100).clamp(0, 1) : rawProgress,
      progressHintText: json['progress_hint_text'] as String? ?? '等待任务启动...',
      displayName: json['display_name'] as String?,
      snapshotId: json['snapshot_id'] as String?,
      totalFiles: (json['total_files'] as num?)?.toInt() ?? 0,
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      restoredFiles: (json['restored_files'] as num?)?.toInt() ?? 0,
      validatedFiles: (json['validated_files'] as num?)?.toInt() ?? 0,
      errorMessage: json['error_message'] as String?,
      resumedFromCheckpoint: json['resumed_from_checkpoint'] as bool? ?? false,
      checkpointId: json['checkpoint_id'] as String?,
      restoreValidation: json['restore_validation'] is Map<String, Object?>
          ? UsbBackupRestoreValidation.fromJson(
              json['restore_validation'] as Map<String, Object?>,
            )
          : null,
    );
  }
}

@immutable
class UsbBackupTaskEvent {
  const UsbBackupTaskEvent({
    required this.event,
    required this.taskId,
    required this.snapshot,
  });

  final String event;
  final String taskId;
  final UsbBackupTaskSnapshot snapshot;

  factory UsbBackupTaskEvent.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> data =
        json['data'] as Map<String, Object?>? ?? <String, Object?>{};
    return UsbBackupTaskEvent(
      event: json['event'] as String? ?? '',
      taskId: json['task_id'] as String? ?? '',
      snapshot: UsbBackupTaskSnapshot.fromJson(<String, Object?>{
        ...data,
        'task_id': json['task_id'],
      }),
    );
  }
}

class UsbBackupBridgeException implements Exception {
  const UsbBackupBridgeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

abstract interface class UsbBackupTaskBridge {
  Future<void> ensureStarted();
  Future<List<UsbBackupVolume>> listUsbVolumes({
    String? selectedPath,
    bool forceRefresh = false,
  });
  Future<UsbBackupVersionListResult> listBackupVersions({String? targetPath});
  Future<UsbBackupTaskSnapshot> startBackupUsb({
    required String sourcePath,
    String? displayName,
  });
  Future<UsbBackupTaskSnapshot> startRestoreSnapshotToUsb({
    required String snapshotId,
    required String targetPath,
    bool clearTarget = true,
  });
  Future<UsbBackupTaskSnapshot> startFormatUsb({
    required String targetPath,
    required String filesystem,
    required String volumeLabel,
  });
  Future<UsbBackupCleanupResult> deleteBackupVersion(String snapshotId);
  Future<UsbBackupCleanupResult> cleanupRepository();
  Future<Map<String, Object?>> ejectUsbVolume({required String targetPath});
  Future<UsbBackupTaskSnapshot> stopTask(String taskId);
  Future<List<UsbBackupTaskEvent>> subscribeTaskEvents({String? taskId});
  Future<void> close();
}
