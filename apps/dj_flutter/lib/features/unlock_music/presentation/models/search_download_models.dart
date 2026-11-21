import 'package:flutter/foundation.dart';

@immutable
class SearchDownloadSourceOption {
  const SearchDownloadSourceOption({
    required this.label,
    required this.value,
    required this.selected,
  });

  final String label;
  final String value;
  final bool selected;

  SearchDownloadSourceOption copyWith({bool? selected}) {
    return SearchDownloadSourceOption(
      label: label,
      value: value,
      selected: selected ?? this.selected,
    );
  }
}

enum SearchDownloadStatus {
  idle,
  configLocked,
  running,
  success,
  cancelled,
  error,
}

SearchDownloadStatus searchDownloadStatusFromValue(String value) {
  return switch (value) {
    'idle' => SearchDownloadStatus.idle,
    'config_locked' => SearchDownloadStatus.configLocked,
    'running' => SearchDownloadStatus.running,
    'success' => SearchDownloadStatus.success,
    'cancelled' => SearchDownloadStatus.cancelled,
    'error' => SearchDownloadStatus.error,
    _ => throw ArgumentError.value(value, 'value', '未知 status'),
  };
}

@immutable
class SearchDownloadTaskSnapshot {
  const SearchDownloadTaskSnapshot({
    required this.taskId,
    required this.taskType,
    required this.status,
    required this.progress,
    required this.progressHintText,
    required this.totalCount,
    required this.successCount,
    required this.failedCount,
    required this.logLines,
  });

  final String taskId;
  final String taskType;
  final SearchDownloadStatus status;
  final double progress;
  final String progressHintText;
  final int totalCount;
  final int successCount;
  final int failedCount;
  final List<String> logLines;

  factory SearchDownloadTaskSnapshot.fromJson(Map<String, Object?> json) {
    final List<Object?> rawLogs =
        json['log_lines'] as List<Object?>? ?? <Object?>[];
    return SearchDownloadTaskSnapshot(
      taskId: json['task_id'] as String,
      taskType: json['task_type'] as String? ?? 'search',
      status: searchDownloadStatusFromValue(json['status'] as String),
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      progressHintText: json['progress_hint_text'] as String? ?? '等待任务载入...',
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      logLines: rawLogs.whereType<String>().toList(),
    );
  }
}

@immutable
class SearchDownloadTaskEvent {
  const SearchDownloadTaskEvent({
    required this.event,
    required this.taskId,
    required this.snapshot,
  });

  final String event;
  final String taskId;
  final SearchDownloadTaskSnapshot snapshot;

  factory SearchDownloadTaskEvent.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> data =
        json['data'] as Map<String, Object?>? ?? <String, Object?>{};
    return SearchDownloadTaskEvent(
      event: json['event'] as String,
      taskId: json['task_id'] as String,
      snapshot: SearchDownloadTaskSnapshot.fromJson(<String, Object?>{
        ...data,
        'task_id': json['task_id'],
      }),
    );
  }
}

@immutable
class SearchDownloadSongItem {
  const SearchDownloadSongItem({
    required this.source,
    required this.rootSource,
    required this.songName,
    required this.singers,
    required this.album,
    required this.identifier,
    required this.ext,
    required this.fileSize,
    required this.duration,
    required this.savePath,
    required this.withValidDownloadUrl,
    required this.raw,
  });

  final String source;
  final String? rootSource;
  final String songName;
  final String? singers;
  final String? album;
  final String? identifier;
  final String? ext;
  final String? fileSize;
  final String? duration;
  final String? savePath;
  final bool withValidDownloadUrl;
  final Map<String, Object?> raw;

  factory SearchDownloadSongItem.fromJson(Map<String, Object?> json) {
    final Object? identifierValue = json['identifier'];
    final String? identifier = identifierValue is int
        ? identifierValue.toString()
        : identifierValue as String?;
    return SearchDownloadSongItem(
      source: json['source'] as String? ?? 'unknown',
      rootSource: json['root_source'] as String?,
      songName: json['song_name'] as String? ?? '未知曲目',
      singers: json['singers'] as String?,
      album: json['album'] as String?,
      identifier: identifier,
      ext: json['ext'] as String?,
      fileSize: json['file_size'] as String?,
      duration: json['duration'] as String?,
      savePath: json['save_path'] as String?,
      withValidDownloadUrl: json['with_valid_download_url'] as bool? ?? false,
      raw: Map<String, Object?>.from(json),
    );
  }
}

@immutable
class SearchDownloadResult {
  const SearchDownloadResult({
    required this.taskId,
    required this.status,
    required this.taskType,
    required this.totalCount,
    required this.successCount,
    required this.failedCount,
    required this.results,
    required this.logLines,
    required this.outputDirectory,
    required this.playlistName,
  });

  final String taskId;
  final SearchDownloadStatus status;
  final String taskType;
  final int totalCount;
  final int successCount;
  final int failedCount;
  final List<SearchDownloadSongItem> results;
  final List<String> logLines;
  final String? outputDirectory;
  final String? playlistName;

  factory SearchDownloadResult.fromJson(Map<String, Object?> json) {
    final List<Object?> rawResults =
        json['results'] as List<Object?>? ?? <Object?>[];
    final List<Object?> rawLogs =
        json['log_lines'] as List<Object?>? ?? <Object?>[];
    return SearchDownloadResult(
      taskId: json['task_id'] as String,
      status: searchDownloadStatusFromValue(json['status'] as String),
      taskType: json['task_type'] as String? ?? 'search',
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      failedCount: (json['failed_count'] as num?)?.toInt() ?? 0,
      results: rawResults
          .whereType<Map<String, Object?>>()
          .map(SearchDownloadSongItem.fromJson)
          .toList(),
      logLines: rawLogs.whereType<String>().toList(),
      outputDirectory: json['output_dir'] as String?,
      playlistName: json['playlist_name'] as String?,
    );
  }
}

class SearchDownloadBridgeException implements Exception {
  const SearchDownloadBridgeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

abstract class SearchDownloadTaskBridge {
  Future<void> ensureStarted();
  Future<List<SearchDownloadSourceOption>> lockConfig(
    Map<String, Object?> config,
  );
  Future<SearchDownloadTaskSnapshot> startSearchTask();
  Future<SearchDownloadTaskSnapshot> startPlaylistParseTask();
  Future<SearchDownloadTaskSnapshot> startDownloadTask(
    List<Map<String, Object?>> songInfos,
  );
  Future<SearchDownloadTaskSnapshot> stopTask(String taskId);
  Future<List<SearchDownloadTaskEvent>> subscribeTaskEvents({String? taskId});
  Future<SearchDownloadResult> fetchSearchResult(String taskId);
  Future<SearchDownloadResult> fetchDownloadResult(String taskId);
  Future<void> close();
}
