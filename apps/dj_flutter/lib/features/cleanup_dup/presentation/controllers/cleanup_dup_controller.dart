import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dj_flutter/shared/task_runtime/polling_helper.dart';

import '../models/cleanup_dup_models.dart';

const MethodChannel _cleanupDupPlatformChannel = MethodChannel(
  'dj_flutter/unlock_music',
);

class CleanupDupController extends ChangeNotifier {
  CleanupDupController({required CleanupDupTaskBridge bridge})
    : _bridge = bridge;

  final CleanupDupTaskBridge _bridge;

  final TextEditingController deleteTextController = TextEditingController();
  final TextEditingController duplicateDeleteTextController =
      TextEditingController();

  CleanupDupStatus _titleCleanStatus = CleanupDupStatus.idle;
  CleanupDupStatus _duplicateSearchStatus = CleanupDupStatus.idle;
  List<FileItem> _titleLoadedFiles = <FileItem>[];
  List<FileItem> _duplicateLoadedFiles = <FileItem>[];
  List<DuplicateGroup> _duplicateGroups = <DuplicateGroup>[];
  int _duplicateCount = 0;
  bool _showReviewModal = false;
  bool _moveToRecycleBin = true;
  bool _isExecutingDelete = false;
  String _matchingMode = '极速比对';
  bool _titleConfigLocked = false;
  bool _duplicateConfigLocked = false;
  bool _titleStartFlashSignal = false;
  bool _duplicateStartFlashSignal = false;
  bool _titleDraggingOver = false;
  bool _duplicateDraggingOver = false;
  String? _titleToastMessage;
  String? _duplicateToastMessage;
  CleanupDupCompletedTaskRecord? _titleLastCompletedTask;
  CleanupDupCompletedTaskRecord? _duplicateLastCompletedTask;

  final PollingHelper _titlePolling = PollingHelper();
  final PollingHelper _duplicatePolling = PollingHelper();
  String? _titleTaskId;
  String? _duplicateTaskId;

  double _titleProgressValue = 0;
  double _duplicateProgressValue = 0;
  String _titleProgressHintText = '等待任务载入...';
  String _duplicateProgressHintText = '等待任务载入...';

  CleanupDupStatus get titleCleanStatus => _titleCleanStatus;
  CleanupDupStatus get duplicateSearchStatus => _duplicateSearchStatus;
  List<FileItem> get titleLoadedFiles =>
      List<FileItem>.unmodifiable(_titleLoadedFiles);
  List<FileItem> get duplicateLoadedFiles =>
      List<FileItem>.unmodifiable(_duplicateLoadedFiles);
  List<DuplicateGroup> get duplicateGroups =>
      List<DuplicateGroup>.unmodifiable(_duplicateGroups);
  int get duplicateCount => _duplicateCount;
  bool get showReviewModal => _showReviewModal;
  bool get moveToRecycleBin => _moveToRecycleBin;
  bool get isExecutingDelete => _isExecutingDelete;
  String get matchingMode => _matchingMode;
  bool get titleConfigLocked => _titleConfigLocked;
  bool get duplicateConfigLocked => _duplicateConfigLocked;
  bool get titleStartFlashSignal => _titleStartFlashSignal;
  bool get duplicateStartFlashSignal => _duplicateStartFlashSignal;
  bool get titleDraggingOver => _titleDraggingOver;
  bool get duplicateDraggingOver => _duplicateDraggingOver;
  String? get titleToastMessage => _titleToastMessage;
  String? get duplicateToastMessage => _duplicateToastMessage;
  CleanupDupCompletedTaskRecord? get titleLastCompletedTask =>
      _titleLastCompletedTask;
  CleanupDupCompletedTaskRecord? get duplicateLastCompletedTask =>
      _duplicateLastCompletedTask;

  bool get titleRunning => _titleCleanStatus == CleanupDupStatus.running;
  bool get duplicateRunning =>
      _duplicateSearchStatus == CleanupDupStatus.running ||
      _duplicateSearchStatus == CleanupDupStatus.executing;

  bool get titleStartEnabled => _titleCleanStatus != CleanupDupStatus.running;

  bool get duplicateStartEnabled =>
      _duplicateSearchStatus != CleanupDupStatus.running &&
      _duplicateSearchStatus != CleanupDupStatus.executing;

  int get selectedDeleteCount => _duplicateGroups
      .expand((DuplicateGroup group) => group.entries)
      .where((DuplicateEntry entry) => entry.isSelectedToDelete)
      .length;

  String get titleStatusText => _statusLabel(_titleCleanStatus);
  String get duplicateStatusText => _statusLabel(_duplicateSearchStatus);
  int get titleFileCount => _titleLoadedFiles.length;
  int get duplicateFileCount => _duplicateLoadedFiles.length;
  int get duplicateFoundCount => _duplicateCount;
  double get titleProgress => _titleProgressValue;
  double get duplicateProgress => _duplicateProgressValue;
  String get titleProgressHint => _titleProgressHintText;
  String get duplicateProgressHint => _duplicateProgressHintText;

  Color statusColor(CleanupDupStatus status) {
    return switch (status) {
      CleanupDupStatus.running => const Color(0xFF10B981),
      CleanupDupStatus.reviewReady => const Color(0xFFD97706),
      CleanupDupStatus.executing => const Color(0xFF10B981),
      CleanupDupStatus.success => const Color(0xFF10B981),
      CleanupDupStatus.cancelled => const Color(0xFFE11D48),
      CleanupDupStatus.error => const Color(0xFFE11D48),
      _ => const Color(0xFFD97706),
    };
  }

  String _statusLabel(CleanupDupStatus status) {
    return switch (status) {
      CleanupDupStatus.running => '处理中',
      CleanupDupStatus.reviewReady => '待审阅',
      CleanupDupStatus.executing => '处理中',
      CleanupDupStatus.success => '完成',
      CleanupDupStatus.cancelled => '已取消',
      CleanupDupStatus.error => '错误',
      _ => '待命',
    };
  }

  String dropHintFor(CleanupDupPanelKind panel) {
    return switch (panel) {
      CleanupDupPanelKind.titleClean => '点击选择或拖入文件文件夹',
      CleanupDupPanelKind.duplicateSearch => '点击选择或拖入文件文件夹',
    };
  }

  bool draggingFor(CleanupDupPanelKind panel) {
    return switch (panel) {
      CleanupDupPanelKind.titleClean => _titleDraggingOver,
      CleanupDupPanelKind.duplicateSearch => _duplicateDraggingOver,
    };
  }

  List<FileItem> filesFor(CleanupDupPanelKind panel) {
    return switch (panel) {
      CleanupDupPanelKind.titleClean => titleLoadedFiles,
      CleanupDupPanelKind.duplicateSearch => duplicateLoadedFiles,
    };
  }

  String? toastFor(CleanupDupPanelKind panel) {
    return switch (panel) {
      CleanupDupPanelKind.titleClean => _titleToastMessage,
      CleanupDupPanelKind.duplicateSearch => _duplicateToastMessage,
    };
  }

  void setMatchingMode(String value) {
    if (_matchingMode == value) {
      return;
    }
    _matchingMode = value;
    notifyListeners();
  }

  void toggleMoveToRecycleBin() {
    _moveToRecycleBin = !_moveToRecycleBin;
    notifyListeners();
  }

  void setMoveToRecycleBin(bool value) {
    if (_moveToRecycleBin == value) {
      return;
    }
    _moveToRecycleBin = value;
    notifyListeners();
  }

  Future<void> onConfigConfirm(CleanupDupPanelKind panel) async {
    await lockConfig(panel);
  }

  Future<void> onSelectFilesClicked(
    CleanupDupPanelKind panel,
    BuildContext context,
  ) async {
    await onSelectAudioFiles(panel);
  }

  Future<void> onSelectAudioFiles(CleanupDupPanelKind panel) async {
    final List<String> selectedPaths = await _pickFileTargets(panel);
    if (selectedPaths.isEmpty) {
      return;
    }
    final bool append = filesFor(panel).isNotEmpty;
    await loadTargets(panel, selectedPaths, append: append);
  }

  Future<void> onSelectAudioFolder(CleanupDupPanelKind panel) async {
    final List<String> selectedPaths = await _pickDirectoryTargets(panel);
    if (selectedPaths.isEmpty) {
      return;
    }
    final bool append = filesFor(panel).isNotEmpty;
    await loadTargets(panel, selectedPaths, append: append);
  }

  Future<void> pickTargetsNative(CleanupDupPanelKind panel) async {
    if (Platform.isMacOS) {
      try {
        final List<Object?>? result = await _cleanupDupPlatformChannel
            .invokeListMethod<Object?>('pickUnlockTargets');
        final List<String> paths =
            result
                ?.whereType<String>()
                .where((String path) => path.isNotEmpty)
                .toList() ??
            <String>[];
        if (paths.isEmpty) {
          return;
        }
        final bool append = filesFor(panel).isNotEmpty;
        await loadTargets(panel, paths, append: append);
      } catch (error) {
        _setToast(panel, '无法打开文件选择器，请检查系统权限后重试。');
      }
      return;
    }
    await onSelectAudioFiles(panel);
  }

  Future<void> onFilesDropped(
    CleanupDupPanelKind panel,
    List<String> filePaths,
  ) async {
    setDraggingOver(panel, false);
    if (filesFor(panel).isNotEmpty) {
      await loadTargets(panel, filePaths, append: true);
      return;
    }
    if (filePaths.isEmpty) {
      _setToast(panel, '未接收到可导入的路径。');
      return;
    }
    await loadTargets(panel, filePaths);
  }

  VoidCallback get onClearTitleFiles =>
      () => onClearFiles(CleanupDupPanelKind.titleClean);
  VoidCallback get onClearDuplicateFiles =>
      () => onClearFiles(CleanupDupPanelKind.duplicateSearch);

  void onClearFiles(CleanupDupPanelKind panel) {
    switch (panel) {
      case CleanupDupPanelKind.titleClean:
        _titlePolling.stop();
        _titleTaskId = null;
        _titleLoadedFiles = <FileItem>[];
        _titleConfigLocked = false;
        _titleCleanStatus = CleanupDupStatus.idle;
        _titleDraggingOver = false;
        _titleProgressValue = 0;
        _titleProgressHintText = '等待任务载入...';
        _titleStartFlashSignal = false;
        _titleToastMessage = null;
        _titleLastCompletedTask = null;
      case CleanupDupPanelKind.duplicateSearch:
        _duplicatePolling.stop();
        _duplicateTaskId = null;
        _duplicateLoadedFiles = <FileItem>[];
        _duplicateGroups = <DuplicateGroup>[];
        _duplicateCount = 0;
        _duplicateConfigLocked = false;
        _duplicateSearchStatus = CleanupDupStatus.idle;
        _duplicateDraggingOver = false;
        _duplicateProgressValue = 0;
        _duplicateProgressHintText = '等待任务载入...';
        _duplicateStartFlashSignal = false;
        _showReviewModal = false;
        _isExecutingDelete = false;
        _duplicateToastMessage = null;
        _duplicateLastCompletedTask = null;
    }
    notifyListeners();
  }

  Future<void> loadTargets(
    CleanupDupPanelKind panel,
    List<String> filePaths, {
    bool append = false,
  }) async {
    _clearToast(panel);
    try {
      final List<String> loadedPaths = await _bridge.loadTargets(
        panel,
        filePaths,
      );
      final Set<String> existingPaths = switch (panel) {
        CleanupDupPanelKind.titleClean =>
          _titleLoadedFiles.map((FileItem f) => f.path).toSet(),
        CleanupDupPanelKind.duplicateSearch =>
          _duplicateLoadedFiles.map((FileItem f) => f.path).toSet(),
      };
      final List<FileItem> newItems = loadedPaths
          .where((String path) => !existingPaths.contains(path))
          .toList()
          .asMap()
          .entries
          .map((MapEntry<int, String> entry) {
            final String path = entry.value;
            return FileItem(
              path: path,
              name: path.split('/').last,
              size: panel == CleanupDupPanelKind.duplicateSearch
                  ? _mockSize(entry.key)
                  : null,
            );
          })
          .toList();
      switch (panel) {
        case CleanupDupPanelKind.titleClean:
          final List<FileItem> current = _titleLoadedFiles;
          _titleLoadedFiles = append ? current + newItems : newItems;
          _titleCleanStatus = CleanupDupStatus.targetReady;
          _titleProgressHintText = '目标就绪，等待执行。';
          if (append && newItems.isEmpty) {
            _titleToastMessage = '未追加新目标，导入项可能已存在。';
          } else if (append) {
            _titleToastMessage = '已追加 ${newItems.length} 个目标。';
          }
        case CleanupDupPanelKind.duplicateSearch:
          final List<FileItem> current = _duplicateLoadedFiles;
          _duplicateLoadedFiles = append ? current + newItems : newItems;
          _duplicateSearchStatus = CleanupDupStatus.targetReady;
          _duplicateProgressHintText = '目标就绪，等待执行。';
          if (append && newItems.isEmpty) {
            _duplicateToastMessage = '未追加新目标，导入项可能已存在。';
          } else if (append) {
            _duplicateToastMessage = '已追加 ${newItems.length} 个目标。';
          }
      }
      notifyListeners();
    } on CleanupDupBridgeException catch (error) {
      _setToast(panel, error.message);
    }
  }

  void removeTarget(CleanupDupPanelKind panel, String path) {
    switch (panel) {
      case CleanupDupPanelKind.titleClean:
        _titleLoadedFiles = _titleLoadedFiles
            .where((FileItem f) => f.path != path)
            .toList();
        if (_titleLoadedFiles.isEmpty) {
          _titleCleanStatus = CleanupDupStatus.idle;
          _titleProgressHintText = '等待任务载入...';
        }
        _titleToastMessage = '已移除目标。';
      case CleanupDupPanelKind.duplicateSearch:
        _duplicateLoadedFiles = _duplicateLoadedFiles
            .where((FileItem f) => f.path != path)
            .toList();
        if (_duplicateLoadedFiles.isEmpty) {
          _duplicateSearchStatus = CleanupDupStatus.idle;
          _duplicateProgressHintText = '等待任务载入...';
        }
        _duplicateToastMessage = '已移除目标。';
    }
    notifyListeners();
  }

  void clearLastCompletedTask(CleanupDupPanelKind panel) {
    switch (panel) {
      case CleanupDupPanelKind.titleClean:
        _titleLastCompletedTask = null;
        _titleToastMessage = '已清除最近一次完成任务记录。';
      case CleanupDupPanelKind.duplicateSearch:
        _duplicateLastCompletedTask = null;
        _duplicateToastMessage = '已清除最近一次完成任务记录。';
    }
    notifyListeners();
  }

  void _storeCompletedTask({
    required CleanupDupPanelKind panel,
    required CleanupDupStatus status,
    String? message,
  }) {
    final String? taskId = switch (panel) {
      CleanupDupPanelKind.titleClean => _titleTaskId,
      CleanupDupPanelKind.duplicateSearch => _duplicateTaskId,
    };
    if (taskId == null) {
      return;
    }
    final List<FileItem> inputFiles = switch (panel) {
      CleanupDupPanelKind.titleClean => List<FileItem>.from(_titleLoadedFiles),
      CleanupDupPanelKind.duplicateSearch => List<FileItem>.from(
        _duplicateLoadedFiles,
      ),
    };
    final int processedCount = inputFiles.length;
    final record = CleanupDupCompletedTaskRecord(
      taskId: taskId,
      panel: panel,
      status: status,
      finishedAt: DateTime.now(),
      inputFiles: inputFiles,
      processedCount: processedCount,
      message: message,
    );
    switch (panel) {
      case CleanupDupPanelKind.titleClean:
        _titleLastCompletedTask = record;
      case CleanupDupPanelKind.duplicateSearch:
        _duplicateLastCompletedTask = record;
    }
  }

  Future<void> lockConfig(CleanupDupPanelKind panel) async {
    _clearToast(panel);
    final Map<String, Object?> config = switch (panel) {
      CleanupDupPanelKind.titleClean => <String, Object?>{
        'delete_text': deleteTextController.text.trim(),
      },
      CleanupDupPanelKind.duplicateSearch => <String, Object?>{
        'matching_mode': _matchingMode,
        'move_to_recycle_bin': _moveToRecycleBin,
      },
    };
    try {
      await _bridge.lockConfig(panel, config);
      switch (panel) {
        case CleanupDupPanelKind.titleClean:
          _titleConfigLocked = true;
          _titleCleanStatus = CleanupDupStatus.configLocked;
          _titleStartFlashSignal = !_titleStartFlashSignal;
        case CleanupDupPanelKind.duplicateSearch:
          _duplicateConfigLocked = true;
          _duplicateSearchStatus = CleanupDupStatus.configLocked;
          _duplicateStartFlashSignal = !_duplicateStartFlashSignal;
      }
      notifyListeners();
    } on CleanupDupBridgeException catch (error) {
      _setToast(panel, error.message);
    }
  }

  Future<void> onStartTask(CleanupDupPanelKind panel) async {
    switch (panel) {
      case CleanupDupPanelKind.titleClean:
        await startTitleCleanTask();
      case CleanupDupPanelKind.duplicateSearch:
        if (_duplicateSearchStatus == CleanupDupStatus.reviewReady) {
          final String? taskId = _duplicateTaskId;
          if (taskId != null) {
            await fetchReviewResult(taskId);
          }
          return;
        }
        await startDuplicateCheckTask();
    }
  }

  Future<void> startTitleCleanTask() async {
    if (_titleLoadedFiles.isEmpty) {
      _titleToastMessage = '请先拖入或选择目标文件库！';
      notifyListeners();
      return;
    }
    if (!_titleConfigLocked) {
      final String deleteText = deleteTextController.text.trim();
      if (deleteText.isEmpty) {
        _titleToastMessage = '请输入要清除的文本内容！';
        notifyListeners();
        return;
      }
      await lockConfig(CleanupDupPanelKind.titleClean);
      if (!_titleConfigLocked) {
        return;
      }
    }
    _clearToast(CleanupDupPanelKind.titleClean);
    _titleStartFlashSignal = false;
    _titleCleanStatus = CleanupDupStatus.running;
    _titleProgressValue = 0;
    _titleProgressHintText = '正在高速扫描扇区数据...';
    notifyListeners();
    try {
      final CleanupDupTaskSnapshot snapshot = await _bridge
          .startTitleCleanTask();
      _titleTaskId = snapshot.taskId;
      _applySnapshot(snapshot);
      _startPolling(CleanupDupPanelKind.titleClean, snapshot.taskId);
    } on CleanupDupBridgeException catch (error) {
      _titleCleanStatus = CleanupDupStatus.error;
      _titleToastMessage = error.message;
      notifyListeners();
    }
  }

  Future<void> startDuplicateCheckTask() async {
    if (_duplicateLoadedFiles.isEmpty) {
      _duplicateToastMessage = '请先拖入或选择目标文件库！';
      notifyListeners();
      return;
    }
    _clearToast(CleanupDupPanelKind.duplicateSearch);
    _duplicateStartFlashSignal = false;
    _duplicateSearchStatus = CleanupDupStatus.running;
    _duplicateCount = 0;
    _duplicateProgressValue = 0;
    _duplicateProgressHintText = '正在高速扫描扇区数据...';
    notifyListeners();
    try {
      final CleanupDupTaskSnapshot snapshot = await _bridge
          .startDuplicateCheckTask();
      _duplicateTaskId = snapshot.taskId;
      _applySnapshot(snapshot);
      _startPolling(CleanupDupPanelKind.duplicateSearch, snapshot.taskId);
    } on CleanupDupBridgeException catch (error) {
      _duplicateSearchStatus = CleanupDupStatus.error;
      _duplicateToastMessage = error.message;
      notifyListeners();
    }
  }

  Future<void> onStopTask(CleanupDupPanelKind panel) async {
    final String? taskId = switch (panel) {
      CleanupDupPanelKind.titleClean => _titleTaskId,
      CleanupDupPanelKind.duplicateSearch => _duplicateTaskId,
    };
    if (taskId == null) {
      switch (panel) {
        case CleanupDupPanelKind.titleClean:
          _titleCleanStatus = CleanupDupStatus.cancelled;
          _titleProgressHintText = '任务已由用户手动停止。';
        case CleanupDupPanelKind.duplicateSearch:
          _duplicateSearchStatus = CleanupDupStatus.cancelled;
          _duplicateProgressHintText = '任务已由用户手动停止。';
      }
      notifyListeners();
      return;
    }
    try {
      final CleanupDupTaskSnapshot snapshot = await _bridge.stopTask(taskId);
      _applySnapshot(snapshot);
      _stopPolling(panel);
    } on CleanupDupBridgeException catch (error) {
      _setToast(panel, error.message);
    }
  }

  Future<void> fetchReviewResult(String taskId) async {
    try {
      final CleanupDupReviewResult result = await _bridge.fetchReviewResult(
        taskId,
      );
      _duplicateGroups = result.groups;
      _duplicateCount = result.duplicateCount;
      _duplicateSearchStatus = result.status;
      _duplicateTaskId = result.taskId;
      _duplicateProgressValue = 1;
      _duplicateProgressHintText = '发现重复项，请审阅确认。';
      _showReviewModal = true;
      notifyListeners();
    } on CleanupDupBridgeException catch (error) {
      _duplicateToastMessage = error.message;
      notifyListeners();
    }
  }

  Future<void> executeDelete(List<FileItem> selectedFiles) async {
    if (selectedFiles.isEmpty) {
      _duplicateToastMessage = '请至少勾选 1 项删除目标。';
      notifyListeners();
      return;
    }
    final String? taskId = _duplicateTaskId;
    if (taskId == null) {
      _duplicateToastMessage = '未找到可执行的任务。';
      notifyListeners();
      return;
    }
    _isExecutingDelete = true;
    notifyListeners();
    try {
      await _bridge.executeDelete(
        taskId: taskId,
        moveToRecycleBin: _moveToRecycleBin,
        selectedFiles: selectedFiles,
      );
      onClearFiles(CleanupDupPanelKind.duplicateSearch);
      _duplicateToastMessage = _moveToRecycleBin
          ? '执行成功！已将文件移至回收站。'
          : '执行成功！已删除所选文件。';
      notifyListeners();
    } on CleanupDupBridgeException catch (error) {
      _duplicateToastMessage = error.message;
      _isExecutingDelete = false;
      notifyListeners();
    }
  }

  Future<void> onExecuteDelete(List<FileItem> selectedFiles) async {
    await executeDelete(selectedFiles);
  }

  void closeReviewModal() {
    _showReviewModal = false;
    notifyListeners();
  }

  void updateUI() {
    notifyListeners();
  }

  Future<List<String>> _pickFileTargets(CleanupDupPanelKind panel) async {
    try {
      final List<XFile> files = await openFiles(
        acceptedTypeGroups: <XTypeGroup>[
          XTypeGroup(
            label: 'audio',
            extensions: <String>[
              'mp3',
              'wav',
              'flac',
              'aac',
              'm4a',
              'aiff',
              'ogg',
              'wma',
            ],
          ),
        ],
        confirmButtonText: '导入',
      );
      return files
          .map((XFile file) => file.path)
          .where((String path) => path.isNotEmpty)
          .toList();
    } catch (error) {
      _setToast(panel, '无法打开文件选择器，请检查系统权限后重试。');
      return <String>[];
    }
  }

  Future<List<String>> _pickDirectoryTargets(CleanupDupPanelKind panel) async {
    try {
      final String? directory = await getDirectoryPath(confirmButtonText: '导入');
      if (directory == null || directory.isEmpty) {
        return <String>[];
      }
      return <String>[directory];
    } catch (error) {
      _setToast(panel, '无法打开文件夹选择器，请检查系统权限后重试。');
      return <String>[];
    }
  }

  void setDraggingOver(CleanupDupPanelKind panel, bool value) {
    switch (panel) {
      case CleanupDupPanelKind.titleClean:
        _titleDraggingOver = value;
      case CleanupDupPanelKind.duplicateSearch:
        _duplicateDraggingOver = value;
    }
    notifyListeners();
  }

  void toggleEntrySelection(int groupIndex, int entryIndex) {
    final DuplicateGroup group = _duplicateGroups[groupIndex];
    final DuplicateEntry entry = group.entries[entryIndex];
    if (entry.isAutoKeep) {
      return;
    }
    final List<DuplicateEntry> nextEntries = List<DuplicateEntry>.from(
      group.entries,
    );
    nextEntries[entryIndex] = entry.copyWith(
      isSelectedToDelete: !entry.isSelectedToDelete,
    );
    _duplicateGroups[groupIndex] = group.copyWith(entries: nextEntries);
    notifyListeners();
  }

  List<FileItem> selectedDeleteFiles() {
    return _duplicateGroups
        .expand((DuplicateGroup group) => group.entries)
        .where((DuplicateEntry entry) => entry.isSelectedToDelete)
        .map((DuplicateEntry entry) => entry.file)
        .toList();
  }

  void _startPolling(CleanupDupPanelKind panel, String taskId) {
    final PollingHelper polling = switch (panel) {
      CleanupDupPanelKind.titleClean => _titlePolling,
      CleanupDupPanelKind.duplicateSearch => _duplicatePolling,
    };
    polling.start(() => _pollTask(panel, taskId));
  }

  Future<void> _pollTask(CleanupDupPanelKind panel, String taskId) async {
    try {
      final List<CleanupDupTaskEvent> events = await _bridge
          .subscribeTaskEvents(taskId: taskId);
      for (final CleanupDupTaskEvent event in events) {
        _applySnapshot(event.snapshot);
      }
      final CleanupDupStatus status = _statusFor(panel);
      if (_isStableStatus(status)) {
        _stopPolling(panel);
        _storeCompletedTask(
          panel: panel,
          status: status,
          message: _progressHintFor(panel),
        );
      }
    } on CleanupDupBridgeException catch (error) {
      _setToast(panel, error.message);
      _stopPolling(panel);
      _storeCompletedTask(
        panel: panel,
        status: CleanupDupStatus.error,
        message: error.message,
      );
    }
  }

  String _progressHintFor(CleanupDupPanelKind panel) {
    return switch (panel) {
      CleanupDupPanelKind.titleClean => _titleProgressHintText,
      CleanupDupPanelKind.duplicateSearch => _duplicateProgressHintText,
    };
  }

  void _applySnapshot(CleanupDupTaskSnapshot snapshot) {
    switch (snapshot.panel) {
      case CleanupDupPanelKind.titleClean:
        _titleTaskId = snapshot.taskId;
        _titleCleanStatus = snapshot.status;
        _titleProgressValue = snapshot.progress;
        _titleProgressHintText = snapshot.progressHintText;
      case CleanupDupPanelKind.duplicateSearch:
        _duplicateTaskId = snapshot.taskId;
        _duplicateSearchStatus = snapshot.status;
        _duplicateCount = snapshot.duplicateCount;
        _duplicateProgressValue = snapshot.progress;
        _duplicateProgressHintText = snapshot.progressHintText;
    }
    notifyListeners();
  }

  CleanupDupStatus _statusFor(CleanupDupPanelKind panel) {
    return switch (panel) {
      CleanupDupPanelKind.titleClean => _titleCleanStatus,
      CleanupDupPanelKind.duplicateSearch => _duplicateSearchStatus,
    };
  }

  bool _isStableStatus(CleanupDupStatus status) {
    return status == CleanupDupStatus.reviewReady ||
        status == CleanupDupStatus.success ||
        status == CleanupDupStatus.cancelled ||
        status == CleanupDupStatus.error;
  }

  void _stopPolling(CleanupDupPanelKind panel) {
    switch (panel) {
      case CleanupDupPanelKind.titleClean:
        _titlePolling.stop();
      case CleanupDupPanelKind.duplicateSearch:
        _duplicatePolling.stop();
    }
  }

  void _clearToast(CleanupDupPanelKind panel) {
    switch (panel) {
      case CleanupDupPanelKind.titleClean:
        _titleToastMessage = null;
      case CleanupDupPanelKind.duplicateSearch:
        _duplicateToastMessage = null;
    }
  }

  void _setToast(CleanupDupPanelKind panel, String message) {
    switch (panel) {
      case CleanupDupPanelKind.titleClean:
        _titleToastMessage = message;
      case CleanupDupPanelKind.duplicateSearch:
        _duplicateToastMessage = message;
    }
    notifyListeners();
  }

  String _mockSize(int index) {
    final int major = 8 + (index % 9);
    final int minor = (index * 3) % 10;
    return '$major.$minor MB';
  }

  @override
  void dispose() {
    _titlePolling.dispose();
    _duplicatePolling.dispose();
    deleteTextController.dispose();
    duplicateDeleteTextController.dispose();
    unawaited(_bridge.close());
    super.dispose();
  }
}
