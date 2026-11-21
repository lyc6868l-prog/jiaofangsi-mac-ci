import 'package:dj_flutter/shared/python_rpc/python_rpc_client.dart';

import '../models/cleanup_dup_models.dart';

class PythonCleanupDupTaskBridge implements CleanupDupTaskBridge {
  PythonCleanupDupTaskBridge({
    required String pythonExecutable,
    required String workingDirectory,
    required String scriptModule,
  }) : _client = PythonRpcClient(
         pythonExecutable: pythonExecutable,
         workingDirectory: workingDirectory,
         scriptModule: scriptModule,
         requestTimeout: const Duration(seconds: 5),
         logStderrInDebugMode: true,
       );

  final PythonRpcClient _client;

  @override
  Future<void> ensureStarted() => _call<void>(() => _client.ensureStarted());

  @override
  Future<List<String>> loadTargets(
    CleanupDupPanelKind panel,
    List<String> filePaths,
  ) async {
    final Map<String, Object?> data = await _request(
      action: 'load_targets',
      payload: <String, Object?>{'panel': panel.value, 'file_paths': filePaths},
    );
    final List<Object?> rawPaths =
        data['file_paths'] as List<Object?>? ?? <Object?>[];
    return rawPaths.whereType<String>().toList();
  }

  @override
  Future<void> lockConfig(
    CleanupDupPanelKind panel,
    Map<String, Object?> config,
  ) {
    return _request(
      action: 'lock_config',
      payload: <String, Object?>{'panel': panel.value, 'config': config},
    );
  }

  @override
  Future<CleanupDupTaskSnapshot> startTitleCleanTask() async {
    final Map<String, Object?> data = await _request(
      action: 'start_title_clean_task',
      payload: const <String, Object?>{'panel': 'title_clean'},
    );
    return CleanupDupTaskSnapshot.fromJson(data);
  }

  @override
  Future<CleanupDupTaskSnapshot> startDuplicateCheckTask() async {
    final Map<String, Object?> data = await _request(
      action: 'start_duplicate_check_task',
      payload: const <String, Object?>{'panel': 'duplicate_search'},
    );
    return CleanupDupTaskSnapshot.fromJson(data);
  }

  @override
  Future<CleanupDupTaskSnapshot> stopTask(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'stop_task',
      payload: <String, Object?>{'task_id': taskId},
    );
    return CleanupDupTaskSnapshot.fromJson(data);
  }

  @override
  Future<CleanupDupReviewResult> fetchReviewResult(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'fetch_review_result',
      payload: <String, Object?>{'task_id': taskId},
    );
    return CleanupDupReviewResult.fromJson(data);
  }

  @override
  Future<CleanupDupDeleteResult> executeDelete({
    required String taskId,
    required bool moveToRecycleBin,
    required List<FileItem> selectedFiles,
  }) async {
    final Map<String, Object?> data = await _request(
      action: 'execute_delete',
      payload: <String, Object?>{
        'task_id': taskId,
        'move_to_recycle_bin': moveToRecycleBin,
        'selected_files': selectedFiles
            .map((FileItem file) => file.toJson())
            .toList(),
      },
    );
    return CleanupDupDeleteResult.fromJson(data);
  }

  @override
  Future<List<CleanupDupTaskEvent>> subscribeTaskEvents({
    String? taskId,
  }) async {
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
        .map(CleanupDupTaskEvent.fromJson)
        .toList();
  }

  Future<Map<String, Object?>> _request({
    required String action,
    required Map<String, Object?> payload,
  }) {
    return _call<Map<String, Object?>>(
      () => _client.request(
        module: 'cleanup_dup',
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
      throw CleanupDupBridgeException(error.code, error.message);
    }
  }
}
