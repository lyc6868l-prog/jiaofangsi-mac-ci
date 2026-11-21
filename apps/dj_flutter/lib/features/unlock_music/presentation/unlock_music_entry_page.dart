import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:dj_flutter/app/dj_app_scope.dart';
import 'package:dj_flutter/app/router/app_router.dart';
import 'package:dj_flutter/shared/hardware_ui/hardware_ui.dart';
import 'package:dj_flutter/shared/platform_utils.dart' as platform_utils;
import 'package:dj_flutter/shared/task_runtime/polling_helper.dart';
import 'package:dj_flutter/shared/task_runtime/task_running_notifier.dart'
    show TaskRunningNotifier, TaskEndState;
import 'package:dj_flutter/shared/task_ui/task_file_outcome_tile.dart';
import 'package:dj_flutter/shared/task_ui/task_history_entry_card.dart';
import 'package:dj_flutter/shared/task_ui/task_import_list_shell.dart';
import 'package:dj_flutter/shared/task_ui/task_item_status_badge.dart';
import 'package:dj_flutter/shared/task_ui/task_result_filter.dart';

import 'controllers/python_search_download_task_bridge.dart';
import 'controllers/python_unlock_music_task_bridge.dart';
import 'models/search_download_models.dart';
import 'models/unlock_music_models.dart';

enum _UnlockMusicPanelView { unlock, search }

const MethodChannel _unlockMusicPlatformChannel = MethodChannel(
  'dj_flutter/unlock_music',
);

class UnlockMusicEntryPage extends StatefulWidget {
  const UnlockMusicEntryPage({
    super.key,
    this.bridge,
    this.searchBridge,
    this.targetPicker,
    this.onOpenOutputDirectory,
  });

  final UnlockMusicTaskBridge? bridge;
  final SearchDownloadTaskBridge? searchBridge;
  final Future<List<String>> Function()? targetPicker;
  final Future<void> Function(String directory)? onOpenOutputDirectory;

  @override
  State<UnlockMusicEntryPage> createState() => _UnlockMusicEntryPageState();
}

class _UnlockMusicEntryPageState extends State<UnlockMusicEntryPage>
    with SingleTickerProviderStateMixin {
  static const List<String> _supportedExtensions = <String>[
    'ncm',
    'uc',
    'cache',
    'qmc0',
    'qmc2',
    'qmc3',
    'qmcflac',
    'qmcogg',
    'mgg',
    'mgg0',
    'mgg1',
    'mggl',
    'mflac',
    'mflac0',
    'mmp4',
    'bkcmp3',
    'bkcflac',
    'tkm',
    '666c6163',
    '6d7033',
    '6f6767',
    '6d3461',
    '776176',
    'kgm',
    'kgma',
    'vpr',
    'kwm',
    'xm',
    'tm0',
    'tm2',
    'tm3',
    'tm6',
    'mp3',
    'flac',
    'm4a',
    'ogg',
    'wav',
    'wma',
    'aac',
    'dff',
    'ofl_en',
  ];

  late final Directory _projectRoot;
  late final UnlockMusicTaskBridge _bridge;
  late final SearchDownloadTaskBridge _searchBridge;
  late final TextEditingController _outputDirController;
  late final TextEditingController _searchQueryController;
  late final ScrollController _searchTableScrollController;
  late final ScrollController _searchLogScrollController;
  late final AnimationController _historyPulseController;
  final GlobalKey _searchDropdownButtonKey = GlobalKey();
  OverlayEntry? _searchDropdownEntry;

  TaskRunningNotifier? _taskRunningNotifier;
  bool _lastReportedRunning = false;

  _UnlockMusicPanelView _activeView = _UnlockMusicPanelView.unlock;
  List<UnlockMusicFileItem> _loadedFiles = <UnlockMusicFileItem>[];
  UnlockMusicCompletedTaskRecord? _lastCompletedTask;
  UnlockMusicTaskSnapshot? _snapshot;
  UnlockMusicResult? _result;
  String? _taskId;
  String? _toastMessage;
  final bool _overwrite = false;
  final bool _keepSource = true;
  final Set<String> _skippedTargets = <String>{};
  final PollingHelper _polling = PollingHelper(
    interval: const Duration(milliseconds: 150),
  );
  bool _isDraggingTargets = false;
  bool _showOnlyFailures = false;
  bool _showMorePlatforms = false;
  String? _resultFetchTaskId;

  SearchDownloadTaskSnapshot? _searchSnapshot;
  SearchDownloadResult? _searchResult;
  String? _searchTaskId;
  String? _searchResultFetchTaskId;
  String? _searchCompletionDialogTaskId;
  final PollingHelper _searchPolling = PollingHelper(
    interval: const Duration(milliseconds: 150),
  );
  Timer? _searchElapsedTimer;
  int _searchElapsedSeconds = 0;
  List<SearchDownloadSourceOption> _searchSources =
      const <SearchDownloadSourceOption>[
        SearchDownloadSourceOption(
          label: 'QQ音乐',
          value: 'QQMusicClient',
          selected: true,
        ),
        SearchDownloadSourceOption(
          label: '网易云',
          value: 'NeteaseMusicClient',
          selected: true,
        ),
        SearchDownloadSourceOption(
          label: '酷狗',
          value: 'KugouMusicClient',
          selected: true,
        ),
        SearchDownloadSourceOption(
          label: '酷我音乐',
          value: 'KuwoMusicClient',
          selected: false,
        ),
        SearchDownloadSourceOption(
          label: '咪咕音乐',
          value: 'MiguMusicClient',
          selected: false,
        ),
        SearchDownloadSourceOption(
          label: '千千音乐',
          value: 'QianqianMusicClient',
          selected: false,
        ),
        SearchDownloadSourceOption(
          label: '汽水音乐',
          value: 'SodaMusicClient',
          selected: false,
        ),
        SearchDownloadSourceOption(
          label: 'Bilibili音乐',
          value: 'BilibiliMusicClient',
          selected: false,
        ),
        SearchDownloadSourceOption(
          label: '5SING音乐',
          value: 'FiveSingMusicClient',
          selected: false,
        ),
        SearchDownloadSourceOption(
          label: '街声',
          value: 'StreetVoiceMusicClient',
          selected: false,
        ),
      ];
  final Set<String> _selectedSearchSongKeys = <String>{};
  String? _searchResolvedOutputDirectory;
  final List<String> _searchBootLogLines = const <String>[
    '[System] 全网搜索下载挂载完毕.',
    '[System] 随时可以接受指令...',
  ];

  @override
  void initState() {
    super.initState();
    _projectRoot = _resolveProjectRoot();
    _bridge = widget.bridge ?? _createDefaultBridge(_projectRoot);
    _searchBridge =
        widget.searchBridge ?? _createDefaultSearchBridge(_projectRoot);
    _outputDirController = TextEditingController(
      text: _buildDefaultUnlockOutputDirectory(),
    );
    _searchQueryController = TextEditingController();
    _searchTableScrollController = ScrollController();
    _searchLogScrollController = ScrollController();
    _historyPulseController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1300),
        )..addStatusListener((AnimationStatus status) {
          if (status == AnimationStatus.completed) {
            _historyPulseController.reverse();
          }
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _taskRunningNotifier = DjAppScope.maybeOf(context)?.taskRunningNotifier;
  }

  PythonUnlockMusicTaskBridge _createDefaultBridge(Directory projectRoot) {
    return PythonUnlockMusicTaskBridge(
      pythonExecutable: _resolvePythonExecutable(projectRoot),
      workingDirectory: p.join(projectRoot.path, 'runtime', 'dj_runtime_py'),
      scriptModule: 'dj_runtime_py',
    );
  }

  PythonSearchDownloadTaskBridge _createDefaultSearchBridge(
    Directory projectRoot,
  ) {
    return PythonSearchDownloadTaskBridge(
      pythonExecutable: _resolvePythonExecutable(projectRoot),
      workingDirectory: p.join(projectRoot.path, 'runtime', 'dj_runtime_py'),
      scriptModule: 'dj_runtime_py',
    );
  }

  Directory _resolveProjectRoot() {
    return platform_utils.resolveProjectRoot();
  }

  String _resolvePythonExecutable(Directory projectRoot) {
    return platform_utils.resolvePythonExecutable(projectRoot);
  }

  String _buildDefaultUnlockOutputDirectory() {
    final Directory desktopDirectory = platform_utils.resolveDesktopDirectory();
    return p.join(
      desktopDirectory.path,
      '解锁输出-${_formatUnlockOutputTimestamp(DateTime.now())}',
    );
  }

  bool get _isRunning => _snapshot?.status == UnlockMusicStatus.running;

  bool get _isSearchRunning =>
      _searchSnapshot?.status == SearchDownloadStatus.running;

  bool get _isSearchProcessing =>
      _isSearchRunning && (_searchSnapshot?.taskType != 'download');

  bool get _isSearchDownloading =>
      _isSearchRunning && _searchSnapshot?.taskType == 'download';

  void _reportRunningStateIfNeeded() {
    final bool isRunning = _isRunning || _isSearchRunning;
    if (_taskRunningNotifier == null) {
      return;
    }
    if (isRunning != _lastReportedRunning) {
      _taskRunningNotifier!.setRunning(AppShellSection.unlockTool, isRunning);
      _lastReportedRunning = isRunning;
    }
    if (!isRunning) {
      final UnlockMusicStatus? unlockStatus = _snapshot?.status;
      final SearchDownloadStatus? searchStatus = _searchSnapshot?.status;
      TaskEndState endState = TaskEndState.none;
      if (unlockStatus == UnlockMusicStatus.success ||
          searchStatus == SearchDownloadStatus.success) {
        endState = TaskEndState.success;
      } else if (unlockStatus == UnlockMusicStatus.error ||
          searchStatus == SearchDownloadStatus.error) {
        endState = TaskEndState.error;
      } else if (unlockStatus == UnlockMusicStatus.cancelled ||
          searchStatus == SearchDownloadStatus.cancelled) {
        endState = TaskEndState.aborted;
      }
      _taskRunningNotifier!.setEndState(AppShellSection.unlockTool, endState);
    }
  }

  String get _statusText {
    if (_activeView == _UnlockMusicPanelView.search) {
      final SearchDownloadStatus? status = _searchSnapshot?.status;
      final String? taskType =
          _searchSnapshot?.taskType ?? _searchResult?.taskType;
      if (status == null) {
        return '引掣就绪';
      }
      return switch (status) {
        SearchDownloadStatus.running => taskType == 'download' ? '下载中' : '搜索中',
        SearchDownloadStatus.success =>
          taskType == 'download' ? '下载完成' : '搜索完成',
        SearchDownloadStatus.cancelled => '已停止',
        SearchDownloadStatus.error => '异常',
        SearchDownloadStatus.configLocked => '已锁定',
        SearchDownloadStatus.idle => '引掣就绪',
      };
    }
    final UnlockMusicStatus? status = _snapshot?.status;
    if (status == null) {
      return _loadedFiles.isEmpty ? '待命' : '待处理';
    }
    return switch (status) {
      UnlockMusicStatus.running => '强解中',
      UnlockMusicStatus.success => '完成',
      UnlockMusicStatus.cancelled => '已停止',
      UnlockMusicStatus.error => '异常',
      UnlockMusicStatus.configLocked => '已锁定',
      UnlockMusicStatus.targetReady => '待处理',
      UnlockMusicStatus.idle => '待命',
    };
  }

  Color get _statusColor {
    if (_activeView == _UnlockMusicPanelView.search) {
      return switch (_searchSnapshot?.status) {
        SearchDownloadStatus.running => const Color(0xFFE11D48),
        SearchDownloadStatus.success => const Color(0xFF10B981),
        SearchDownloadStatus.cancelled => const Color(0xFFD97706),
        SearchDownloadStatus.error => const Color(0xFFE11D48),
        _ => const Color(0xFFD1D5DB),
      };
    }
    return switch (_snapshot?.status) {
      UnlockMusicStatus.running => const Color(0xFFE11D48),
      UnlockMusicStatus.success => const Color(0xFF10B981),
      UnlockMusicStatus.cancelled => const Color(0xFFD97706),
      UnlockMusicStatus.error => const Color(0xFFE11D48),
      _ => const Color(0xFFD1D5DB),
    };
  }

  double get _progressValue => _snapshot?.progress ?? 0;

  String get _progressHintText {
    return _snapshot?.progressHintText ??
        (_loadedFiles.isEmpty ? '等待目标文件导入...' : '目标已就绪，请核对后执行解锁。');
  }

  int get _successCount {
    if (_activeView == _UnlockMusicPanelView.search) {
      if (!_isSearchDownloadTask) {
        return 0;
      }
      return _searchResult?.successCount ?? _searchSnapshot?.successCount ?? 0;
    }
    return _result?.successCount ?? _snapshot?.successCount ?? 0;
  }

  int get _failedCount {
    if (_activeView == _UnlockMusicPanelView.search) {
      if (!_isSearchDownloadTask) {
        return 0;
      }
      return _searchResult?.failedCount ?? _searchSnapshot?.failedCount ?? 0;
    }
    return _result?.failedCount ?? _snapshot?.failedCount ?? 0;
  }

  int get _targetCount => _activeView == _UnlockMusicPanelView.search
      ? (_searchSongs.isNotEmpty
            ? _searchSongs.length
            : (_searchResult?.totalCount ?? _searchSnapshot?.totalCount ?? 0))
      : _loadedFiles.length;

  String get _watermarkText =>
      _activeView == _UnlockMusicPanelView.unlock ? '解' : '搜';

  String get _panelTitle =>
      _activeView == _UnlockMusicPanelView.unlock ? '音乐解锁' : '全网搜索下载';

  List<_UnifiedUnlockEntry> get _visibleEntries {
    final Map<String, UnlockMusicResultItem> resultMap =
        <String, UnlockMusicResultItem>{
          for (final UnlockMusicResultItem item
              in _result?.results ?? <UnlockMusicResultItem>[])
            item.inputPath: item,
        };
    final List<_UnifiedUnlockEntry> entries = _loadedFiles
        .map(
          (UnlockMusicFileItem file) =>
              _UnifiedUnlockEntry(file: file, result: resultMap[file.path]),
        )
        .toList(growable: false);
    return filterTaskResults<_UnifiedUnlockEntry>(
      entries,
      filter: _showOnlyFailures
          ? TaskResultFilter.failureOnly
          : TaskResultFilter.all,
      isSuccess: (_UnifiedUnlockEntry entry) => entry.result?.success == true,
      isFailure: (_UnifiedUnlockEntry entry) => entry.result?.success == false,
    );
  }

  @visibleForTesting
  Future<void> debugLoadTargets(
    List<String> filePaths, {
    bool append = false,
  }) => _loadTargets(filePaths, append: append);

  @visibleForTesting
  Set<String> get debugSkippedTargets => Set<String>.from(_skippedTargets);

  @visibleForTesting
  void debugSetLastCompletedTask(UnlockMusicCompletedTaskRecord? record) {
    setState(() {
      _lastCompletedTask = record;
    });
  }

  @visibleForTesting
  Future<void> debugShowCompletionDialog({
    required String title,
    required int successCount,
    required int failedCount,
    required String outputDirectory,
  }) {
    return _showCompletionDialog(
      title: title,
      successCount: successCount,
      failedCount: failedCount,
      outputDirectory: outputDirectory,
    );
  }

  @visibleForTesting
  void debugSetOutputDirectory(String directory) {
    _outputDirController.text = directory;
  }

  Future<void> _pickFiles() async {
    try {
      final List<String> paths = await _pickTargets();
      if (paths.isEmpty) {
        return;
      }
      await _loadTargets(paths, append: _loadedFiles.isNotEmpty);
    } catch (error) {
      _setToast('无法打开文件选择器，请检查系统权限后重试。');
    }
  }

  Future<List<String>> _pickTargets() async {
    if (widget.targetPicker
        case final Future<List<String>> Function() targetPicker) {
      return targetPicker();
    }
    if (Platform.isMacOS) {
      final List<Object?>? result = await _unlockMusicPlatformChannel
          .invokeListMethod<Object?>('pickUnlockTargets');
      return result
              ?.whereType<String>()
              .where((String path) => path.isNotEmpty)
              .toList() ??
          <String>[];
    }

    final List<XFile> files = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[
        const XTypeGroup(label: '待解锁音频', extensions: _supportedExtensions),
      ],
      confirmButtonText: '导入',
    );
    return files
        .map((XFile file) => file.path)
        .where((String path) => path.isNotEmpty)
        .toList();
  }

  Future<void> _pickOutputDirectory() async {
    try {
      final String? directory = await getDirectoryPath(
        confirmButtonText: '选择目录',
      );
      if (directory == null || directory.isEmpty) {
        return;
      }
      setState(() {
        _toastMessage = null;
        _outputDirController.text = directory;
      });
    } catch (error) {
      _setToast('无法打开输出目录选择器，请检查系统权限后重试。');
    }
  }

  Future<void> _loadTargets(
    List<String> filePaths, {
    bool append = false,
  }) async {
    try {
      final UnlockMusicLoadResult loadResult = await _bridge.loadTargets(
        filePaths,
        append: append,
      );
      if (!mounted) {
        return;
      }
      final List<UnlockMusicFileItem> loadedItems = _toUnlockMusicFileItems(
        loadResult.filePaths,
      );
      final String suggestedOutputDirectory = _suggestUnlockOutputDirectory(
        loadedItems,
      );
      setState(() {
        _result = null;
        _taskId = null;
        _snapshot = null;
        _resultFetchTaskId = null;
        _showOnlyFailures = false;
        _loadedFiles = loadedItems;
        _skippedTargets
          ..clear()
          ..addAll(loadResult.skippedPaths);
        _toastMessage = _buildTargetLoadMessage(loadResult, append: append);
        if (suggestedOutputDirectory.isNotEmpty) {
          _outputDirController.text = suggestedOutputDirectory;
        }
      });
    } on UnlockMusicBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  List<UnlockMusicFileItem> _toUnlockMusicFileItems(List<String> filePaths) {
    return filePaths
        .map(
          (String filePath) =>
              UnlockMusicFileItem(path: filePath, name: p.basename(filePath)),
        )
        .toList();
  }

  String? _buildTargetLoadMessage(
    UnlockMusicLoadResult loadResult, {
    required bool append,
  }) {
    final int importedCount = append
        ? loadResult.addedPaths.length
        : loadResult.filePaths.length;
    final int skippedCount = loadResult.skippedPaths.length;
    if (append) {
      if (importedCount > 0 && skippedCount > 0) {
        return '已追加 $importedCount 个目标，忽略 $skippedCount 个不支持项。';
      }
      if (importedCount > 0) {
        return '已追加 $importedCount 个目标。';
      }
      if (skippedCount > 0) {
        return '未追加新目标，忽略 $skippedCount 个不支持项。';
      }
      return '未追加新目标，导入项可能已存在。';
    }
    if (importedCount > 0 && skippedCount > 0) {
      return '已载入 $importedCount 个目标，忽略 $skippedCount 个不支持项。';
    }
    if (importedCount > 0) {
      return '已载入 $importedCount 个目标。';
    }
    if (skippedCount > 0) {
      return '未载入可处理目标，忽略 $skippedCount 个不支持项。';
    }
    return null;
  }

  void _storeCompletedUnlockTask({
    required UnlockMusicStatus status,
    required UnlockMusicResult? result,
    String? message,
  }) {
    final String? taskId = _taskId;
    if (taskId == null) {
      return;
    }
    final UnlockMusicTaskSnapshot? snapshot = _snapshot;
    final String outputDirectory = _outputDirController.text.trim();
    final List<UnlockMusicFileItem> frozenInputs = _loadedFiles
        .map(
          (UnlockMusicFileItem item) =>
              UnlockMusicFileItem(path: item.path, name: item.name),
        )
        .toList(growable: false);
    final List<UnlockMusicResultItem> frozenResults =
        (result?.results ?? const <UnlockMusicResultItem>[])
            .map(
              (UnlockMusicResultItem item) => UnlockMusicResultItem(
                inputPath: item.inputPath,
                outputPath: item.outputPath,
                success: item.success,
                format: item.format,
                error: item.error,
              ),
            )
            .toList(growable: false);
    final int successCount =
        result?.successCount ?? snapshot?.successCount ?? 0;
    final int failedCount = result?.failedCount ?? snapshot?.failedCount ?? 0;
    if (_historyPulseController.status != AnimationStatus.forward) {
      _historyPulseController.forward(from: 0);
    }
    setState(() {
      _lastCompletedTask = UnlockMusicCompletedTaskRecord(
        taskId: taskId,
        status: status,
        finishedAt: DateTime.now(),
        outputDirectory: outputDirectory,
        inputFiles: frozenInputs,
        successCount: successCount,
        failedCount: failedCount,
        results: frozenResults,
        message: message ?? snapshot?.progressHintText,
      );
    });
  }

  Color _historyAccentColor(UnlockMusicCompletedTaskRecord record) {
    if (record.isAllSuccess) {
      return const Color(0xFFD97706);
    }
    if (record.status == UnlockMusicStatus.cancelled) {
      return const Color(0xFFFB7185);
    }
    return const Color(0xFFE11D48);
  }

  String _historyStatusText(UnlockMusicCompletedTaskRecord record) {
    return switch (record.status) {
      UnlockMusicStatus.success => record.failedCount > 0 ? '完成但有失败项' : '全部完成',
      UnlockMusicStatus.cancelled => '已中止',
      UnlockMusicStatus.error => '执行失败',
      _ => '任务结束',
    };
  }

  String _formatHistoryTimestamp(DateTime time) {
    String twoDigit(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${twoDigit(time.month)}-${twoDigit(time.day)} ${twoDigit(time.hour)}:${twoDigit(time.minute)}:${twoDigit(time.second)}';
  }

  void _clearHistoryTask() {
    if (!mounted) {
      return;
    }
    setState(() {
      _lastCompletedTask = null;
      _toastMessage = '已清除最近一次完成任务记录。';
    });
  }

  Future<bool> _canOpenOutputDirectory(String directory) async {
    if (directory.trim().isEmpty) {
      _setToast('该历史任务未记录输出目录。');
      return false;
    }
    final Directory outputDirectory = Directory(directory);
    final bool exists = await outputDirectory.exists();
    if (!exists) {
      _setToast('输出目录不存在，可能已被移动或删除。');
      return false;
    }
    return true;
  }

  List<UnlockMusicResultItem> _historyResultsForFilter(
    UnlockMusicCompletedTaskRecord record,
    TaskResultFilter filter,
  ) {
    return filterTaskResults<UnlockMusicResultItem>(
      record.results,
      filter: filter,
      isSuccess: (UnlockMusicResultItem item) => item.success,
      isFailure: (UnlockMusicResultItem item) => !item.success,
    );
  }

  Future<void> _loadDroppedTargets(List<String> filePaths) async {
    if (_isRunning) {
      return;
    }
    final List<String> normalized = filePaths
        .map((String path) => path.trim())
        .where((String path) => path.isNotEmpty)
        .toSet()
        .toList();
    if (normalized.isEmpty) {
      _setToast('未接收到可导入的路径。');
      return;
    }
    await _loadTargets(normalized, append: _loadedFiles.isNotEmpty);
  }

  String _suggestUnlockOutputDirectory(List<UnlockMusicFileItem> loadedFiles) {
    final Directory baseDirectory =
        _resolveUnlockOutputBaseDirectory(loadedFiles) ??
        platform_utils.resolveDesktopDirectory();
    return p.join(
      baseDirectory.path,
      '解锁输出-${_formatUnlockOutputTimestamp(DateTime.now())}',
    );
  }

  Future<String> _ensureUnlockOutputDirectory(
    String configuredOutputDir,
    List<UnlockMusicFileItem> loadedFiles,
  ) async {
    final Directory configuredDirectory = Directory(configuredOutputDir);
    if (await configuredDirectory.exists()) {
      return configuredDirectory.path;
    }
    final Directory fallbackBaseDirectory =
        _resolveUnlockOutputBaseDirectory(loadedFiles) ??
        platform_utils.resolveDesktopDirectory();
    final Directory fallbackDirectory = Directory(
      p.join(
        fallbackBaseDirectory.path,
        '解锁输出-${_formatUnlockOutputTimestamp(DateTime.now())}',
      ),
    );
    try {
      await fallbackDirectory.create(recursive: true);
      return fallbackDirectory.path;
    } catch (error) {
      _setToast('无法自动创建输出目录，请检查目录权限后重试。');
      return '';
    }
  }

  Directory? _resolveUnlockOutputBaseDirectory(
    List<UnlockMusicFileItem> loadedFiles,
  ) {
    if (loadedFiles.isEmpty) {
      return null;
    }
    final List<String> parentPaths = loadedFiles
        .map((UnlockMusicFileItem item) => p.normalize(p.dirname(item.path)))
        .where((String path) => path.isNotEmpty)
        .toList(growable: false);
    if (parentPaths.isEmpty) {
      return null;
    }
    String candidate = parentPaths.first;
    while (true) {
      final bool isCommonDirectory = parentPaths.every(
        (String path) =>
            p.equals(path, candidate) || p.isWithin(candidate, path),
      );
      if (isCommonDirectory && Directory(candidate).existsSync()) {
        return Directory(candidate);
      }
      final String parent = p.dirname(candidate);
      if (parent == candidate) {
        break;
      }
      candidate = parent;
    }
    final Directory firstParent = Directory(parentPaths.first);
    if (firstParent.existsSync()) {
      return firstParent;
    }
    return null;
  }

  String _formatUnlockOutputTimestamp(DateTime time) {
    String twoDigit(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${twoDigit(time.month)}${twoDigit(time.day)}-${twoDigit(time.hour)}${twoDigit(time.minute)}${twoDigit(time.second)}';
  }

  Future<String> _prepareSearchOutputDirectory({
    required bool isPlaylist,
    required String query,
    required List<SearchDownloadSongItem> selectedSongs,
    required SearchDownloadResult? result,
  }) async {
    final Directory desktopDirectory = platform_utils.resolveDesktopDirectory();
    final Directory baseDirectory = await desktopDirectory.create(
      recursive: true,
    );
    final String folderSeed = _resolveSearchOutputFolderSeed(
      isPlaylist: isPlaylist,
      query: query,
      selectedSongs: selectedSongs,
      result: result,
    );
    final String directoryName = platform_utils.sanitizeWindowsFileName(
      '$folderSeed-${_formatUnlockOutputTimestamp(DateTime.now())}',
      fallback: '下载结果-${_formatUnlockOutputTimestamp(DateTime.now())}',
    );
    final Directory outputDirectory = Directory(
      p.join(baseDirectory.path, directoryName),
    );
    try {
      await outputDirectory.create(recursive: true);
      return outputDirectory.path;
    } catch (error) {
      _setToast('无法创建下载目录，请检查桌面目录权限后重试。');
      return '';
    }
  }

  String _resolveSearchOutputFolderSeed({
    required bool isPlaylist,
    required String query,
    required List<SearchDownloadSongItem> selectedSongs,
    required SearchDownloadResult? result,
  }) {
    if (isPlaylist) {
      final String playlistName =
          result?.playlistName?.trim().isNotEmpty == true
          ? result!.playlistName!.trim()
          : _extractPlaylistNameFromQuery(query);
      if (playlistName.isNotEmpty) {
        return playlistName;
      }
      return '歌单';
    }
    final SearchDownloadSongItem? firstSong = selectedSongs.isNotEmpty
        ? selectedSongs.first
        : (_searchSongs.isNotEmpty ? _searchSongs.first : null);
    final String firstSongName = firstSong?.songName.trim() ?? '';
    if (firstSongName.isNotEmpty) {
      return firstSongName;
    }
    final String normalizedQuery = query.trim();
    if (normalizedQuery.isNotEmpty && !_isPlaylistUrl(normalizedQuery)) {
      return normalizedQuery;
    }
    return '下载结果';
  }

  String _extractPlaylistNameFromQuery(String query) {
    final Uri? uri = Uri.tryParse(query.trim());
    if (uri == null) {
      return '';
    }
    for (final String key in <String>[
      'name',
      'title',
      'playlistName',
      'listname',
    ]) {
      final String? value = uri.queryParameters[key];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    final List<String> segments = uri.pathSegments
        .where((String segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return '';
    }
    final String lastSegment = Uri.decodeComponent(segments.last).trim();
    if (lastSegment.isEmpty || RegExp(r'^\d+$').hasMatch(lastSegment)) {
      return '';
    }
    return lastSegment;
  }

  Future<void> _startTask() async {
    if (_loadedFiles.isEmpty) {
      _setToast('请先导入待解锁文件。');
      return;
    }
    final String outputDir = _outputDirController.text.trim();
    if (outputDir.isEmpty) {
      _setToast('请先设置输出目录。');
      return;
    }
    final String resolvedOutputDir = await _ensureUnlockOutputDirectory(
      outputDir,
      _loadedFiles,
    );
    if (resolvedOutputDir.isEmpty) {
      return;
    }
    _stopPolling();
    setState(() {
      _toastMessage = null;
      _result = null;
      _resultFetchTaskId = null;
      _outputDirController.text = resolvedOutputDir;
    });
    try {
      await _bridge.lockConfig(<String, Object?>{
        'output_dir': resolvedOutputDir,
        'overwrite': _overwrite,
        'keep_source': _keepSource,
      });
      final UnlockMusicTaskSnapshot snapshot = await _bridge.startUnlockTask();
      _applySnapshot(snapshot);
      _startPolling(snapshot.taskId);
    } on UnlockMusicBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> _stopTask() async {
    final String? taskId = _taskId;
    if (taskId == null) {
      _setToast('当前没有可停止的任务。');
      return;
    }
    try {
      final UnlockMusicTaskSnapshot snapshot = await _bridge.stopTask(taskId);
      _applySnapshot(snapshot);
      if (snapshot.status == UnlockMusicStatus.cancelled) {
        _storeCompletedUnlockTask(
          status: snapshot.status,
          result: _result,
          message: snapshot.progressHintText,
        );
      }
    } on UnlockMusicBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  void _startPolling(String taskId) {
    _polling.start(() => _pollTask(taskId));
  }

  void _stopPolling() {
    _polling.stop();
  }

  Future<void> _pollTask(String taskId) async {
    try {
      final List<UnlockMusicTaskEvent> events = await _bridge
          .subscribeTaskEvents(taskId: taskId);
      for (final UnlockMusicTaskEvent event in events) {
        _applySnapshot(event.snapshot);
      }
      final UnlockMusicTaskSnapshot? snapshot = _snapshot;
      if (snapshot != null &&
          snapshot.taskId == taskId &&
          _isStableStatus(snapshot.status)) {
        _stopPolling();
        await _fetchResultIfNeeded(snapshot.taskId, snapshot.status);
      }
    } on UnlockMusicBridgeException catch (error) {
      _stopPolling();
      if (_taskId == taskId) {
        _storeCompletedUnlockTask(
          status: UnlockMusicStatus.error,
          result: _result,
          message: error.message,
        );
      }
      _setToast(error.message);
    }
  }

  void _applySnapshot(UnlockMusicTaskSnapshot snapshot) {
    if (!mounted) {
      return;
    }
    setState(() {
      _taskId = snapshot.taskId;
      _snapshot = snapshot;
      _toastMessage = null;
    });
    _reportRunningStateIfNeeded();
  }

  bool _isStableStatus(UnlockMusicStatus status) {
    return status == UnlockMusicStatus.success ||
        status == UnlockMusicStatus.cancelled ||
        status == UnlockMusicStatus.error;
  }

  Future<void> _fetchResultIfNeeded(
    String taskId,
    UnlockMusicStatus status,
  ) async {
    if (status == UnlockMusicStatus.error || _resultFetchTaskId == taskId) {
      return;
    }
    _resultFetchTaskId = taskId;
    try {
      final UnlockMusicResult result = await _bridge.fetchUnlockResult(taskId);
      if (!mounted || _taskId != taskId) {
        return;
      }
      setState(() {
        _result = result;
      });
      _storeCompletedUnlockTask(status: status, result: result);
      if (status == UnlockMusicStatus.success) {
        await _showCompletionDialog(
          title: '解锁完成',
          successCount: result.successCount,
          failedCount: result.failedCount,
          outputDirectory: _outputDirController.text.trim(),
        );
      }
    } on UnlockMusicBridgeException catch (error) {
      if (error.code == 'TASK_NOT_COMPLETED') {
        _resultFetchTaskId = null;
        return;
      }
      _setToast(error.message);
    }
  }

  Future<void> _clearAll() async {
    _stopPolling();
    try {
      await _bridge.clearTargets();
      if (!mounted) {
        return;
      }
      setState(() {
        _loadedFiles = <UnlockMusicFileItem>[];
        _snapshot = null;
        _result = null;
        _taskId = null;
        _toastMessage = '已清空导入列表。';
        _resultFetchTaskId = null;
        _showOnlyFailures = false;
        _skippedTargets.clear();
      });
    } on UnlockMusicBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> _handleDropDone(List<XFile> files) async {
    final List<String> paths = <String>[];
    for (final XFile file in files) {
      if (file.path.isNotEmpty) {
        paths.add(file.path);
        continue;
      }
      final dynamic dropItem = file;
      final Object? bookmark = dropItem.extraAppleBookmark;
      if (bookmark is! Uint8List) {
        continue;
      }
      bool accessStarted = false;
      try {
        accessStarted = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
        if (accessStarted && file.path.isNotEmpty) {
          paths.add(file.path);
        }
      } finally {
        if (accessStarted) {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
        }
      }
    }
    await _loadDroppedTargets(paths);
  }

  void _setDragging(bool value) {
    if (!mounted || _isRunning) {
      return;
    }
    setState(() {
      _isDraggingTargets = value;
    });
  }

  Future<void> _removeLoadedFile(String path) async {
    try {
      final UnlockMusicLoadResult loadResult = await _bridge.removeTarget(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _loadedFiles = _toUnlockMusicFileItems(loadResult.filePaths);
        _skippedTargets.clear();
        _snapshot = null;
        _result = null;
        _taskId = null;
        _resultFetchTaskId = null;
        _showOnlyFailures = false;
        _toastMessage = _loadedFiles.isEmpty ? '已移除目标，列表已清空。' : '已移除目标。';
      });
    } on UnlockMusicBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  void _removeSearchDropdown() {
    _searchDropdownEntry?.remove();
    _searchDropdownEntry = null;
  }

  void _toggleMorePlatforms() {
    if (_showMorePlatforms) {
      _removeSearchDropdown();
      if (mounted) {
        setState(() {
          _showMorePlatforms = false;
        });
      }
      return;
    }
    final BuildContext? buttonContext = _searchDropdownButtonKey.currentContext;
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (buttonContext == null || overlay == null) {
      return;
    }
    final RenderBox buttonBox = buttonContext.findRenderObject()! as RenderBox;
    final RenderBox overlayBox =
        overlay.context.findRenderObject()! as RenderBox;
    final Offset buttonTopLeft = buttonBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final Size buttonSize = buttonBox.size;
    _searchDropdownEntry = OverlayEntry(
      builder: (BuildContext context) {
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleMorePlatforms,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: buttonTopLeft.dx + buttonSize.width - 150,
              top: buttonTopLeft.dy + buttonSize.height + 6,
              child: Material(
                color: Colors.transparent,
                child: _SearchDropdownPanel(
                  options: _secondarySearchSources,
                  onToggle: _isSearchProcessing
                      ? null
                      : _handleDropdownSourceToggle,
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_searchDropdownEntry!);
    setState(() {
      _showMorePlatforms = true;
    });
  }

  void _setToast(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _toastMessage = message;
    });
  }

  List<String> get _selectedSearchSources {
    return _searchSources
        .where((SearchDownloadSourceOption option) => option.selected)
        .map((SearchDownloadSourceOption option) => option.label)
        .toList();
  }

  List<SearchDownloadSourceOption> get _primarySearchSources =>
      _searchSources.take(3).toList();

  List<SearchDownloadSourceOption> get _secondarySearchSources =>
      _searchSources.skip(3).toList();

  List<SearchDownloadSongItem> get _searchSongs =>
      _searchResult?.results ?? const <SearchDownloadSongItem>[];

  bool get _isSearchDownloadTask {
    final String? taskType =
        _searchSnapshot?.taskType ?? _searchResult?.taskType;
    return taskType == 'download';
  }

  double get _searchTotalProgress {
    if (!_isSearchDownloadTask) {
      return 0;
    }
    return _searchSnapshot?.progress ?? 0;
  }

  double get _searchCurrentProgress {
    if (!_isSearchDownloadTask) {
      return 0;
    }
    final SearchDownloadTaskSnapshot? snapshot = _searchSnapshot;
    if (snapshot == null) {
      return 0;
    }
    final int total = snapshot.totalCount;
    if (total <= 0) {
      return snapshot.progress;
    }
    final int completed = snapshot.successCount + snapshot.failedCount;
    return (completed / total).clamp(0, 1).toDouble();
  }

  String get _searchStageText {
    final SearchDownloadTaskSnapshot? snapshot = _searchSnapshot;
    if (snapshot == null) {
      return '等待任务开始';
    }
    return snapshot.progressHintText;
  }

  String get _searchStatsText {
    final SearchDownloadTaskSnapshot? snapshot = _searchSnapshot;
    if (snapshot == null) {
      return '未开始';
    }
    if (_isSearchDownloadTask) {
      final int total = snapshot.totalCount;
      final int processed = snapshot.successCount + snapshot.failedCount;
      if (total > 0) {
        return '已补全 $processed / $total';
      }
      return snapshot.status == SearchDownloadStatus.running ? '处理中' : '待命';
    }
    final int resultCount =
        _searchResult?.results.length ?? snapshot.successCount;
    if (snapshot.status == SearchDownloadStatus.running) {
      return '已找到 $resultCount 条';
    }
    if (resultCount > 0) {
      return '共 $resultCount 条';
    }
    return '待命';
  }

  List<String> get _searchLogLines {
    final List<String> logs = <String>[
      ..._searchBootLogLines,
      ...?_searchSnapshot?.logLines,
      ...?_searchResult?.logLines,
    ];
    final List<String> deduped = <String>[];
    for (final String line in logs) {
      if (line.trim().isEmpty) {
        continue;
      }
      if (deduped.isEmpty || deduped.last != line) {
        deduped.add(line);
      }
    }
    return deduped;
  }

  bool _isPlaylistUrl(String value) {
    final String input = value.trim().toLowerCase();
    return input.startsWith('http://') || input.startsWith('https://');
  }

  String _songSelectionKey(SearchDownloadSongItem item) {
    return '${item.source}|${item.identifier ?? item.songName}|${item.songName}';
  }

  String _getSourceLabel(String source) {
    const Map<String, String> labels = <String, String>{
      'QQMusicClient': 'QQ音乐',
      'NeteaseMusicClient': '网易云',
      'KugouMusicClient': '酷狗',
      'KuwoMusicClient': '酷我音乐',
      'MiguMusicClient': '咪咕音乐',
      'QianqianMusicClient': '千千音乐',
      'SodaMusicClient': '汽水音乐',
      'BilibiliMusicClient': 'Bilibili音乐',
      'FiveSingMusicClient': '5SING音乐',
      'StreetVoiceMusicClient': '街声',
    };
    return labels[source] ?? source.replaceAll('MusicClient', '');
  }

  Color _getSourceColor(String source) {
    if (source == 'QQMusicClient') {
      return const Color(0xFF10B981);
    }
    if (source == 'NeteaseMusicClient') {
      return const Color(0xFFE11D48);
    }
    if (source == 'KugouMusicClient') {
      return const Color(0xFF3B82F6);
    }
    return const Color(0xFFE11D48);
  }

  bool _isSearchSongSelected(SearchDownloadSongItem item) {
    return _selectedSearchSongKeys.contains(_songSelectionKey(item));
  }

  void _toggleSearchSongSelection(SearchDownloadSongItem item, bool value) {
    final String key = _songSelectionKey(item);
    setState(() {
      if (value) {
        _selectedSearchSongKeys.add(key);
      } else {
        _selectedSearchSongKeys.remove(key);
      }
    });
  }

  void _toggleSearchSourceByValue(String value) {
    setState(() {
      _searchSources = _searchSources
          .map(
            (SearchDownloadSourceOption option) => option.value == value
                ? option.copyWith(selected: !option.selected)
                : option,
          )
          .toList();
    });
  }

  void _handleDropdownSourceToggle(String value) {
    _toggleSearchSourceByValue(value);
    _removeSearchDropdown();
    if (mounted) {
      setState(() {
        _showMorePlatforms = false;
      });
    }
  }

  void _startSearchElapsedTimer() {
    if (_searchElapsedTimer != null) {
      return;
    }
    _searchElapsedSeconds = 0;
    _searchElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _searchElapsedSeconds += 1);
    });
  }

  void _stopSearchElapsedTimer() {
    _searchElapsedTimer?.cancel();
    _searchElapsedTimer = null;
  }

  void _applySearchSnapshot(SearchDownloadTaskSnapshot snapshot) {
    if (!mounted) {
      return;
    }
    if (snapshot.status == SearchDownloadStatus.running) {
      _startSearchElapsedTimer();
    } else {
      _stopSearchElapsedTimer();
    }
    setState(() {
      _searchTaskId = snapshot.taskId;
      _searchSnapshot = snapshot;
      _toastMessage = null;
    });
    if (snapshot.taskType == 'download' &&
        snapshot.totalCount > 0 &&
        (snapshot.successCount + snapshot.failedCount) >= snapshot.totalCount) {
      unawaited(_fetchSearchResultIfNeeded(snapshot.taskId, snapshot.status));
    }
    _reportRunningStateIfNeeded();
  }

  bool _isStableSearchStatus(SearchDownloadStatus status) {
    return status == SearchDownloadStatus.success ||
        status == SearchDownloadStatus.cancelled ||
        status == SearchDownloadStatus.error;
  }

  void _startSearchPolling(String taskId) {
    _searchPolling.start(() => _pollSearchTask(taskId));
  }

  void _stopSearchPolling() {
    _searchPolling.stop();
  }

  Future<void> _pollSearchTask(String taskId) async {
    try {
      final List<SearchDownloadTaskEvent> events = await _searchBridge
          .subscribeTaskEvents(taskId: taskId);
      for (final SearchDownloadTaskEvent event in events) {
        _applySearchSnapshot(event.snapshot);
      }
      final SearchDownloadTaskSnapshot? snapshot = _searchSnapshot;
      if (snapshot != null &&
          snapshot.taskId == taskId &&
          _isStableSearchStatus(snapshot.status)) {
        await _fetchSearchResultIfNeeded(snapshot.taskId, snapshot.status);
        if (_searchResult?.taskId == taskId && _searchTaskId == taskId) {
          _stopSearchPolling();
        }
      }
    } on SearchDownloadBridgeException catch (error) {
      if (error.code == 'TIMEOUT') {
        return;
      }
      _stopSearchPolling();
      _setToast(error.message);
    }
  }

  Future<void> _fetchSearchResultIfNeeded(
    String taskId,
    SearchDownloadStatus status,
  ) async {
    if (status == SearchDownloadStatus.error ||
        _searchResultFetchTaskId == taskId) {
      return;
    }
    _searchResultFetchTaskId = taskId;
    try {
      final SearchDownloadResult result =
          _searchSnapshot?.taskType == 'download'
          ? await _searchBridge.fetchDownloadResult(taskId)
          : await _searchBridge.fetchSearchResult(taskId);
      if (!mounted || _searchTaskId != taskId) {
        return;
      }
      setState(() {
        _searchResult = result;
        if ((result.outputDirectory ?? '').trim().isNotEmpty) {
          _searchResolvedOutputDirectory = result.outputDirectory!.trim();
        }
        if (result.taskType != 'download') {
          _selectedSearchSongKeys.clear();
        }
      });
      if (result.taskType == 'download' &&
          result.status == SearchDownloadStatus.success &&
          _searchCompletionDialogTaskId != taskId) {
        _searchCompletionDialogTaskId = taskId;
        await _showCompletionDialog(
          title: '下载完成',
          successCount: result.successCount,
          failedCount: result.failedCount,
          outputDirectory: _resolveResultOutputDirectory(result),
          openLabel: '打开文件所在文件夹',
        );
      }
    } on SearchDownloadBridgeException catch (error) {
      if (error.code == 'TASK_NOT_COMPLETED' || error.code == 'TIMEOUT') {
        _searchResultFetchTaskId = null;
        return;
      }
      _setToast(error.message);
    }
  }

  Future<void> _showHistoryTaskDialog(
    UnlockMusicCompletedTaskRecord record,
  ) async {
    if (!mounted) {
      return;
    }
    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final Color accentColor = _historyAccentColor(record);
        TaskResultFilter filter = TaskResultFilter.all;

        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setState) {
            final List<UnlockMusicResultItem> visibleItems =
                _historyResultsForFilter(record, filter);

            return HardwareDialog(
              width: 760,
              title: '最近一次完成任务',
              titleIcon: Icon(Icons.history_rounded, color: accentColor),
              onClose: () => Navigator.of(dialogContext).pop(),
              hudTitle: 'Task History / 任务记录',
              hudText: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${_historyStatusText(record)} · ${_formatHistoryTimestamp(record.finishedAt)}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '共 ${record.inputFiles.length} 首，成功 ${record.successCount}，失败 ${record.failedCount}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '输出目录：${record.outputDirectory.isEmpty ? '未设置' : record.outputDirectory}',
                  ),
                  if ((record.message ?? '').isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      '状态说明：${record.message}',
                      style: TextStyle(
                        color: record.hasFailures
                            ? const Color(0xFFFB7185)
                            : const Color(0xFFD1D5DB),
                      ),
                    ),
                  ],
                ],
              ),
              scrollable: true,
              maxHeight: 720,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _SmallHardwareButton(
                        label: '全部结果',
                        onTap: () {
                          setState(() {
                            filter = TaskResultFilter.all;
                          });
                        },
                      ),
                      _SmallHardwareButton(
                        label: '仅成功项',
                        onTap: () {
                          setState(() {
                            filter = TaskResultFilter.successOnly;
                          });
                        },
                      ),
                      _SmallHardwareButton(
                        label: '仅失败项',
                        accent: true,
                        onTap: () {
                          setState(() {
                            filter = TaskResultFilter.failureOnly;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (visibleItems.isEmpty)
                    const Text(
                      '当前筛选条件下没有结果。',
                      style: TextStyle(
                        color: Color(0xFFD1D5DB),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    ...visibleItems.map((UnlockMusicResultItem item) {
                      final bool success = item.success;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: HardwareDialogSectionCard(
                          child: Text(
                            success
                                ? '${p.basename(item.inputPath)} -> ${item.outputPath ?? '未生成输出文件'}'
                                : '${p.basename(item.inputPath)} -> ${item.error ?? '未知错误'}',
                            style: TextStyle(
                              color: success
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFFB7185),
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
              footer: HardwareDialogFooter(
                actions: <Widget>[
                  HardwareDialogAction(
                    label: '打开输出文件夹',
                    variant: HardwareDialogActionVariant.confirm,
                    onPressed: record.outputDirectory.isEmpty
                        ? null
                        : () async {
                            final bool canOpen = await _canOpenOutputDirectory(
                              record.outputDirectory,
                            );
                            if (!canOpen) {
                              return;
                            }
                            await _openOutputDirectory(record.outputDirectory);
                          },
                  ),
                  HardwareDialogAction(
                    label: '关闭',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCompletionDialog({
    required String title,
    required int successCount,
    required int failedCount,
    required String outputDirectory,
    String openLabel = '打开输出目录',
  }) async {
    if (!mounted) {
      return;
    }
    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return HardwareDialog(
          width: 560,
          title: title,
          titleIcon: const Icon(Icons.library_music_rounded),
          onClose: () => Navigator.of(dialogContext).pop(),
          hudTitle: 'Task Summary / 任务摘要',
          hudText: Text(
            '成功数量：$successCount\n失败数量：$failedCount\n输出目录：$outputDirectory',
            style: const TextStyle(height: 1.7),
          ),
          body: const SizedBox.shrink(),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          footer: HardwareDialogFooter(
            actions: <Widget>[
              HardwareDialogAction(
                label: openLabel,
                variant: HardwareDialogActionVariant.confirm,
                onPressed: outputDirectory.isEmpty
                    ? null
                    : () async {
                        final bool canOpen = await _canOpenOutputDirectory(
                          outputDirectory,
                        );
                        if (!canOpen) {
                          return;
                        }
                        await _openOutputDirectory(outputDirectory);
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
              ),
              HardwareDialogAction(
                label: '知道了',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  String _resolveResultOutputDirectory(SearchDownloadResult result) {
    final String resolved = result.outputDirectory?.trim() ?? '';
    if (resolved.isNotEmpty) {
      return resolved;
    }
    final String configured = _searchResolvedOutputDirectory?.trim() ?? '';
    if (configured.isNotEmpty) {
      return configured;
    }
    for (final SearchDownloadSongItem item in result.results) {
      final String? savePath = item.savePath;
      if (savePath == null || savePath.isEmpty) {
        continue;
      }
      return p.dirname(savePath);
    }
    return '';
  }

  Future<void> _openOutputDirectory(String directory) async {
    if (widget.onOpenOutputDirectory
        case final Future<void> Function(String directory)
            openOutputDirectory) {
      try {
        await openOutputDirectory(directory);
      } catch (error) {
        _setToast('无法打开输出文件夹，请检查目录是否存在后重试。');
      }
      return;
    }
    try {
      await platform_utils.openDirectory(directory);
    } catch (error) {
      _setToast('无法打开输出文件夹，请检查目录是否存在后重试。');
    }
  }

  Future<void> _submitSearchOrPlaylist() async {
    if (_showMorePlatforms) {
      _toggleMorePlatforms();
    }
    final String query = _searchQueryController.text.trim();
    if (query.isEmpty) {
      _setToast('请输入关键词或歌单地址。');
      return;
    }
    if (_selectedSearchSources.isEmpty) {
      _setToast('请至少选择一个平台。');
      return;
    }
    final bool isPlaylist = _isPlaylistUrl(query);
    final String resolvedOutputDir = await _prepareSearchOutputDirectory(
      isPlaylist: isPlaylist,
      query: query,
      selectedSongs: const <SearchDownloadSongItem>[],
      result: null,
    );
    if (resolvedOutputDir.isEmpty) {
      return;
    }
    _stopSearchPolling();
    setState(() {
      _toastMessage = null;
      _searchResult = null;
      _searchSnapshot = null;
      _searchTaskId = null;
      _searchResultFetchTaskId = null;
      _searchCompletionDialogTaskId = null;
      _selectedSearchSongKeys.clear();
      _searchResolvedOutputDirectory = resolvedOutputDir;
    });
    try {
      _searchSources = await _searchBridge.lockConfig(<String, Object?>{
        'output_dir': resolvedOutputDir,
        'sources': _selectedSearchSources,
        if (isPlaylist) 'playlist_url': query else 'keyword': query,
      });
      final SearchDownloadTaskSnapshot snapshot = isPlaylist
          ? await _searchBridge.startPlaylistParseTask()
          : await _searchBridge.startSearchTask();
      _applySearchSnapshot(snapshot);
      _startSearchPolling(snapshot.taskId);
    } on SearchDownloadBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> _startSearchDownloadTask() async {
    if (_showMorePlatforms) {
      _toggleMorePlatforms();
    }
    final List<SearchDownloadSongItem> selectedSongs = _searchSongs
        .where(_isSearchSongSelected)
        .toList(growable: false);
    final List<Map<String, Object?>> selected = selectedSongs
        .map((SearchDownloadSongItem item) => item.raw)
        .toList(growable: false);
    if (selected.isEmpty) {
      _setToast('请先勾选待下载曲目。');
      return;
    }
    final String query = _searchQueryController.text.trim();
    final String resolvedOutputDir = await _prepareSearchOutputDirectory(
      isPlaylist: _isPlaylistUrl(query),
      query: query,
      selectedSongs: selectedSongs,
      result: _searchResult,
    );
    if (resolvedOutputDir.isEmpty) {
      return;
    }
    _stopSearchPolling();
    setState(() {
      _toastMessage = null;
      _searchResultFetchTaskId = null;
      _searchCompletionDialogTaskId = null;
      _searchResolvedOutputDirectory = resolvedOutputDir;
    });
    try {
      _searchSources = await _searchBridge.lockConfig(<String, Object?>{
        'output_dir': resolvedOutputDir,
        'sources': _selectedSearchSources,
      });
      final SearchDownloadTaskSnapshot snapshot = await _searchBridge
          .startDownloadTask(selected);
      _applySearchSnapshot(snapshot);
      _startSearchPolling(snapshot.taskId);
    } on SearchDownloadBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> _stopSearchTask() async {
    final String? taskId = _searchTaskId;
    if (taskId == null) {
      _setToast('当前没有可终止的检索任务。');
      return;
    }
    try {
      final SearchDownloadTaskSnapshot snapshot = await _searchBridge.stopTask(
        taskId,
      );
      _applySearchSnapshot(snapshot);
    } on SearchDownloadBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  @override
  void dispose() {
    _polling.dispose();
    _searchPolling.dispose();
    _stopSearchElapsedTimer();
    _historyPulseController.dispose();
    _outputDirController.dispose();
    _searchQueryController.dispose();
    _searchTableScrollController.dispose();
    _searchLogScrollController.dispose();
    _removeSearchDropdown();
    if (_taskRunningNotifier != null && _lastReportedRunning) {
      _taskRunningNotifier!.setRunning(AppShellSection.unlockTool, false);
    }
    unawaited(_bridge.close());
    unawaited(_searchBridge.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 920;
        final bool dense = constraints.maxWidth < 760;
        return DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xFF030303)),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(painter: _GridBackgroundPainter()),
              ),
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(dense ? 12 : 20),
                  child: _buildShellPanel(
                    context,
                    compact: compact,
                    dense: dense,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShellPanel(
    BuildContext context, {
    required bool compact,
    required bool dense,
  }) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF08080A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0xCC000000),
            blurRadius: 40,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Text(
                  _watermarkText,
                  style: TextStyle(
                    fontSize: compact ? 180 : 260,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withValues(alpha: 0.015),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              dense ? 16 : 28,
              dense ? 16 : 20,
              dense ? 16 : 28,
              dense ? 16 : 20,
            ),
            child: Column(
              children: <Widget>[
                _buildHeader(theme, compact: compact),
                const SizedBox(height: 14),
                _buildTabs(theme),
                const SizedBox(height: 14),
                if (_toastMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _MessageBanner(
                    message: _toastMessage!,
                    background: const Color(0xFF3A0E17),
                    foreground: const Color(0xFFF3D3DB),
                  ),
                  const SizedBox(height: 14),
                ] else
                  const SizedBox(height: 14),
                Expanded(
                  child: _activeView == _UnlockMusicPanelView.unlock
                      ? _buildUnlockView(theme, compact: compact, dense: dense)
                      : _buildSearchView(theme, compact: compact, dense: dense),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, {required bool compact}) {
    final double titleSize = compact ? 16 : 18;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          _panelTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: titleSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: const Color(0xFFE11D48),
          ),
        ),
        const Spacer(),
        Flexible(
          child: _StatusStrip(
            statusText: _statusText,
            targetCount: _targetCount,
            successCount: _successCount,
            failedCount: _failedCount,
            active: _activeView == _UnlockMusicPanelView.search
                ? _isSearchRunning
                : _isRunning,
            statusColor: _statusColor,
            hideSuccessFail:
                _activeView == _UnlockMusicPanelView.search &&
                !_isSearchDownloadTask,
          ),
        ),
      ],
    );
  }

  Widget _buildTabs(ThemeData theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF020202),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0xE6000000),
              blurRadius: 14,
              offset: Offset(0, 2),
            ),
            BoxShadow(
              color: Color(0x1AFFFFFF),
              blurRadius: 1,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _EngineTabButton(
              label: '🔓 音乐解锁引擎',
              active: _activeView == _UnlockMusicPanelView.unlock,
              onTap: () {
                setState(() {
                  _activeView = _UnlockMusicPanelView.unlock;
                });
              },
            ),
            const SizedBox(width: 8),
            _EngineTabButton(
              label: '🌐 全网搜索下载',
              active: _activeView == _UnlockMusicPanelView.search,
              onTap: () {
                if (_isRunning) {
                  _setToast('当前有引擎正在执行任务，为保证数据安全，请先停止！');
                  return;
                }
                setState(() {
                  _activeView = _UnlockMusicPanelView.search;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnlockView(
    ThemeData theme, {
    required bool compact,
    required bool dense,
  }) {
    return Column(
      children: <Widget>[
        _buildOutputRow(theme, compact: compact),
        const SizedBox(height: 14),
        Expanded(child: _buildDropzone(theme)),
        const SizedBox(height: 14),
        _buildProgress(theme),
        const SizedBox(height: 14),
        _buildActionRow(compact: compact),
      ],
    );
  }

  Widget _buildOutputRow(ThemeData theme, {required bool compact}) {
    if (_activeView == _UnlockMusicPanelView.search) {
      return _buildSearchOutputHint(theme, compact: compact);
    }
    final Widget label = SizedBox(
      width: compact ? double.infinity : 72,
      child: Text(
        '输出目录',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF8B8F98),
        ),
      ),
    );
    final Widget input = Expanded(
      child: TextField(
        controller: _outputDirController,
        readOnly: true,
        spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
        enableSuggestions: false,
        autocorrect: false,
        style: const TextStyle(
          color: Color(0xFFE5E7EB),
          fontFamily: 'monospace',
        ),
        decoration: _hardwareInputDecoration(),
      ),
    );
    final Widget button = _SmallHardwareButton(
      label: '选择目录',
      onTap: _pickOutputDirectory,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          label,
          const SizedBox(height: 10),
          Row(children: <Widget>[input, const SizedBox(width: 12), button]),
        ],
      );
    }
    return Row(
      children: <Widget>[label, input, const SizedBox(width: 12), button],
    );
  }

  Widget _buildSearchOutputHint(ThemeData theme, {required bool compact}) {
    final String hintText =
        _searchResolvedOutputDirectory?.trim().isNotEmpty == true
        ? _searchResolvedOutputDirectory!.trim()
        : '下载时自动在桌面创建“第一首歌曲名-时间”或“歌单名-时间”文件夹';
    final Widget label = SizedBox(
      width: compact ? double.infinity : 72,
      child: Text(
        '输出目录',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF8B8F98),
        ),
      ),
    );
    final Widget hint = Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF020202),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Text(
          hintText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFE5E7EB),
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      ),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[label, const SizedBox(height: 10), hint],
      );
    }
    return Row(children: <Widget>[label, hint]);
  }

  Widget _buildDropzone(ThemeData theme) {
    final List<_UnifiedUnlockEntry> entries = _visibleEntries;
    final bool hasFiles = _loadedFiles.isNotEmpty;
    return TaskImportListShell(
      hasItems: hasFiles,
      isDragging: _isDraggingTargets,
      onDragStateChanged: _setDragging,
      onDropDone: _handleDropDone,
      onEmptyTap: _pickFiles,
      header: _buildDropzoneHeader(theme),
      emptyBuilder: (BuildContext context, bool isDragging) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '🗂️',
              style: TextStyle(
                fontSize: 28,
                color: isDragging
                    ? const Color(0xFFE11D48)
                    : const Color(0xFF4B5563),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isDragging ? '松开导入文件或文件夹' : '点击选择或拖入文件文件夹',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isDragging
                    ? const Color(0xFFE11D48)
                    : const Color(0xFF4B5563),
                letterSpacing: 1,
              ),
            ),
          ],
        );
      },
      contentBuilder: (BuildContext context) {
        if (entries.isEmpty && _lastCompletedTask == null) {
          return Center(
            child: Text(
              '当前过滤条件下没有结果。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF4B5563),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: entries.length + (_lastCompletedTask == null ? 0 : 1),
          itemBuilder: (BuildContext context, int index) {
            final UnlockMusicCompletedTaskRecord? lastCompletedTask =
                _lastCompletedTask;
            if (lastCompletedTask != null && index == 0) {
              return _buildHistoryTaskEntry(theme, lastCompletedTask);
            }
            final int entryIndex = index - (lastCompletedTask == null ? 0 : 1);
            final _UnifiedUnlockEntry entry = entries[entryIndex];
            return _buildUnifiedListItem(theme, entry, entryIndex);
          },
        );
      },
      idleBorderColorWhenEmpty: Colors.white.withValues(alpha: 0.05),
      idleBorderColorWhenFilled: Colors.white.withValues(alpha: 0.02),
    );
  }

  Widget _buildDropzoneHeader(ThemeData theme) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: <Widget>[
          _SmallHardwareButton(
            label: '📄 追加目标 (文件/目录)',
            onTap: _isRunning ? null : _pickFiles,
          ),

          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() {
                _showOnlyFailures = !_showOnlyFailures;
              });
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _HardwareCheckbox(value: _showOnlyFailures),
                const SizedBox(width: 8),
                Text(
                  '仅看失败项',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8B8F98),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _SmallHardwareButton(
            label: '🗑️ 清空列表',
            accent: true,
            onTap: _isRunning ? null : _clearAll,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTaskEntry(
    ThemeData theme,
    UnlockMusicCompletedTaskRecord record,
  ) {
    final Color accentColor = _historyAccentColor(record);
    return AnimatedBuilder(
      animation: _historyPulseController,
      builder: (BuildContext context, Widget? child) {
        return TaskHistoryEntryCard(
          key: const ValueKey<String>('unlock_music_history_entry'),
          title: '最近一次完成任务',
          summaryText:
              '共 ${record.inputFiles.length} 首 · 成功 ${record.successCount} · 失败 ${record.failedCount}',
          metaText:
              '${_historyStatusText(record)} · ${_formatHistoryTimestamp(record.finishedAt)} · ${record.outputDirectory.isEmpty ? '未设置输出目录' : record.outputDirectory}',
          accentColor: accentColor,
          pulseValue: _historyPulseController.value,
          badgeLabel: '查看结果',
          onTap: () => _showHistoryTaskDialog(record),
          onClear: _clearHistoryTask,
          clearKey: const ValueKey<String>('unlock_music_history_clear'),
        );
      },
    );
  }

  Widget _buildUnifiedListItem(
    ThemeData theme,
    _UnifiedUnlockEntry entry,
    int index,
  ) {
    return TaskFileOutcomeTile(
      key: ValueKey<String>(entry.file.path),
      leading: SizedBox(
        width: 20,
        child: Text(
          entry.leadingGlyph,
          textAlign: TextAlign.center,
          style: TextStyle(color: entry.statusColor, fontSize: 16),
        ),
      ),
      title: entry.file.name,
      secondaryText: entry.outputName == null ? null : '↳ ${entry.outputName}',
      pathLabel: '输入: ',
      pathText: entry.file.path,
      errorText: entry.result?.error,
      trailing: TaskItemStatusBadge(
        label: entry.tagText,
        foreground: entry.statusColor,
        background: entry.tagBackground,
        border: entry.tagBorder,
      ),
      trailingAfter: _isRunning
          ? const SizedBox(width: 20)
          : GestureDetector(
              onTap: () => _removeLoadedFile(entry.file.path),
              child: const SizedBox(
                width: 20,
                child: Text(
                  '×',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 16),
                ),
              ),
            ),
    );
  }

  Widget _buildProgress(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _progressHintText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B7280),
                  letterSpacing: 1,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${(_progressValue * 100).floor()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFE11D48),
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _LaserProgressBar(value: _progressValue),
      ],
    );
  }

  Widget _buildActionRow({required bool compact}) {
    final Widget startButton = _GiantActionButton(
      label: _isRunning ? '⏳ 任务执行中...' : '▶ 开始批量解锁',
      accent: true,
      active: _isRunning,
      onTap: _isRunning ? null : _startTask,
    );
    final Widget stopButton = SizedBox(
      width: compact ? double.infinity : 160,
      child: _GiantActionButton(
        label: '■ 紧急停止',
        onTap: _taskId == null ? null : _stopTask,
      ),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[startButton, const SizedBox(height: 12), stopButton],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(child: startButton),
        const SizedBox(width: 16),
        stopButton,
      ],
    );
  }

  Widget _buildSearchView(
    ThemeData theme, {
    required bool compact,
    required bool dense,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compressed = constraints.maxHeight < 640;
        final double verticalGap = compressed ? 8 : 12;
        final Widget statusBar = _buildSearchStatusBar(
          theme,
          compressed: compressed,
        );
        final Widget transportControls = _buildSearchTransportControls(
          compact: compact,
          compressed: compressed,
        );
        if (compact) {
          return SingleChildScrollView(
            primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildSearchConsole(theme, compact: compact),
                SizedBox(height: verticalGap),
                SizedBox(height: 280, child: _buildSearchTable(theme)),
                SizedBox(height: verticalGap),
                statusBar,
                SizedBox(height: verticalGap),
                transportControls,
              ],
            ),
          );
        }
        return Column(
          children: <Widget>[
            _buildSearchConsole(theme, compact: compact),
            SizedBox(height: verticalGap),
            Expanded(child: _buildSearchTable(theme)),
            SizedBox(height: verticalGap),
            statusBar,
            SizedBox(height: verticalGap),
            transportControls,
          ],
        );
      },
    );
  }

  Widget _buildSearchConsole(ThemeData theme, {required bool compact}) {
    final Widget searchField = TextField(
      controller: _searchQueryController,
      readOnly: _isSearchProcessing,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      enableSuggestions: false,
      autocorrect: false,
      style: const TextStyle(
        color: Color(0xFFE5E7EB),
        fontSize: 14,
        fontFamily: '-apple-system',
      ),
      decoration: _hardwareInputDecoration(
        hintText: '输入单曲/歌手精确检索，或直接贴入歌单链接解析...',
        giant: true,
      ),
    );
    final Widget actionButton = _SmallHardwareButton(
      label: _isSearchProcessing ? '检索中...' : '🔍 搜索 / 解析',
      large: true,
      accent: true,
      leading: _isSearchProcessing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFE11D48),
              ),
            )
          : null,
      onTap: _isSearchProcessing ? null : _submitSearchOrPlaylist,
    );
    final List<Widget> filterChildren = <Widget>[
      Text(
        '搜索范围:',
        style: theme.textTheme.bodySmall?.copyWith(
          color: const Color(0xFF8B8F98),
          fontSize: 12,
        ),
      ),
      ..._primarySearchSources.map(
        (SearchDownloadSourceOption option) => _SearchToggle(
          label: option.label,
          value: option.selected,
          onTap: _isSearchProcessing
              ? null
              : () => _toggleSearchSourceByValue(option.value),
        ),
      ),
      Container(
        width: 1,
        height: 12,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: Colors.white.withValues(alpha: 0.1),
      ),
      SizedBox(
        key: _searchDropdownButtonKey,
        child: _SearchDropdownSmall(
          expanded: _showMorePlatforms,
          onTap: _toggleMorePlatforms,
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        compact
            ? Column(
                children: <Widget>[
                  searchField,
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: actionButton),
                ],
              )
            : Row(
                children: <Widget>[
                  Expanded(child: searchField),
                  SizedBox(width: compact ? 8 : 12),

                  actionButton,
                ],
              ),
        const SizedBox(height: 12),
        compact
            ? Wrap(
                spacing: 16,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: filterChildren,
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  for (
                    int index = 0;
                    index < filterChildren.length;
                    index++
                  ) ...<Widget>[
                    filterChildren[index],
                    if (index != filterChildren.length - 1)
                      const SizedBox(width: 16),
                  ],
                ],
              ),
      ],
    );
  }

  Widget _buildSearchTable(ThemeData theme) {
    final TextStyle? headerStyle = theme.textTheme.bodySmall?.copyWith(
      color: const Color(0xFF9CA3AF),
      fontWeight: FontWeight.w700,
      fontSize: 13,
    );
    final List<SearchDownloadSongItem> songs = _searchSongs;
    final bool allSelected =
        songs.isNotEmpty &&
        songs.every(
          (SearchDownloadSongItem item) => _isSearchSongSelected(item),
        );
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF020202),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0xE6000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0C),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 30,
                  child: Center(
                    child: GestureDetector(
                      onTap: songs.isEmpty || _isSearchDownloading
                          ? null
                          : () {
                              setState(() {
                                if (allSelected) {
                                  _selectedSearchSongKeys.clear();
                                } else {
                                  _selectedSearchSongKeys
                                    ..clear()
                                    ..addAll(songs.map(_songSelectionKey));
                                }
                              });
                            },
                      child: _HardwareCheckbox(value: allSelected),
                    ),
                  ),
                ),
                Expanded(flex: 6, child: Text('歌曲名称', style: headerStyle)),
                Expanded(flex: 3, child: Text('歌手', style: headerStyle)),
                Expanded(flex: 2, child: Text('来源', style: headerStyle)),
                Expanded(flex: 2, child: Text('大小', style: headerStyle)),
                Expanded(flex: 2, child: Text('格式', style: headerStyle)),
              ],
            ),
          ),
          Expanded(
            child: songs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (_isSearchProcessing)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFE11D48),
                            ),
                          ),
                        if (_isSearchProcessing) const SizedBox(height: 14),
                        Text(
                          _isSearchProcessing
                              ? '正在全网检索，请稍候...'
                              : '输入关键词，开始全网搜索',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF4B5563),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : Theme(
                    data: theme.copyWith(
                      scrollbarTheme: ScrollbarThemeData(
                        thumbColor: WidgetStateProperty.all(
                          const Color(0xFF2A2A31),
                        ),
                        trackColor: WidgetStateProperty.all(
                          const Color(0xFF09090B),
                        ),
                        trackBorderColor: WidgetStateProperty.all(
                          Colors.white.withValues(alpha: 0.04),
                        ),
                        thickness: WidgetStateProperty.all(8),
                        radius: const Radius.circular(4),
                      ),
                    ),
                    child: Scrollbar(
                      controller: _searchTableScrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      interactive: true,
                      child: ListView.builder(
                        controller: _searchTableScrollController,
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: songs.length,
                        itemBuilder: (BuildContext context, int index) {
                          final SearchDownloadSongItem item = songs[index];
                          final bool selected = _isSearchSongSelected(item);
                          return MouseRegion(
                            cursor: _isSearchDownloading
                                ? SystemMouseCursors.basic
                                : SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _isSearchDownloading
                                  ? null
                                  : () => _toggleSearchSongSelection(
                                      item,
                                      !selected,
                                    ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Colors.white.withValues(alpha: 0.03)
                                      : null,
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.02,
                                      ),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    SizedBox(
                                      width: 30,
                                      child: Center(
                                        child: GestureDetector(
                                          onTap: _isSearchDownloading
                                              ? null
                                              : () =>
                                                    _toggleSearchSongSelection(
                                                      item,
                                                      !selected,
                                                    ),
                                          child: _HardwareCheckbox(
                                            value: selected,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 6,
                                      child: Text(
                                        item.songName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFD1D5DB),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        item.singers ?? '-',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFD1D5DB),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        _getSourceLabel(item.source),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: _getSourceColor(item.source),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        item.fileSize ?? '-',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFD1D5DB),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        (item.ext ?? '-').toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: item.ext == 'flac'
                                              ? const Color(0xFF10B981)
                                              : const Color(0xFFD1D5DB),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchStatusBar(ThemeData theme, {required bool compressed}) {
    final SearchDownloadTaskSnapshot? snapshot = _searchSnapshot;
    final bool running =
        _isSearchProcessing ||
        _isSearchDownloading ||
        snapshot?.status == SearchDownloadStatus.running;
    final bool downloading = _isSearchDownloadTask;
    final double? progress = downloading ? _searchTotalProgress : null;
    final String elapsed = running ? ' · 已等待 $_searchElapsedSeconds 秒' : '';
    final String statusText = _isSearchProcessing
        ? '正在全网检索$elapsed'
        : (snapshot == null ? '等待检索' : '$_searchStageText$elapsed');
    return Container(
      height: compressed ? 34 : 38,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF08080A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: <Widget>[
          if (running)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: const Color(0xFFE11D48),
                value: downloading ? progress : null,
              ),
            ),
          if (running) const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
                fontFamily: '-apple-system',
              ),
            ),
          ),
          if (!_isSearchProcessing && !downloading) ...<Widget>[
            const SizedBox(width: 12),
            Text(
              _searchStatsText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE11D48),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchTransportControls({
    required bool compact,
    required bool compressed,
  }) {
    final Widget controls = Container(
      height: compressed ? 38 : 42,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: <Widget>[
          _SmallHardwareButton(label: '💾 输出路径', onTap: _pickOutputDirectory),
        ],
      ),
    );
    final Widget startButton = SizedBox(
      height: compressed ? 42 : 48,
      child: _isSearchDownloading
          ? _SearchDownloadProgressButton(
              progress: _searchCurrentProgress,
              completed:
                  (_searchSnapshot?.successCount ?? 0) +
                  (_searchSnapshot?.failedCount ?? 0),
              total: _searchSnapshot?.totalCount ?? 0,
            )
          : _GiantActionButton(
              label: '▶ 开始下载选中项',
              accent: true,
              onTap: _startSearchDownloadTask,
            ),
    );
    final Widget start = Expanded(child: startButton);
    final Widget stop = SizedBox(
      width: compact ? double.infinity : 140,
      height: compressed ? 42 : 48,
      child: _GiantActionButton(
        label: '■ 终止',
        onTap: _searchTaskId == null ? null : _stopSearchTask,
      ),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          controls,
          const SizedBox(height: 12),
          startButton,
          const SizedBox(height: 12),
          stop,
        ],
      );
    }
    return Row(
      children: <Widget>[
        controls,
        const SizedBox(width: 16),
        start,
        const SizedBox(width: 16),
        stop,
      ],
    );
  }

  InputDecoration _hardwareInputDecoration({
    String? hintText,
    bool giant = false,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF4B5563)),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFF020202),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: giant ? 14 : 10,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(giant ? 8 : 6),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: Color(0x66E11D48)),
      ),
    );
  }

  BoxDecoration _insetDecoration({double radius = 6}) {
    return BoxDecoration(
      color: const Color(0xFF020202),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.9),
          blurRadius: 14,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

class _UnifiedUnlockEntry {
  const _UnifiedUnlockEntry({required this.file, required this.result});

  final UnlockMusicFileItem file;
  final UnlockMusicResultItem? result;

  bool get isSuccess => result?.success == true;
  bool get isFailure => result?.success == false;

  String get leadingGlyph {
    if (isSuccess) {
      return '✓';
    }
    if (isFailure) {
      return '×';
    }
    return '⠿';
  }

  String get tagText {
    if (isSuccess) {
      return '✓ 成功';
    }
    if (isFailure) {
      return '⚠ 失败';
    }
    return '🔒 待处理';
  }

  Color get statusColor {
    if (isSuccess) {
      return const Color(0xFF10B981);
    }
    if (isFailure) {
      return const Color(0xFFE11D48);
    }
    return const Color(0xFF8B8F98);
  }

  Color get tagBackground {
    if (isSuccess) {
      return const Color(0x1A10B981);
    }
    if (isFailure) {
      return const Color(0x1AE11D48);
    }
    return Colors.white.withValues(alpha: 0.04);
  }

  Color get tagBorder {
    if (isSuccess) {
      return const Color(0x4D10B981);
    }
    if (isFailure) {
      return const Color(0x4DE11D48);
    }
    return Colors.white.withValues(alpha: 0.1);
  }

  String? get outputName {
    final String? outputPath = result?.outputPath;
    if (outputPath == null || outputPath.isEmpty) {
      return null;
    }
    return p.basename(outputPath);
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.message,
    required this.background,
    required this.foreground,
  });

  final String message;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Text(message, style: TextStyle(color: foreground, fontSize: 13)),
    );
  }
}

class _GridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.015)
      ..strokeWidth = 1;
    const double gap = 32;
    for (double x = 0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.statusText,
    required this.targetCount,
    required this.successCount,
    required this.failedCount,
    required this.active,
    required this.statusColor,
    this.hideSuccessFail = false,
  });

  final String statusText;
  final int targetCount;
  final int successCount;
  final int failedCount;
  final bool active;
  final Color statusColor;
  final bool hideSuccessFail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF020202),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 1),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.03),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        primary: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _StatusCell(
              label: '状态',
              value: statusText,
              valueColor: statusColor,
            ),
            _StripDivider(),
            _StatusCell(label: '目标', value: '$targetCount'),
            if (!hideSuccessFail) ...<Widget>[
              _StripDivider(),
              _StatusCell(
                label: '成功',
                value: '$successCount',
                valueColor: const Color(0xFF10B981),
              ),
              _StripDivider(),
              _StatusCell(
                label: '失败',
                value: '$failedCount',
                valueColor: const Color(0xFFE11D48),
              ),
            ],
            const SizedBox(width: 8),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? const Color(0xFFE11D48)
                    : const Color(0xFFD97706),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: active
                        ? const Color(0xCCE11D48)
                        : const Color(0xCCD97706),
                    blurRadius: 8,
                    spreadRadius: active ? 1 : 0,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell({
    required this.label,
    required this.value,
    this.valueColor = const Color(0xFFD1D5DB),
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$label:',
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 13,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _StripDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.white.withValues(alpha: 0.05),
    );
  }
}

class _EngineTabButton extends StatelessWidget {
  const _EngineTabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: active ? const Color(0x1AE11D48) : Colors.transparent,
          border: Border.all(
            color: active ? const Color(0x4DE11D48) : Colors.transparent,
          ),
          boxShadow: active
              ? <BoxShadow>[
                  BoxShadow(
                    color: const Color(0x1AE11D48),
                    blurRadius: 10,
                    offset: const Offset(0, 0),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: active ? const Color(0xFFE11D48) : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}

class _SearchDownloadProgressButton extends StatelessWidget {
  const _SearchDownloadProgressButton({
    required this.progress,
    required this.completed,
    required this.total,
  });

  final double progress;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final double value = progress.clamp(0, 1).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xFF2A0710), Color(0xFF120308)],
              ),
            ),
          ),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[Color(0xFF4C0519), Color(0xFFE11D48)],
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              total > 0 ? '下载中  $completed / $total' : '下载中...',
              style: const TextStyle(
                color: Color(0xFFE11D48),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallHardwareButton extends StatelessWidget {
  const _SmallHardwareButton({
    required this.label,
    this.onTap,
    this.accent = false,
    this.large = false,
    this.horizontalPadding,
    this.leading,
  });

  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final bool large;
  final double? horizontalPadding;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final double height = large ? 44 : 36;
    final BorderRadius radius = BorderRadius.circular(large ? 8 : 6);
    final Color textColor = accent
        ? const Color(0xFFE11D48)
        : const Color(0xFFD1D5DB);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: height,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding ?? (large ? 24 : 16),
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: <Color>[
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.025),
              ],
            ),
            border: Border.all(
              color: accent
                  ? const Color(0x4DE11D48)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: large ? 14 : 13,
                  color: onTap == null ? const Color(0xFF52525B) : textColor,
                  fontWeight: large ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GiantActionButton extends StatelessWidget {
  const _GiantActionButton({
    required this.label,
    this.onTap,
    this.accent = false,
    this.active = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color color = accent
        ? const Color(0xFFE11D48)
        : const Color(0xFF9CA3AF);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              colors: <Color>[
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.025),
              ],
            ),
            border: Border.all(
              color: active || accent
                  ? color.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: active ? 18 : 12,
                offset: const Offset(0, 6),
              ),
              if (active)
                BoxShadow(
                  color: const Color(0x55E11D48),
                  blurRadius: 20,
                  offset: const Offset(0, 0),
                ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: onTap == null ? const Color(0xFF52525B) : color,
            ),
          ),
        ),
      ),
    );
  }
}

class _HardwareCheckbox extends StatelessWidget {
  const _HardwareCheckbox({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return HardwareCheckboxIndicator(
      value: value,
      size: 18,
      radius: 4,
      uncheckedFillColor: const Color(0xFF020202),
      checkedBorderColor: const Color(0xCCE11D48),
      uncheckedBorderColor: Colors.white.withValues(alpha: 0.28),
      checkSize: 14,
      borderWidth: 1.2,
    );
  }
}

class _LaserProgressBar extends StatelessWidget {
  const _LaserProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final double clamped = value.clamp(0, 1).toDouble();
    return SizedBox(
      height: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF020202),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.black.withValues(alpha: 0.8)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.9),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.05),
              blurRadius: 0,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            children: <Widget>[
              if (clamped > 0)
                FractionallySizedBox(
                  widthFactor: clamped,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: <Color>[
                          Color(0xFF4C0519),
                          Color(0xFFBE123C),
                          Color(0xFFFB7185),
                        ],
                        stops: <double>[0, 0.8, 1],
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Color(0x99E11D48),
                          blurRadius: 15,
                          offset: Offset(0, 0),
                        ),
                      ],
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 15,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: <Color>[Colors.transparent, Colors.white],
                          ),
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(5),
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0xCCFFFFFF),
                              blurRadius: 15,
                              spreadRadius: 3,
                            ),
                            BoxShadow(
                              color: Color(0xCCE11D48),
                              blurRadius: 25,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _ProgressSegmentsPainter()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressSegmentsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = Colors.black.withValues(alpha: 0.7);
    for (double x = 4; x < size.width; x += 6) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SearchToggle extends StatelessWidget {
  const _SearchToggle({required this.label, required this.value, this.onTap});

  final String label;
  final bool value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _HardwareCheckbox(value: value),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchDropdownSmall extends StatelessWidget {
  const _SearchDropdownSmall({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SmallHardwareButton(
      label: expanded ? '更多平台选项 ▲' : '更多平台选项 ▼',
      onTap: onTap,
      horizontalPadding: 12,
    );
  }
}

class _SearchDropdownPanel extends StatelessWidget {
  const _SearchDropdownPanel({required this.options, this.onToggle});

  final List<SearchDownloadSourceOption> options;
  final ValueChanged<String>? onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          constraints: const BoxConstraints(minWidth: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF08080A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0xF2000000),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Color(0x0DFFFFFF),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int index = 0; index < options.length; index++) ...<Widget>[
                _SearchToggleItem(
                  label: options[index].label,
                  value: options[index].selected,
                  sourceValue: options[index].value,
                  onToggle: onToggle,
                ),
                if (index != options.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchToggleItem extends StatelessWidget {
  const _SearchToggleItem({
    required this.label,
    required this.value,
    required this.sourceValue,
    this.onToggle,
  });

  final String label;
  final bool value;
  final String sourceValue;
  final ValueChanged<String>? onToggle;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onToggle == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle == null ? null : () => onToggle!(sourceValue),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _HardwareCheckbox(value: value),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchProgressRow extends StatelessWidget {
  const _SearchProgressRow({
    required this.label,
    required this.value,
    this.trailingText,
    this.compact = false,
  });

  final String label;
  final double value;
  final String? trailingText;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 16 : 18,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 35,
            child: Text(
              label,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF8B8F98),
                fontSize: compact ? 9 : 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(child: _LaserProgressBar(value: value)),
          SizedBox(width: compact ? 8 : 10),
          SizedBox(
            width: compact ? 68 : 88,
            child: Text(
              trailingText ?? '${(value * 100).floor()}%',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE11D48),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
