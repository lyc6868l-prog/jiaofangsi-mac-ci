import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart'
    as inset;
import 'package:path/path.dart' as p;

import '../../../app/dj_app_scope.dart';
import '../../../app/router/app_router.dart';
import '../../../shared/hardware_ui/hardware_ui.dart';
import '../../../shared/platform_utils.dart' as platform_utils;
import '../../../shared/task_runtime/task_running_notifier.dart'
    show TaskRunningNotifier, TaskEndState;
import 'controllers/python_usb_backup_task_bridge.dart';
import 'controllers/usb_backup_controller.dart';
import 'models/usb_backup_models.dart';

class UsbBackupEntryPage extends StatefulWidget {
  const UsbBackupEntryPage({
    super.key,
    UsbBackupController? controller,
    this.isFeatureLocked = false,
    this.onLockedStartPressed,
  }) : _controller = controller;

  final UsbBackupController? _controller;
  final bool isFeatureLocked;
  final VoidCallback? onLockedStartPressed;

  @override
  State<UsbBackupEntryPage> createState() => _UsbBackupEntryPageState();
}

enum UsbBackupMode { backup, restore }

class _UsbBackupEntryPageState extends State<UsbBackupEntryPage> {
  @visibleForTesting
  UsbBackupController get debugController => _controller;

  PythonUsbBackupTaskBridge? _bridge;
  late final UsbBackupController _controller;
  late final TextEditingController _displayNameController;
  late final TextEditingController _formatVolumeLabelController;
  TaskRunningNotifier? _taskRunningNotifier;
  bool _lastReportedRunning = false;
  bool _isShowingDialog = false;
  UsbBackupMode _selectedMode = UsbBackupMode.backup;
  String? _selectedRestoreVersionId;

  // 视觉常量
  static const Color bgColor = Color(0xFF030303);
  static const Color panelBgColor = Color(0xFF08080A);
  static const Color lcdBgColor = Color(0xFF020202);
  static const Color accentColor = Color(0xFFE11D48);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFD97706);
  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textMuted = Color(0xFFD1D5DB);

  @override
  void initState() {
    super.initState();
    if (widget._controller != null) {
      _controller = widget._controller!;
    } else {
      final Directory projectRoot = _resolveProjectRoot();
      _bridge = PythonUsbBackupTaskBridge(
        pythonExecutable: _resolvePythonExecutable(projectRoot),
        workingDirectory: p.join(projectRoot.path, 'runtime', 'dj_runtime_py'),
        scriptModule: 'dj_runtime_py',
      );
      _controller = UsbBackupController(bridge: _bridge!);
      _controller.initialize();
    }
    _displayNameController = TextEditingController(
      text: _controller.customDisplayName,
    );
    _formatVolumeLabelController = TextEditingController(
      text: _controller.formatVolumeLabel,
    );
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
      _taskRunningNotifier!.setRunning(AppShellSection.usbBackup, false);
    }
    _displayNameController.dispose();
    _formatVolumeLabelController.dispose();
    _controller.close();
    super.dispose();
  }

  void _handleControllerChanged() {
    final UsbBackupTaskStatus status = _controller.snapshot.status;
    final bool isRunning = status == UsbBackupTaskStatus.running;
    if (_taskRunningNotifier == null) {
      return;
    }
    if (isRunning != _lastReportedRunning) {
      _taskRunningNotifier!.setRunning(AppShellSection.usbBackup, isRunning);
      _lastReportedRunning = isRunning;
    }
    if (!isRunning) {
      TaskEndState endState = TaskEndState.none;
      if (status == UsbBackupTaskStatus.success) {
        endState = TaskEndState.success;
      } else if (status == UsbBackupTaskStatus.error) {
        endState = TaskEndState.error;
      } else if (status == UsbBackupTaskStatus.cancelled) {
        endState = TaskEndState.aborted;
      }
      _taskRunningNotifier!.setEndState(AppShellSection.usbBackup, endState);
    }

    if (_displayNameController.text != _controller.customDisplayName) {
      _displayNameController.value = TextEditingValue(
        text: _controller.customDisplayName,
        selection: TextSelection.collapsed(
          offset: _controller.customDisplayName.length,
        ),
      );
    }
    if (_formatVolumeLabelController.text != _controller.formatVolumeLabel) {
      _formatVolumeLabelController.value = TextEditingValue(
        text: _controller.formatVolumeLabel,
        selection: TextSelection.collapsed(
          offset: _controller.formatVolumeLabel.length,
        ),
      );
    }
    final String? toastMessage = _controller.toastMessage;
    if (mounted && toastMessage != null && toastMessage.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(toastMessage), backgroundColor: accentColor),
        );
      _controller.clearToast();
    }

    final UsbBackupDialogData? dialogData = _controller.dialogData;
    if (!mounted || dialogData == null || _isShowingDialog) {
      return;
    }
    _isShowingDialog = true;
    showHardwareMessageDialog(
      context: context,
      title: dialogData.title,
      message: dialogData.message,
      actionLabel: '我知道了',
    ).then((_) {
      _isShowingDialog = false;
      _controller.clearDialog();
    });
  }

  Directory _resolveProjectRoot() {
    return platform_utils.resolveProjectRoot();
  }

  String _resolvePythonExecutable(Directory projectRoot) {
    return platform_utils.resolvePythonExecutable(projectRoot);
  }

  String _formatBytes(int value) {
    if (value <= 0) return '0 B';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double size = value.toDouble();
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    return '${size.toStringAsFixed(size >= 10 || unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  String _formatTimestamp(String value) {
    try {
      final DateTime dateTime = DateTime.parse(value).toLocal();
      return '${dateTime.year.toString().padLeft(4, '0')}-'
          '${dateTime.month.toString().padLeft(2, '0')}-'
          '${dateTime.day.toString().padLeft(2, '0')} '
          '${dateTime.hour.toString().padLeft(2, '0')}:'
          '${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }

  UsbBackupVolume? get _selectedDisplayVolume {
    final volumes = _controller.volumes;
    final selectedPath = _selectedMode == UsbBackupMode.backup
        ? _controller.selectedSourcePath
        : _controller.selectedTargetPath;
    if (selectedPath == null) {
      return null;
    }
    for (final volume in volumes) {
      if (volume.path == selectedPath) {
        return volume;
      }
    }
    return null;
  }

  UsbBackupVersion? get _selectedRestoreVersion {
    final versions = _controller.latestVersions;
    if (versions.isEmpty) {
      return null;
    }
    final selectedId = _selectedRestoreVersionId;
    if (selectedId == null) {
      return versions.first;
    }
    for (final version in versions) {
      if (version.snapshotId == selectedId) {
        return version;
      }
    }
    return versions.first;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Container(
          decoration: const BoxDecoration(
            color: bgColor,
            // 可以在这里加一个简单的网格背景装饰
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),

            child: Center(
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: 1200,
                  minHeight: 480,
                ),
                decoration: BoxDecoration(
                  color: panelBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    /*
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: Text(
                            '盘',
                            style: TextStyle(
                              fontSize: 260,
                              fontWeight: FontWeight.w900,
                              color: Colors.white.withValues(alpha: 0.012),
                            ),
                          ),
                        ),
                      ),
                    ),
                    */
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Column(
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 12),
                          Opacity(
                            opacity: widget.isFeatureLocked ? 0.5 : 1,
                            child: IgnorePointer(
                              ignoring: widget.isFeatureLocked,
                              child: Column(
                                children: [
                                  _buildDeviceRow(),
                                  const SizedBox(height: 12),
                                  _buildModeSwitch(),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Opacity(
                              opacity: widget.isFeatureLocked ? 0.5 : 1,
                              child: IgnorePointer(
                                ignoring: widget.isFeatureLocked,
                                child: _buildDynamicPanel(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildFooter(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _statusLabel(UsbBackupTaskSnapshot snapshot) {
    if (snapshot.status == UsbBackupTaskStatus.running) {
      return switch (snapshot.taskType) {
        'backup' => '备份中',
        'restore' => '恢复备份中',
        _ => snapshot.status.label,
      };
    }
    return snapshot.status.label;
  }

  String? _currentRestoreContent(UsbBackupTaskSnapshot snapshot) {
    if (snapshot.taskType != 'restore') {
      return null;
    }
    final parts = snapshot.progressHintText.split(' · ');
    if (parts.length < 2) {
      return null;
    }
    final String current = parts.last.trim();
    if (current.isEmpty) {
      return null;
    }
    return current;
  }

  Widget _buildHeader() {
    final snapshot = _controller.snapshot;
    final statusColor = switch (snapshot.status) {
      UsbBackupTaskStatus.running => successColor,
      UsbBackupTaskStatus.success => successColor,
      UsbBackupTaskStatus.error => accentColor,
      UsbBackupTaskStatus.cancelled => warningColor,
      _ => textSecondary,
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          '🆘 U 盘备份与恢复',
          style: TextStyle(
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: lcdBgColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '状态: ',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                _statusLabel(snapshot),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 1,
                height: 16,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              const SizedBox(width: 12),
              const Text(
                '检测到 U 盘: ',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                '${_controller.volumes.length}',
                style: const TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceRow() {
    final volumes = _controller.volumes;
    final currentPath = _selectedMode == UsbBackupMode.backup
        ? _controller.selectedSourcePath
        : _controller.selectedTargetPath;
    final selectedVolume = _selectedDisplayVolume;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
      ),
      child: Row(
        children: [
          _buildHardwareDropdown(volumes, currentPath),
          const SizedBox(width: 24),
          Expanded(child: _buildCapacityBar(selectedVolume)),
          const SizedBox(width: 16),
          _buildToolButton(
            '🔄 刷新',
            accent: successColor,
            onTap: _controller.hasActiveTask
                ? null
                : () => _controller.refreshAll(forceRefresh: true),
          ),
          const SizedBox(width: 12),
          _buildToolButton(
            '⏏ 弹出',
            accent: warningColor,
            onTap: _controller.hasActiveTask
                ? null
                : () => _controller.ejectVolumeForPath(selectedVolume?.path),
          ),
          const SizedBox(width: 12),
          _buildToolButton(
            '格式化',
            accent: accentColor,
            isDanger: true,
            onTap: _controller.hasActiveTask ? null : _showFormatConfirmDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareDropdown(
    List<UsbBackupVolume> volumes,
    String? currentPath,
  ) {
    return Container(
      constraints: const BoxConstraints(minWidth: 320),
      height: 36,
      decoration: BoxDecoration(
        color: lcdBgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: volumes.any((v) => v.path == currentPath) ? currentPath : null,
          dropdownColor: panelBgColor,
          isDense: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          icon: const Icon(Icons.arrow_drop_down, color: textSecondary),
          hint: Text(
            _selectedMode == UsbBackupMode.backup ? '选择备份源 U 盘' : '选择恢复目标 U 盘',
            style: const TextStyle(color: textSecondary, fontSize: 14),
          ),
          items: volumes.map((v) {
            return DropdownMenuItem(
              value: v.path,
              child: Text(
                '💾 [${v.volumeName}] (${v.filesystem?.toUpperCase() ?? '未知'}) - ${_formatBytes(v.totalBytes)}',
                style: const TextStyle(
                  color: Color(0xFFD1D5DB),
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
            );
          }).toList(),
          onChanged: _controller.hasActiveTask
              ? null
              : (val) {
                  if (_selectedMode == UsbBackupMode.backup) {
                    _controller.selectSourcePath(val);
                  } else {
                    setState(() => _selectedRestoreVersionId = null);
                    _controller.selectTargetPath(val);
                  }
                },
        ),
      ),
    );
  }

  Widget _buildCapacityBar(UsbBackupVolume? volume) {
    if (volume == null) return const SizedBox(height: 36);
    final usedBytes = volume.totalBytes - volume.freeBytes;
    final progress = volume.totalBytes > 0
        ? (usedBytes / volume.totalBytes).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '已用: ${_formatBytes(usedBytes)}',
              style: const TextStyle(
                color: textMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              '剩余: ${_formatBytes(volume.freeBytes)}',
              style: const TextStyle(
                color: textMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildHardwareProgressBar(
          progress,
          gradientColors: const <Color>[
            Color(0xFF064E3B),
            Color(0xFF10B981),
            Color(0xFF6EE7B7),
          ],
          glowColor: successColor,
        ),
      ],
    );
  }

  Widget _buildToolButton(
    String text, {
    Key? key,
    bool isDanger = false,
    bool isWarning = false,
    Color? accent,
    VoidCallback? onTap,
  }) {
    return _UsbActionButton(
      key: key,
      text: text,
      onTap: onTap,
      accent:
          accent ??
          (isDanger
              ? accentColor
              : (isWarning ? warningColor : const Color(0xFFD1D5DB))),
    );
  }

  Widget _buildModeSwitch() {
    return Row(
      children: [
        _buildModeRadio(UsbBackupMode.backup, '一键 U 盘备份'),
        const SizedBox(width: 40),
        _buildModeRadio(UsbBackupMode.restore, '从备份恢复 U 盘'),
      ],
    );
  }

  Widget _buildModeRadio(UsbBackupMode mode, String label) {
    final isSelected = _selectedMode == mode;
    return InkWell(
      onTap: _controller.hasActiveTask
          ? null
          : () => setState(() => _selectedMode = mode),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: lcdBgColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? accentColor : const Color(0xFF4B5563),
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: isSelected
                ? Container(
                    decoration: const BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? accentColor : textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(12),
      child: IndexedStack(
        index: _selectedMode == UsbBackupMode.backup ? 0 : 1,
        children: [_buildBackupView(), _buildRestoreView()],
      ),
    );
  }

  Widget _buildBackupView() {
    final pending = _controller.selectedSourcePendingBackup;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _displayNameController,
                onChanged: _controller.updateCustomDisplayName,
                style: const TextStyle(color: textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: lcdBgColor,
                  hintText: '备份名称...',
                  hintStyle: const TextStyle(color: textSecondary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (pending != null)
              _buildToolButton(
                '检测到未完成备份',
                key: const ValueKey('pending_backup_btn'),
                isWarning: true,
                onTap: () => _showResumeDialog(pending),
              ),
            const SizedBox(width: 12),
            _buildToolButton('清理仓库', onTap: _showCleanupRepositoryDialog),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _buildInfoCard(
            title: 'Rekordbox 摘要',
            subtitle:
                '(${_selectedDisplayVolume?.rekordboxDetected == true ? '已读取当前 U 盘 Rekordbox 摘要' : '未检测到 Rekordbox 导出结构'})',
            child: _buildRekordboxGrid(_selectedDisplayVolume),
          ),
        ),
      ],
    );
  }

  Widget _buildRestoreView() {
    final versions = _controller.latestVersions;
    final selectedVersion = _selectedRestoreVersion;
    final targetVolume = _selectedDisplayVolume;
    final showFormatHint = targetVolume?.requiresFormatBeforeRestore ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '恢复推荐',
          style: TextStyle(
            color: textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: lcdBgColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedVersion?.snapshotId,
                    dropdownColor: panelBgColor,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: textSecondary,
                    ),
                    hint: const Text(
                      '选择恢复包...',
                      style: TextStyle(color: textSecondary, fontSize: 13),
                    ),
                    items: versions.map((v) {
                      return DropdownMenuItem(
                        value: v.snapshotId,
                        child: Text(
                          '📦 ${v.displayName} (${_formatTimestamp(v.createdAt)})',
                          style: const TextStyle(
                            color: Color(0xFFD1D5DB),
                            fontSize: 13,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: _controller.hasActiveTask
                        ? null
                        : (val) =>
                              setState(() => _selectedRestoreVersionId = val),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _buildToolButton('清理仓库', onTap: _showCleanupRepositoryDialog),
          ],
        ),
        const SizedBox(height: 8),
        if (selectedVersion != null) ...[
          Row(
            children: [
              _buildToolButton(
                '查看恢复包详情',
                onTap: () => _showRestorePackageDetailDialog(
                  selectedVersion,
                  showFormatHint: showFormatHint,
                ),
              ),
            ],
          ),
        ] else
          const Expanded(
            child: Center(
              child: Text('暂无可恢复备份包', style: TextStyle(color: textSecondary)),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: lcdBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null)
                Expanded(
                  child: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: textMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildRekordboxGrid(UsbBackupVolume? volume) {
    final detected = volume?.rekordboxDetected ?? false;
    final List<(String, String, bool)> items = <(String, String, bool)>[
      ('设备名称', volume?.volumeName ?? '--', false),
      ('Rekordbox', detected ? '已检测到' : '未检测到', detected),
      ('文件系统', volume?.filesystem?.toUpperCase() ?? '未知', false),
      ('总容量', volume == null ? '--' : _formatBytes(volume.totalBytes), false),
      ('可用容量', volume == null ? '--' : _formatBytes(volume.freeBytes), false),
      ('总线协议', volume?.busProtocol ?? '--', false),
      ('序列号', volume?.serialNumber ?? '--', false),
      (
        '恢复前格式化',
        volume?.requiresFormatBeforeRestore == true ? '需要' : '无需',
        volume?.requiresFormatBeforeRestore == false,
      ),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items.map((item) {
        return SizedBox(
          width: 160,
          child: _buildGridItem(item.$1, item.$2, isOk: item.$3),
        );
      }).toList(),
    );
  }

  Widget _buildGridItem(String label, String value, {bool isOk = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isOk ? successColor : textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedVersionCard(
    UsbBackupVersion version, {
    bool showFormatHint = false,
  }) {
    final summary = version.rekordboxSummary;
    final List<(String, String, bool)> detailItems = <(String, String, bool)>[
      ('版本名称', version.displayName, false),
      ('创建时间', _formatTimestamp(version.createdAt), false),
      ('文件系统', version.sourceFilesystem?.toUpperCase() ?? '未知', false),
      ('容量', _formatBytes(version.totalBytes), false),
      ('歌曲数量', summary == null ? '--' : '${summary.audioFileCount}', false),
      ('波纹数量', summary == null ? '--' : '${summary.analysisFileCount}', false),
      ('热点数量', summary == null ? '--' : '${summary.playlistSyncCount}', false),
      ('数据库文件', summary == null ? '--' : '${summary.databaseFileCount}', false),
      (
        'PIONEER 目录',
        summary?.hasPioneerDir == true ? '有' : '无',
        summary?.hasPioneerDir == true,
      ),
      (
        'Contents 目录',
        summary?.hasContentsDir == true ? '有' : '无',
        summary?.hasContentsDir == true,
      ),
      (
        'export.pdb',
        summary?.hasExportLibraryDb == true ? '有' : '无',
        summary?.hasExportLibraryDb == true,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: lcdBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: successColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '恢复包详情',
                style: TextStyle(
                  color: textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: successColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: successColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  version.canRestore ? '可恢复' : '当前不可恢复',
                  style: TextStyle(
                    color: version.canRestore ? successColor : accentColor,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: detailItems.map((item) {
              return SizedBox(
                width: 170,
                child: _buildGridItem(item.$1, item.$2, isOk: item.$3),
              );
            }).toList(),
          ),
          if (version.disabledReason != null) ...[
            const SizedBox(height: 6),
            Text(
              version.disabledReason!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFB7185),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (showFormatHint) ...[
            const SizedBox(height: 6),
            const Text(
              '目标 U 盘需要先格式化为 FAT32 或 ExFAT，之后才能执行恢复。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (!version.recommended) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _buildToolButton(
                '删除版本',
                isDanger: true,
                onTap: () => _showDeleteVersionDialog(version),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRestorePackageDetailDialog(
    UsbBackupVersion version, {
    bool showFormatHint = false,
  }) async {
    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return HardwareDialog(
          width: kHardwareDialogWideWidth,
          maxHeight: 760,
          scrollable: true,
          title: '恢复包详情',
          titleIcon: const Icon(Icons.inventory_2_rounded),
          onClose: () => Navigator.pop(dialogContext),
          hudTitle: 'Package Detail / 恢复包信息',
          hudText: Text(
            '请确认当前恢复包内容、目标设备与格式要求一致，再继续执行恢复流程。',
            style: const TextStyle(height: 1.6),
          ),
          body: _buildSelectedVersionCard(
            version,
            showFormatHint: showFormatHint,
          ),
          footer: HardwareDialogFooter(
            actions: <Widget>[
              HardwareDialogAction(
                label: '关闭',
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    final snapshot = _controller.snapshot;
    final validation = snapshot.restoreValidation;
    final currentRestoreContent = _currentRestoreContent(snapshot);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (validation != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: validation.filesPresentOk
                  ? const Color(0xFF0F2E1A)
                  : const Color(0xFF331B1B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: validation.filesPresentOk ? successColor : accentColor,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '恢复后校验',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  validation.message,
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  '进度: ',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  '${(snapshot.progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 24),
                Text(
                  snapshot.taskType == 'restore' ? '当前内容: ' : '文件: ',
                  style: const TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  snapshot.taskType == 'restore'
                      ? (currentRestoreContent ?? '等待恢复内容...')
                      : '${snapshot.restoredFiles} / ${snapshot.totalFiles}',
                  style: const TextStyle(
                    color: textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Flexible(
              child: Text(
                snapshot.status == UsbBackupTaskStatus.error &&
                        snapshot.errorMessage?.isNotEmpty == true
                    ? snapshot.errorMessage!
                    : snapshot.progressHintText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildHardwareProgressBar(
          snapshot.progress,
          gradientColors: const <Color>[
            Color(0xFF4C0519),
            Color(0xFFBE123C),
            Color(0xFFFB7185),
          ],
          glowColor: accentColor,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildGiantButton(
                _selectedMode == UsbBackupMode.backup ? '一键开始备份' : '一键开始恢复',
                isActive: _controller.hasActiveTask,
                onTap: _controller.hasActiveTask
                    ? null
                    : (widget.isFeatureLocked
                          ? widget.onLockedStartPressed
                          : (_selectedMode == UsbBackupMode.backup
                                ? (_controller.canStartBackup
                                      ? _showBackupConfirmDialog
                                      : null)
                                : (_selectedRestoreVersion != null &&
                                          _selectedRestoreVersion!.canRestore &&
                                          _controller.selectedTargetPath != null
                                      ? () => _showRestoreConfirmDialog(
                                          _selectedRestoreVersion!,
                                        )
                                      : null))),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: _buildGiantButton(
                '紧急停止',
                isStop: true,
                onTap: _controller.canStopTask ? _controller.stopTask : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHardwareProgressBar(
    double value, {
    required List<Color> gradientColors,
    required Color glowColor,
  }) {
    final double clamped = value.clamp(0.0, 1.0);
    return Container(
      height: 10,
      clipBehavior: Clip.antiAlias,
      decoration: inset.BoxDecoration(
        color: lcdBgColor,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.black.withValues(alpha: 0.8)),
        boxShadow: <inset.BoxShadow>[
          inset.BoxShadow(
            color: Colors.black.withValues(alpha: 0.9),
            offset: const Offset(0, 2),
            blurRadius: 6,
            inset: true,
          ),
          inset.BoxShadow(
            color: Colors.white.withValues(alpha: 0.05),
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: clamped,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: gradientColors,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: glowColor, blurRadius: 15),
                  ],
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 15,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Colors.transparent, Colors.white],
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.8),
                          blurRadius: 15,
                          spreadRadius: 3,
                        ),
                        BoxShadow(
                          color: glowColor.withValues(alpha: 0.8),
                          blurRadius: 25,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(child: _UsbProgressSegmentsLayer()),
          ),
        ],
      ),
    );
  }

  Widget _buildGiantButton(
    String text, {
    bool isStop = false,
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          gradient: isStop
              ? const LinearGradient(
                  colors: [Color(0xFF1E0A0F), Color(0xFF0F0508)],
                )
              : const LinearGradient(
                  colors: [Color(0xFF28282D), Color(0xFF141418)],
                ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isStop
                ? accentColor.withValues(alpha: 0.3)
                : (isActive ? successColor : Colors.black),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isStop
                  ? accentColor
                  : (isActive ? successColor : textPrimary),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  // --- 弹窗逻辑 ---

  Future<void> _showResumeDialog(UsbBackupPendingBackup backup) async {
    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return HardwareDialog(
          width: kHardwareDialogStandardWidth,
          title: '发现未完成的备份任务',
          titleIcon: const Icon(Icons.restore_rounded),
          onClose: () => Navigator.pop(dialogContext),
          hudTitle: 'Resume Backup / 断点续传',
          hudText: Text(
            '历史节点：${backup.displayName}\n已完成：${backup.completedFiles} / ${backup.totalFiles} 文件\n您可以选择从断点继续封装剩余文件，或者直接放弃此次续传记录。',
            style: const TextStyle(height: 1.7),
          ),
          body: const SizedBox.shrink(),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          footer: HardwareDialogFooter(
            actions: <Widget>[
              HardwareDialogAction(
                label: '放弃续传',
                variant: HardwareDialogActionVariant.danger,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              HardwareDialogAction(
                label: '从断点继续备份',
                variant: HardwareDialogActionVariant.confirm,
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _controller.startBackup();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showBackupConfirmDialog() async {
    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return HardwareDialog(
          width: kHardwareDialogStandardWidth,
          title: '备份前置确认',
          titleIcon: const Icon(Icons.backup_rounded),
          onClose: () => Navigator.pop(dialogContext),
          hudTitle: 'Backup Checklist / 备份检查项',
          hudText: const Text(
            '开始备份前，请先确认以下事项：\n\n1. 已彻底关闭 rekordbox。\n2. 不要在备份过程中拔出 U 盘。\n3. 备份完成前不要打开 U 盘内容。\n\n说明：rekordbox 可能仍在后台读写数据库，若未关闭，备份结果可能不完整。',
            style: TextStyle(height: 1.7),
          ),
          body: const SizedBox.shrink(),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          footer: HardwareDialogFooter(
            actions: <Widget>[
              HardwareDialogAction(
                label: '取消',
                variant: HardwareDialogActionVariant.danger,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              HardwareDialogAction(
                label: '确认无误，开始备份',
                variant: HardwareDialogActionVariant.confirm,
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _controller.startBackup();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRestoreConfirmDialog(UsbBackupVersion version) async {
    bool confirmed = false;
    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setModalState,
              ) {
                return HardwareDialog(
                  width: kHardwareDialogStandardWidth,
                  title: '确认恢复到 U 盘',
                  titleIcon: const Icon(Icons.usb_rounded),
                  onClose: () => Navigator.pop(dialogContext),
                  hudTitle: 'Restore Warning / 恢复警告',
                  hudText: Text(
                    '备份版本：${version.displayName}\n恢复操作将覆盖目标 U 盘现有内容，请再次确认。',
                    style: const TextStyle(height: 1.7),
                  ),
                  body: Material(
                    color: Colors.transparent,
                    child: HardwareDialogSectionCard(
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '我已确认将清空目标 U 盘现有内容',
                          style: TextStyle(color: textPrimary, fontSize: 13),
                        ),
                        value: confirmed,
                        onChanged: (bool? v) =>
                            setModalState(() => confirmed = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                  ),
                  footer: HardwareDialogFooter(
                    actions: <Widget>[
                      HardwareDialogAction(
                        label: '取消',
                        variant: HardwareDialogActionVariant.danger,
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                      HardwareDialogAction(
                        label: '确认恢复',
                        variant: HardwareDialogActionVariant.confirm,
                        onPressed: confirmed
                            ? () {
                                Navigator.pop(dialogContext);
                                _controller.restoreVersion(version);
                              }
                            : null,
                      ),
                    ],
                  ),
                );
              },
        );
      },
    );
  }

  Future<void> _showFormatConfirmDialog() async {
    final target = _selectedDisplayVolume;
    if (target == null) return;
    _formatVolumeLabelController.value = TextEditingValue(
      text: _controller.formatVolumeLabel,
      selection: TextSelection.collapsed(
        offset: _controller.formatVolumeLabel.length,
      ),
    );

    await showHardwareDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setModalState,
              ) {
                Widget buildOption(String value, String title, String desc) {
                  final bool selected = _controller.formatFilesystem == value;
                  return Expanded(
                    child: InkWell(
                      onTap: () {
                        _controller.updateFormatFilesystem(value);
                        setModalState(() {});
                      },
                      child: HardwareDialogSectionCard(
                        backgroundColor: selected
                            ? accentColor.withValues(alpha: 0.06)
                            : lcdBgColor,
                        borderColor: selected
                            ? accentColor.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.05),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              desc,
                              style: const TextStyle(
                                color: textMuted,
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return HardwareDialog(
                  width: kHardwareDialogWideWidth,
                  maxHeight: 780,
                  scrollable: true,
                  title: '确认格式化 U 盘',
                  titleIcon: const Icon(Icons.sd_storage_rounded),
                  onClose: () => Navigator.pop(dialogContext),
                  hudTitle: 'Format Warning / 格式化警告',
                  hudText: const Text(
                    '格式化会清空目标 U 盘现有内容。请在执行前确认目标盘符、卷标与文件系统格式。',
                    style: TextStyle(height: 1.6),
                  ),
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '第 1 步：确认目标驱动器',
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      HardwareDialogSectionCard(
                        child: Text(
                          '[${target.volumeName}] - ${_formatBytes(target.totalBytes)}',
                          style: const TextStyle(color: textPrimary),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '第 2 步：设置卷标',
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _formatVolumeLabelController,
                        spellCheckConfiguration:
                            const SpellCheckConfiguration.disabled(),
                        enableSuggestions: false,
                        autocorrect: false,
                        onChanged: _controller.updateFormatVolumeLabel,
                        style: const TextStyle(
                          color: textPrimary,
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(hintText: '卷标名称'),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '第 3 步：选择文件系统格式',
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          buildOption('fat32', 'FAT32', '传统 DJ 设备兼容性更强'),
                          const SizedBox(width: 12),
                          buildOption('exfat', 'ExFAT', '适合新设备与大文件'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      HardwareDialogSectionCard(
                        backgroundColor: accentColor.withValues(alpha: 0.08),
                        borderColor: accentColor.withValues(alpha: 0.22),
                        child: const Text(
                          '开始前请关闭 Finder 中该 U 盘窗口、播放器、同步盘等占用程序。格式化时系统会先尝试卸载磁盘，若检测到设备忙碌会自动等待后重试一次。',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 12,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  footer: HardwareDialogFooter(
                    actions: <Widget>[
                      HardwareDialogAction(
                        label: '取消',
                        variant: HardwareDialogActionVariant.danger,
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                      HardwareDialogAction(
                        label: '确认格式化',
                        variant: HardwareDialogActionVariant.confirm,
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _controller.startFormatForPath(target.path);
                        },
                      ),
                    ],
                  ),
                );
              },
        );
      },
    );
  }

  Future<void> _showCleanupRepositoryDialog() async {
    final bool confirmed = await showHardwareConfirmDialog(
      context: context,
      title: '确认清理仓库',
      message: '将清理当前仓库内未被任何快照引用的孤立对象。',
      cancelLabel: '取消',
      confirmLabel: '开始清理',
    );
    if (confirmed) {
      _controller.cleanupRepository();
    }
  }

  Future<void> _showDeleteVersionDialog(UsbBackupVersion version) async {
    final bool confirmed = await showHardwareConfirmDialog(
      context: context,
      title: '确认删除备份版本',
      message: '确认要删除“${version.displayName}”吗？',
      cancelLabel: '取消',
      confirmLabel: '确认删除',
    );
    if (confirmed) {
      _controller.deleteBackupVersion(version);
    }
  }
}

class _UsbProgressSegmentsLayer extends StatelessWidget {
  const _UsbProgressSegmentsLayer();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _UsbProgressSegmentsPainter());
  }
}

class _UsbProgressSegmentsPainter extends CustomPainter {
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

class _UsbActionButton extends StatefulWidget {
  const _UsbActionButton({
    super.key,
    required this.text,
    required this.accent,
    required this.onTap,
  });

  final String text;
  final Color accent;
  final VoidCallback? onTap;

  @override
  State<_UsbActionButton> createState() => _UsbActionButtonState();
}

class _UsbActionButtonState extends State<_UsbActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool disabled = widget.onTap == null;
    final double pressOffset = _isPressed ? 1 : 0;
    final Color accent = widget.accent;
    final Color borderColor = disabled
        ? Colors.white.withValues(alpha: 0.08)
        : (_isPressed
              ? accent.withValues(alpha: 0.95)
              : (_isHovered
                    ? accent.withValues(alpha: 0.7)
                    : accent.withValues(alpha: 0.38)));
    final Color fillColor = disabled
        ? const Color(0xFF1E1E23).withValues(alpha: 0.35)
        : (_isPressed
              ? accent.withValues(alpha: 0.22)
              : (_isHovered
                    ? accent.withValues(alpha: 0.12)
                    : const Color(0xFF1E1E23).withValues(alpha: 0.6)));
    final List<BoxShadow> shadows = <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.8),
        offset: const Offset(0, 1),
        blurRadius: 3,
      ),
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.05),
        offset: const Offset(0, 1),
        blurRadius: 1,
      ),
      if (!disabled && (_isHovered || _isPressed))
        BoxShadow(
          color: accent.withValues(alpha: _isPressed ? 0.38 : 0.22),
          blurRadius: _isPressed ? 10 : 7,
          spreadRadius: _isPressed ? 0.5 : 0,
        ),
    ];

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: Listener(
        onPointerDown: disabled
            ? null
            : (_) => setState(() => _isPressed = true),
        onPointerUp: disabled
            ? null
            : (_) => setState(() => _isPressed = false),
        onPointerCancel: disabled
            ? null
            : (_) => setState(() => _isPressed = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, pressOffset, 0),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: fillColor,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(6),
              boxShadow: shadows,
            ),
            child: Center(
              child: Text(
                widget.text,
                style: TextStyle(
                  color: disabled
                      ? const Color(0xFF6B7280)
                      : (_isPressed || _isHovered
                            ? accent
                            : accent.withValues(alpha: 0.92)),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
