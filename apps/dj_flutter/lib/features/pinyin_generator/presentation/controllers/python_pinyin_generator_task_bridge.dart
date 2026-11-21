import 'package:dj_flutter/shared/python_rpc/python_rpc_client.dart';

import '../models/pinyin_generator_models.dart';

class PythonPinyinGeneratorTaskBridge implements PinyinGeneratorTaskBridge {
  PythonPinyinGeneratorTaskBridge({
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
  Future<PinyinGeneratorLoadResult> loadTargets(List<String> filePaths) async {
    final Map<String, Object?> data = await _request(
      action: 'load_targets',
      payload: <String, Object?>{'panel': 'generator', 'file_paths': filePaths},
    );
    return PinyinGeneratorLoadResult.fromJson(data);
  }

  @override
  Future<void> lockConfig(Map<String, Object?> config) async {
    await _request(
      action: 'lock_config',
      payload: <String, Object?>{'panel': 'generator', 'config': config},
    );
  }

  @override
  Future<PinyinGeneratorTaskSnapshot> startPinyinGeneratorTask() async {
    final Map<String, Object?> data = await _request(
      action: 'start_pinyin_generator_task',
      payload: const <String, Object?>{'panel': 'generator'},
    );
    return PinyinGeneratorTaskSnapshot.fromJson(data);
  }

  @override
  Future<PinyinGeneratorTaskSnapshot> stopTask(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'stop_task',
      payload: <String, Object?>{'task_id': taskId},
    );
    return PinyinGeneratorTaskSnapshot.fromJson(data);
  }

  @override
  Future<List<PinyinGeneratorTaskEvent>> subscribeTaskEvents({
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
        .map(PinyinGeneratorTaskEvent.fromJson)
        .toList();
  }

  @override
  Future<PinyinGeneratorResult> fetchPinyinGeneratorResult(
    String taskId,
  ) async {
    final Map<String, Object?> data = await _request(
      action: 'fetch_pinyin_generator_result',
      payload: <String, Object?>{'task_id': taskId},
    );
    return PinyinGeneratorResult.fromJson(data);
  }

  Future<Map<String, Object?>> _request({
    required String action,
    required Map<String, Object?> payload,
  }) {
    return _call<Map<String, Object?>>(
      () => _client.request(
        module: 'pinyin_generator',
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
      throw PinyinGeneratorBridgeException(error.code, error.message);
    }
  }
}
