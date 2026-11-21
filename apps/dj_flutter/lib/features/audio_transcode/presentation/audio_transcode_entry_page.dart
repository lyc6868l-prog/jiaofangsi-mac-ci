import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:dj_flutter/app/dj_app_scope.dart';
import 'package:dj_flutter/app/router/app_router.dart';
import 'package:dj_flutter/shared/hardware_ui/hardware_ui.dart';
import 'package:dj_flutter/shared/platform_utils.dart' as platform_utils;
import 'package:dj_flutter/shared/task_runtime/task_running_notifier.dart'
    show TaskRunningNotifier, TaskEndState;
import 'package:dj_flutter/shared/task_ui/task_file_outcome_tile.dart';
import 'package:dj_flutter/shared/task_ui/task_history_entry_card.dart';
import 'package:dj_flutter/shared/task_ui/task_import_list_shell.dart';
import 'package:dj_flutter/shared/task_ui/task_item_status_badge.dart';
import 'package:dj_flutter/shared/task_ui/task_result_filter.dart';
import 'controllers/audio_transcode_controller.dart';
import 'controllers/python_audio_transcode_task_bridge.dart';
import 'models/audio_transcode_models.dart';

class AudioTranscodeEntryPage extends StatefulWidget {
  const AudioTranscodeEntryPage({
    super.key,
    AudioTranscodeController? controller,
    this.isFeatureLocked = false,
    this.onLockedStartPressed,
    this.onOpenOutputDirectory,
  }) : _controller = controller;

  final AudioTranscodeController? _controller;
  final bool isFeatureLocked;
  final VoidCallback? onLockedStartPressed;
  final Future<void> Function(String directory)? onOpenOutputDirectory;

  @override
  State<AudioTranscodeEntryPage> createState() =>
      _AudioTranscodeEntryPageState();
}

class _AudioTranscodeEntryPageState extends State<AudioTranscodeEntryPage> {
  @visibleForTesting
  AudioTranscodeController get debugController => _controller;

  static const MethodChannel _platformChannel = MethodChannel(
    'dj_flutter/unlock_music',
  );

  static const List<String> _supportedExtensions = <String>[
    'mp3',
    'wav',
    'aiff',
    'flac',
    'm4a',
    'ogg',
    'aac',
    'wma',
    'dff',
  ];
  static const String _autoOutputLabel = '原文件夹 (自动子目录)';
  static const String _customOutputLabel = '自定义';
  PythonAudioTranscodeTaskBridge? _bridge;
  late final AudioTranscodeController _controller;
  TaskRunningNotifier? _taskRunningNotifier;
  bool _lastReportedRunning = false;
  bool _isDragActive = false;
  bool _isButtonPressed = false;
  bool _isStopButtonPressed = false;
  bool _showOnlyFailures = false;
  String? _lastCompletedTaskId;
  AudioTranscodeCompletedTaskRecord? _lastCompletedTask;

  @override
  void initState() {
    super.initState();
    if (widget._controller != null) {
      _controller = widget._controller!;
    } else {
      final Directory projectRoot = _resolveProjectRoot();
      _bridge = PythonAudioTranscodeTaskBridge(
        pythonExecutable: _resolvePythonExecutable(projectRoot),
        workingDirectory: p.join(projectRoot.path, 'runtime', 'dj_runtime_py'),
        scriptModule: 'dj_runtime_py',
      );
      _controller = AudioTranscodeController(
        defaultOutputDirectory: p.join(
          projectRoot.path,
          'audio_transcode_output',
        ),
        bridge: _bridge!,
        ffmpegPath: _resolveFfBinaryPath(projectRoot, 'ffmpeg'),
        ffprobePath: _resolveFfBinaryPath(projectRoot, 'ffprobe'),
      );
    }
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _taskRunningNotifier = DjAppScope.maybeOf(context)?.taskRunningNotifier;
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    if (_taskRunningNotifier != null && _lastReportedRunning) {
      _taskRunningNotifier!.setRunning(AppShellSection.audioTranscode, false);
    }
    _controller.close();
    super.dispose();
  }

  void _handleControllerChanged() {
    final AudioTranscodeStatus status = _controller.snapshot.status;
    final bool isRunning = status == AudioTranscodeStatus.running;
    if (_taskRunningNotifier == null) {
      return;
    }
    if (isRunning != _lastReportedRunning) {
      _taskRunningNotifier!.setRunning(
        AppShellSection.audioTranscode,
        isRunning,
      );
      _lastReportedRunning = isRunning;
    }
    if (!isRunning) {
      TaskEndState endState = TaskEndState.none;
      if (status == AudioTranscodeStatus.success) {
        endState = TaskEndState.success;
      } else if (status == AudioTranscodeStatus.error) {
        endState = TaskEndState.error;
      } else if (status == AudioTranscodeStatus.cancelled) {
        endState = TaskEndState.aborted;
      }
      _taskRunningNotifier!.setEndState(
        AppShellSection.audioTranscode,
        endState,
      );
    }

    final String? toastMessage = _controller.toastMessage;
    if (mounted && toastMessage != null && toastMessage.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(toastMessage),
            backgroundColor: const Color(0xFFE11D48),
          ),
        );
      _controller.clearToast();
    }
    final AudioTranscodeTaskSnapshot snapshot = _controller.snapshot;
    if (!mounted) {
      return;
    }
    _updateLastCompletedTask(snapshot);
    if ((snapshot.status == AudioTranscodeStatus.success ||
            snapshot.status == AudioTranscodeStatus.cancelled ||
            snapshot.status == AudioTranscodeStatus.error) &&
        snapshot.taskId.isNotEmpty &&
        snapshot.taskId != _lastCompletedTaskId) {
      _lastCompletedTaskId = snapshot.taskId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _showCompletionDialog(snapshot);
      });
    }
  }

  Directory _resolveProjectRoot() {
    return platform_utils.resolveProjectRoot();
  }

  String _resolvePythonExecutable(Directory projectRoot) {
    return platform_utils.resolvePythonExecutable(projectRoot);
  }

  String? _resolveFfBinaryPath(Directory projectRoot, String executableName) {
    return platform_utils.resolveFfBinaryPath(projectRoot, executableName);
  }

  Future<void> _pickFiles() async {
    try {
      final List<String> paths = await _pickTargets();
      if (paths.isNotEmpty) {
        await _controller.loadTargets(
          paths,
          append: _controller.loadedFiles.isNotEmpty,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('无法打开文件选择器，请检查系统权限后重试。'),
            backgroundColor: const Color(0xFFE11D48),
          ),
        );
    }
  }

  Future<List<String>> _pickTargets() async {
    if (Platform.isMacOS) {
      final List<Object?>? result = await _platformChannel
          .invokeListMethod<Object?>('pickUnlockTargets');
      return result
              ?.whereType<String>()
              .where((String path) => path.isNotEmpty)
              .toList() ??
          <String>[];
    }

    final List<XFile> files = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[
        const XTypeGroup(label: '音频文件', extensions: _supportedExtensions),
      ],
      confirmButtonText: '导入',
    );
    return files
        .map((XFile file) => file.path)
        .where((String path) => path.isNotEmpty)
        .toList();
  }

  Future<void> _pickCustomOutputDirectory() async {
    final String? directory = await getDirectoryPath(confirmButtonText: '选择目录');
    if (directory == null || directory.isEmpty) {
      return;
    }
    _controller.updateOutputLocation(AudioTranscodeOutputLocation.custom);
    _controller.updateOutputDirectory(directory);
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
      if (bookmark is Uint8List) {
        final bool allowed = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
        if (allowed && file.path.isNotEmpty) {
          paths.add(file.path);
        }
      }
    }
    if (paths.isNotEmpty) {
      await _controller.loadTargets(
        paths,
        append: _controller.loadedFiles.isNotEmpty,
      );
    }
  }

  Future<void> debugLoadTargets(List<String> paths, {bool append = false}) {
    return _controller.loadTargets(paths, append: append);
  }

  @visibleForTesting
  Future<void> debugShowCompletionDialog(AudioTranscodeTaskSnapshot snapshot) {
    return _showCompletionDialog(snapshot);
  }

  Future<bool> _canOpenOutputDirectory(String directory) async {
    if (directory.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('该任务未记录输出目录。'),
            backgroundColor: Color(0xFFE11D48),
          ),
        );
      return false;
    }
    if (!Directory(directory).existsSync()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('输出目录不存在，可能已被移动或删除。'),
            backgroundColor: Color(0xFFE11D48),
          ),
        );
      return false;
    }
    return true;
  }

  Future<void> _openOutputDirectory(String directory) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (widget.onOpenOutputDirectory
        case final Future<void> Function(String directory)
            openOutputDirectory) {
      try {
        await openOutputDirectory(directory);
      } on Object catch (error) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('无法打开输出文件夹，请检查目录是否存在后重试。'),
              backgroundColor: Color(0xFFE11D48),
            ),
          );
      }
      return;
    }
    try {
      await platform_utils.openDirectory(directory);
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('无法打开输出文件夹，请检查目录是否存在后重试。'),
            backgroundColor: Color(0xFFE11D48),
          ),
        );
    }
  }

  Future<void> _showCompletionDialog(
    AudioTranscodeTaskSnapshot snapshot,
  ) async {
    final String? resolvedOutputDirectory =
        snapshot.outputDirectory ?? _controller.effectiveOutputDirectory;
    final String outputDirectory = resolvedOutputDirectory ?? '原文件夹自动子目录';

    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return HardwareDialog(
          width: kHardwareDialogStandardWidth,
          title: snapshot.status == AudioTranscodeStatus.success
              ? '转码已完成'
              : '转码已结束',
          titleIcon: const Icon(Icons.multitrack_audio_rounded),
          onClose: () => Navigator.of(dialogContext).pop(),
          hudTitle: 'Task Summary / 任务摘要',
          hudText: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('成功数量：${snapshot.successCount}'),
              const SizedBox(height: 4),
              Text('失败数量：${snapshot.failedCount}'),
              const SizedBox(height: 4),
              Text('输出目录：$outputDirectory'),
            ],
          ),
          body: const SizedBox.shrink(),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          footer: HardwareDialogFooter(
            actions: <Widget>[
              HardwareDialogAction(
                label: '打开文件所在文件夹',
                variant: HardwareDialogActionVariant.confirm,
                onPressed:
                    resolvedOutputDirectory == null ||
                        resolvedOutputDirectory.isEmpty
                    ? null
                    : () async {
                        final bool canOpen = await _canOpenOutputDirectory(
                          resolvedOutputDirectory,
                        );
                        if (!canOpen) {
                          return;
                        }
                        await _openOutputDirectory(resolvedOutputDirectory);
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF030303), Color(0xFF000000)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF08080A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF000000), width: 1),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.95),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 10,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.03),
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildHeader(),
                      const SizedBox(height: 8),
                      _buildConfigBlock(),
                      const SizedBox(height: 8),
                      Expanded(child: _buildDropzone()),
                      const SizedBox(height: 8),
                      _buildProgressWrapper(),
                      const SizedBox(height: 8),
                      _buildMainActionRow(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text('♻️', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            const Text(
              '音频格式转换',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Color(0xFFF3F4F6),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            if (_controller.snapshot.status != AudioTranscodeStatus.running)
              _BtnClearSm(
                label: '清空列表',
                onTap: () => _controller.clearTargets(),
              ),
            const SizedBox(width: 16),
            _LcdStatusBar(snapshot: _controller.snapshot),
          ],
        ),
      ],
    );
  }

  Widget _buildConfigBlock() {
    final bool isRunning =
        _controller.snapshot.status == AudioTranscodeStatus.running;
    final bool isInteractionLocked = isRunning || widget.isFeatureLocked;
    return Opacity(
      opacity: isInteractionLocked ? 0.5 : 1.0,
      child: IgnorePointer(
        ignoring: isInteractionLocked,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
            borderRadius: BorderRadius.circular(8),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildConfigRow(label: '目标格式:', child: _buildFormatRadioGroup()),
              const SizedBox(height: 14),
              _buildConfigRow(
                label: '输出位置:',
                child: _buildLocationRadioGroup(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigRow({required String label, required Widget child}) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFD1D5DB),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildFormatRadioGroup() {
    return Row(
      children: <Widget>[
        _buildRadioWrapper(
          value: AudioTranscodeOutputFormat.mp3,
          label: 'MP3 320k',
        ),
        const SizedBox(width: 20),
        _buildRadioWrapper(
          value: AudioTranscodeOutputFormat.wav,
          label: 'WAV 原始',
        ),
        const SizedBox(width: 20),
        _buildRadioWrapper(
          value: AudioTranscodeOutputFormat.aiff,
          label: 'AIFF (CDJ通用)',
        ),
        const SizedBox(width: 20),
        _buildRadioWrapper(
          value: AudioTranscodeOutputFormat.flac,
          label: 'FLAC (CDJ3000支持)',
        ),
      ],
    );
  }

  Widget _buildRadioWrapper({
    required AudioTranscodeOutputFormat value,
    required String label,
  }) {
    final bool isRunning =
        _controller.snapshot.status == AudioTranscodeStatus.running;
    final bool isSelected = _controller.outputFormat == value;
    return GestureDetector(
      onTap: isRunning ? null : () => _controller.updateOutputFormat(value),
      child: Row(
        children: <Widget>[
          _buildHardwareRadio(isSelected: isSelected, isDisabled: isRunning),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isRunning
                  ? const Color(0xFF9CA3AF)
                  : (isSelected
                        ? const Color(0xFFE11D48)
                        : const Color(0xFFD1D5DB)),
              fontWeight: isSelected && !isRunning
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareRadio({
    required bool isSelected,
    bool isDisabled = false,
  }) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF020202),
        border: Border.all(
          color: isDisabled
              ? const Color(0xFF6B7280).withValues(alpha: 0.5)
              : (isSelected
                    ? const Color(0xFFE11D48).withValues(alpha: 0.6)
                    : const Color(0xFFFFFFFF).withValues(alpha: 0.15)),
          width: 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isSelected && !isDisabled
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE11D48),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.8),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildLocationRadioGroup() {
    final bool isCustom =
        _controller.outputLocation == AudioTranscodeOutputLocation.custom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _buildSimpleRadioWrapper(
              value: AudioTranscodeOutputLocation.sourceSubdir,
              label: _autoOutputLabel,
            ),
            const SizedBox(width: 20),
            _buildSimpleRadioWrapper(
              value: AudioTranscodeOutputLocation.custom,
              label: _customOutputLabel,
            ),
          ],
        ),
        if (isCustom) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  height: 36,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF020202),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    _controller.outputDirectory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFD1D5DB),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _BtnClearSm(label: '选择目录', onTap: _pickCustomOutputDirectory),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSimpleRadioWrapper({
    required AudioTranscodeOutputLocation value,
    required String label,
  }) {
    final bool isRunning =
        _controller.snapshot.status == AudioTranscodeStatus.running;
    final bool isSelected = _controller.outputLocation == value;
    return GestureDetector(
      onTap: isRunning ? null : () => _controller.updateOutputLocation(value),
      child: Row(
        children: <Widget>[
          _buildHardwareRadio(isSelected: isSelected, isDisabled: isRunning),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isRunning
                  ? const Color(0xFF9CA3AF)
                  : (isSelected
                        ? const Color(0xFFE11D48)
                        : const Color(0xFFD1D5DB)),
              fontWeight: isSelected && !isRunning
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropzone() {
    final bool hasFiles = _controller.loadedFiles.isNotEmpty;
    final bool isRunning =
        _controller.snapshot.status == AudioTranscodeStatus.running;
    final bool isInteractionLocked = isRunning || widget.isFeatureLocked;
    return TaskImportListShell(
      hasItems: hasFiles,
      isDragging: _isDragActive,
      isInteractionLocked: isInteractionLocked,
      disabledOpacity: isInteractionLocked ? 0.7 : 1.0,
      highlightWhenHasItems: false,
      onDragStateChanged: (bool value) {
        if (hasFiles || isRunning) {
          if (_isDragActive) {
            setState(() => _isDragActive = false);
          }
          return;
        }
        setState(() => _isDragActive = value);
      },
      onDropDone: _handleDropDone,
      onEmptyTap: !hasFiles ? _pickFiles : null,
      header: hasFiles ? _buildDropzoneHeader() : null,
      emptyBuilder: (BuildContext context, bool isDragging) {
        return _buildDropzoneEmptyState();
      },
      contentBuilder: (BuildContext context) => _buildFileList(),
      idleBorderColorWhenEmpty: const Color(0xFFFFFFFF).withValues(alpha: 0.05),
      idleBorderColorWhenFilled: const Color(0xFF000000).withValues(alpha: 0.9),
      dragActiveBorderColor: const Color(0xFFE11D48).withValues(alpha: 0.8),
      idleShadowColor: Colors.black.withValues(alpha: 0.98),
      dragShadowColor: const Color(0xFFE11D48).withValues(alpha: 0.2),
    );
  }

  Widget _buildDropzoneHeader() {
    final bool isRunning =
        _controller.snapshot.status == AudioTranscodeStatus.running;
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
          if (!widget.isFeatureLocked)
            _BtnClearSm(
              label: '追加目标 (文件/目录)',
              onTap: isRunning ? () {} : _pickFiles,
            ),
          const Spacer(),
          GestureDetector(
            key: const ValueKey<String>('audio_transcode_fail_filter_toggle'),
            onTap: isRunning
                ? null
                : () {
                    setState(() {
                      _showOnlyFailures = !_showOnlyFailures;
                    });
                  },
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _AudioTranscodeCheckbox(value: _showOnlyFailures),
                const SizedBox(width: 8),
                Text(
                  '仅看失败项',
                  style: TextStyle(
                    color: isRunning
                        ? const Color(0xFF6B7280)
                        : const Color(0xFF8B8F98),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropzoneEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '🗂️',
            style: TextStyle(
              fontSize: 28,
              color: _isDragActive
                  ? const Color(0xFFE11D48)
                  : const Color(0xFF4B5563),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isDragActive ? '松开导入文件或文件夹' : '点击选择或拖入文件文件夹',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _isDragActive
                  ? const Color(0xFFE11D48)
                  : const Color(0xFF4B5563),
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    final Map<String, AudioTranscodeResultItem> resultMap =
        <String, AudioTranscodeResultItem>{
          for (final AudioTranscodeResultItem item in _controller.results)
            item.inputPath: item,
        };
    final List<_AudioTranscodeListEntry> entries = _controller.loadedFiles
        .map(
          (AudioTranscodeFileItem file) => _AudioTranscodeListEntry(
            file: file,
            result: resultMap[file.path],
          ),
        )
        .toList(growable: false);
    final List<_AudioTranscodeListEntry> visibleEntries =
        filterTaskResults<_AudioTranscodeListEntry>(
          entries,
          filter: _showOnlyFailures
              ? TaskResultFilter.failureOnly
              : TaskResultFilter.all,
          isSuccess: (_AudioTranscodeListEntry entry) =>
              entry.result?.success == true,
          isFailure: (_AudioTranscodeListEntry entry) =>
              entry.result?.success == false,
        );
    if (visibleEntries.isEmpty && _lastCompletedTask == null) {
      return const Center(
        child: Text(
          '当前过滤条件下没有结果。',
          style: TextStyle(
            color: Color(0xFFD1D5DB),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: visibleEntries.length + (_lastCompletedTask == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final AudioTranscodeCompletedTaskRecord? lastCompletedTask =
            _lastCompletedTask;
        if (lastCompletedTask != null && index == 0) {
          return _buildHistoryTaskEntry(lastCompletedTask);
        }
        final int entryIndex = index - (lastCompletedTask == null ? 0 : 1);
        final _AudioTranscodeListEntry entry = visibleEntries[entryIndex];
        return _buildFileItem(
          name: entry.file.name,
          path: entry.file.path,
          targetFormat: _controller.outputFormat.label,
          result: entry.result,
        );
      },
    );
  }

  Widget _buildFileItem({
    required String name,
    required String path,
    required String targetFormat,
    AudioTranscodeResultItem? result,
  }) {
    final String status = switch (result?.success) {
      true => 'success',
      false =>
        _controller.snapshot.status == AudioTranscodeStatus.cancelled
            ? 'cancelled'
            : 'failed',
      null =>
        _controller.snapshot.status == AudioTranscodeStatus.running
            ? 'running'
            : 'pending',
    };
    final bool isSuccess = status == 'success';
    final String? outputPath = result?.outputPath;

    final bool isRunning =
        _controller.snapshot.status == AudioTranscodeStatus.running;
    return TaskFileOutcomeTile(
      leading: Text(
        isSuccess ? '✓' : '🎵',
        style: TextStyle(
          fontSize: 16,
          color: isSuccess ? const Color(0xFF10B981) : const Color(0xFF6B7280),
        ),
      ),
      title: name,
      secondaryText: outputPath != null && outputPath.isNotEmpty
          ? '↳ 输出：${p.basename(outputPath)}'
          : null,
      secondaryTextColor: isSuccess
          ? const Color(0xFF10B981)
          : const Color(0xFF8B8F98),
      pathLabel: '源：',
      pathText: path,
      pathStyle: const TextStyle(
        fontSize: 11,
        color: Color(0xFF6B7280),
        fontFamily: 'monospace',
      ),
      errorText: result?.error?.isNotEmpty == true ? result?.error : null,
      trailing: _buildStatusBadge(status: status, targetFormat: targetFormat),
      trailingAfter: isRunning
          ? const SizedBox(width: 20)
          : GestureDetector(
              onTap: () => _controller.removeTarget(path),
              child: const SizedBox(
                width: 20,
                child: Text(
                  '×',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFD1D5DB),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
      contentGap: 16,
      trailingGap: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1E1E23), Color(0xFF0F0F12)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border.all(
          color: isSuccess
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFFFFFFF).withValues(alpha: 0.03),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _buildStatusBadge({
    required String status,
    required String targetFormat,
  }) {
    late final Color foreground;
    late final Color border;
    late final Color background;
    late final String label;
    switch (status) {
      case 'success':
        foreground = const Color(0xFF10B981);
        border = const Color(0xFF10B981).withValues(alpha: 0.3);
        background = const Color(0xFF10B981).withValues(alpha: 0.1);
        label = '✓ 成功';
        break;
      case 'failed':
        foreground = const Color(0xFFE11D48);
        border = const Color(0xFFE11D48).withValues(alpha: 0.3);
        background = const Color(0xFFE11D48).withValues(alpha: 0.1);
        label = '✕ 失败';
        break;
      case 'cancelled':
        foreground = const Color(0xFFD97706);
        border = const Color(0xFFD97706).withValues(alpha: 0.3);
        background = const Color(0xFFD97706).withValues(alpha: 0.1);
        label = '■ 已取消';
        break;
      case 'running':
        foreground = const Color(0xFFE11D48);
        border = const Color(0xFFE11D48).withValues(alpha: 0.25);
        background = const Color(0xFFE11D48).withValues(alpha: 0.08);
        label = '⏳ 转码中';
        break;
      default:
        foreground = const Color(0xFF8B8F98);
        border = Colors.white.withValues(alpha: 0.1);
        background = Colors.white.withValues(alpha: 0.05);
        label = '⏳ 待转 → $targetFormat';
        break;
    }
    return TaskItemStatusBadge(
      label: label,
      foreground: foreground,
      background: background,
      border: border,
      fontWeight: FontWeight.bold,
    );
  }

  void _updateLastCompletedTask(AudioTranscodeTaskSnapshot snapshot) {
    if (snapshot.taskId.isEmpty) {
      return;
    }
    if (snapshot.status != AudioTranscodeStatus.success &&
        snapshot.status != AudioTranscodeStatus.cancelled &&
        snapshot.status != AudioTranscodeStatus.error) {
      return;
    }
    _lastCompletedTask = AudioTranscodeCompletedTaskRecord(
      taskId: snapshot.taskId,
      status: snapshot.status,
      finishedAt: DateTime.now(),
      outputDirectory: _controller.effectiveOutputDirectory ?? '',
      inputFiles: List<AudioTranscodeFileItem>.from(_controller.loadedFiles),
      successCount: snapshot.successCount,
      failedCount: snapshot.failedCount,
      results: List<AudioTranscodeResultItem>.from(_controller.results),
      message: snapshot.hintText,
    );
  }

  String _formatHistoryTimestamp(DateTime time) {
    String twoDigit(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${twoDigit(time.month)}-${twoDigit(time.day)} ${twoDigit(time.hour)}:${twoDigit(time.minute)}:${twoDigit(time.second)}';
  }

  String _historyStatusText(AudioTranscodeCompletedTaskRecord record) {
    return switch (record.status) {
      AudioTranscodeStatus.success =>
        record.failedCount > 0 ? '完成但有失败项' : '全部完成',
      AudioTranscodeStatus.cancelled => '已中止',
      AudioTranscodeStatus.error => '执行失败',
      _ => '任务结束',
    };
  }

  Color _historyAccentColor(AudioTranscodeCompletedTaskRecord record) {
    if (record.status == AudioTranscodeStatus.cancelled) {
      return const Color(0xFFD97706);
    }
    if (record.status == AudioTranscodeStatus.error || record.hasFailures) {
      return const Color(0xFFE11D48);
    }
    return const Color(0xFF60A5FA);
  }

  void _clearHistoryTask() {
    if (!mounted) {
      return;
    }
    setState(() {
      _lastCompletedTask = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已清除最近一次完成任务记录。'),
          backgroundColor: Color(0xFFE11D48),
        ),
      );
  }

  Widget _buildHistoryTaskEntry(AudioTranscodeCompletedTaskRecord record) {
    return TaskHistoryEntryCard(
      key: const ValueKey<String>('audio_transcode_history_entry'),
      title: '最近一次完成任务',
      summaryText:
          '共 ${record.inputFiles.length} 项 · 成功 ${record.successCount} · 失败 ${record.failedCount}',
      metaText:
          '${_historyStatusText(record)} · ${_formatHistoryTimestamp(record.finishedAt)} · ${record.outputDirectory.isEmpty ? '未设置输出目录' : record.outputDirectory}',
      accentColor: _historyAccentColor(record),
      pulseValue: 0.3,
      badgeLabel: '查看结果',
      onTap: () => _showHistoryTaskDialog(record),
      onClear: _clearHistoryTask,
      clearKey: const ValueKey<String>('audio_transcode_history_clear'),
    );
  }

  Future<void> _showHistoryTaskDialog(
    AudioTranscodeCompletedTaskRecord record,
  ) async {
    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final Color accentColor = _historyAccentColor(record);
        TaskResultFilter filter = TaskResultFilter.all;
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setState) {
            final List<AudioTranscodeResultItem> visibleItems =
                filterTaskResults<AudioTranscodeResultItem>(
                  record.results,
                  filter: filter,
                  isSuccess: (AudioTranscodeResultItem item) => item.success,
                  isFailure: (AudioTranscodeResultItem item) => !item.success,
                );
            return HardwareDialog(
              width: 760,
              title: '最近一次完成任务',
              titleIcon: Icon(Icons.history_rounded, color: accentColor),
              onClose: () => Navigator.of(dialogContext).pop(),
              hudTitle: 'Task History / 任务记录',
              hudText: Text(
                '${_historyStatusText(record)} · ${_formatHistoryTimestamp(record.finishedAt)}\n共 ${record.inputFiles.length} 项，成功 ${record.successCount}，失败 ${record.failedCount}\n输出目录：${record.outputDirectory.isEmpty ? '未设置' : record.outputDirectory}${(record.message ?? '').isNotEmpty ? '\n状态说明：${record.message}' : ''}',
                style: TextStyle(
                  height: 1.6,
                  color: record.hasFailures
                      ? const Color(0xFFFB7185)
                      : const Color(0xFFD1D5DB),
                ),
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
                      _BtnClearSm(
                        label: '全部结果',
                        onTap: () {
                          setState(() {
                            filter = TaskResultFilter.all;
                          });
                        },
                      ),
                      _BtnClearSm(
                        label: '仅成功项',
                        onTap: () {
                          setState(() {
                            filter = TaskResultFilter.successOnly;
                          });
                        },
                      ),
                      _BtnClearSm(
                        label: '仅失败项',
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
                    ...visibleItems.map((AudioTranscodeResultItem item) {
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

  Widget _buildProgressWrapper() {
    final double pct = (_controller.snapshot.progress * 100).clamp(0.0, 100.0);
    final String? currentFileName = _controller.currentFileName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                currentFileName == null
                    ? _controller.snapshot.hintText
                    : '当前文件：$currentFileName',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8B8F98),
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '已完成 ${_controller.completedCount}/${_controller.snapshot.inputCount}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8B8F98)),
            ),
            const SizedBox(width: 12),
            Text(
              '${pct.toInt()}%',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFE11D48),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFF020202),
              border: Border.all(color: const Color(0xFF000000), width: 1),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.9),
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.05),
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Stack(
              children: <Widget>[
                FractionallySizedBox(
                  widthFactor: pct / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[
                          Color(0xFF4C0519),
                          Color(0xFFBE123C),
                          Color(0xFFFB7185),
                        ],
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(0xFFE11D48).withValues(alpha: 0.6),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                            Colors.black.withValues(alpha: 0.7),
                          ],
                          stops: const <double>[0, 0.4, 0.4, 0.6],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainActionRow() {
    final bool isRunning =
        _controller.snapshot.status == AudioTranscodeStatus.running;
    final bool isFeatureLocked = widget.isFeatureLocked;
    final bool canViewResults =
        _controller.hasResults &&
        _controller.snapshot.status != AudioTranscodeStatus.running;
    final String primaryLabel = switch (_controller.snapshot.status) {
      AudioTranscodeStatus.running => '⏳ 格式转换中...',
      AudioTranscodeStatus.success ||
      AudioTranscodeStatus.cancelled => '📂 查看转码结果',
      _ => '▶ 开始转码',
    };
    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: GestureDetector(
            onTap: isRunning
                ? null
                : canViewResults
                ? () {
                    _showCompletionDialog(_controller.snapshot);
                  }
                : isFeatureLocked
                ? widget.onLockedStartPressed
                : _controller.canStartTask
                ? _controller.startTranscodeTask
                : null,
            onTapDown: (_) {
              setState(() => _isButtonPressed = true);
            },
            onTapUp: (_) {
              setState(() => _isButtonPressed = false);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: 48,
              transform: Matrix4.translationValues(
                0,
                _isButtonPressed &&
                        (isFeatureLocked || _controller.canStartTask) &&
                        !isRunning
                    ? 3
                    : 0,
                0,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    const Color(0xFF1E1E23).withValues(alpha: 0.6),
                    const Color(0xFF0F0F12).withValues(alpha: 0.8),
                  ],
                ),
                border: Border.all(
                  color: isRunning
                      ? const Color(0xFF10B981).withValues(alpha: 0.6)
                      : canViewResults
                      ? const Color(0xFF60A5FA).withValues(alpha: 0.6)
                      : const Color(0xFF000000),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: isRunning
                        ? const Color(0xFF10B981).withValues(alpha: 0.4)
                        : canViewResults
                        ? const Color(0xFF60A5FA).withValues(alpha: 0.35)
                        : Colors.black.withValues(alpha: 0.6),
                    blurRadius: isRunning || canViewResults ? 20 : 0,
                    spreadRadius: 0,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.05),
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  primaryLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: isRunning
                        ? const Color(0xFF10B981)
                        : canViewResults
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFFD1D5DB),
                    shadows: isRunning
                        ? <Shadow>[
                            Shadow(
                              color: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.6),
                              blurRadius: 12,
                            ),
                          ]
                        : canViewResults
                        ? <Shadow>[
                            Shadow(
                              color: const Color(
                                0xFF60A5FA,
                              ).withValues(alpha: 0.45),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 1,
          child: GestureDetector(
            onTap: isRunning ? _controller.stopTask : null,
            onTapDown: (_) {
              setState(() => _isStopButtonPressed = true);
            },
            onTapUp: (_) {
              setState(() => _isStopButtonPressed = false);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              height: 48,
              transform: Matrix4.translationValues(
                0,
                _isStopButtonPressed && isRunning ? 3 : 0,
                0,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    const Color(0xFF1E1E23).withValues(alpha: 0.6),
                    const Color(0xFF0F0F12).withValues(alpha: 0.8),
                  ],
                ),
                border: Border.all(
                  color: isRunning
                      ? const Color(0xFFE11D48).withValues(alpha: 0.6)
                      : const Color(0xFF000000),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: isRunning
                        ? const Color(0xFFE11D48).withValues(alpha: 0.4)
                        : Colors.black.withValues(alpha: 0.6),
                    blurRadius: isRunning ? 20 : 0,
                    spreadRadius: isRunning ? 0 : 0,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.05),
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '■ 紧急停止',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: isRunning
                        ? const Color(0xFFE11D48)
                        : const Color(0xFF6B7280),
                    shadows: isRunning
                        ? <Shadow>[
                            Shadow(
                              color: const Color(
                                0xFFE11D48,
                              ).withValues(alpha: 0.6),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AudioTranscodeListEntry {
  const _AudioTranscodeListEntry({required this.file, required this.result});

  final AudioTranscodeFileItem file;
  final AudioTranscodeResultItem? result;
}

class _BtnClearSm extends StatelessWidget {
  const _BtnClearSm({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(
            color: onTap == null
                ? const Color(0xFF6B7280).withValues(alpha: 0.5)
                : const Color(0xFF6B7280),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: onTap == null
                  ? const Color(0xFF6B7280).withValues(alpha: 0.5)
                  : const Color(0xFF6B7280),
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioTranscodeCheckbox extends StatelessWidget {
  const _AudioTranscodeCheckbox({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return HardwareCheckboxIndicator(
      value: value,
      size: 14,
      radius: 2,
      uncheckedFillColor: const Color(0xFF020202),
      checkedFillColor: const Color(0xFFE11D48),
      uncheckedBorderColor: Colors.white.withValues(alpha: 0.2),
      checkSize: 10,
      borderWidth: 1,
    );
  }
}

class _LcdStatusBar extends StatelessWidget {
  const _LcdStatusBar({required this.snapshot});
  final AudioTranscodeTaskSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final bool isRunning = snapshot.status == AudioTranscodeStatus.running;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF020202),
        borderRadius: BorderRadius.circular(6),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 1),
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.03),
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              _StatusDot(isRunning: isRunning),
              const SizedBox(width: 8),
              Text(
                snapshot.status.label,
                style: TextStyle(
                  color: isRunning
                      ? const Color(0xFF10B981)
                      : const Color(0xFF6B7280),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          _Divider(),
          const SizedBox(width: 16),
          Row(
            children: <Widget>[
              const Text(
                '目标:',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
              const SizedBox(width: 8),
              Text(
                '${snapshot.inputCount}',
                style: const TextStyle(
                  color: Color(0xFFD1D5DB),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          _Divider(),
          const SizedBox(width: 16),
          Row(
            children: <Widget>[
              const Text(
                '完成:',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
              const SizedBox(width: 8),
              Text(
                '${snapshot.successCount}',
                style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.isRunning});
  final bool isRunning;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isRunning ? const Color(0xFF10B981) : const Color(0xFFD97706),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color:
                (isRunning ? const Color(0xFF10B981) : const Color(0xFFD97706))
                    .withValues(alpha: 0.8),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      color: Colors.white.withValues(alpha: 0.05),
    );
  }
}
