import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide BoxDecoration, BoxShadow;
import 'package:flutter/services.dart';
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart';
import 'package:path/path.dart' as p;
import 'package:dj_flutter/app/dj_app_scope.dart';
import 'package:dj_flutter/app/router/app_router.dart';
import 'package:dj_flutter/shared/hardware_ui/hardware_ui.dart'
    show
        HardwareCheckboxIndicator,
        showHardwareMessageDialog,
        showHardwareDialog,
        HardwareDialog,
        HardwareDialogFooter,
        HardwareDialogAction,
        HardwareDialogActionVariant,
        HardwareDialogSectionCard,
        kHardwareDialogStandardWidth,
        kHardwareDialogWideWidth,
        kHardwareDialogReviewWidth;
import 'package:dj_flutter/shared/platform_utils.dart' as platform_utils;
import 'package:dj_flutter/shared/task_runtime/task_running_notifier.dart'
    show TaskRunningNotifier, TaskEndState;
import 'package:dj_flutter/shared/task_ui/task_file_outcome_tile.dart';
import 'package:dj_flutter/shared/task_ui/task_history_entry_card.dart';
import 'package:dj_flutter/shared/task_ui/task_import_list_shell.dart';
import 'package:dj_flutter/shared/task_ui/task_item_status_badge.dart';
import 'package:dj_flutter/shared/task_ui/task_result_filter.dart';

import '../../cleanup_dup/presentation/widgets/hardware_widgets.dart';
import 'controllers/pinyin_generator_controller.dart';
import 'controllers/python_pinyin_generator_task_bridge.dart';
import 'models/pinyin_generator_models.dart';

class PinyinGeneratorEntryPage extends StatefulWidget {
  const PinyinGeneratorEntryPage({
    super.key,
    this.controller,
    this.isFeatureLocked = false,
    this.onLockedStartPressed,
  });

  final PinyinGeneratorController? controller;
  final bool isFeatureLocked;
  final VoidCallback? onLockedStartPressed;

  @override
  State<PinyinGeneratorEntryPage> createState() =>
      _PinyinGeneratorEntryPageState();
}

class _PinyinGeneratorEntryPageState extends State<PinyinGeneratorEntryPage> {
  @visibleForTesting
  PinyinGeneratorController get debugController => _controller;

  static const MethodChannel _platformChannel = MethodChannel(
    'dj_flutter/unlock_music',
  );

  @visibleForTesting
  void debugSetShowOnlyFailures(bool value) {
    setState(() {
      _showOnlyFailures = value;
    });
  }

  @visibleForTesting
  void debugShowLastCompletedTaskDialog() {
    final PinyinGeneratorCompletedTaskRecord? record = _lastCompletedTask;
    if (record == null) {
      return;
    }
    _showHistoryTaskDialog(record);
  }

  PythonPinyinGeneratorTaskBridge? _bridge;
  late final PinyinGeneratorController _controller;
  late final TextEditingController _stopwordsController;
  TaskRunningNotifier? _taskRunningNotifier;
  bool _lastReportedRunning = false;
  bool _isDragging = false;
  bool _isShowingDialog = false;
  bool _showOnlyFailures = false;
  String? _completionDialogTaskId;
  PinyinGeneratorCompletedTaskRecord? _lastCompletedTask;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      final Directory projectRoot = _resolveProjectRoot();
      _bridge = PythonPinyinGeneratorTaskBridge(
        pythonExecutable: _resolvePythonExecutable(projectRoot),
        workingDirectory: p.join(projectRoot.path, 'runtime', 'dj_runtime_py'),
        scriptModule: 'dj_runtime_py',
      );
      _controller = PinyinGeneratorController(bridge: _bridge!);
    }
    _stopwordsController = TextEditingController(
      text: _controller.stopwordsText,
    )..addListener(_handleStopwordsChanged);
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _taskRunningNotifier = DjAppScope.maybeOf(context)?.taskRunningNotifier;
  }

  @override
  void dispose() {
    _stopwordsController
      ..removeListener(_handleStopwordsChanged)
      ..dispose();
    _controller.removeListener(_handleControllerChanged);
    if (_taskRunningNotifier != null && _lastReportedRunning) {
      _taskRunningNotifier!.setRunning(AppShellSection.pinyinGenerator, false);
    }
    _controller.close();
    super.dispose();
  }

  Directory _resolveProjectRoot() {
    return platform_utils.resolveProjectRoot();
  }

  String _resolvePythonExecutable(Directory projectRoot) {
    return platform_utils.resolvePythonExecutable(projectRoot);
  }

  void _handleStopwordsChanged() {
    if (_stopwordsController.text != _controller.stopwordsText) {
      _controller.updateStopwordsText(_stopwordsController.text);
    }
  }

  void _handleControllerChanged() {
    final PinyinGeneratorStatus status = _controller.snapshot.status;
    final bool isRunning = status == PinyinGeneratorStatus.running;
    if (_taskRunningNotifier == null) {
      return;
    }
    if (isRunning != _lastReportedRunning) {
      _taskRunningNotifier!.setRunning(
        AppShellSection.pinyinGenerator,
        isRunning,
      );
      _lastReportedRunning = isRunning;
    }
    if (!isRunning) {
      TaskEndState endState = TaskEndState.none;
      if (status == PinyinGeneratorStatus.success) {
        endState = TaskEndState.success;
      } else if (status == PinyinGeneratorStatus.error) {
        endState = TaskEndState.error;
      } else if (status == PinyinGeneratorStatus.cancelled) {
        endState = TaskEndState.aborted;
      }
      _taskRunningNotifier!.setEndState(
        AppShellSection.pinyinGenerator,
        endState,
      );
    }

    final String? toastMessage = _controller.toastMessage;
    if (mounted && toastMessage != null && toastMessage.isNotEmpty) {
      _controller.clearToast();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showMessageDialog(title: '导入提醒', message: toastMessage);
      });
    }

    final PinyinGeneratorTaskSnapshot snapshot = _controller.snapshot;
    _updateLastCompletedTask(snapshot);
    final bool completed =
        snapshot.status == PinyinGeneratorStatus.success ||
        snapshot.status == PinyinGeneratorStatus.cancelled ||
        snapshot.status == PinyinGeneratorStatus.error;
    if (!mounted || !completed || snapshot.taskId.isEmpty) {
      return;
    }
    if (_completionDialogTaskId == snapshot.taskId) {
      return;
    }
    _completionDialogTaskId = snapshot.taskId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showCompletionDialog();
    });
  }

  Future<void> _showMessageDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted || _isShowingDialog) {
      return;
    }
    _isShowingDialog = true;
    await showHardwareMessageDialog(
      context: context,
      title: title,
      message: message,
    );
    _isShowingDialog = false;
  }

  Future<void> _showCompletionDialog() async {
    if (!mounted || _isShowingDialog) {
      return;
    }
    final PinyinGeneratorTaskSnapshot snapshot = _controller.snapshot;
    final String outputSummary = _buildOutputLocationSummary();
    _isShowingDialog = true;
    final String title = switch (snapshot.status) {
      PinyinGeneratorStatus.success => '首拼生成已完成',
      PinyinGeneratorStatus.cancelled => '首拼生成已中止',
      PinyinGeneratorStatus.error => '首拼生成执行失败',
      _ => '首拼任务已结束',
    };
    final bool canReviewResults = _controller.results.isNotEmpty;
    final bool? showResults = await showHardwareDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return HardwareDialog(
          width: kHardwareDialogStandardWidth,
          title: title,
          titleIcon: const Icon(Icons.sort_by_alpha_rounded),
          onClose: () => Navigator.of(dialogContext).pop(false),
          hudTitle: 'Task Summary / 任务摘要',
          hudText: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('成功 ${snapshot.successCount} 首'),
              const SizedBox(height: 4),
              Text('失败 ${snapshot.failedCount} 首'),
              const SizedBox(height: 4),
              Text('跳过 ${snapshot.skippedCount} 首'),
              const SizedBox(height: 4),
              Text('输出位置：$outputSummary'),
              if (snapshot.hintText.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(snapshot.hintText),
              ],
              if (canReviewResults) ...<Widget>[
                const SizedBox(height: 8),
                const Text('是否立即查看首拼生成结果？'),
              ],
            ],
          ),
          body: const SizedBox.shrink(),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          footer: HardwareDialogFooter(
            actions: <Widget>[
              HardwareDialogAction(
                label: canReviewResults ? '稍后查看' : '知道了',
                variant: HardwareDialogActionVariant.danger,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              if (canReviewResults)
                HardwareDialogAction(
                  label: '查看首拼生成结果',
                  variant: HardwareDialogActionVariant.confirm,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
            ],
          ),
        );
      },
    );
    _isShowingDialog = false;
    if (showResults == true && mounted) {
      await _showResultsDialog();
    }
  }

  String _buildOutputLocationSummary() {
    final Set<String> directories = _controller.results
        .map((PinyinGeneratorResultItem item) => p.dirname(item.inputPath))
        .where((String value) => value.isNotEmpty)
        .toSet();
    if (directories.isEmpty) {
      return '原文件所在目录（就地写入专辑名）';
    }
    if (directories.length == 1) {
      return '${directories.first}（就地写入专辑名）';
    }
    return '原文件所在的 ${directories.length} 个目录（就地写入专辑名）';
  }

  Future<void> _showResultsDialog() async {
    if (!mounted || _controller.results.isEmpty) {
      return;
    }
    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return _PinyinResultDialog(
          successCount: _controller.snapshot.successCount,
          skippedCount: _controller.snapshot.skippedCount,
          failedCount: _controller.snapshot.failedCount,
          results: _controller.results,
        );
      },
    );
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
      await _showMessageDialog(title: '导入提醒', message: '无法打开文件选择器，请检查系统权限后重试。');
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
        const XTypeGroup(
          label: '音频文件',
          extensions: <String>[
            'mp3',
            'flac',
            'm4a',
            'ogg',
            'wma',
            'aiff',
            'aac',
            'wav',
          ],
        ),
      ],
      confirmButtonText: '导入',
    );
    return files
        .map((XFile file) => file.path)
        .where((String path) => path.isNotEmpty)
        .toList();
  }

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    final List<String> paths = files
        .map((XFile file) => file.path)
        .where((String path) => path.isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) {
      return;
    }
    await _controller.loadTargets(
      paths,
      append: _controller.loadedFiles.isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CleanupDupGridBackground(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: HardwarePanel(
                    watermark: '拼',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _buildHeader(),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Opacity(
                            opacity: widget.isFeatureLocked ? 0.5 : 1,
                            child: IgnorePointer(
                              ignoring: widget.isFeatureLocked,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  _buildConfigBlock(),
                                  const SizedBox(height: 8),
                                  Expanded(child: _buildImportList()),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildProgressAndControls(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    final bool isRunning =
        _controller.snapshot.status == PinyinGeneratorStatus.running;
    final Color statusColor = isRunning
        ? kEmerald
        : (_controller.snapshot.status == PinyinGeneratorStatus.error
              ? kCrimson
              : kAmber);
    final String statusLabel = isRunning
        ? '处理中'
        : _controller.snapshot.status.label;

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text('📝', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text(
                    '一键生成中文歌曲首拼写入专辑栏',
                    style: TextStyle(
                      color: kTextLightGray,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LcdStatusStrip(
                statusText: statusLabel,
                statusColor: statusColor,
                items: <Widget>[
                  _LcdItem(
                    label: '目标',
                    value: '${_controller.snapshot.inputCount}',
                  ),
                  _LcdItem(
                    label: '成功',
                    value: '${_controller.snapshot.successCount}',
                    valueColor: kEmerald,
                  ),
                  _LcdItem(
                    label: '跳过 (无中文)',
                    value: '${_controller.snapshot.skippedCount}',
                    valueColor: const Color(0xFF9CA3AF),
                  ),
                  _LcdItem(
                    label: '失败',
                    value: '${_controller.snapshot.failedCount}',
                    valueColor: kCrimson,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfigBlock() {
    final bool isRunning =
        _controller.snapshot.status == PinyinGeneratorStatus.running;
    final bool isInteractionLocked = isRunning || widget.isFeatureLocked;
    return Opacity(
      opacity: isInteractionLocked ? 0.6 : 1,
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
                blurRadius: 10,
                inset: true,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    const Text(
                      '写入模式:',
                      style: TextStyle(
                        color: kTextGray,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _HardwareRadio(
                      label: '覆盖原专辑',
                      value:
                          _controller.writeMode ==
                          PinyinGeneratorWriteMode.overwrite,
                      onChanged: () => _controller.updateWriteMode(
                        PinyinGeneratorWriteMode.overwrite,
                      ),
                    ),
                    const SizedBox(width: 20),
                    _HardwareRadio(
                      label: '追加到原专辑后',
                      value:
                          _controller.writeMode ==
                          PinyinGeneratorWriteMode.append,
                      onChanged: () => _controller.updateWriteMode(
                        PinyinGeneratorWriteMode.append,
                      ),
                    ),
                  ],
                ),
              ),
              _ClearButton(
                onPressed: _controller.clearTargets,
                enabled: !isRunning && _controller.loadedFiles.isNotEmpty,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressAndControls() {
    final bool showReview =
        _controller.snapshot.status == PinyinGeneratorStatus.success &&
        _controller.results.isNotEmpty;
    final bool showResume =
        _controller.snapshot.status == PinyinGeneratorStatus.cancelled;
    return Column(
      children: <Widget>[
        _ProgressWrapper(
          value: _controller.snapshot.progress,
          hintText: _controller.snapshot.hintText,
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            _GiantButton(
              label: showReview
                  ? '查看首拼生成结果'
                  : (showResume
                        ? '继续处理'
                        : (_controller.snapshot.status ==
                                  PinyinGeneratorStatus.running
                              ? '处理中'
                              : '开始处理')),
              isActive:
                  _controller.snapshot.status == PinyinGeneratorStatus.running,
              onPressed: showReview
                  ? _showResultsDialog
                  : (widget.isFeatureLocked
                        ? (widget.onLockedStartPressed ?? () {})
                        : _controller.startPinyinGeneratorTask),
              enabled:
                  showReview ||
                  widget.isFeatureLocked ||
                  _controller.canStartTask,
            ),
            const SizedBox(width: 16),
            _GiantButton(
              label: '紧急停止',
              isStop: true,
              onPressed: _controller.stopTask,
              enabled:
                  _controller.snapshot.status == PinyinGeneratorStatus.running,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImportList() {
    final bool hasFiles = _controller.loadedFiles.isNotEmpty;
    final bool isRunning =
        _controller.snapshot.status == PinyinGeneratorStatus.running;
    final bool isInteractionLocked = isRunning || widget.isFeatureLocked;
    return TaskImportListShell(
      hasItems: hasFiles,
      isDragging: _isDragging,
      isInteractionLocked: isInteractionLocked,
      disabledOpacity: isInteractionLocked ? 0.6 : 1,
      highlightWhenHasItems: false,
      onDragStateChanged: (bool value) {
        if (hasFiles || isRunning) {
          if (_isDragging) {
            setState(() => _isDragging = false);
          }
          return;
        }
        setState(() => _isDragging = value);
      },
      onDropDone: _handleDroppedFiles,
      onEmptyTap: !hasFiles ? _pickFiles : null,
      header: hasFiles ? _buildImportListHeader() : null,
      emptyBuilder: (BuildContext context, bool isDragging) {
        return _buildEmptyImportState(isDragging);
      },
      contentBuilder: (BuildContext context) => _buildImportItems(),
      idleBorderColorWhenEmpty: Colors.white.withValues(alpha: 0.05),
      idleBorderColorWhenFilled: Colors.white.withValues(alpha: 0.05),
      dragActiveBorderColor: kCrimson.withValues(alpha: 0.8),
      idleShadowColor: Colors.black.withValues(alpha: 0.98),
      dragShadowColor: kCrimson.withValues(alpha: 0.2),
    );
  }

  Widget _buildImportListHeader() {
    final bool isRunning =
        _controller.snapshot.status == PinyinGeneratorStatus.running;
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
            _ClearButtonLikeAction(
              label: '追加目标 (文件/目录)',
              onPressed: isRunning ? null : _showAppendTargetPicker,
            ),
          const Spacer(),
          GestureDetector(
            key: const ValueKey<String>('pinyin_generator_fail_filter_toggle'),
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
                _PinyinFilterCheckbox(value: _showOnlyFailures),
                const SizedBox(width: 8),
                Text(
                  '仅看失败项',
                  style: TextStyle(
                    color: isRunning ? kTextGray : kTextGray,
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

  Future<void> _showAppendTargetPicker() async {
    await _pickFiles();
  }

  Widget _buildEmptyImportState(bool isDragging) {
    final Color accent = isDragging ? kCrimson : const Color(0xFF4B5563);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text('🗂️', style: TextStyle(fontSize: 28, color: accent)),
          const SizedBox(height: 8),
          Text(
            isDragging ? '松开导入文件或文件夹' : '点击选择或拖入文件文件夹',
            style: TextStyle(
              color: accent,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportItems() {
    final Map<String, PinyinGeneratorResultItem> resultMap =
        <String, PinyinGeneratorResultItem>{
          for (final PinyinGeneratorResultItem item in _controller.results)
            item.inputPath: item,
        };
    final List<_PinyinListEntry> entries = _controller.loadedFiles
        .map(
          (PinyinGeneratorFileItem file) =>
              _PinyinListEntry(file: file, result: resultMap[file.path]),
        )
        .toList(growable: false);
    final List<_PinyinListEntry> visibleEntries =
        filterTaskResults<_PinyinListEntry>(
          entries,
          filter: _showOnlyFailures
              ? TaskResultFilter.failureOnly
              : TaskResultFilter.all,
          isSuccess: (_PinyinListEntry entry) =>
              entry.result?.status == PinyinGeneratorItemStatus.success,
          isFailure: (_PinyinListEntry entry) =>
              entry.result?.status == PinyinGeneratorItemStatus.failed,
        );
    if (visibleEntries.isEmpty && _lastCompletedTask == null) {
      return const Center(
        child: Text('当前过滤条件下没有结果。', style: TextStyle(color: kTextGray)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: visibleEntries.length + (_lastCompletedTask == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final PinyinGeneratorCompletedTaskRecord? lastCompletedTask =
            _lastCompletedTask;
        if (lastCompletedTask != null && index == 0) {
          return _buildHistoryTaskEntry(lastCompletedTask);
        }
        final int entryIndex = index - (lastCompletedTask == null ? 0 : 1);
        final _PinyinListEntry entry = visibleEntries[entryIndex];
        return _buildImportItem(entry);
      },
    );
  }

  Widget _buildImportItem(_PinyinListEntry entry) {
    final PinyinGeneratorResultItem? result = entry.result;
    final bool isRunning =
        _controller.snapshot.status == PinyinGeneratorStatus.running;
    final String secondaryText = switch (result?.status) {
      PinyinGeneratorItemStatus.success =>
        '首拼生成：${result?.generatedInitials ?? '-'}',
      PinyinGeneratorItemStatus.skipped => result?.message ?? '标题不含中文，已跳过。',
      PinyinGeneratorItemStatus.failed => result?.message ?? '执行失败。',
      null => '等待处理...',
    };
    final Color secondaryTextColor = switch (result?.status) {
      PinyinGeneratorItemStatus.success => kEmerald,
      PinyinGeneratorItemStatus.skipped => const Color(0xFF9CA3AF),
      PinyinGeneratorItemStatus.failed => kCrimson,
      null => kTextGray,
    };
    return TaskFileOutcomeTile(
      leading: Text(
        switch (result?.status) {
          PinyinGeneratorItemStatus.success => '✓',
          PinyinGeneratorItemStatus.skipped => '⏭',
          PinyinGeneratorItemStatus.failed => '✕',
          null => '🎵',
        },
        style: TextStyle(
          fontSize: 16,
          color: switch (result?.status) {
            PinyinGeneratorItemStatus.success => kEmerald,
            PinyinGeneratorItemStatus.skipped => const Color(0xFF9CA3AF),
            PinyinGeneratorItemStatus.failed => kCrimson,
            null => kTextGray,
          },
        ),
      ),
      title: entry.file.name,
      secondaryText: secondaryText,
      secondaryTextColor: secondaryTextColor,
      pathLabel: '位置：',
      pathText: entry.file.path,
      errorText: result?.status == PinyinGeneratorItemStatus.failed
          ? result?.message
          : null,
      trailing: _buildStatusBadge(entry),
      trailingAfter: isRunning
          ? const SizedBox(width: 20)
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _controller.removeTarget(entry.file.path),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: Text(
                  '×',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kTextGray, fontSize: 16),
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
          color: result?.status == PinyinGeneratorItemStatus.failed
              ? kCrimson.withValues(alpha: 0.3)
              : (result?.status == PinyinGeneratorItemStatus.success
                    ? kEmerald.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.03)),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _buildStatusBadge(_PinyinListEntry entry) {
    final PinyinGeneratorResultItem? result = entry.result;
    final String label;
    final Color foreground;
    final Color background;
    final Color border;
    switch (result?.status) {
      case PinyinGeneratorItemStatus.success:
        label = '✓ 写入：${result?.generatedInitials ?? '-'}';
        foreground = kEmerald;
        background = kEmerald.withValues(alpha: 0.1);
        border = kEmerald.withValues(alpha: 0.3);
        break;
      case PinyinGeneratorItemStatus.skipped:
        label = '⏭ 跳过';
        foreground = const Color(0xFF9CA3AF);
        background = const Color(0xFF9CA3AF).withValues(alpha: 0.08);
        border = const Color(0xFF9CA3AF).withValues(alpha: 0.2);
        break;
      case PinyinGeneratorItemStatus.failed:
        label = '✕ 失败';
        foreground = kCrimson;
        background = kCrimson.withValues(alpha: 0.1);
        border = kCrimson.withValues(alpha: 0.3);
        break;
      case null:
        label = _controller.snapshot.status == PinyinGeneratorStatus.running
            ? '⏳ 处理中'
            : '⏳ 待处理';
        foreground = kTextGray;
        background = Colors.white.withValues(alpha: 0.05);
        border = Colors.white.withValues(alpha: 0.1);
        break;
    }
    return TaskItemStatusBadge(
      label: label,
      foreground: foreground,
      background: background,
      border: border,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.6,
    );
  }

  void _updateLastCompletedTask(PinyinGeneratorTaskSnapshot snapshot) {
    if (snapshot.taskId.isEmpty) {
      return;
    }
    if (snapshot.status != PinyinGeneratorStatus.success &&
        snapshot.status != PinyinGeneratorStatus.cancelled &&
        snapshot.status != PinyinGeneratorStatus.error) {
      return;
    }
    _lastCompletedTask = PinyinGeneratorCompletedTaskRecord(
      taskId: snapshot.taskId,
      status: snapshot.status,
      finishedAt: DateTime.now(),
      inputFiles: List<PinyinGeneratorFileItem>.from(_controller.loadedFiles),
      successCount: snapshot.successCount,
      skippedCount: snapshot.skippedCount,
      failedCount: snapshot.failedCount,
      results: List<PinyinGeneratorResultItem>.from(_controller.results),
      message: snapshot.hintText,
      locationSummary: _buildOutputLocationSummary(),
    );
  }

  String _formatHistoryTimestamp(DateTime time) {
    String twoDigit(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${twoDigit(time.month)}-${twoDigit(time.day)} ${twoDigit(time.hour)}:${twoDigit(time.minute)}:${twoDigit(time.second)}';
  }

  String _historyStatusText(PinyinGeneratorCompletedTaskRecord record) {
    return switch (record.status) {
      PinyinGeneratorStatus.success =>
        record.failedCount > 0
            ? '完成但有失败项'
            : (record.skippedCount > 0 ? '完成，含跳过项' : '全部完成'),
      PinyinGeneratorStatus.cancelled => '已中止',
      PinyinGeneratorStatus.error => '执行失败',
      _ => '任务结束',
    };
  }

  Color _historyAccentColor(PinyinGeneratorCompletedTaskRecord record) {
    if (record.status == PinyinGeneratorStatus.cancelled) {
      return kAmber;
    }
    if (record.status == PinyinGeneratorStatus.error || record.hasFailures) {
      return kCrimson;
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

  Widget _buildHistoryTaskEntry(PinyinGeneratorCompletedTaskRecord record) {
    return TaskHistoryEntryCard(
      key: const ValueKey<String>('pinyin_generator_history_entry'),
      title: '最近一次完成任务',
      summaryText:
          '共 ${record.inputFiles.length} 项 · 成功 ${record.successCount} · 跳过 ${record.skippedCount} · 失败 ${record.failedCount}',
      metaText:
          '${_historyStatusText(record)} · ${_formatHistoryTimestamp(record.finishedAt)} · ${record.locationSummary}',
      accentColor: _historyAccentColor(record),
      pulseValue: 0.3,
      badgeLabel: '查看结果',
      onTap: () => _showHistoryTaskDialog(record),
      onClear: _clearHistoryTask,
      clearKey: const ValueKey<String>('pinyin_generator_history_clear'),
    );
  }

  Future<void> _showHistoryTaskDialog(
    PinyinGeneratorCompletedTaskRecord record,
  ) async {
    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final Color accentColor = _historyAccentColor(record);
        TaskResultFilter filter = TaskResultFilter.all;
        return StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setState) {
            final List<PinyinGeneratorResultItem> visibleItems =
                filterTaskResults<PinyinGeneratorResultItem>(
                  record.results,
                  filter: filter,
                  isSuccess: (PinyinGeneratorResultItem item) =>
                      item.status == PinyinGeneratorItemStatus.success,
                  isFailure: (PinyinGeneratorResultItem item) =>
                      item.status == PinyinGeneratorItemStatus.failed,
                );
            return HardwareDialog(
              width: kHardwareDialogWideWidth,
              title: '最近一次完成任务',
              titleIcon: Icon(Icons.history_rounded, color: accentColor),
              onClose: () => Navigator.of(dialogContext).pop(),
              hudTitle: 'Task History / 任务记录',
              hudText: Text(
                '${_historyStatusText(record)} · ${_formatHistoryTimestamp(record.finishedAt)}\n共 ${record.inputFiles.length} 项，成功 ${record.successCount}，跳过 ${record.skippedCount}，失败 ${record.failedCount}\n输出位置：${record.locationSummary}${(record.message ?? '').isNotEmpty ? '\n状态说明：${record.message}' : ''}',
                style: TextStyle(
                  height: 1.6,
                  color: record.hasFailures ? kCrimson : kTextLightGray,
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
                      _ClearButtonLikeAction(
                        label: '全部结果',
                        onPressed: () {
                          setState(() {
                            filter = TaskResultFilter.all;
                          });
                        },
                      ),
                      _ClearButtonLikeAction(
                        label: '仅成功项',
                        onPressed: () {
                          setState(() {
                            filter = TaskResultFilter.successOnly;
                          });
                        },
                      ),
                      _ClearButtonLikeAction(
                        label: '仅失败项',
                        onPressed: () {
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
                      style: TextStyle(color: kTextGray),
                    )
                  else
                    ...visibleItems.map((PinyinGeneratorResultItem item) {
                      final Color color = switch (item.status) {
                        PinyinGeneratorItemStatus.success => kEmerald,
                        PinyinGeneratorItemStatus.skipped => kAmber,
                        PinyinGeneratorItemStatus.failed => kCrimson,
                      };
                      final String text = switch (item.status) {
                        PinyinGeneratorItemStatus.success =>
                          '${item.inputName} -> ${item.generatedInitials ?? '-'}',
                        PinyinGeneratorItemStatus.skipped =>
                          '${item.inputName} -> ${item.message}',
                        PinyinGeneratorItemStatus.failed =>
                          '${item.inputName} -> ${item.message}',
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: HardwareDialogSectionCard(
                          child: Text(
                            text,
                            style: TextStyle(color: color, fontSize: 12),
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
}

class _LcdItem extends StatelessWidget {
  const _LcdItem({
    required this.label,
    required this.value,
    this.valueColor = kTextLightGray,
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
            fontFamily: 'monospace',
            fontSize: 12,
            color: kTextGray,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _HardwareRadio extends StatelessWidget {
  const _HardwareRadio({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: kHardwareBlack,
              shape: BoxShape.circle,
              border: Border.all(
                color: value
                    ? kCrimson.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.8),
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                  inset: true,
                ),
              ],
            ),
            child: value
                ? Center(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: kCrimson,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: kCrimson.withValues(alpha: 0.8),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: value ? kCrimson : kTextGray,
              fontSize: 13,
              fontWeight: value ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onPressed, required this.enabled});

  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF1E1E23).withValues(alpha: 0.6)
              : const Color(0xFF1E1E23).withValues(alpha: 0.3),
          border: Border.all(
            color: enabled
                ? kCrimson.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.05),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              offset: const Offset(0, 4),
              blurRadius: 6,
            ),
            if (enabled)
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.03),
                offset: const Offset(0, 1),
              ),
          ],
        ),
        child: Center(
          child: Text(
            '清空列表',
            style: TextStyle(
              color: enabled
                  ? kTextLightGray
                  : kTextGray.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressWrapper extends StatelessWidget {
  const _ProgressWrapper({required this.value, required this.hintText});

  final double value;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final double progress = value > 1 ? (value / 100).clamp(0.0, 1.0) : value;
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              hintText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: kTextGray,
                letterSpacing: 1,
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: kCrimson,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ProgressTrack(progress: progress),
      ],
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double safeProgress = progress.clamp(0, 1);
        return Container(
          height: 10,
          decoration: BoxDecoration(
            color: kHardwareBlack,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.black.withValues(alpha: 0.8)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.9),
                offset: const Offset(0, 2),
                blurRadius: 6,
                inset: true,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.05),
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: constraints.maxWidth * safeProgress,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    gradient: const LinearGradient(
                      colors: <Color>[
                        Color(0xFF4C0519),
                        Color(0xFFBE123C),
                        Color(0xFFFB7185),
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: kCrimson.withValues(alpha: 0.6),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: safeProgress <= 0
                      ? null
                      : Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            width: 15,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: <Color>[
                                  Colors.transparent,
                                  Colors.white.withValues(alpha: 0.8),
                                ],
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  blurRadius: 15,
                                  spreadRadius: 3,
                                ),
                                BoxShadow(
                                  color: kCrimson.withValues(alpha: 0.8),
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
                child: CustomPaint(painter: _ProgressSegmentsPainter()),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressSegmentsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GiantButton extends StatelessWidget {
  const _GiantButton({
    required this.label,
    this.isActive = false,
    this.isStop = false,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final bool isActive;
  final bool isStop;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color baseColor = isStop ? kCrimson : kEmerald;
    return Expanded(
      flex: isStop ? 1 : 3,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                const Color(0xFF1E1E23).withValues(alpha: 0.6),
                const Color(0xFF0F0F12).withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.9),
              width: 1,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                offset: const Offset(0, 6),
                blurRadius: 12,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.05),
                offset: const Offset(0, 1),
              ),
              if (isActive || isStop)
                BoxShadow(
                  color: baseColor.withValues(alpha: 0.15),
                  blurRadius: 15,
                ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    color: enabled
                        ? (isActive || isStop ? baseColor : kTextLightGray)
                        : kTextGray.withValues(alpha: 0.5),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinyinListEntry {
  const _PinyinListEntry({required this.file, required this.result});

  final PinyinGeneratorFileItem file;
  final PinyinGeneratorResultItem? result;
}

class _ClearButtonLikeAction extends StatelessWidget {
  const _ClearButtonLikeAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF1E1E23).withValues(alpha: 0.6)
              : const Color(0xFF1E1E23).withValues(alpha: 0.3),
          border: Border.all(
            color: enabled
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.05),
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              offset: const Offset(0, 4),
              blurRadius: 6,
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: enabled
                  ? kTextLightGray
                  : kTextGray.withValues(alpha: 0.5),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _PinyinFilterCheckbox extends StatelessWidget {
  const _PinyinFilterCheckbox({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return HardwareCheckboxIndicator(
      value: value,
      size: 14,
      radius: 3,
      uncheckedFillColor: Colors.transparent,
      checkedFillColor: kCrimson.withValues(alpha: 0.16),
      checkedBorderColor: kCrimson.withValues(alpha: 0.7),
      uncheckedBorderColor: kTextGray,
      checkColor: kCrimson,
      checkSize: 10,
      borderWidth: 1,
    );
  }
}

class _PinyinResultDialog extends StatelessWidget {
  const _PinyinResultDialog({
    required this.successCount,
    required this.skippedCount,
    required this.failedCount,
    required this.results,
  });

  final int successCount;
  final int skippedCount;
  final int failedCount;
  final List<PinyinGeneratorResultItem> results;

  @override
  Widget build(BuildContext context) {
    return HardwareDialog(
      width: kHardwareDialogReviewWidth,
      maxHeight: 760,
      scrollable: true,
      title: '首拼生成结果审阅',
      titleIcon: const Icon(Icons.fact_check_rounded),
      onClose: () => Navigator.of(context).pop(),
      hudTitle: 'Task Review / 结果审阅',
      hudText: Text(
        '成功 $successCount / 跳过 $skippedCount / 失败 $failedCount',
        style: const TextStyle(height: 1.6),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: results.asMap().entries.map((entry) {
          final int index = entry.key;
          final PinyinGeneratorResultItem item = entry.value;
          final Color badgeColor = switch (item.status) {
            PinyinGeneratorItemStatus.success => kEmerald,
            PinyinGeneratorItemStatus.skipped => kAmber,
            PinyinGeneratorItemStatus.failed => kCrimson,
          };
          final String badgeText = switch (item.status) {
            PinyinGeneratorItemStatus.success =>
              item.generatedInitials == null
                  ? 'SUCCESS'
                  : 'SUCCESS ${item.generatedInitials}',
            PinyinGeneratorItemStatus.skipped => 'SKIP',
            PinyinGeneratorItemStatus.failed => 'FAIL',
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HardwareDialogSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '#${index + 1}: ${item.inputName}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFF3F4F6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: badgeColor.withValues(alpha: 0.14),
                          border: Border.all(
                            color: badgeColor.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 12,
                            color: badgeColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '文件名来源：${item.sourceTitle}',
                    style: const TextStyle(fontSize: 12, color: kTextLightGray),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '专辑名: ${item.albumBefore ?? '<空>'} -> ${item.albumAfter ?? '<空>'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: kTextLightGray,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.message,
                    style: const TextStyle(
                      fontSize: 12,
                      color: kTextLightGray,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.inputPath,
                    style: const TextStyle(
                      fontSize: 11,
                      color: kTextGray,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
      footer: HardwareDialogFooter(
        actions: <Widget>[
          HardwareDialogAction(
            label: '关闭并返回',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
