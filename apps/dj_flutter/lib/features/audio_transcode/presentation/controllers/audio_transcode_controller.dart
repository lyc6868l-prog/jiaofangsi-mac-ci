import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:dj_flutter/shared/task_runtime/polling_helper.dart';

import '../models/audio_transcode_models.dart';

class AudioTranscodeController extends ChangeNotifier {
  AudioTranscodeController({
    required String defaultOutputDirectory,
    required AudioTranscodeTaskBridge bridge,
    String? ffmpegPath,
    String? ffprobePath,
  }) : _outputDirectory = defaultOutputDirectory,
       _bridge = bridge,
       _ffmpegPath = ffmpegPath,
       _ffprobePath = ffprobePath;

  final AudioTranscodeTaskBridge _bridge;
  final String? _ffmpegPath;
  final String? _ffprobePath;
  final List<AudioTranscodeFileItem> _loadedFiles = <AudioTranscodeFileItem>[];
  final List<AudioTranscodeResultItem> _results = <AudioTranscodeResultItem>[];

  AudioTranscodeOutputFormat _outputFormat = AudioTranscodeOutputFormat.mp3;
  AudioTranscodeOutputLocation _outputLocation =
      AudioTranscodeOutputLocation.sourceSubdir;
  AudioTranscodeTaskSnapshot _snapshot = const AudioTranscodeTaskSnapshot(
    taskId: '',
    status: AudioTranscodeStatus.idle,
    progress: 0,
    hintText: '等待导入音频文件并启动转码任务。',
    inputCount: 0,
    plannedCount: 0,
    successCount: 0,
    failedCount: 0,
  );
  String _outputDirectory;
  String? _toastMessage;
  bool _overwriteExisting = false;
  bool _preserveMetadata = true;
  final PollingHelper _polling = PollingHelper();
  bool _isFetchingResult = false;

  List<AudioTranscodeFileItem> get loadedFiles =>
      List<AudioTranscodeFileItem>.unmodifiable(_loadedFiles);
  List<AudioTranscodeResultItem> get results =>
      List<AudioTranscodeResultItem>.unmodifiable(_results);
  AudioTranscodeOutputFormat get outputFormat => _outputFormat;
  AudioTranscodeOutputLocation get outputLocation => _outputLocation;
  AudioTranscodeTaskSnapshot get snapshot => _snapshot;
  String get outputDirectory => _outputDirectory;
  String? get toastMessage => _toastMessage;
  bool get overwriteExisting => _overwriteExisting;
  bool get preserveMetadata => _preserveMetadata;
  bool get hasResults => _results.isNotEmpty;
  String? get currentFileName => _snapshot.currentFilePath == null
      ? null
      : p.basename(_snapshot.currentFilePath!);
  int get completedCount => _snapshot.successCount + _snapshot.failedCount;
  String? get effectiveOutputDirectory => _snapshot.outputDirectory;

  bool get canStartTask =>
      _loadedFiles.isNotEmpty &&
      (_outputLocation == AudioTranscodeOutputLocation.sourceSubdir ||
          _outputDirectory.isNotEmpty) &&
      _snapshot.status != AudioTranscodeStatus.running;

  Future<void> loadTargets(List<String> rawPaths, {bool append = false}) async {
    try {
      await _bridge.ensureStarted();
      final int existingCount = _loadedFiles.length;
      final List<String> mergedPaths = append
          ? <String>{
              ..._loadedFiles.map((AudioTranscodeFileItem item) => item.path),
              ...rawPaths,
            }.toList(growable: false)
          : rawPaths;
      final List<String> normalized = await _bridge.loadTargets(mergedPaths);
      final int addedCount = append
          ? (normalized.length - existingCount).clamp(0, normalized.length)
          : 0;
      _setLoadedFiles(normalized, append: append, addedCount: addedCount);
    } on AudioTranscodeBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  void updateOutputFormat(AudioTranscodeOutputFormat format) {
    _outputFormat = format;
    _resetTaskState('输出格式已更新，请重新启动转码任务。');
  }

  void updateOutputLocation(AudioTranscodeOutputLocation value) {
    _outputLocation = value;
    _resetTaskState('输出位置已更新，请重新启动转码任务。');
  }

  void updateOutputDirectory(String value) {
    _outputDirectory = value;
    _resetTaskState('输出目录已更新，请重新启动转码任务。');
  }

  void setOverwriteExisting(bool value) {
    _overwriteExisting = value;
    _resetTaskState('覆盖策略已更新，请重新启动转码任务。');
  }

  void setPreserveMetadata(bool value) {
    _preserveMetadata = value;
    _resetTaskState('元数据策略已更新，请重新启动转码任务。');
  }

  void clearTargets() {
    _polling.stop();
    _loadedFiles.clear();
    _results.clear();
    _toastMessage = null;
    _snapshot = const AudioTranscodeTaskSnapshot(
      taskId: '',
      status: AudioTranscodeStatus.idle,
      progress: 0,
      hintText: '等待导入音频文件并启动转码任务。',
      inputCount: 0,
      plannedCount: 0,
      successCount: 0,
      failedCount: 0,
    );
    notifyListeners();
  }

  Future<void> removeTarget(String path) async {
    final List<String> remainingPaths = _loadedFiles
        .map((AudioTranscodeFileItem item) => item.path)
        .where((String itemPath) => itemPath != path)
        .toList(growable: false);
    if (remainingPaths.length == _loadedFiles.length) {
      return;
    }
    if (remainingPaths.isEmpty) {
      clearTargets();
      _setToast('已移除目标，列表已清空。');
      return;
    }
    try {
      await _bridge.ensureStarted();
      final List<String> normalized = await _bridge.loadTargets(remainingPaths);
      _setLoadedFiles(normalized);
      _setToast('已移除目标。');
    } on AudioTranscodeBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  void clearToast() {
    if (_toastMessage == null) {
      return;
    }
    _toastMessage = null;
    notifyListeners();
  }

  Future<void> startTranscodeTask() async {
    if (_loadedFiles.isEmpty) {
      _setToast('请先导入需要转码的音频文件。');
      return;
    }
    if (_outputLocation == AudioTranscodeOutputLocation.custom &&
        _outputDirectory.isEmpty) {
      _setToast('请先选择输出目录。');
      return;
    }
    try {
      await _bridge.lockConfig(_buildConfig());
      _results.clear();
      _snapshot = AudioTranscodeTaskSnapshot(
        taskId: _snapshot.taskId,
        status: AudioTranscodeStatus.configLocked,
        progress: 0.02,
        hintText: '配置已锁定，正在提交转码任务...',
        inputCount: _loadedFiles.length,
        plannedCount: _loadedFiles.length,
        successCount: 0,
        failedCount: 0,
        outputDirectory: _outputLocation == AudioTranscodeOutputLocation.custom
            ? _outputDirectory
            : null,
      );
      notifyListeners();
      final AudioTranscodeTaskSnapshot started = await _bridge
          .startAudioTranscodeTask();
      _snapshot = started;
      _startPolling(started.taskId);
      notifyListeners();
    } on AudioTranscodeBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> stopTask() async {
    if (_snapshot.taskId.isEmpty) {
      return;
    }
    try {
      final AudioTranscodeTaskSnapshot stopped = await _bridge.stopTask(
        _snapshot.taskId,
      );
      _snapshot = stopped;
      notifyListeners();
    } on AudioTranscodeBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> close() async {
    _polling.stop();
    await _bridge.close();
  }

  void _setLoadedFiles(
    List<String> normalizedPaths, {
    bool append = false,
    int addedCount = 0,
  }) {
    _polling.stop();
    _loadedFiles
      ..clear()
      ..addAll(
        normalizedPaths.map(
          (String path) =>
              AudioTranscodeFileItem(path: path, name: p.basename(path)),
        ),
      );
    _results.clear();
    _snapshot = AudioTranscodeTaskSnapshot(
      taskId: '',
      status: _loadedFiles.isEmpty
          ? AudioTranscodeStatus.idle
          : AudioTranscodeStatus.targetReady,
      progress: 0,
      hintText: _loadedFiles.isEmpty
          ? '等待导入音频文件并启动转码任务。'
          : '已载入 ${_loadedFiles.length} 个音频文件，请确认参数并启动转码。',
      inputCount: _loadedFiles.length,
      plannedCount: _loadedFiles.length,
      successCount: 0,
      failedCount: 0,
    );
    _toastMessage = _loadedFiles.isEmpty
        ? '未找到可用于转码的音频文件。'
        : (append && addedCount > 0 ? '已追加 $addedCount 个目标。' : null);
    notifyListeners();
  }

  void _resetTaskState(String hintText) {
    if (_loadedFiles.isEmpty ||
        _snapshot.status == AudioTranscodeStatus.running) {
      notifyListeners();
      return;
    }
    _polling.stop();
    _results.clear();
    _snapshot = AudioTranscodeTaskSnapshot(
      taskId: '',
      status: AudioTranscodeStatus.planReady,
      progress: 0,
      hintText: hintText,
      inputCount: _loadedFiles.length,
      plannedCount: _loadedFiles.length,
      successCount: 0,
      failedCount: 0,
      outputDirectory: _outputLocation == AudioTranscodeOutputLocation.custom
          ? _outputDirectory
          : null,
    );
    notifyListeners();
  }

  Map<String, Object?> _buildConfig() {
    final String outputDir =
        _outputLocation == AudioTranscodeOutputLocation.custom
        ? _outputDirectory
        : '';
    final bool isAiff = _outputFormat == AudioTranscodeOutputFormat.aiff;
    return <String, Object?>{
      'output_dir': outputDir,
      'output_mode': _outputLocation.value,
      'output_format': _outputFormat.value,
      'channels': 'stereo',
      'sample_rate_hz': isAiff ? 44100 : null,
      'bitrate_kbps': _outputFormat == AudioTranscodeOutputFormat.mp3
          ? 320
          : null,
      'compression_level': _outputFormat == AudioTranscodeOutputFormat.flac
          ? 5
          : null,
      'overwrite_existing': _overwriteExisting,
      'preserve_metadata': _preserveMetadata,
      'ffmpeg_path': _ffmpegPath,
      'ffprobe_path': _ffprobePath,
    };
  }

  void _startPolling(String taskId) {
    _polling.start(() async {
      try {
        final List<AudioTranscodeTaskEvent> events = await _bridge
            .subscribeTaskEvents(taskId: taskId);
        if (events.isEmpty) {
          return;
        }
        for (final AudioTranscodeTaskEvent event in events) {
          _snapshot = event.snapshot;
        }
        notifyListeners();
        if (_isTerminalStatus(_snapshot.status)) {
          _polling.stop();
          await _loadFinalResult();
        }
      } on AudioTranscodeBridgeException catch (error) {
        _polling.stop();
        _setToast(error.message);
      }
    });
  }

  Future<void> _loadFinalResult() async {
    if (_isFetchingResult || _snapshot.taskId.isEmpty) {
      return;
    }
    if (_snapshot.status == AudioTranscodeStatus.error) {
      notifyListeners();
      return;
    }
    _isFetchingResult = true;
    try {
      final AudioTranscodeResult result = await _bridge.fetchTranscodeResult(
        _snapshot.taskId,
      );
      _results
        ..clear()
        ..addAll(result.results);
      _snapshot = AudioTranscodeTaskSnapshot(
        taskId: result.taskId,
        status: result.status,
        progress: 1,
        hintText: result.status == AudioTranscodeStatus.success
            ? '转码完成：成功 ${result.successCount} 个，失败 ${result.failedCount} 个。'
            : _snapshot.hintText,
        inputCount: _loadedFiles.length,
        plannedCount: _loadedFiles.length,
        successCount: result.successCount,
        failedCount: result.failedCount,
        error: _snapshot.error,
        currentFilePath: _snapshot.currentFilePath,
        outputDirectory: _snapshot.outputDirectory,
      );
      notifyListeners();
    } on AudioTranscodeBridgeException catch (error) {
      _setToast(error.message);
    } finally {
      _isFetchingResult = false;
    }
  }

  bool _isTerminalStatus(AudioTranscodeStatus status) {
    return status == AudioTranscodeStatus.success ||
        status == AudioTranscodeStatus.cancelled ||
        status == AudioTranscodeStatus.error;
  }

  void _setToast(String message) {
    _toastMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _polling.dispose();
    super.dispose();
  }
}
