import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dj_flutter/shared/task_ui/task_file_outcome_tile.dart';
import 'package:dj_flutter/shared/task_ui/task_history_entry_card.dart';
import 'package:dj_flutter/shared/task_ui/task_import_list_shell.dart';
import 'package:dj_flutter/shared/task_ui/task_item_status_badge.dart';
import 'package:dj_flutter/shared/task_ui/task_result_filter.dart';

import '../controllers/metadata_edit_controller.dart';
import '../models/metadata_edit_models.dart';
import 'hardware_widgets.dart';

class CoverInjectionPanel extends StatefulWidget {
  const CoverInjectionPanel({
    super.key,
    required this.controller,
    this.isFeatureLocked = false,
    this.onLockedStartPressed,
  });

  final MetadataEditController controller;
  final bool isFeatureLocked;
  final VoidCallback? onLockedStartPressed;

  @override
  State<CoverInjectionPanel> createState() => _CoverInjectionPanelState();
}

class _CoverInjectionPanelState extends State<CoverInjectionPanel> {
  static const MethodChannel _platformChannel = MethodChannel(
    'dj_flutter/unlock_music',
  );
  static const List<String> _supportedExtensions = <String>[
    'mp3',
    'flac',
    'm4a',
    'aac',
    'ogg',
    'wma',
    'aiff',
  ];

  @visibleForTesting
  void debugSetShowOnlyFailures(bool value) {
    setState(() {
      _showOnlyFailures = value;
    });
  }

  @visibleForTesting
  void debugShowLastCompletedTaskDialog() {
    final MetadataEditCompletedTaskRecord? record = _lastCompletedTask;
    if (record == null) {
      return;
    }
    _showHistoryTaskDialog(record);
  }

  bool _isDragging = false;
  bool _showOnlyFailures = false;
  MetadataEditCompletedTaskRecord? _lastCompletedTask;

  MetadataEditController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _captureCompletedTask();
  }

  @override
  void didUpdateWidget(covariant CoverInjectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _captureCompletedTask();
  }

  @override
  Widget build(BuildContext context) {
    final MetadataEditTaskSnapshot snapshot = controller.coverSnapshot;
    final bool showReview =
        controller.coverResults.isNotEmpty &&
        (snapshot.status == MetadataEditStatus.success ||
            snapshot.status == MetadataEditStatus.error);
    final bool coverReady = controller.coverImagePath != null;
    final bool keepPrompting =
        controller.coverConfigLocked &&
        snapshot.status != MetadataEditStatus.running &&
        !showReview;

    return HardwarePanel(
      watermark: '图',
      headerTitle: '🖼️ 批量封面图注入',
      headerAction: TextButton(
        onPressed: () => controller.clearPanel(MetadataEditPanelKind.cover),
        style: TextButton.styleFrom(
          foregroundColor: Colors.grey[700],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          minimumSize: const Size(0, 28),
        ),
        child: const Text('清空列表', style: TextStyle(fontSize: 12)),
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: Opacity(
              opacity: widget.isFeatureLocked ? 0.5 : 1,
              child: IgnorePointer(
                ignoring: widget.isFeatureLocked,
                child: Column(
                  children: <Widget>[
                    HardwareLcdStatusStrip(
                      items: <Widget>[
                        _buildStatusDot(snapshot.status),
                        const SizedBox(width: 16),
                        HardwareLcdItem(
                          label: '目标数量',
                          value: '${controller.coverFiles.length}',
                        ),
                        const SizedBox(width: 16),
                        HardwareLcdItem(
                          label: '封面状态',
                          value: coverReady ? '已就绪' : '未选择',
                          valueColor: coverReady ? kEmerald : kCrimson,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildCoverConfigRow(context, coverReady),
                    const SizedBox(height: 12),
                    Expanded(child: _buildImportList(snapshot)),
                    const SizedBox(height: 12),
                    HardwareProgressBar(
                      value: snapshot.progress <= 1
                          ? snapshot.progress
                          : snapshot.progress / 100,
                      hintText: snapshot.hintText,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: HardwareGiantButton(
                  onPressed: showReview
                      ? () => _showResults(context)
                      : (widget.isFeatureLocked
                            ? (widget.onLockedStartPressed ?? () {})
                            : () => controller.startTask(
                                MetadataEditPanelKind.cover,
                              )),
                  label: showReview ? '🔍 查看注入结果' : '开始注入',
                  variant: showReview
                      ? HardwareGiantButtonVariant.review
                      : HardwareGiantButtonVariant.start,
                  flashSignal: controller.coverStartFlashSignal,
                  keepFlashing: keepPrompting,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: HardwareGiantButton(
                  onPressed: widget.isFeatureLocked
                      ? null
                      : (snapshot.status == MetadataEditStatus.running
                            ? () => controller.stopTask(
                                MetadataEditPanelKind.cover,
                              )
                            : null),
                  label: '紧急停止',
                  variant: HardwareGiantButtonVariant.stop,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDot(MetadataEditStatus status) {
    final Color color = switch (status) {
      MetadataEditStatus.running => kEmerald,
      MetadataEditStatus.success => kEmerald,
      MetadataEditStatus.cancelled => kCrimson,
      MetadataEditStatus.error => kCrimson,
      _ => kAmber,
    };
    final String label = switch (status) {
      MetadataEditStatus.running => '处理中',
      MetadataEditStatus.success => '完成',
      MetadataEditStatus.cancelled => '已取消',
      MetadataEditStatus.error => '错误',
      _ => '待命',
    };
    return Row(
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: <BoxShadow>[
              BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: color),
        ),
      ],
    );
  }

  Widget _buildCoverConfigRow(BuildContext context, bool coverReady) {
    return Row(
      children: <Widget>[
        const Text('封面图片:', style: TextStyle(fontSize: 13, color: kTextGray)),
        const SizedBox(width: 8),
        DropTarget(
          onDragDone: (DropDoneDetails details) async {
            final String? imagePath = await _firstAcceptedImagePath(
              details.files,
            );
            if (imagePath != null) {
              controller.updateCoverImagePath(imagePath);
            }
          },
          child: GestureDetector(
            onTap: () => _pickCoverImage(context),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kHardwareBlack,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: coverReady
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(controller.coverImagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _CoverPlaceholder(),
                      ),
                    )
                  : const _CoverPlaceholder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: HardwareInput(
            controller: TextEditingController(
              text: controller.coverImagePath ?? '',
            ),
            placeholder: '未选择图片...',
            readOnly: true,
            onTap: () => _pickCoverImage(context),
          ),
        ),
        const SizedBox(width: 8),
        HardwareConfirmButton(
          confirmed: controller.coverConfigLocked,
          onPressed: () =>
              controller.lockPanelConfig(MetadataEditPanelKind.cover),
        ),
      ],
    );
  }

  Widget _buildImportList(MetadataEditTaskSnapshot snapshot) {
    final bool hasItems = controller.coverFiles.isNotEmpty;
    final bool isRunning = snapshot.status == MetadataEditStatus.running;
    return TaskImportListShell(
      hasItems: hasItems,
      isDragging: _isDragging,
      isInteractionLocked: isRunning,
      disabledOpacity: isRunning ? 0.65 : 1,
      highlightWhenHasItems: false,
      onDragStateChanged: (bool value) {
        if (hasItems || isRunning) {
          if (_isDragging) {
            setState(() {
              _isDragging = false;
            });
          }
          return;
        }
        setState(() {
          _isDragging = value;
        });
      },
      onDropDone: _handleDroppedFiles,
      onEmptyTap: hasItems ? null : _pickTargets,
      header: hasItems ? _buildImportListHeader(isRunning) : null,
      emptyBuilder: (BuildContext context, bool isDragging) {
        return _buildEmptyImportState(isDragging);
      },
      contentBuilder: (BuildContext context) => _buildImportItems(snapshot),
      idleBorderColorWhenEmpty: Colors.white.withValues(alpha: 0.05),
      idleBorderColorWhenFilled: Colors.white.withValues(alpha: 0.05),
      dragActiveBorderColor: kCrimson.withValues(alpha: 0.8),
      idleShadowColor: Colors.black.withValues(alpha: 0.98),
      dragShadowColor: kCrimson.withValues(alpha: 0.2),
    );
  }

  Widget _buildImportListHeader(bool isRunning) {
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
          _MetadataPanelAction(
            label: '追加目标 (文件/目录)',
            onPressed: isRunning ? null : _pickTargets,
          ),
          const Spacer(),
          GestureDetector(
            key: const ValueKey<String>('metadata_cover_fail_filter_toggle'),
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
                _MetadataFailureCheckbox(value: _showOnlyFailures),
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

  Widget _buildEmptyImportState(bool isDragging) {
    final Color accent = isDragging ? kCrimson : const Color(0xFF4B5563);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('🗂️', style: TextStyle(fontSize: 28, color: accent)),
        const SizedBox(height: 8),
        Text(
          isDragging ? '松开导入文件或文件夹' : '点击选择或拖入文件文件夹',
          style: TextStyle(
            color: accent,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildImportItems(MetadataEditTaskSnapshot snapshot) {
    final List<_CoverListEntry> entries = controller.coverFiles
        .map(
          (MetadataEditFileItem file) => _CoverListEntry(
            file: file,
            result: _findResultForFile(file, controller.coverResults),
          ),
        )
        .toList(growable: false);
    final List<_CoverListEntry> visibleEntries =
        filterTaskResults<_CoverListEntry>(
          entries,
          filter: _showOnlyFailures
              ? TaskResultFilter.failureOnly
              : TaskResultFilter.all,
          isSuccess: (_CoverListEntry entry) =>
              entry.result?.status == MetadataEditItemStatus.ok,
          isFailure: (_CoverListEntry entry) =>
              entry.result?.status == MetadataEditItemStatus.fail,
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
        final MetadataEditCompletedTaskRecord? lastCompletedTask =
            _lastCompletedTask;
        if (lastCompletedTask != null && index == 0) {
          return _buildHistoryTaskEntry(lastCompletedTask);
        }
        final int entryIndex = index - (lastCompletedTask == null ? 0 : 1);
        return _buildImportItem(visibleEntries[entryIndex], snapshot);
      },
    );
  }

  Widget _buildImportItem(
    _CoverListEntry entry,
    MetadataEditTaskSnapshot snapshot,
  ) {
    final MetadataEditResultItem? result = entry.result;
    final bool isRunning = snapshot.status == MetadataEditStatus.running;
    final String secondaryText = switch (result?.status) {
      MetadataEditItemStatus.ok => result?.message ?? '处理成功。',
      MetadataEditItemStatus.skip => result?.message ?? '已跳过。',
      MetadataEditItemStatus.need => result?.message ?? '需先转码后再处理。',
      MetadataEditItemStatus.fail => result?.message ?? '执行失败。',
      null => isRunning ? '处理中...' : '等待处理...',
    };
    final Color secondaryColor = switch (result?.status) {
      MetadataEditItemStatus.ok => kEmerald,
      MetadataEditItemStatus.skip => const Color(0xFF9CA3AF),
      MetadataEditItemStatus.need => kAmber,
      MetadataEditItemStatus.fail => kCrimson,
      null => kTextGray,
    };
    final Color borderColor = switch (result?.status) {
      MetadataEditItemStatus.ok => kEmerald.withValues(alpha: 0.3),
      MetadataEditItemStatus.need => kAmber.withValues(alpha: 0.3),
      MetadataEditItemStatus.fail => kCrimson.withValues(alpha: 0.3),
      _ => Colors.white.withValues(alpha: 0.03),
    };
    return TaskFileOutcomeTile(
      leading: Text(
        switch (result?.status) {
          MetadataEditItemStatus.ok => '✓',
          MetadataEditItemStatus.skip => '⏭',
          MetadataEditItemStatus.need => '!',
          MetadataEditItemStatus.fail => '✕',
          null => '🎵',
        },
        style: TextStyle(
          fontSize: 16,
          color: switch (result?.status) {
            MetadataEditItemStatus.ok => kEmerald,
            MetadataEditItemStatus.skip => const Color(0xFF9CA3AF),
            MetadataEditItemStatus.need => kAmber,
            MetadataEditItemStatus.fail => kCrimson,
            null => kTextGray,
          },
        ),
      ),
      title: entry.file.name,
      secondaryText: secondaryText,
      secondaryTextColor: secondaryColor,
      pathLabel: '位置：',
      pathText: entry.file.path,
      errorText: result?.status == MetadataEditItemStatus.fail
          ? result?.message
          : null,
      trailing: _buildStatusBadge(entry, snapshot),
      trailingAfter: isRunning
          ? const SizedBox(width: 20)
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.removeTarget(
                MetadataEditPanelKind.cover,
                entry.file.path,
              ),
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
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _buildStatusBadge(
    _CoverListEntry entry,
    MetadataEditTaskSnapshot snapshot,
  ) {
    final MetadataEditResultItem? result = entry.result;
    final String label;
    final Color foreground;
    final Color background;
    final Color border;
    switch (result?.status) {
      case MetadataEditItemStatus.ok:
        label = '✓ 成功';
        foreground = kEmerald;
        background = kEmerald.withValues(alpha: 0.1);
        border = kEmerald.withValues(alpha: 0.3);
        break;
      case MetadataEditItemStatus.skip:
        label = '⏭ 跳过';
        foreground = const Color(0xFF9CA3AF);
        background = const Color(0xFF9CA3AF).withValues(alpha: 0.08);
        border = const Color(0xFF9CA3AF).withValues(alpha: 0.2);
        break;
      case MetadataEditItemStatus.need:
        label = '! 需转码';
        foreground = kAmber;
        background = kAmber.withValues(alpha: 0.08);
        border = kAmber.withValues(alpha: 0.24);
        break;
      case MetadataEditItemStatus.fail:
        label = '✕ 失败';
        foreground = kCrimson;
        background = kCrimson.withValues(alpha: 0.1);
        border = kCrimson.withValues(alpha: 0.3);
        break;
      case null:
        label = snapshot.status == MetadataEditStatus.running
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

  void _captureCompletedTask() {
    final MetadataEditTaskSnapshot snapshot = controller.coverSnapshot;
    if (!_isCompletedStatus(snapshot.status) || snapshot.taskId.isEmpty) {
      return;
    }
    if (_lastCompletedTask?.taskId == snapshot.taskId) {
      return;
    }
    _lastCompletedTask = MetadataEditCompletedTaskRecord(
      panel: MetadataEditPanelKind.cover,
      taskId: snapshot.taskId,
      status: snapshot.status,
      finishedAt: DateTime.now(),
      inputFiles: List<MetadataEditFileItem>.from(controller.coverFiles),
      successCount: snapshot.successCount,
      skippedCount: snapshot.skippedCount,
      needCount: snapshot.needCount,
      failedCount: snapshot.failedCount,
      results: List<MetadataEditResultItem>.from(controller.coverResults),
      message: snapshot.hintText,
    );
  }

  Widget _buildHistoryTaskEntry(MetadataEditCompletedTaskRecord record) {
    return TaskHistoryEntryCard(
      key: const ValueKey<String>('metadata_cover_history_entry'),
      title: '最近一次完成任务',
      summaryText:
          '共 ${record.inputFiles.length} 项 · 成功 ${record.successCount} · 跳过 ${record.skippedCount} · 需转码 ${record.needCount} · 失败 ${record.failedCount}',
      metaText:
          '${_historyStatusText(record)} · ${_formatTimestamp(record.finishedAt)}',
      accentColor: _historyAccentColor(record),
      pulseValue: 0.28,
      badgeLabel: '查看结果',
      onTap: () => _showHistoryTaskDialog(record),
      onClear: () {
        setState(() {
          _lastCompletedTask = null;
        });
      },
      clearKey: const ValueKey<String>('metadata_cover_history_clear'),
    );
  }

  String _historyStatusText(MetadataEditCompletedTaskRecord record) {
    return switch (record.status) {
      MetadataEditStatus.success =>
        record.failedCount > 0
            ? '完成但有失败项'
            : (record.needCount > 0 ? '完成但含需转码项' : '全部完成'),
      MetadataEditStatus.cancelled => '已中止',
      MetadataEditStatus.error => '执行失败',
      _ => '任务结束',
    };
  }

  Color _historyAccentColor(MetadataEditCompletedTaskRecord record) {
    if (record.status == MetadataEditStatus.cancelled) {
      return kAmber;
    }
    if (record.hasFailures) {
      return kCrimson;
    }
    if (record.needCount > 0) {
      return kAmber;
    }
    return const Color(0xFF60A5FA);
  }

  String _formatTimestamp(DateTime time) {
    String twoDigit(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${twoDigit(time.month)}-${twoDigit(time.day)} ${twoDigit(time.hour)}:${twoDigit(time.minute)}:${twoDigit(time.second)}';
  }

  MetadataEditResultItem? _findResultForFile(
    MetadataEditFileItem file,
    List<MetadataEditResultItem> results,
  ) {
    for (final MetadataEditResultItem item in results) {
      if (item.inputPath == file.path) {
        return item;
      }
      if (item.outputPath.isNotEmpty && item.outputPath == file.path) {
        return item;
      }
    }
    return null;
  }

  bool _isCompletedStatus(MetadataEditStatus status) {
    return status == MetadataEditStatus.success ||
        status == MetadataEditStatus.cancelled ||
        status == MetadataEditStatus.error;
  }

  Future<void> _pickTargets() async {
    try {
      final List<String> paths = await _resolveTargetPaths();
      if (paths.isEmpty) {
        return;
      }
      await controller.loadTargets(
        MetadataEditPanelKind.cover,
        paths,
        append: controller.coverFiles.isNotEmpty,
      );
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFE11D48),
            content: Text('无法打开文件选择器，请检查系统权限后重试。'),
          ),
        );
    }
  }

  Future<List<String>> _resolveTargetPaths() async {
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
        .toList(growable: false);
  }

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    final List<String> paths = files
        .map((XFile file) => file.path)
        .where((String path) => path.isNotEmpty)
        .toList(growable: false);
    if (paths.isEmpty) {
      return;
    }
    await controller.loadTargets(
      MetadataEditPanelKind.cover,
      paths,
      append: controller.coverFiles.isNotEmpty,
    );
  }

  Future<void> _pickCoverImage(BuildContext context) async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: '图片文件',
          extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
      confirmButtonText: '选择',
    );
    if (file == null || file.path.isEmpty) {
      return;
    }
    controller.updateCoverImagePath(file.path);
  }

  Future<void> _showResults(BuildContext context) async {
    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final MetadataEditTaskSnapshot snapshot = controller.coverSnapshot;
        return _ResultDialog(
          title: '注入处理结果全屏审阅',
          successCount: snapshot.successCount,
          skippedCount: snapshot.skippedCount,
          needCount: snapshot.needCount,
          failedCount: snapshot.failedCount,
          results: controller.coverResults,
        );
      },
    );
    controller.markResultsReviewed(MetadataEditPanelKind.cover);
  }

  Future<void> _showHistoryTaskDialog(
    MetadataEditCompletedTaskRecord record,
  ) async {
    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return _ResultDialog(
          title: '最近一次完成任务',
          successCount: record.successCount,
          skippedCount: record.skippedCount,
          needCount: record.needCount,
          failedCount: record.failedCount,
          results: record.results,
        );
      },
    );
  }

  Future<String?> _firstAcceptedImagePath(List<XFile> files) async {
    for (final XFile file in files) {
      String path = file.path;
      if (path.isEmpty) {
        final dynamic dropItem = file;
        final Object? bookmark = dropItem.extraAppleBookmark;
        if (bookmark is Uint8List) {
          final bool allowed = await DesktopDrop.instance
              .startAccessingSecurityScopedResource(bookmark: bookmark);
          if (allowed) {
            path = file.path;
          }
        }
      }
      if (path.isEmpty) {
        continue;
      }
      final String lower = path.toLowerCase();
      if (lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.webp')) {
        return path;
      }
    }
    return null;
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '点击选择\n或拖入图片',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: kTextGray),
      ),
    );
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({
    required this.title,
    required this.successCount,
    required this.skippedCount,
    required this.needCount,
    required this.failedCount,
    required this.results,
  });

  final String title;
  final int successCount;
  final int skippedCount;
  final int needCount;
  final int failedCount;
  final List<MetadataEditResultItem> results;

  @override
  Widget build(BuildContext context) {
    return HardwareDialog(
      width: kHardwareDialogReviewWidth,
      maxHeight: 760,
      scrollable: true,
      title: title,
      titleIcon: const Icon(Icons.fact_check_rounded),
      onClose: () => Navigator.of(context).pop(),
      hudTitle: 'Task Review / 结果审阅',
      hudText: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('成功 $successCount'),
          const SizedBox(height: 4),
          Text('跳过 $skippedCount'),
          const SizedBox(height: 4),
          Text('需转码 $needCount'),
          const SizedBox(height: 4),
          Text('失败 $failedCount'),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: results.asMap().entries.map((entry) {
          final int index = entry.key;
          final MetadataEditResultItem item = entry.value;
          final String fileName = item.inputPath.split('/').last;
          final ({String label, Color color}) tag = switch (item.status) {
            MetadataEditItemStatus.ok => (label: '成功', color: kEmerald),
            MetadataEditItemStatus.skip => (label: '跳过', color: kAmber),
            MetadataEditItemStatus.need => (label: '待处理', color: kAmber),
            MetadataEditItemStatus.fail => (label: '失败', color: kCrimson),
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HardwareDialogSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '#${index + 1}: $fileName',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFF3F4F6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: tag.color.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          tag.label,
                          style: TextStyle(fontSize: 12, color: tag.color),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.message,
                          style: const TextStyle(
                            fontSize: 12,
                            color: kTextLightGray,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
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
            expand: false,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _CoverListEntry {
  const _CoverListEntry({required this.file, required this.result});

  final MetadataEditFileItem file;
  final MetadataEditResultItem? result;
}

class _MetadataPanelAction extends StatelessWidget {
  const _MetadataPanelAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
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

class _MetadataFailureCheckbox extends StatelessWidget {
  const _MetadataFailureCheckbox({required this.value});

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
