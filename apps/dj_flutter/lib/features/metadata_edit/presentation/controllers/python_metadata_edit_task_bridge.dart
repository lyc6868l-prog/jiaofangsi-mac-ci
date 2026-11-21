import 'package:dj_flutter/shared/python_rpc/python_rpc_client.dart';

import '../models/metadata_edit_models.dart';

class PythonMetadataEditTaskBridge implements MetadataEditTaskBridge {
  PythonMetadataEditTaskBridge({
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
      payload: <String, Object?>{
        'panel': 'metadata_edit',
        'file_paths': filePaths,
      },
    );
    final List<Object?> rawPaths =
        data['file_paths'] as List<Object?>? ?? <Object?>[];
    return rawPaths.whereType<String>().toList();
  }

  @override
  Future<void> lockConfig(Map<String, Object?> config) {
    return _request(
      action: 'lock_config',
      payload: <String, Object?>{'panel': 'metadata_edit', 'config': config},
    );
  }

  @override
  Future<MetadataEditTaskSnapshot> startCoverInjectionTask() async {
    final Map<String, Object?> data = await _request(
      action: 'start_cover_injection_task',
      payload: const <String, Object?>{'panel': 'metadata_edit'},
    );
    return MetadataEditTaskSnapshot.fromJson(data);
  }

  @override
  Future<MetadataEditTaskSnapshot> startFilenameInjectionTask() async {
    final Map<String, Object?> data = await _request(
      action: 'start_filename_injection_task',
      payload: const <String, Object?>{'panel': 'metadata_edit'},
    );
    return MetadataEditTaskSnapshot.fromJson(data);
  }

  @override
  Future<MetadataEditTaskSnapshot> stopTask(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'stop_task',
      payload: <String, Object?>{'task_id': taskId},
    );
    return MetadataEditTaskSnapshot.fromJson(data);
  }

  @override
  Future<List<MetadataEditTaskEvent>> subscribeTaskEvents({
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
        .map(MetadataEditTaskEvent.fromJson)
        .toList();
  }

  @override
  Future<MetadataEditResult> fetchMetadataEditResult(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'fetch_metadata_edit_result',
      payload: <String, Object?>{'task_id': taskId},
    );
    return MetadataEditResult.fromJson(data);
  }

  @override
  Future<List<String>> loadTemplates() async {
    final Map<String, Object?> data = await _request(
      action: 'load_templates',
      payload: const <String, Object?>{},
    );
    final List<Object?> rawTemplates =
        data['templates'] as List<Object?>? ?? <Object?>[];
    return rawTemplates.whereType<String>().toList();
  }

  @override
  Future<List<String>> saveTemplate(String template) async {
    final Map<String, Object?> data = await _request(
      action: 'save_template',
      payload: <String, Object?>{'template': template},
    );
    final List<Object?> rawTemplates =
        data['templates'] as List<Object?>? ?? <Object?>[];
    return rawTemplates.whereType<String>().toList();
  }

  @override
  Future<List<String>> deleteTemplate(String template) async {
    final Map<String, Object?> data = await _request(
      action: 'delete_template',
      payload: <String, Object?>{'template': template},
    );
    final List<Object?> rawTemplates =
        data['templates'] as List<Object?>? ?? <Object?>[];
    return rawTemplates.whereType<String>().toList();
  }

  Future<Map<String, Object?>> _request({
    required String action,
    required Map<String, Object?> payload,
  }) {
    return _call<Map<String, Object?>>(
      () => _client.request(
        module: 'metadata_edit',
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
      throw MetadataEditBridgeException(error.code, error.message);
    }
  }
}
