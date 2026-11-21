import 'package:dj_flutter/shared/python_rpc/python_rpc_client.dart';

import '../models/audio_transcode_models.dart';

class PythonAudioTranscodeTaskBridge implements AudioTranscodeTaskBridge {
  PythonAudioTranscodeTaskBridge({
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
  Future<List<String>> loadTargets(List<String> filePaths) async {
    final Map<String, Object?> data = await _request(
      action: 'load_targets',
      payload: <String, Object?>{'panel': 'transcode', 'file_paths': filePaths},
    );
    final List<Object?> rawPaths =
        data['file_paths'] as List<Object?>? ?? <Object?>[];
    return rawPaths.whereType<String>().toList();
  }

  @override
  Future<void> lockConfig(Map<String, Object?> config) {
    return _request(
      action: 'lock_config',
      payload: <String, Object?>{'panel': 'transcode', 'config': config},
    );
  }

  @override
  Future<AudioTranscodeTaskSnapshot> startAudioTranscodeTask() async {
    final Map<String, Object?> data = await _request(
      action: 'start_audio_transcode_task',
      payload: const <String, Object?>{'panel': 'transcode'},
    );
    return AudioTranscodeTaskSnapshot.fromJson(data);
  }

  @override
  Future<AudioTranscodeTaskSnapshot> stopTask(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'stop_task',
      payload: <String, Object?>{'task_id': taskId},
    );
    return AudioTranscodeTaskSnapshot.fromJson(data);
  }

  @override
  Future<List<AudioTranscodeTaskEvent>> subscribeTaskEvents({
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
        .map(AudioTranscodeTaskEvent.fromJson)
        .toList();
  }

  @override
  Future<AudioTranscodeResult> fetchTranscodeResult(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'fetch_transcode_result',
      payload: <String, Object?>{'task_id': taskId},
    );
    return AudioTranscodeResult.fromJson(data);
  }

  Future<Map<String, Object?>> _request({
    required String action,
    required Map<String, Object?> payload,
  }) {
    return _call<Map<String, Object?>>(
      () => _client.request(
        module: 'audio_transcode',
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
      throw AudioTranscodeBridgeException(error.code, error.message);
    }
  }
}
