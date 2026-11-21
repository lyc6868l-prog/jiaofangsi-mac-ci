import 'package:dj_flutter/shared/hardware_ui/hardware_ui.dart'
    show
        showHardwareDialog,
        HardwareDialog,
        HardwareDialogFooter,
        HardwareDialogAction,
        HardwareDialogActionVariant;
import 'package:flutter/material.dart';

import '../controllers/cleanup_dup_controller.dart';
import '../models/cleanup_dup_models.dart';
import 'hardware_widgets.dart';

void _showHistoryDialog(
  BuildContext context,
  CleanupDupCompletedTaskRecord record,
  VoidCallback onClear,
) {
  showHardwareDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      final Color accentColor = record.isAllSuccess
          ? const Color(0xFF10B981)
          : const Color(0xFFE11D48);
      final String statusText = switch (record.status) {
        CleanupDupStatus.success => '完成',
        CleanupDupStatus.cancelled => '已中止',
        CleanupDupStatus.error => '执行失败',
        _ => '任务结束',
      };
      final String timestamp =
          '${record.finishedAt.year}-${record.finishedAt.month.toString().padLeft(2, '0')}-${record.finishedAt.day.toString().padLeft(2, '0')} ${record.finishedAt.hour.toString().padLeft(2, '0')}:${record.finishedAt.minute.toString().padLeft(2, '0')}:${record.finishedAt.second.toString().padLeft(2, '0')}';

      return HardwareDialog(
        width: 460,
        title: '最近一次完成任务',
        titleIcon: Icon(Icons.history_rounded, color: accentColor),
        onClose: () => Navigator.of(dialogContext).pop(),
        hudTitle: 'Task History / 任务记录',
        hudText: Text(
          '$statusText · $timestamp\n共处理 ${record.inputFiles.length} 个目标${record.message != null && record.message!.isNotEmpty ? '\n状态说明：${record.message}' : ''}',
          style: TextStyle(
            height: 1.6,
            color: record.hasFailures
                ? const Color(0xFFFB7185)
                : kTextLightGray,
          ),
        ),
        body: const SizedBox.shrink(),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        footer: HardwareDialogFooter(
          actions: <Widget>[
            HardwareDialogAction(
              label: '清除记录',
              variant: HardwareDialogActionVariant.confirm,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onClear();
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
}

class TitleCleanupPanel extends StatelessWidget {
  const TitleCleanupPanel({
    super.key,
    required this.controller,
    this.isFeatureLocked = false,
    this.onLockedStartPressed,
  });

  final CleanupDupController controller;
  final bool isFeatureLocked;
  final VoidCallback? onLockedStartPressed;

  @override
  Widget build(BuildContext context) {
    return HardwarePanel(
      watermark: '雷',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Opacity(
              opacity: isFeatureLocked ? 0.5 : 1,
              child: IgnorePointer(
                ignoring: isFeatureLocked,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      height: 36,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          const Text(
                            '🧹 曲目标题广告清理',
                            style: TextStyle(
                              color: Color(0xFFF3F4F6),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1,
                            ),
                          ),
                          if (controller.titleLastCompletedTask != null)
                            _HistoryButton(
                              onPressed: () => _showHistoryDialog(
                                context,
                                controller.titleLastCompletedTask!,
                                () => controller.clearLastCompletedTask(
                                  CleanupDupPanelKind.titleClean,
                                ),
                              ),
                            ),
                          _ClearSmallButton(
                            onPressed: controller.onClearTitleFiles,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    LcdStatusStrip(
                      statusText: controller.titleStatusText,
                      statusColor: controller.statusColor(
                        controller.titleCleanStatus,
                      ),
                      items: <Widget>[
                        _LcdItem(
                          label: '目标数量',
                          value: '${controller.titleFileCount}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 36,
                      child: Row(
                        children: <Widget>[
                          const Text(
                            '指定删除文本:',
                            style: TextStyle(
                              color: Color(0xFF8B8F98),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: HardwareInput(
                              controller: controller.deleteTextController,
                              placeholder: '例如: 微信xxx / www.xxx.com...',
                              enabled: !controller.titleConfigLocked,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _ConfirmButton(
                            isLocked: controller.titleConfigLocked,
                            onPressed: () => controller.onConfigConfirm(
                              CleanupDupPanelKind.titleClean,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    HardwareDropZone(
                      hasFiles: controller.titleLoadedFiles.isNotEmpty,
                      isDragging: controller.draggingFor(
                        CleanupDupPanelKind.titleClean,
                      ),
                      files: controller.titleLoadedFiles,
                      hintText: controller.dropHintFor(
                        CleanupDupPanelKind.titleClean,
                      ),
                      onEmptyTap: () => controller.pickTargetsNative(
                        CleanupDupPanelKind.titleClean,
                      ),
                      onAppendTap: () => controller.pickTargetsNative(
                        CleanupDupPanelKind.titleClean,
                      ),
                      onRemoveFile: (String path) => controller.removeTarget(
                        CleanupDupPanelKind.titleClean,
                        path,
                      ),
                      onDragChanged: (bool value) => controller.setDraggingOver(
                        CleanupDupPanelKind.titleClean,
                        value,
                      ),
                      onFilesDropped: (List<String> paths) =>
                          controller.onFilesDropped(
                            CleanupDupPanelKind.titleClean,
                            paths,
                          ),
                    ),
                    const SizedBox(height: 8),
                    HardwareProgressBar(
                      value: controller.titleProgress,
                      hintText: controller.titleProgressHint,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: Row(
              children: <Widget>[
                HardwareGiantButton(
                  label: '开始清理',
                  onPressed: isFeatureLocked
                      ? onLockedStartPressed ?? () {}
                      : () => controller.onStartTask(
                          CleanupDupPanelKind.titleClean,
                        ),
                  isStart: true,
                  enabled: isFeatureLocked || controller.titleStartEnabled,
                  flashSignal: controller.titleStartFlashSignal,
                ),
                const SizedBox(width: 16),
                HardwareGiantButton(
                  label: '紧急停止',
                  isStart: false,
                  enabled: true,
                  onPressed: () {
                    if (isFeatureLocked) {
                      return;
                    }
                    controller.onStopTask(CleanupDupPanelKind.titleClean);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryButton extends StatefulWidget {
  const _HistoryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_HistoryButton> createState() => _HistoryButtonState();
}

class _HistoryButtonState extends State<_HistoryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onPressed,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? kEmerald.withValues(alpha: 0.05)
                : Colors.transparent,
            border: Border.all(
              color: _hovered
                  ? kEmerald.withValues(alpha: 0.4)
                  : Colors.white12,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            '最近任务',
            style: TextStyle(
              color: _hovered ? kEmerald : kTextGray,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearSmallButton extends StatefulWidget {
  const _ClearSmallButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_ClearSmallButton> createState() => _ClearSmallButtonState();
}

class _ClearSmallButtonState extends State<_ClearSmallButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onPressed,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? kCrimson.withValues(alpha: 0.05)
                : Colors.transparent,
            border: Border.all(
              color: _hovered
                  ? kCrimson.withValues(alpha: 0.4)
                  : Colors.white12,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            '清空列表',
            style: TextStyle(
              color: _hovered ? kCrimson : kTextGray,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _LcdItem extends StatelessWidget {
  const _LcdItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          '$label: ',
          style: const TextStyle(
            color: kTextGray,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: kTextLightGray,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _ConfirmButton extends StatefulWidget {
  const _ConfirmButton({required this.isLocked, required this.onPressed});

  final bool isLocked;
  final VoidCallback onPressed;

  @override
  State<_ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<_ConfirmButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.isLocked ? null : widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        transform: Matrix4.translationValues(
          0,
          _pressed && !widget.isLocked ? 2 : 0,
          0,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: widget.isLocked
                ? <Color>[
                    const Color(0xFF1E1E23).withValues(alpha: 0.3),
                    const Color(0xFF0F0F12).withValues(alpha: 0.3),
                  ]
                : <Color>[
                    const Color(0xFF1E1E23).withValues(alpha: 0.8),
                    const Color(0xFF0F0F12).withValues(alpha: 0.9),
                  ],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black.withValues(alpha: 0.8)),
          boxShadow: <BoxShadow>[
            if (!widget.isLocked && !_pressed)
              const BoxShadow(
                color: Colors.black54,
                offset: Offset(0, 4),
                blurRadius: 6,
              ),
            if (_pressed)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 5,
              ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (!widget.isLocked)
              Positioned(
                top: 0,
                left: 1,
                right: 1,
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            Text(
              widget.isLocked ? '已锁定' : '确定',
              style: TextStyle(
                color: widget.isLocked ? kTextGray : Colors.white,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
