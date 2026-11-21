import 'package:dj_flutter/shared/python_rpc/python_rpc_client.dart';

import '../models/search_download_models.dart';

class PythonSearchDownloadTaskBridge implements SearchDownloadTaskBridge {
  PythonSearchDownloadTaskBridge({
    required String pythonExecutable,
    required String workingDirectory,
    required String scriptModule,
  }) : _client = PythonRpcClient(
         pythonExecutable: pythonExecutable,
         workingDirectory: workingDirectory,
         scriptModule: scriptModule,
         requestTimeout: const Duration(minutes: 3),
       );

  final PythonRpcClient _client;

  @override
  Future<void> ensureStarted() => _call<void>(() => _client.ensureStarted());

  @override
  Future<List<SearchDownloadSourceOption>> lockConfig(
    Map<String, Object?> config,
  ) async {
    final Map<String, Object?> data = await _request(
      action: 'lock_config',
      payload: <String, Object?>{'panel': 'search', 'config': config},
    );
    final List<Object?> rawOptions =
        data['available_sources'] as List<Object?>? ?? <Object?>[];
    final Set<String> selected =
        ((config['sources'] as List<Object?>?) ?? const <Object?>[])
            .whereType<String>()
            .toSet();
    return rawOptions.whereType<Map<String, Object?>>().map((
      Map<String, Object?> item,
    ) {
      final String label = item['label'] as String? ?? '';
      final String value = item['value'] as String? ?? '';
      return SearchDownloadSourceOption(
        label: label,
        value: value,
        selected: selected.contains(label) || selected.contains(value),
      );
    }).toList();
  }

  @override
  Future<SearchDownloadTaskSnapshot> startSearchTask() async {
    final Map<String, Object?> data = await _request(
      action: 'start_search_task',
      payload: const <String, Object?>{'panel': 'search'},
    );
    return SearchDownloadTaskSnapshot.fromJson(data);
  }

  @override
  Future<SearchDownloadTaskSnapshot> startPlaylistParseTask() async {
    final Map<String, Object?> data = await _request(
      action: 'start_playlist_parse_task',
      payload: const <String, Object?>{'panel': 'search'},
    );
    return SearchDownloadTaskSnapshot.fromJson(data);
  }

  @override
  Future<SearchDownloadTaskSnapshot> startDownloadTask(
    List<Map<String, Object?>> songInfos,
  ) async {
    final Map<String, Object?> data = await _request(
      action: 'start_download_task',
      payload: <String, Object?>{'panel': 'search', 'song_infos': songInfos},
    );
    return SearchDownloadTaskSnapshot.fromJson(data);
  }

  @override
  Future<SearchDownloadTaskSnapshot> stopTask(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'stop_task',
      payload: <String, Object?>{'task_id': taskId},
    );
    return SearchDownloadTaskSnapshot.fromJson(data);
  }

  @override
  Future<List<SearchDownloadTaskEvent>> subscribeTaskEvents({
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
        .map(SearchDownloadTaskEvent.fromJson)
        .toList();
  }

  @override
  Future<SearchDownloadResult> fetchSearchResult(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'fetch_search_result',
      payload: <String, Object?>{'task_id': taskId},
    );
    return SearchDownloadResult.fromJson(data);
  }

  @override
  Future<SearchDownloadResult> fetchDownloadResult(String taskId) async {
    final Map<String, Object?> data = await _request(
      action: 'fetch_download_result',
      payload: <String, Object?>{'task_id': taskId},
    );
    return SearchDownloadResult.fromJson(data);
  }

  Future<Map<String, Object?>> _request({
    required String action,
    required Map<String, Object?> payload,
  }) {
    return _call<Map<String, Object?>>(
      () => _client.request(
        module: 'search_download',
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
      throw SearchDownloadBridgeException(error.code, error.message);
    }
  }
}
