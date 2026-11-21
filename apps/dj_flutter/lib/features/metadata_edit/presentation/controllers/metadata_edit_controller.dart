import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:dj_flutter/shared/task_runtime/polling_helper.dart';

import '../models/metadata_edit_models.dart';

class MetadataEditController extends ChangeNotifier {
  MetadataEditController({
    required MetadataEditTaskBridge bridge,
    String? ffmpegPath,
    String? ffprobePath,
  }) : _bridge = bridge,
       _ffmpegPath = ffmpegPath,
       _ffprobePath = ffprobePath;

  final MetadataEditTaskBridge _bridge;
  final String? _ffmpegPath;
  final String? _ffprobePath;

  final List<MetadataEditFileItem> _coverFiles = <MetadataEditFileItem>[];
  final List<MetadataEditFileItem> _filenameFiles = <MetadataEditFileItem>[];
  final List<MetadataEditResultItem> _coverResults = <MetadataEditResultItem>[];
  final List<MetadataEditResultItem> _filenameResults =
      <MetadataEditResultItem>[];

  List<String> _templates = <String>[];
  String? _selectedTemplate;
  String? _coverImagePath;
  String _appendText = '';
  String? _toastMessage;
  bool _coverStartFlashSignal = false;
  bool _filenameStartFlashSignal = false;

  MetadataEditTaskSnapshot _coverSnapshot = MetadataEditTaskSnapshot.idleCover;
  MetadataEditTaskSnapshot _filenameSnapshot =
      MetadataEditTaskSnapshot.idleFilename;

  bool _coverConfigLocked = false;
  bool _filenameConfigLocked = false;
  bool _initialized = false;
  final PollingHelper _coverPolling = PollingHelper();
  final PollingHelper _filenamePolling = PollingHelper();
  bool _isFetchingCoverResult = false;
  bool _isFetchingFilenameResult = false;

  List<MetadataEditFileItem> get coverFiles =>
      List<MetadataEditFileItem>.unmodifiable(_coverFiles);
  List<MetadataEditFileItem> get filenameFiles =>
      List<MetadataEditFileItem>.unmodifiable(_filenameFiles);
  List<MetadataEditResultItem> get coverResults =>
      List<MetadataEditResultItem>.unmodifiable(_coverResults);
  List<MetadataEditResultItem> get filenameResults =>
      List<MetadataEditResultItem>.unmodifiable(_filenameResults);
  List<String> get templates => List<String>.unmodifiable(_templates);

  MetadataEditTaskSnapshot get coverSnapshot => _coverSnapshot;
  MetadataEditTaskSnapshot get filenameSnapshot => _filenameSnapshot;
  String? get selectedTemplate => _selectedTemplate;
  String? get coverImagePath => _coverImagePath;
  String get appendText => _appendText;
  String? get toastMessage => _toastMessage;
  String? get ffmpegPath => _ffmpegPath;
  String? get ffprobePath => _ffprobePath;
  bool get coverConfigLocked => _coverConfigLocked;
  bool get filenameConfigLocked => _filenameConfigLocked;
  bool get coverStartFlashSignal => _coverStartFlashSignal;
  bool get filenameStartFlashSignal => _filenameStartFlashSignal;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    try {
      await _bridge.ensureStarted();
      _templates = await _bridge.loadTemplates();
      _initialized = true;
      notifyListeners();
    } on MetadataEditBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> loadTargets(
    MetadataEditPanelKind panel,
    List<String> rawPaths, {
    bool append = false,
  }) async {
    try {
      await _bridge.ensureStarted();
      final List<MetadataEditFileItem> existingFiles = switch (panel) {
        MetadataEditPanelKind.cover => _coverFiles,
        MetadataEditPanelKind.filename => _filenameFiles,
      };
      final int existingCount = existingFiles.length;
      final List<String> mergedPaths = append
          ? <String>{
              ...existingFiles.map((MetadataEditFileItem item) => item.path),
              ...rawPaths,
            }.toList(growable: false)
          : rawPaths;
      final List<String> normalized = await _bridge.loadTargets(mergedPaths);
      final int addedCount = append
          ? (normalized.length - existingCount).clamp(0, normalized.length)
          : 0;
      _applyLoadedTargets(
        panel,
        normalized,
        append: append,
        addedCount: addedCount,
      );
    } on MetadataEditBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> removeTarget(MetadataEditPanelKind panel, String path) async {
    final List<String> remainingPaths =
        switch (panel) {
              MetadataEditPanelKind.cover => _coverFiles,
              MetadataEditPanelKind.filename => _filenameFiles,
            }
            .map((MetadataEditFileItem item) => item.path)
            .where((String itemPath) => itemPath != path)
            .toList(growable: false);
    final int previousCount = switch (panel) {
      MetadataEditPanelKind.cover => _coverFiles.length,
      MetadataEditPanelKind.filename => _filenameFiles.length,
    };
    if (remainingPaths.length == previousCount) {
      return;
    }
    try {
      await _bridge.ensureStarted();
      final List<String> normalized = remainingPaths.isEmpty
          ? <String>[]
          : await _bridge.loadTargets(remainingPaths);
      _applyLoadedTargets(panel, normalized);
      _setToast(remainingPaths.isEmpty ? '已移除目标，列表已清空。' : '已移除目标。');
    } on MetadataEditBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  void updateCoverImagePath(String? value) {
    _coverImagePath = value?.trim().isEmpty ?? true ? null : value?.trim();
    _coverConfigLocked = false;
    _coverStartFlashSignal = false;
    notifyListeners();
    _resetPanelState(MetadataEditPanelKind.cover, '封面配置已更新，请重新锁定后执行。');
  }

  void updateAppendText(String value) {
    final String normalized = value.trim();
    if (_appendText == normalized) {
      return;
    }
    _appendText = normalized;
    if (_filenameConfigLocked) {
      _filenameConfigLocked = false;
      _filenameStartFlashSignal = false;
      _resetPanelState(MetadataEditPanelKind.filename, '文本配置已更新，请重新锁定后执行。');
    }
    notifyListeners();
  }

  void applyTemplate(String template) {
    _selectedTemplate = template;
    _appendText = template;
    _filenameConfigLocked = false;
    _filenameStartFlashSignal = false;
    _resetPanelState(MetadataEditPanelKind.filename, '文本配置已更新，请重新锁定后执行。');
    notifyListeners();
  }

  Future<void> saveCurrentTemplate() async {
    final String text = _appendText.trim();
    if (text.isEmpty) {
      _setToast('请输入需要保存的模板文本。');
      return;
    }
    try {
      _templates = await _bridge.saveTemplate(text);
      notifyListeners();
    } on MetadataEditBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> deleteTemplate(String template) async {
    try {
      _templates = await _bridge.deleteTemplate(template);
      if (_selectedTemplate == template) {
        _selectedTemplate = null;
      }
      notifyListeners();
    } on MetadataEditBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> lockPanelConfig(MetadataEditPanelKind panel) async {
    try {
      await _stageTargetsFor(panel);
      await _bridge.lockConfig(_buildConfig(panel));
      switch (panel) {
        case MetadataEditPanelKind.cover:
          _coverConfigLocked = true;
          _coverStartFlashSignal = !_coverStartFlashSignal;
          _coverSnapshot = MetadataEditTaskSnapshot(
            taskId: _coverSnapshot.taskId,
            taskType: MetadataEditTaskType.coverInjection,
            status: MetadataEditStatus.configLocked,
            progress: 0.02,
            hintText: '配置已锁定，等待开始注入。',
            fileCount: _coverFiles.length,
            successCount: 0,
            skippedCount: 0,
            needCount: 0,
            failedCount: 0,
          );
        case MetadataEditPanelKind.filename:
          _filenameConfigLocked = true;
          _filenameStartFlashSignal = !_filenameStartFlashSignal;
          _filenameSnapshot = MetadataEditTaskSnapshot(
            taskId: _filenameSnapshot.taskId,
            taskType: MetadataEditTaskType.filenameInjection,
            status: MetadataEditStatus.configLocked,
            progress: 0.02,
            hintText: '配置已锁定，等待开始注入。',
            fileCount: _filenameFiles.length,
            successCount: 0,
            skippedCount: 0,
            needCount: 0,
            failedCount: 0,
          );
      }
      notifyListeners();
    } on MetadataEditBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> startTask(MetadataEditPanelKind panel) async {
    try {
      if (!_shouldResumeCancelledTask(panel)) {
        await _stageTargetsFor(panel);
      }
      if (!_isPanelConfigLocked(panel)) {
        await _bridge.lockConfig(_buildConfig(panel));
      }
      switch (panel) {
        case MetadataEditPanelKind.cover:
          _coverStartFlashSignal = false;
          final MetadataEditTaskSnapshot started = await _bridge
              .startCoverInjectionTask();
          _coverSnapshot = started;
          _coverConfigLocked = true;
          _startPolling(MetadataEditPanelKind.cover, started.taskId);
        case MetadataEditPanelKind.filename:
          _filenameStartFlashSignal = false;
          final MetadataEditTaskSnapshot started = await _bridge
              .startFilenameInjectionTask();
          _filenameSnapshot = started;
          _filenameConfigLocked = true;
          _startPolling(MetadataEditPanelKind.filename, started.taskId);
      }
      notifyListeners();
    } on MetadataEditBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> stopTask(MetadataEditPanelKind panel) async {
    final MetadataEditTaskSnapshot snapshot = switch (panel) {
      MetadataEditPanelKind.cover => _coverSnapshot,
      MetadataEditPanelKind.filename => _filenameSnapshot,
    };
    if (snapshot.taskId.isEmpty) {
      return;
    }
    try {
      final MetadataEditTaskSnapshot stopped = await _bridge.stopTask(
        snapshot.taskId,
      );
      _applySnapshot(panel, stopped);
      notifyListeners();
    } on MetadataEditBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  void clearPanel(MetadataEditPanelKind panel) {
    switch (panel) {
      case MetadataEditPanelKind.cover:
        _coverPolling.stop();
        _coverFiles.clear();
        _coverResults.clear();
        _coverImagePath = null;
        _coverConfigLocked = false;
        _coverStartFlashSignal = false;
        _coverSnapshot = MetadataEditTaskSnapshot.idleCover;
      case MetadataEditPanelKind.filename:
        _filenamePolling.stop();
        _filenameFiles.clear();
        _filenameResults.clear();
        _appendText = '';
        _selectedTemplate = null;
        _filenameConfigLocked = false;
        _filenameStartFlashSignal = false;
        _filenameSnapshot = MetadataEditTaskSnapshot.idleFilename;
    }
    notifyListeners();
  }

  void clearToast() {
    if (_toastMessage == null) {
      return;
    }
    _toastMessage = null;
    notifyListeners();
  }

  Future<void> close() async {
    _coverPolling.dispose();
    _filenamePolling.dispose();
    await _bridge.close();
  }

  void markResultsReviewed(MetadataEditPanelKind panel) {
    switch (panel) {
      case MetadataEditPanelKind.cover:
        _coverResults.clear();
        _coverSnapshot = MetadataEditTaskSnapshot(
          taskId: '',
          taskType: MetadataEditTaskType.coverInjection,
          status: _coverConfigLocked
              ? MetadataEditStatus.configLocked
              : MetadataEditStatus.targetReady,
          progress: 0,
          hintText: _coverConfigLocked ? '配置已锁定，等待开始注入。' : '目标就绪，等待执行。',
          fileCount: _coverFiles.length,
          successCount: 0,
          skippedCount: 0,
          needCount: 0,
          failedCount: 0,
        );
      case MetadataEditPanelKind.filename:
        _filenameResults.clear();
        _filenameSnapshot = MetadataEditTaskSnapshot(
          taskId: '',
          taskType: MetadataEditTaskType.filenameInjection,
          status: _filenameConfigLocked
              ? MetadataEditStatus.configLocked
              : MetadataEditStatus.targetReady,
          progress: 0,
          hintText: _filenameConfigLocked ? '配置已锁定，等待开始注入。' : '目标就绪，等待执行。',
          fileCount: _filenameFiles.length,
          successCount: 0,
          skippedCount: 0,
          needCount: 0,
          failedCount: 0,
        );
    }
    notifyListeners();
  }

  void _applyLoadedTargets(
    MetadataEditPanelKind panel,
    List<String> normalizedPaths, {
    bool append = false,
    int addedCount = 0,
  }) {
    final List<MetadataEditFileItem> items = normalizedPaths
        .map(
          (String path) =>
              MetadataEditFileItem(path: path, name: p.basename(path)),
        )
        .toList(growable: false);
    switch (panel) {
      case MetadataEditPanelKind.cover:
        _coverFiles
          ..clear()
          ..addAll(items);
        _coverResults.clear();
        _coverConfigLocked = false;
        _coverStartFlashSignal = false;
        _coverSnapshot = MetadataEditTaskSnapshot(
          taskId: '',
          taskType: MetadataEditTaskType.coverInjection,
          status: items.isEmpty
              ? MetadataEditStatus.idle
              : MetadataEditStatus.targetReady,
          progress: 0,
          hintText: items.isEmpty ? '等待任务载入...' : '目标就绪，等待执行。',
          fileCount: items.length,
          successCount: 0,
          skippedCount: 0,
          needCount: 0,
          failedCount: 0,
        );
      case MetadataEditPanelKind.filename:
        _filenameFiles
          ..clear()
          ..addAll(items);
        _filenameResults.clear();
        _filenameConfigLocked = false;
        _filenameStartFlashSignal = false;
        _filenameSnapshot = MetadataEditTaskSnapshot(
          taskId: '',
          taskType: MetadataEditTaskType.filenameInjection,
          status: items.isEmpty
              ? MetadataEditStatus.idle
              : MetadataEditStatus.targetReady,
          progress: 0,
          hintText: items.isEmpty ? '等待任务载入...' : '目标就绪，等待执行。',
          fileCount: items.length,
          successCount: 0,
          skippedCount: 0,
          needCount: 0,
          failedCount: 0,
        );
    }
    _toastMessage = items.isEmpty
        ? null
        : (append && addedCount > 0 ? '已追加 $addedCount 个目标。' : null);
    notifyListeners();
  }

  Future<void> _stageTargetsFor(MetadataEditPanelKind panel) async {
    final List<String> filePaths = switch (panel) {
      MetadataEditPanelKind.cover =>
        _coverFiles.map((item) => item.path).toList(),
      MetadataEditPanelKind.filename =>
        _filenameFiles.map((item) => item.path).toList(),
    };
    if (filePaths.isEmpty) {
      throw MetadataEditBridgeException('EMPTY_TARGETS', '请先导入目标音频文件。');
    }
    await _bridge.loadTargets(filePaths);
  }

  Map<String, Object?> _buildConfig(MetadataEditPanelKind panel) {
    return switch (panel) {
      MetadataEditPanelKind.cover => <String, Object?>{
        'operation': 'cover_injection',
        'cover_image_path': _coverImagePath,
        'ffmpeg_path': _ffmpegPath,
        'ffprobe_path': _ffprobePath,
      },
      MetadataEditPanelKind.filename => <String, Object?>{
        'operation': 'filename_injection',
        'append_text': _appendText.trim(),
        'ffmpeg_path': _ffmpegPath,
        'ffprobe_path': _ffprobePath,
      },
    };
  }

  bool _isPanelConfigLocked(MetadataEditPanelKind panel) {
    return switch (panel) {
      MetadataEditPanelKind.cover => _coverConfigLocked,
      MetadataEditPanelKind.filename => _filenameConfigLocked,
    };
  }

  void _startPolling(MetadataEditPanelKind panel, String taskId) {
    final PollingHelper polling = switch (panel) {
      MetadataEditPanelKind.cover => _coverPolling,
      MetadataEditPanelKind.filename => _filenamePolling,
    };
    polling.start(() async {
      try {
        final List<MetadataEditTaskEvent> events = await _bridge
            .subscribeTaskEvents(taskId: taskId);
        if (events.isEmpty) {
          return;
        }
        for (final MetadataEditTaskEvent event in events) {
          _applySnapshot(panel, event.snapshot);
        }
        notifyListeners();
        final MetadataEditStatus status = switch (panel) {
          MetadataEditPanelKind.cover => _coverSnapshot.status,
          MetadataEditPanelKind.filename => _filenameSnapshot.status,
        };
        if (_isTerminalStatus(status)) {
          polling.stop();
          await _loadFinalResult(panel, taskId);
        }
      } on MetadataEditBridgeException catch (error) {
        polling.stop();
        _setToast(error.message);
      }
    });
  }

  Future<void> _loadFinalResult(
    MetadataEditPanelKind panel,
    String taskId,
  ) async {
    final bool isFetching = switch (panel) {
      MetadataEditPanelKind.cover => _isFetchingCoverResult,
      MetadataEditPanelKind.filename => _isFetchingFilenameResult,
    };
    if (isFetching) {
      return;
    }
    switch (panel) {
      case MetadataEditPanelKind.cover:
        _isFetchingCoverResult = true;
      case MetadataEditPanelKind.filename:
        _isFetchingFilenameResult = true;
    }
    try {
      final MetadataEditResult result = await _bridge.fetchMetadataEditResult(
        taskId,
      );
      switch (panel) {
        case MetadataEditPanelKind.cover:
          _coverResults
            ..clear()
            ..addAll(result.results);
          _coverSnapshot = MetadataEditTaskSnapshot(
            taskId: result.taskId,
            taskType: MetadataEditTaskType.coverInjection,
            status: result.status,
            progress: 1,
            hintText: result.failedCount > 0 ? '任务执行完毕，存在失败项。' : '任务执行完毕。',
            fileCount: _coverFiles.length,
            successCount: result.successCount,
            skippedCount: result.skippedCount,
            needCount: result.needCount,
            failedCount: result.failedCount,
          );
        case MetadataEditPanelKind.filename:
          _filenameResults
            ..clear()
            ..addAll(result.results);
          _applyFilenameOutputPaths(result.results);
          _filenameSnapshot = MetadataEditTaskSnapshot(
            taskId: result.taskId,
            taskType: MetadataEditTaskType.filenameInjection,
            status: result.status,
            progress: 1,
            hintText: result.failedCount > 0 ? '任务执行完毕，存在失败项。' : '任务执行完毕。',
            fileCount: _filenameFiles.length,
            successCount: result.successCount,
            skippedCount: result.skippedCount,
            needCount: result.needCount,
            failedCount: result.failedCount,
          );
      }
      notifyListeners();
    } on MetadataEditBridgeException catch (error) {
      _setToast(error.message);
    } finally {
      switch (panel) {
        case MetadataEditPanelKind.cover:
          _isFetchingCoverResult = false;
        case MetadataEditPanelKind.filename:
          _isFetchingFilenameResult = false;
      }
    }
  }

  void _applySnapshot(
    MetadataEditPanelKind panel,
    MetadataEditTaskSnapshot snapshot,
  ) {
    switch (panel) {
      case MetadataEditPanelKind.cover:
        _coverSnapshot = snapshot;
      case MetadataEditPanelKind.filename:
        _filenameSnapshot = snapshot;
    }
  }

  bool _isTerminalStatus(MetadataEditStatus status) {
    return status == MetadataEditStatus.success ||
        status == MetadataEditStatus.cancelled ||
        status == MetadataEditStatus.error;
  }

  bool _shouldResumeCancelledTask(MetadataEditPanelKind panel) {
    final MetadataEditTaskSnapshot snapshot = switch (panel) {
      MetadataEditPanelKind.cover => _coverSnapshot,
      MetadataEditPanelKind.filename => _filenameSnapshot,
    };
    return snapshot.status == MetadataEditStatus.cancelled &&
        snapshot.taskId.isNotEmpty;
  }

  void _applyFilenameOutputPaths(List<MetadataEditResultItem> results) {
    final Map<String, String> renamedPaths = <String, String>{
      for (final MetadataEditResultItem item in results)
        if (item.changed && item.outputPath.isNotEmpty)
          item.inputPath: item.outputPath,
    };
    if (renamedPaths.isEmpty) {
      return;
    }
    for (int index = 0; index < _filenameFiles.length; index += 1) {
      final MetadataEditFileItem current = _filenameFiles[index];
      final String? updatedPath = renamedPaths[current.path];
      if (updatedPath == null) {
        continue;
      }
      _filenameFiles[index] = MetadataEditFileItem(
        path: updatedPath,
        name: p.basename(updatedPath),
      );
    }
  }

  void _resetPanelState(MetadataEditPanelKind panel, String hintText) {
    switch (panel) {
      case MetadataEditPanelKind.cover:
        if (_coverFiles.isEmpty ||
            _coverSnapshot.status == MetadataEditStatus.running) {
          return;
        }
        _coverResults.clear();
        _coverSnapshot = MetadataEditTaskSnapshot(
          taskId: '',
          taskType: MetadataEditTaskType.coverInjection,
          status: MetadataEditStatus.targetReady,
          progress: 0,
          hintText: hintText,
          fileCount: _coverFiles.length,
          successCount: 0,
          skippedCount: 0,
          needCount: 0,
          failedCount: 0,
        );
      case MetadataEditPanelKind.filename:
        if (_filenameFiles.isEmpty ||
            _filenameSnapshot.status == MetadataEditStatus.running) {
          return;
        }
        _filenameResults.clear();
        _filenameSnapshot = MetadataEditTaskSnapshot(
          taskId: '',
          taskType: MetadataEditTaskType.filenameInjection,
          status: MetadataEditStatus.targetReady,
          progress: 0,
          hintText: hintText,
          fileCount: _filenameFiles.length,
          successCount: 0,
          skippedCount: 0,
          needCount: 0,
          failedCount: 0,
        );
    }
  }

  void _setToast(String message) {
    _toastMessage = message;
    notifyListeners();
  }
}
