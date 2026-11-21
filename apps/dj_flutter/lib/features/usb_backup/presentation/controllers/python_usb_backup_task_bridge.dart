import 'package:dj_flutter/shared/python_rpc/python_rpc_client.dart';

import '../models/usb_backup_models.dart';

class PythonUsbBackupTaskBridge implements UsbBackupTaskBridge {
  PythonUsbBackupTaskBridge({
    required String pythonExecutable,
    required String workingDirectory,
    required String scriptModule,
  }) : _client = PythonRpcClient(
         pythonExecutable: pythonExecutable,
         workingDirectory: workingDirectory,
         scriptModule: scriptModule,
         requestTimeout: const Duration(seconds: 120),
       );

  final PythonRpcClient _client;

  @override
  Future<void> ensureStarted() => _call<void>(() => _client.ensureStarted());

  @override
  Future<List<UsbBackupVolume>> listUsbVolumes({
    String? selectedPath,
    bool forceRefresh = false,
  }) async {
    final Map<String, Object?> data = await _request(
      action: 'list_usb_volumes',
      payload: <String, Object?>{
        if (selectedPath case final String value) 'selected_path': value,
        if (forceRefresh) 'force_refresh': true,
      },
    );
    final List<Object?> rawVolumes =
        data['volumes'] as List<Object?>? ?? <Object?>[];
    return rawVolumes
        .whereType<Map<String, Object?>>()
        .map(UsbBackupVolume.fromJson)
        .toList();
  }

  @override
  Future<UsbBackupVersionListResult> listBackupVersions({
    String? targetPath,
  }) async {
    final Map<String, Object?> data = await _request(
      action: 'list_backup_versions',
      payload: targetPath == null
          ? const <String, Object?>{}
          : <String, Object?>{'target_path': targetPath},
    );
    return UsbBackupVersionListResult.fromJson(data);
  }

  @override
  Future<UsbBackupTaskSnapshot> startBackupUsb({
    required String sourcePath,
    String? displayName,
  }) async {
    final Map<String, Object?> data = await _request(
      action: 'start_backup_usb',
      payload: <String, Object?>{
        'source_path': sourcePath,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName,
      },
    );
    return UsbBackupTaskSnapshot.fromJson(data);
  }

  @override
  Future<UsbBackupTaskSnapshot> startRestoreSnapshotToUsb({
    required String snapshotId,
    required String targetPath,
    bool clearTarget = true,
  }) async {
    final Map<String, Object?> data = await _request(
      action: 'start_restore_snapshot_to_usb',
      payload: <String, Object?>{
        'snapshot_id': snapshotId,
        'target_path': targetPath,
        'clear_target': clearTarget,
      },
    );
    return UsbBackupTaskSnapshot.fromJson(data);
  }

  @override
  Future<UsbBackupTaskSnapshot> startFormatUsb({
    required String targetPath,
    required String filesystem,
    required String volumeLabel,
  }) async {
    final Map<String, Object?> data = await _request(
      action: 'start_format_usb',
      payload: <String, Object?>{
        'target_path': targetPath,
        'filesystem': filesystem,
        'volume_label': volumeLabel,
      },
    );
    return UsbBackupTaskSnapshot.fromJson(data);
  }

  @override
  Future<UsbBackupCleanupResult> deleteBackupVersion(String snapshotId) async {
    final Map<String, Object?> data = await _request(
      action: 'delete_backup_version',
      payload: <String, Object?>{'snapshot_id': snapshotId},
    );
    return UsbBackupCleanupResult.fromJson(data);
  }

  @override
  Future<UsbBackupCleanupResult> cleanupRepository() async {
    final Map<String, Object?> data = await _request(
      action: 'cleanup_repository',
      payload: const <String, Object?>{},
    );
    return UsbBackupCleanupResult.fromJson(data);
  }

  @override
  Future<Map<String, Object?>> ejectUsbVolume({required String targetPath}) {
    return _request(
      action: 'eject_usb_volume',
      payload: <String, Object?>{'target_path': targetPath},
    );
  }

  @override
  Future<UsbBackupTaskSnapshot> stopTask(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'stop_task',
      payload: <String, Object?>{'task_id': taskId},
    );
    return UsbBackupTaskSnapshot.fromJson(data);
  }

  @override
  Future<List<UsbBackupTaskEvent>> subscribeTaskEvents({String? taskId}) async {
    final Map<String, Object?> data = await _request(
      action: 'subscribe_task_events',
      payload: taskId == null
          ? const <String, Object?>{}
          : <String, Object?>{'task_id': taskId},
    );
    final List<Object?> rawEvents =
        data['events'] as List<Object?>? ?? <Object?>[];
    return rawEvents
        .whereType<Map<String, Object?>>()
        .map(UsbBackupTaskEvent.fromJson)
        .toList();
  }

  Future<Map<String, Object?>> _request({
    required String action,
    required Map<String, Object?> payload,
  }) {
    return _call<Map<String, Object?>>(
      () => _client.request(
        module: 'usb_backup',
        action: action,
        payload: payload,
      ),
    );
  }

  @override
  Future<void> close() => _call<void>(() => _client.close());

  Future<T> _call<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PythonRpcClientException catch (error) {
      throw UsbBackupBridgeException(error.code, error.message);
    }
  }
}
