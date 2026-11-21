import 'package:dj_flutter/shared/python_rpc/python_rpc_client.dart';

import '../models/unlock_music_models.dart';

class PythonUnlockMusicTaskBridge implements UnlockMusicTaskBridge {
  PythonUnlockMusicTaskBridge({
    required String pythonExecutable,
    required String workingDirectory,
    required String scriptModule,
  }) : _client = PythonRpcClient(
         pythonExecutable: pythonExecutable,
         workingDirectory: workingDirectory,
         scriptModule: scriptModule,
       );

  final PythonRpcClient _client;

  @override
  Future<void> ensureStarted() => _call<void>(() => _client.ensureStarted());

  @override
  Future<UnlockMusicLoadResult> loadTargets(
    List<String> filePaths, {
    bool append = false,
  }) async {
    final Map<String, Object?> data = await _request(
      action: 'load_targets',
      payload: <String, Object?>{
        'panel': 'unlock',
        'file_paths': filePaths,
        'append': append,
      },
    );
    return UnlockMusicLoadResult.fromJson(data);
  }

  @override
  Future<UnlockMusicLoadResult> removeTarget(String filePath) async {
    final Map<String, Object?> data = await _request(
      action: 'remove_target',
      payload: <String, Object?>{'panel': 'unlock', 'file_path': filePath},
    );
    return UnlockMusicLoadResult.fromJson(data);
  }

  @override
  Future<UnlockMusicLoadResult> clearTargets() async {
    final Map<String, Object?> data = await _request(
      action: 'clear_targets',
      payload: const <String, Object?>{'panel': 'unlock'},
    );
    return UnlockMusicLoadResult.fromJson(data);
  }

  @override
  Future<void> lockConfig(Map<String, Object?> config) async {
    await _request(
      action: 'lock_config',
      payload: <String, Object?>{'panel': 'unlock', 'config': config},
    );
  }

  @override
  Future<UnlockMusicTaskSnapshot> startUnlockTask() async {
    final Map<String, Object?> data = await _request(
      action: 'start_unlock_task',
      payload: const <String, Object?>{'panel': 'unlock'},
    );
    return UnlockMusicTaskSnapshot.fromJson(data);
  }

  @override
  Future<UnlockMusicTaskSnapshot> stopTask(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'stop_task',
      payload: <String, Object?>{'task_id': taskId},
    );
    return UnlockMusicTaskSnapshot.fromJson(data);
  }

  @override
  Future<List<UnlockMusicTaskEvent>> subscribeTaskEvents({
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
        .map(UnlockMusicTaskEvent.fromJson)
        .toList();
  }

  @override
  Future<UnlockMusicResult> fetchUnlockResult(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'fetch_unlock_result',
      payload: <String, Object?>{'task_id': taskId},
    );
    return UnlockMusicResult.fromJson(data);
  }

  Future<Map<String, Object?>> _request({
    required String action,
    required Map<String, Object?> payload,
  }) {
    return _call<Map<String, Object?>>(
      () => _client.request(
        module: 'unlock_music',
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
      throw UnlockMusicBridgeException(error.code, error.message);
    }
  }
}
