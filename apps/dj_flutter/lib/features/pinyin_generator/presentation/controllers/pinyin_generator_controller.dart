import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:dj_flutter/shared/task_runtime/polling_helper.dart';

import '../models/pinyin_generator_models.dart';

class PinyinGeneratorController extends ChangeNotifier {
  PinyinGeneratorController({required PinyinGeneratorTaskBridge bridge})
    : _bridge = bridge;

  final PinyinGeneratorTaskBridge _bridge;
  final List<PinyinGeneratorFileItem> _loadedFiles =
      <PinyinGeneratorFileItem>[];
  final List<PinyinGeneratorResultItem> _results =
      <PinyinGeneratorResultItem>[];

  PinyinGeneratorWriteMode _writeMode = PinyinGeneratorWriteMode.overwrite;
  PinyinGeneratorTaskSnapshot _snapshot = const PinyinGeneratorTaskSnapshot(
    taskId: '',
    status: PinyinGeneratorStatus.idle,
    progress: 0,
    hintText: '等待导入音频文件并启动首拼写入任务。',
    inputCount: 0,
    successCount: 0,
    skippedCount: 0,
    failedCount: 0,
  );
  String _stopwordsText = 'mp3 remix vip dj';
  String? _toastMessage;
  final PollingHelper _polling = PollingHelper();
  bool _isFetchingResult = false;
  int _maxInitialsLength = 12;

  List<PinyinGeneratorFileItem> get loadedFiles =>
      List<PinyinGeneratorFileItem>.unmodifiable(_loadedFiles);
  List<PinyinGeneratorResultItem> get results =>
      List<PinyinGeneratorResultItem>.unmodifiable(_results);
  PinyinGeneratorWriteMode get writeMode => _writeMode;
  PinyinGeneratorTaskSnapshot get snapshot => _snapshot;
  String get stopwordsText => _stopwordsText;
  int get maxInitialsLength => _maxInitialsLength;
  String? get toastMessage => _toastMessage;

  bool get canStartTask =>
      _loadedFiles.isNotEmpty &&
      _snapshot.status != PinyinGeneratorStatus.running;

  Future<void> loadTargets(List<String> rawPaths, {bool append = false}) async {
    try {
      await _bridge.ensureStarted();
      final int existingCount = _loadedFiles.length;
      final List<String> mergedPaths = append
          ? <String>{
              ..._loadedFiles.map((PinyinGeneratorFileItem item) => item.path),
              ...rawPaths,
            }.toList(growable: false)
          : rawPaths;
      final PinyinGeneratorLoadResult loaded = await _bridge.loadTargets(
        mergedPaths,
      );
      final int addedCount = append
          ? (loaded.filePaths.length - existingCount).clamp(
              0,
              loaded.filePaths.length,
            )
          : 0;
      _setLoadedFiles(loaded.filePaths, append: append, addedCount: addedCount);
      if (loaded.warningMessage case final String warning
          when warning.isNotEmpty) {
        _toastMessage = warning;
        notifyListeners();
      }
    } on PinyinGeneratorBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  void updateWriteMode(PinyinGeneratorWriteMode mode) {
    _writeMode = mode;
    _resetTaskState('写入模式已更新，请重新启动首拼任务。');
  }

  void updateStopwordsText(String value) {
    _stopwordsText = value;
    _resetTaskState('停用词已更新，请重新启动首拼任务。');
  }

  void updateMaxInitialsLength(int value) {
    _maxInitialsLength = value.clamp(1, 12);
    _resetTaskState('首拼长度已更新，请重新启动首拼任务。');
  }

  void clearTargets() {
    _polling.stop();
    _loadedFiles.clear();
    _results.clear();
    _toastMessage = null;
    _snapshot = const PinyinGeneratorTaskSnapshot(
      taskId: '',
      status: PinyinGeneratorStatus.idle,
      progress: 0,
      hintText: '等待导入音频文件并启动首拼写入任务。',
      inputCount: 0,
      successCount: 0,
      skippedCount: 0,
      failedCount: 0,
    );
    notifyListeners();
  }

  Future<void> removeTarget(String path) async {
    final List<String> remainingPaths = _loadedFiles
        .map((PinyinGeneratorFileItem item) => item.path)
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
      final PinyinGeneratorLoadResult loaded = await _bridge.loadTargets(
        remainingPaths,
      );
      _setLoadedFiles(loaded.filePaths);
      _setToast('已移除目标。');
    } on PinyinGeneratorBridgeException catch (error) {
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

  Future<void> startPinyinGeneratorTask() async {
    if (_loadedFiles.isEmpty) {
      _setToast('请先导入需要处理的音频文件。');
      return;
    }
    try {
      await _bridge.lockConfig(_buildConfig());
      _results.clear();
      _snapshot = PinyinGeneratorTaskSnapshot(
        taskId: _snapshot.taskId,
        status: PinyinGeneratorStatus.configLocked,
        progress: 0,
        hintText: '配置已锁定，正在提交首拼写入任务...',
        inputCount: _loadedFiles.length,
        successCount: 0,
        skippedCount: 0,
        failedCount: 0,
      );
      notifyListeners();
      final PinyinGeneratorTaskSnapshot started = await _bridge
          .startPinyinGeneratorTask();
      _snapshot = started;
      _startPolling(started.taskId);
      notifyListeners();
    } on PinyinGeneratorBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> stopTask() async {
    if (_snapshot.taskId.isEmpty) {
      return;
    }
    try {
      final PinyinGeneratorTaskSnapshot stopped = await _bridge.stopTask(
        _snapshot.taskId,
      );
      _snapshot = stopped;
      notifyListeners();
    } on PinyinGeneratorBridgeException catch (error) {
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
              PinyinGeneratorFileItem(path: path, name: p.basename(path)),
        ),
      );
    _results.clear();
    _snapshot = PinyinGeneratorTaskSnapshot(
      taskId: '',
      status: _loadedFiles.isEmpty
          ? PinyinGeneratorStatus.idle
          : PinyinGeneratorStatus.targetReady,
      progress: 0,
      hintText: _loadedFiles.isEmpty
          ? '等待导入音频文件并启动首拼写入任务。'
          : '已载入 ${_loadedFiles.length} 个音频文件，请确认参数并启动首拼写入。',
      inputCount: _loadedFiles.length,
      successCount: 0,
      skippedCount: 0,
      failedCount: 0,
    );
    _toastMessage = _loadedFiles.isEmpty
        ? '未找到可用于首拼写入的音频文件。'
        : (append && addedCount > 0 ? '已追加 $addedCount 个目标。' : null);
    notifyListeners();
  }

  void _resetTaskState(String hintText) {
    if (_loadedFiles.isEmpty ||
        _snapshot.status == PinyinGeneratorStatus.running) {
      notifyListeners();
      return;
    }
    _polling.stop();
    _results.clear();
    _snapshot = PinyinGeneratorTaskSnapshot(
      taskId: '',
      status: PinyinGeneratorStatus.planReady,
      progress: 0,
      hintText: hintText,
      inputCount: _loadedFiles.length,
      successCount: 0,
      skippedCount: 0,
      failedCount: 0,
    );
    notifyListeners();
  }

  Map<String, Object?> _buildConfig() {
    final List<String> stopwords = _stopwordsText
        .split(RegExp(r'[\s,，/]+'))
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
    return <String, Object?>{
      'write_mode': _writeMode.value,
      'max_initials_length': _maxInitialsLength,
      'stopwords': stopwords,
    };
  }

  void _startPolling(String taskId) {
    _polling.start(() async {
      try {
        final List<PinyinGeneratorTaskEvent> events = await _bridge
            .subscribeTaskEvents(taskId: taskId);
        if (events.isEmpty) {
          return;
        }
        for (final PinyinGeneratorTaskEvent event in events) {
          _snapshot = event.snapshot;
        }
        notifyListeners();
        if (_isTerminalStatus(_snapshot.status)) {
          _polling.stop();
          await _loadFinalResult();
        }
      } on PinyinGeneratorBridgeException catch (error) {
        _polling.stop();
        _setToast(error.message);
      }
    });
  }

  Future<void> _loadFinalResult() async {
    if (_isFetchingResult || _snapshot.taskId.isEmpty) {
      return;
    }
    if (_snapshot.status == PinyinGeneratorStatus.error) {
      notifyListeners();
      return;
    }
    _isFetchingResult = true;
    try {
      final PinyinGeneratorResult result = await _bridge
          .fetchPinyinGeneratorResult(_snapshot.taskId);
      _results
        ..clear()
        ..addAll(result.results);
      final double terminalProgress =
          result.status == PinyinGeneratorStatus.success
          ? 1
          : _snapshot.progress;
      _snapshot = PinyinGeneratorTaskSnapshot(
        taskId: result.taskId,
        status: result.status,
        progress: terminalProgress,
        hintText: result.status == PinyinGeneratorStatus.success
            ? '首拼写入任务执行完毕。'
            : _snapshot.hintText,
        inputCount: _loadedFiles.length,
        successCount: result.successCount,
        skippedCount: result.skippedCount,
        failedCount: result.failedCount,
      );
      notifyListeners();
    } on PinyinGeneratorBridgeException catch (error) {
      _setToast(error.message);
    } finally {
      _isFetchingResult = false;
    }
  }

  bool _isTerminalStatus(PinyinGeneratorStatus status) {
    return status == PinyinGeneratorStatus.success ||
        status == PinyinGeneratorStatus.cancelled ||
        status == PinyinGeneratorStatus.error;
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
