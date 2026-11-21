import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dj_flutter/shared/task_runtime/polling_helper.dart';

import '../models/usb_backup_models.dart';

class UsbBackupController extends ChangeNotifier {
  UsbBackupController({required UsbBackupTaskBridge bridge}) : _bridge = bridge;

  final UsbBackupTaskBridge _bridge;

  List<UsbBackupVolume> _volumes = <UsbBackupVolume>[];
  List<UsbBackupVersion> _versions = <UsbBackupVersion>[];
  List<UsbBackupVersion> _latestVersions = <UsbBackupVersion>[];
  List<UsbBackupPendingBackup> _pendingBackups = <UsbBackupPendingBackup>[];
  UsbBackupTaskSnapshot _snapshot = const UsbBackupTaskSnapshot.idle();
  String _repoRoot = '';
  String _customDisplayName = '';
  String _formatFilesystem = 'fat32';
  String _formatVolumeLabel = 'PIONEER';
  String? _selectedSourcePath;
  String? _selectedTargetPath;
  String? _selectedSourceIdentity;
  String? _selectedTargetIdentity;
  String? _pendingFormatIdentity;
  bool _pendingFormatAffectsSource = false;
  bool _pendingFormatAffectsTarget = false;
  String? _toastMessage;
  UsbBackupDialogData? _dialogData;
  bool _isLoading = false;
  DateTime? _lastVolumesRefreshedAt;
  Future<void>? _refreshVolumesFuture;
  Future<void>? _refreshAllFuture;
  int _refreshVersionsRequestId = 0;
  final PollingHelper _polling = PollingHelper(
    interval: const Duration(milliseconds: 160),
  );
  static const Duration _volumeRefreshDebounce = Duration(milliseconds: 350);

  List<UsbBackupVolume> get volumes =>
      List<UsbBackupVolume>.unmodifiable(_volumes);
  List<UsbBackupVersion> get versions =>
      List<UsbBackupVersion>.unmodifiable(_versions);
  List<UsbBackupVersion> get latestVersions =>
      List<UsbBackupVersion>.unmodifiable(_latestVersions);
  List<UsbBackupPendingBackup> get pendingBackups =>
      List<UsbBackupPendingBackup>.unmodifiable(_pendingBackups);
  UsbBackupTaskSnapshot get snapshot => _snapshot;
  String get repoRoot => _repoRoot;
  String get customDisplayName => _customDisplayName;
  String get formatFilesystem => _formatFilesystem;
  String get formatVolumeLabel => _formatVolumeLabel;
  String? get selectedSourcePath => _selectedSourcePath;
  String? get selectedTargetPath => _selectedTargetPath;
  String? get toastMessage => _toastMessage;
  UsbBackupDialogData? get dialogData => _dialogData;
  bool get isLoading => _isLoading;
  bool get hasActiveTask => _snapshot.status == UsbBackupTaskStatus.running;
  bool get canStartBackup =>
      !hasActiveTask &&
      _selectedSourcePath != null &&
      _selectedSourcePath!.isNotEmpty;
  bool get canStartFormat =>
      !hasActiveTask &&
      _selectedTargetPath != null &&
      _selectedTargetPath!.isNotEmpty;
  bool get canStopTask => hasActiveTask && _snapshot.taskType != 'format';
  bool get canMutateRepository => !hasActiveTask;
  UsbBackupPendingBackup? get selectedSourcePendingBackup {
    final String? selectedSourcePath = _selectedSourcePath;
    if (selectedSourcePath == null) {
      return null;
    }
    for (final UsbBackupPendingBackup backup in _pendingBackups) {
      if (backup.sourceRoot == selectedSourcePath) {
        return backup;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    await refreshAll();
  }

  Future<void> refreshAll({bool forceRefresh = false}) async {
    final Future<void>? existing = _refreshAllFuture;
    if (existing != null) {
      return existing;
    }
    final Future<void> future = _runRefreshAll(forceRefresh: forceRefresh);
    _refreshAllFuture = future;
    try {
      await future;
    } finally {
      if (identical(_refreshAllFuture, future)) {
        _refreshAllFuture = null;
      }
    }
  }

  Future<void> _runRefreshAll({required bool forceRefresh}) async {
    await refreshVolumes(forceRefresh: forceRefresh);
    await refreshVersions();
  }

  Future<void> refreshVolumes({bool forceRefresh = false}) async {
    final Future<void>? existing = _refreshVolumesFuture;
    if (existing != null) {
      return existing;
    }
    final DateTime now = DateTime.now();
    if (!forceRefresh &&
        _lastVolumesRefreshedAt != null &&
        now.difference(_lastVolumesRefreshedAt!) < _volumeRefreshDebounce) {
      return;
    }
    final Future<void> future = _runRefreshVolumes(forceRefresh: forceRefresh);
    _refreshVolumesFuture = future;
    try {
      await future;
    } finally {
      if (identical(_refreshVolumesFuture, future)) {
        _refreshVolumesFuture = null;
      }
    }
  }

  Future<void> _runRefreshVolumes({required bool forceRefresh}) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _bridge.ensureStarted();
      final String? selectedSourceIdentity =
          _selectedSourceIdentity ??
          _identityForPath(_selectedSourcePath, _volumes);
      final String? selectedTargetIdentity =
          _selectedTargetIdentity ??
          _identityForPath(_selectedTargetPath, _volumes);
      final List<UsbBackupVolume> volumes = await _bridge.listUsbVolumes(
        selectedPath: _selectedTargetPath,
        forceRefresh: forceRefresh,
      );
      _volumes = volumes;
      _selectedSourcePath = _resolveSelectedPath(
        currentPath: _selectedSourcePath,
        currentIdentity: selectedSourceIdentity,
        volumes: volumes,
        fallbackToFirstVolume: _selectedSourcePath == null,
      );
      _selectedTargetPath = _resolveSelectedPath(
        currentPath: _selectedTargetPath,
        currentIdentity: selectedTargetIdentity,
        volumes: volumes,
        fallbackToFirstVolume: false,
      );
      _selectedSourceIdentity = _identityForPath(_selectedSourcePath, volumes);
      _selectedTargetIdentity = _identityForPath(_selectedTargetPath, volumes);
      _lastVolumesRefreshedAt = DateTime.now();
    } on UsbBackupBridgeException catch (error) {
      _setToast(error.message);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshVersions() async {
    final int requestId = ++_refreshVersionsRequestId;
    final String? requestedTargetPath = _selectedTargetPath;
    try {
      await _bridge.ensureStarted();
      final UsbBackupVersionListResult result = await _bridge
          .listBackupVersions(targetPath: requestedTargetPath);
      if (requestId != _refreshVersionsRequestId ||
          requestedTargetPath != _selectedTargetPath) {
        return;
      }
      _repoRoot = result.repoRoot;
      _versions = result.versions;
      _latestVersions = result.latestVersions;
      _pendingBackups = result.pendingBackups;
      notifyListeners();
    } on UsbBackupBridgeException catch (error) {
      if (requestId != _refreshVersionsRequestId) {
        return;
      }
      _clearPendingFormatSelection();
      _setToast(error.message);
    }
  }

  void updateCustomDisplayName(String value) {
    _customDisplayName = value;
    notifyListeners();
  }

  void updateFormatFilesystem(String value) {
    _formatFilesystem = value;
    notifyListeners();
  }

  void updateFormatVolumeLabel(String value) {
    _formatVolumeLabel = value;
    notifyListeners();
  }

  Future<void> selectSourcePath(String? path) async {
    _selectedSourcePath = path;
    _selectedSourceIdentity = _identityForPath(path, _volumes);
    notifyListeners();
  }

  Future<void> selectTargetPath(String? path) async {
    _selectedTargetPath = path;
    _selectedTargetIdentity = _identityForPath(path, _volumes);
    notifyListeners();
    await refreshVersions();
    if (path != _selectedTargetPath) {
      return;
    }
    final UsbBackupVolume? targetVolume = selectedTargetVolume;
    if (targetVolume != null && !targetVolume.isCdjSupportedFs) {
      _dialogData = UsbBackupDialogData(
        title: '目标U盘格式不支持',
        message:
            '当前U盘文件系统为 ${targetVolume.filesystem ?? targetVolume.normalizedFilesystem ?? '未知格式'}，'
            'CDJ 仅支持 FAT32 或 ExFAT。请先格式化后再恢复。',
      );
      notifyListeners();
    }
  }

  UsbBackupVolume? get selectedTargetVolume {
    final String? targetPath = _selectedTargetPath;
    if (targetPath == null) {
      return null;
    }
    for (final UsbBackupVolume volume in _volumes) {
      if (volume.path == targetPath) {
        return volume;
      }
    }
    return null;
  }

  Future<void> startBackup() async {
    final String? sourcePath = _selectedSourcePath;
    if (sourcePath == null || sourcePath.isEmpty) {
      _setToast('请先选择一个要备份的 U 盘。');
      return;
    }
    try {
      final UsbBackupTaskSnapshot started = await _bridge.startBackupUsb(
        sourcePath: sourcePath,
        displayName: _customDisplayName.trim().isEmpty
            ? null
            : _customDisplayName.trim(),
      );
      _snapshot = started;
      _startPolling(started.taskId);
      notifyListeners();
    } on UsbBackupBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> restoreVersion(UsbBackupVersion version) async {
    final String? targetPath = _selectedTargetPath;
    if (targetPath == null || targetPath.isEmpty) {
      _setToast('请先选择一个用于恢复的新 U 盘。');
      return;
    }
    if (!version.canRestore) {
      _setToast(version.disabledReason ?? '当前版本不可恢复。');
      return;
    }
    try {
      final UsbBackupTaskSnapshot started = await _bridge
          .startRestoreSnapshotToUsb(
            snapshotId: version.snapshotId,
            targetPath: targetPath,
          );
      _snapshot = started;
      _startPolling(started.taskId);
      notifyListeners();
    } on UsbBackupBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> startFormat() async {
    await startFormatForPath(_selectedTargetPath);
  }

  Future<void> startFormatForPath(String? targetPath) async {
    if (targetPath == null || targetPath.isEmpty) {
      _setToast('请先选择一个要格式化的目标 U 盘。');
      return;
    }
    try {
      _pendingFormatIdentity = _identityForPath(targetPath, _volumes);
      _pendingFormatAffectsSource = _selectedSourcePath == targetPath;
      _pendingFormatAffectsTarget = _selectedTargetPath == targetPath;
      final UsbBackupTaskSnapshot started = await _bridge.startFormatUsb(
        targetPath: targetPath,
        filesystem: _formatFilesystem,
        volumeLabel: _formatVolumeLabel.trim().isEmpty
            ? 'PIONEER'
            : _formatVolumeLabel.trim(),
      );
      _snapshot = started;
      _startPolling(started.taskId);
      notifyListeners();
    } on UsbBackupBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> deleteBackupVersion(UsbBackupVersion version) async {
    try {
      final UsbBackupCleanupResult result = await _bridge.deleteBackupVersion(
        version.snapshotId,
      );
      await refreshVersions();
      _setToast('已删除 1 个备份版本，清理 ${result.deletedObjects} 个孤立对象。');
    } on UsbBackupBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> cleanupRepository() async {
    try {
      final UsbBackupCleanupResult result = await _bridge.cleanupRepository();
      await refreshVersions();
      _setToast('仓库清理完成，删除 ${result.deletedObjects} 个孤立对象。');
    } on UsbBackupBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> ejectVolumeForPath(String? targetPath) async {
    if (hasActiveTask) {
      _setToast('当前有任务正在运行，暂时不能弹出 U 盘。');
      return;
    }
    if (targetPath == null || targetPath.isEmpty) {
      _setToast('请先选择一个要弹出的 U 盘。');
      return;
    }
    try {
      final Map<String, Object?> result = await _bridge.ejectUsbVolume(
        targetPath: targetPath,
      );
      final String volumeName = result['volume_name'] as String? ?? 'U 盘';
      if (_selectedSourcePath == targetPath) {
        _selectedSourcePath = null;
        _selectedSourceIdentity = null;
      }
      if (_selectedTargetPath == targetPath) {
        _selectedTargetPath = null;
        _selectedTargetIdentity = null;
      }
      await refreshAll(forceRefresh: true);
      _setToast('已安全弹出 U 盘: $volumeName');
    } on UsbBackupBridgeException catch (error) {
      _setToast(error.message);
    }
  }

  Future<void> stopTask() async {
    if (_snapshot.taskId.isEmpty) {
      return;
    }
    try {
      final UsbBackupTaskSnapshot stopped = await _bridge.stopTask(
        _snapshot.taskId,
      );
      _snapshot = stopped;
      notifyListeners();
    } on UsbBackupBridgeException catch (error) {
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

  void clearDialog() {
    if (_dialogData == null) {
      return;
    }
    _dialogData = null;
    if (_snapshot.status != UsbBackupTaskStatus.running) {
      _snapshot = const UsbBackupTaskSnapshot.idle();
    }
    notifyListeners();
  }

  Future<void> close() async {
    _polling.stop();
    await _bridge.close();
  }

  void _startPolling(String taskId) {
    _polling.start(() async {
      try {
        final List<UsbBackupTaskEvent> events = await _bridge
            .subscribeTaskEvents(taskId: taskId);
        if (events.isEmpty) {
          return;
        }
        for (final UsbBackupTaskEvent event in events) {
          _snapshot = event.snapshot;
        }
        notifyListeners();
        if (_snapshot.status == UsbBackupTaskStatus.running &&
            (_snapshot.taskType == 'backup' ||
                _snapshot.taskType == 'restore')) {
          unawaited(refreshVolumes(forceRefresh: true));
        }
        if (_snapshot.status != UsbBackupTaskStatus.running) {
          _polling.stop();
          await refreshAll(forceRefresh: true);
          _handleTerminalTaskOutcome();
        }
      } on UsbBackupBridgeException catch (error) {
        _polling.stop();
        _setToast(error.message);
      }
    });
  }

  void _setToast(String message) {
    _toastMessage = message;
    notifyListeners();
  }

  void _handleTerminalTaskOutcome() {
    switch (_snapshot.taskType) {
      case 'backup':
        _handleBackupTerminalOutcome();
        return;
      case 'restore':
        _handleRestoreTerminalOutcome();
        return;
      case 'format':
        _handleFormatTerminalOutcome();
        return;
      default:
        return;
    }
  }

  void _handleBackupTerminalOutcome() {
    if (_snapshot.status == UsbBackupTaskStatus.success) {
      final String displayName = _snapshot.displayName ?? '当前备份';
      _dialogData = UsbBackupDialogData(
        title: '备份完成',
        message:
            '备份已完成。\n\n备份名称: $displayName\n文件数: ${_snapshot.totalFiles}\n数据量: ${_snapshot.totalBytes} 字节',
      );
      notifyListeners();
      return;
    }
    if (_snapshot.status == UsbBackupTaskStatus.error) {
      _dialogData = UsbBackupDialogData(
        title:
            _isLikelyVolumeRemoved(
              _snapshot.errorMessage ?? _snapshot.progressHintText,
            )
            ? '备份中断：U 盘已断开'
            : '备份失败',
        message: _buildTerminalErrorMessage(
          _snapshot.errorMessage ?? _snapshot.progressHintText,
          volumeRemovedAction: '备份',
        ),
      );
      notifyListeners();
    }
  }

  void _handleRestoreTerminalOutcome() {
    if (_snapshot.status == UsbBackupTaskStatus.success) {
      final String validationMessage =
          _snapshot.restoreValidation?.message ?? '恢复后校验结果暂未返回。';
      _dialogData = UsbBackupDialogData(
        title: '恢复完成',
        message: '恢复已完成，目标 U 盘现在可以继续操作。\n\n$validationMessage',
      );
      notifyListeners();
      return;
    }
    if (_snapshot.status == UsbBackupTaskStatus.error) {
      _dialogData = UsbBackupDialogData(
        title:
            _isLikelyVolumeRemoved(
              _snapshot.errorMessage ?? _snapshot.progressHintText,
            )
            ? '恢复中断：U 盘已断开'
            : '恢复失败',
        message: _buildTerminalErrorMessage(
          _snapshot.errorMessage ?? _snapshot.progressHintText,
          volumeRemovedAction: '恢复',
        ),
      );
      notifyListeners();
    }
  }

  void _handleFormatTerminalOutcome() {
    if (_snapshot.status == UsbBackupTaskStatus.success) {
      _restoreFormattedVolumeSelection();
      _setToast('格式化完成，设备列表已刷新。');
      return;
    }
    if (_snapshot.status == UsbBackupTaskStatus.error &&
        _snapshot.errorMessage != null &&
        _snapshot.errorMessage!.isNotEmpty) {
      _dialogData = UsbBackupDialogData(
        title: '格式化失败',
        message: _snapshot.errorMessage!,
      );
      notifyListeners();
    }
    _clearPendingFormatSelection();
  }

  String _buildTerminalErrorMessage(
    String message, {
    required String volumeRemovedAction,
  }) {
    if (_isLikelyVolumeRemoved(message)) {
      return '执行$volumeRemovedAction时检测到目标 U 盘已断开或被系统移除。\n\n$message\n\n请重新插入 U 盘并点击刷新后再试。';
    }
    return message;
  }

  bool _isLikelyVolumeRemoved(String message) {
    final String lowered = message.toLowerCase();
    return lowered.contains('no such file or directory') ||
        lowered.contains('not found') ||
        lowered.contains('media not present') ||
        lowered.contains('device not configured') ||
        lowered.contains('目标 u 盘可能已断开') ||
        lowered.contains('目标 u 盘已断开') ||
        lowered.contains('u 盘已断开');
  }

  void _restoreFormattedVolumeSelection() {
    final String? identity = _pendingFormatIdentity;
    if (identity == null) {
      _clearPendingFormatSelection();
      return;
    }
    UsbBackupVolume? matchedVolume;
    for (final UsbBackupVolume volume in _volumes) {
      if (_volumeIdentity(volume) == identity) {
        matchedVolume = volume;
        break;
      }
    }
    if (matchedVolume == null) {
      _clearPendingFormatSelection();
      return;
    }
    if (_pendingFormatAffectsSource) {
      _selectedSourcePath = matchedVolume.path;
      _selectedSourceIdentity = identity;
    }
    if (_pendingFormatAffectsTarget) {
      _selectedTargetPath = matchedVolume.path;
      _selectedTargetIdentity = identity;
    }
    _clearPendingFormatSelection();
    notifyListeners();
  }

  void _clearPendingFormatSelection() {
    _pendingFormatIdentity = null;
    _pendingFormatAffectsSource = false;
    _pendingFormatAffectsTarget = false;
  }

  String? _resolveSelectedPath({
    required String? currentPath,
    required String? currentIdentity,
    required List<UsbBackupVolume> volumes,
    required bool fallbackToFirstVolume,
  }) {
    if (currentPath != null &&
        volumes.any((UsbBackupVolume item) => item.path == currentPath)) {
      return currentPath;
    }
    if (currentIdentity != null) {
      for (final UsbBackupVolume volume in volumes) {
        if (_volumeIdentity(volume) == currentIdentity) {
          return volume.path;
        }
      }
    }
    if (fallbackToFirstVolume && volumes.isNotEmpty) {
      return volumes.first.path;
    }
    return null;
  }

  String? _identityForPath(String? path, List<UsbBackupVolume> volumes) {
    if (path == null || path.isEmpty) {
      return null;
    }
    for (final UsbBackupVolume volume in volumes) {
      if (volume.path == path) {
        return _volumeIdentity(volume);
      }
    }
    return path;
  }

  String? _volumeIdentity(UsbBackupVolume volume) {
    return volume.wholeDiskIdentifier ??
        volume.diskIdentifier ??
        volume.serialNumber ??
        (volume.path.isEmpty ? null : volume.path);
  }
}
