import 'dart:io';
import 'dart:ui' show Offset, PointerDeviceKind, Size;

import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'package:dj_flutter/app/dj_app_scope.dart';
import 'package:dj_flutter/app/layout/app_layout_contract.dart';
import 'package:dj_flutter/app/router/app_router.dart';
import 'package:dj_flutter/app/shell/app_shell_page.dart';
import 'package:dj_flutter/app/shell/feature_card/glass_card.dart';
import 'package:dj_flutter/features/auth/presentation/controllers/auth_controller.dart';
import 'package:dj_flutter/features/auth/presentation/controllers/python_auth_task_bridge.dart';
import 'package:dj_flutter/features/auth/presentation/controllers/python_guest_task_bridge.dart';
import 'package:dj_flutter/features/auth/presentation/models/auth_session_store.dart';
import 'package:dj_flutter/features/auth/presentation/pages/login_page.dart';
import 'package:dj_flutter/features/auth/presentation/models/auth_session_snapshot.dart';
import 'package:dj_flutter/features/auth/presentation/models/auth_models.dart';
import 'package:dj_flutter/features/cleanup_dup/presentation/cleanup_dup_entry_page.dart';
import 'package:dj_flutter/features/cleanup_dup/presentation/controllers/cleanup_dup_controller.dart';
import 'package:dj_flutter/features/cleanup_dup/presentation/controllers/python_cleanup_dup_task_bridge.dart';
import 'package:dj_flutter/features/cleanup_dup/presentation/models/cleanup_dup_models.dart';
import 'package:dj_flutter/features/audio_transcode/presentation/audio_transcode_entry_page.dart';
import 'package:dj_flutter/shared/hardware_ui/hardware_ui.dart';
import 'package:dj_flutter/shared/task_runtime/task_running_notifier.dart';
import 'package:dj_flutter/features/audio_transcode/presentation/controllers/audio_transcode_controller.dart';
import 'package:dj_flutter/features/audio_transcode/presentation/models/audio_transcode_models.dart';
import 'package:dj_flutter/features/metadata_edit/presentation/controllers/metadata_edit_controller.dart';
import 'package:dj_flutter/features/metadata_edit/presentation/metadata_edit_entry_page.dart';
import 'package:dj_flutter/features/metadata_edit/presentation/models/metadata_edit_models.dart';
import 'package:dj_flutter/features/metadata_edit/presentation/widgets/cover_injection_panel.dart';
import 'package:dj_flutter/features/metadata_edit/presentation/widgets/filename_injection_panel.dart';
import 'package:dj_flutter/features/pinyin_generator/presentation/controllers/pinyin_generator_controller.dart';
import 'package:dj_flutter/features/pinyin_generator/presentation/models/pinyin_generator_models.dart';
import 'package:dj_flutter/features/pinyin_generator/presentation/pinyin_generator_entry_page.dart';
import 'package:dj_flutter/features/usb_backup/presentation/controllers/usb_backup_controller.dart';
import 'package:dj_flutter/features/usb_backup/presentation/models/usb_backup_models.dart';
import 'package:dj_flutter/features/usb_backup/presentation/usb_backup_entry_page.dart';
import 'package:dj_flutter/features/auth/presentation/widgets/history_dropdown.dart';
import 'package:dj_flutter/features/auth/presentation/widgets/login_credential_store.dart';
import 'package:dj_flutter/features/auth/presentation/widgets/login_card.dart';
import 'package:dj_flutter/features/auth/presentation/widgets/tactical_input.dart';
import 'package:dj_flutter/features/unlock_music/presentation/models/search_download_models.dart';
import 'package:dj_flutter/features/unlock_music/presentation/models/unlock_music_models.dart';
import 'package:dj_flutter/features/unlock_music/presentation/unlock_music_entry_page.dart';

String _pythonRuntimeDirectory() {
  return p.normalize(
    p.join(Directory.current.path, '..', '..', 'runtime', 'dj_runtime_py'),
  );
}

String _pythonRuntimeExecutable() {
  final String repoPython = p.normalize(
    p.join(Directory.current.path, '..', '..', '.venv', 'bin', 'python'),
  );
  if (File(repoPython).existsSync()) {
    return repoPython;
  }
  return 'python3';
}

void _mockWindowManager() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), (
        MethodCall methodCall,
      ) async {
        switch (methodCall.method) {
          case 'getBounds':
            return <String, double>{
              'x': 0,
              'y': 0,
              'width': 540,
              'height': 700,
            };
          case 'setBounds':
          case 'setMinimumSize':
          case 'setMaximumSize':
          case 'setSize':
          case 'setResizable':
          case 'center':
          case 'minimize':
          case 'close':
            return null;
        }
        return null;
      });
}

class _FakeAuthTaskBridge implements AuthTaskBridge {
  _FakeAuthTaskBridge({
    this.restoredSession,
    this.logoutDelay = Duration.zero,
    this.onLogout,
    this.onClearLocalSession,
  });

  final SavedSession? restoredSession;
  final Duration logoutDelay;
  final Future<void> Function(String token)? onLogout;
  final Future<void> Function()? onClearLocalSession;
  int checkEntitlementCallCount = 0;
  int getProfileCallCount = 0;

  @override
  Future<EntitlementResult> checkEntitlement({required String token}) async {
    checkEntitlementCallCount += 1;
    return const EntitlementResult(
      isVip: false,
      expiresAt: null,
      hasDjtool: false,
      guestRemainingSeconds: 0,
      message: '',
    );
  }

  @override
  Future<void> clearLocalSession() async {
    if (onClearLocalSession case final Future<void> Function() callback) {
      await callback();
    }
  }

  @override
  Future<PurchaseOrderResult> createDjToolOrder({required String token}) async {
    return const PurchaseOrderResult(
      codeUrl: 'https://example.com/pay/djtool',
      orderId: 'djtool-order',
      amountFen: 0,
    );
  }

  @override
  Future<PurchaseOrderResult> createVipOrder({required String token}) async {
    return const PurchaseOrderResult(
      codeUrl: 'https://example.com/pay/vip',
      orderId: 'vip-order',
      amountFen: 0,
    );
  }

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<ProfileResult> getFullProfile({required String token}) async {
    getProfileCallCount += 1;
    return const ProfileResult(
      isSuccess: true,
      user: UserProfile(
        email: 'tester@example.com',
        vipLevel: 0,
        vipExpireTime: null,
        points: 0,
      ),
      message: '',
    );
  }

  @override
  Future<ProfileResult> getProfile({required String token}) async {
    getProfileCallCount += 1;
    return const ProfileResult(
      isSuccess: true,
      user: UserProfile(
        email: 'tester@example.com',
        vipLevel: 0,
        vipExpireTime: null,
        points: 0,
      ),
      message: '',
    );
  }

  @override
  Future<AuthLoginResult> login({
    required String loginName,
    required String password,
  }) async {
    return AuthLoginResult(
      token: 'mock-token',
      authData: AuthSessionSnapshot(
        kind: AuthSessionKind.user,
        token: 'mock-token',
        tokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }

  @override
  Future<void> logout({required String token}) async {
    if (logoutDelay != Duration.zero) {
      await Future<void>.delayed(logoutDelay);
    }
    if (onLogout case final Future<void> Function(String token) callback) {
      await callback(token);
    }
  }

  @override
  Future<SavedSession?> restoreSession() async => restoredSession;

  @override
  Future<MetadataEditTaskSnapshot> startCoverInjectionTask() async {
    final String taskId = 'cover_task_${++_seed}';
    _taskPanels[taskId] = MetadataEditPanelKind.cover;
    return MetadataEditTaskSnapshot(
      taskId: taskId,
      taskType: MetadataEditTaskType.coverInjection,
      status: MetadataEditStatus.running,
      progress: 0.4,
      hintText: '正在注入封面图...',
      fileCount: (_effectiveResults(MetadataEditPanelKind.cover)).length,
      successCount: 0,
      skippedCount: 0,
      needCount: 0,
      failedCount: 0,
    );
  }

  @override
  Future<MetadataEditTaskSnapshot> startFilenameInjectionTask() async {
    final String taskId = 'filename_task_${++_seed}';
    _taskPanels[taskId] = MetadataEditPanelKind.filename;
    return MetadataEditTaskSnapshot(
      taskId: taskId,
      taskType: MetadataEditTaskType.filenameInjection,
      status: MetadataEditStatus.running,
      progress: 0.4,
      hintText: '正在注入文件名...',
      fileCount: (_effectiveResults(MetadataEditPanelKind.filename)).length,
      successCount: 0,
      skippedCount: 0,
      needCount: 0,
      failedCount: 0,
    );
  }

  @override
  Future<MetadataEditTaskSnapshot> stopTask(String taskId) async {
    final MetadataEditPanelKind panel =
        _taskPanels[taskId] ?? MetadataEditPanelKind.filename;
    return MetadataEditTaskSnapshot(
      taskId: taskId,
      taskType: panel == MetadataEditPanelKind.cover
          ? MetadataEditTaskType.coverInjection
          : MetadataEditTaskType.filenameInjection,
      status: MetadataEditStatus.cancelled,
      progress: 0.5,
      hintText: '任务已取消。',
      fileCount: (_effectiveResults(panel)).length,
      successCount: 0,
      skippedCount: 0,
      needCount: 0,
      failedCount: 0,
    );
  }

  @override
  Future<List<MetadataEditTaskEvent>> subscribeTaskEvents({
    String? taskId,
  }) async {
    if (taskId == null || _emitted.contains(taskId)) {
      return <MetadataEditTaskEvent>[];
    }
    _emitted.add(taskId);
    final MetadataEditPanelKind panel =
        _taskPanels[taskId] ?? MetadataEditPanelKind.filename;
    final List<MetadataEditResultItem> results = _effectiveResults(panel);
    return <MetadataEditTaskEvent>[
      MetadataEditTaskEvent(
        event: 'task_finished',
        taskId: taskId,
        snapshot: MetadataEditTaskSnapshot(
          taskId: taskId,
          taskType: panel == MetadataEditPanelKind.cover
              ? MetadataEditTaskType.coverInjection
              : MetadataEditTaskType.filenameInjection,
          status: panel == MetadataEditPanelKind.cover
              ? coverFinalStatus
              : filenameFinalStatus,
          progress: 1,
          hintText: '任务执行完毕。',
          fileCount: results.length,
          successCount: _countStatus(results, MetadataEditItemStatus.ok),
          skippedCount: _countStatus(results, MetadataEditItemStatus.skip),
          needCount: _countStatus(results, MetadataEditItemStatus.need),
          failedCount: _countStatus(results, MetadataEditItemStatus.fail),
        ),
      ),
    ];
  }

  @override
  Future<MetadataEditResult> fetchMetadataEditResult(String taskId) async {
    final MetadataEditPanelKind panel =
        _taskPanels[taskId] ?? MetadataEditPanelKind.filename;
    final List<MetadataEditResultItem> results = _effectiveResults(panel);
    return MetadataEditResult(
      taskId: taskId,
      status: panel == MetadataEditPanelKind.cover
          ? coverFinalStatus
          : filenameFinalStatus,
      results: results,
      successCount: _countStatus(results, MetadataEditItemStatus.ok),
      skippedCount: _countStatus(results, MetadataEditItemStatus.skip),
      needCount: _countStatus(results, MetadataEditItemStatus.need),
      failedCount: _countStatus(results, MetadataEditItemStatus.fail),
      logLines: const <String>[],
    );
  }

  @override
  Future<List<String>> loadTemplates() async => templates;

  @override
  Future<List<String>> saveTemplate(String template) async {
    templates = <String>[...templates, template];
    return templates;
  }

  @override
  Future<List<String>> deleteTemplate(String template) async {
    templates = templates.where((String item) => item != template).toList();
    return templates;
  }

  @override
  Future<void> close() async {}

  List<MetadataEditResultItem> _effectiveResults(MetadataEditPanelKind panel) {
    if (panel == MetadataEditPanelKind.cover) {
      return coverResultItems ??
          const <MetadataEditResultItem>[
            MetadataEditResultItem(
              status: MetadataEditItemStatus.ok,
              inputPath: '/music/cover_ok.mp3',
              outputPath: '/music/cover_ok.mp3',
              changed: true,
              backupPath: null,
              message: '封面注入成功。',
            ),
          ];
    }
    return filenameResultItems ??
        const <MetadataEditResultItem>[
          MetadataEditResultItem(
            status: MetadataEditItemStatus.ok,
            inputPath: '/music/name_ok.mp3',
            outputPath: '/music/name_ok.mp3',
            changed: true,
            backupPath: null,
            message: '文件名注入成功。',
          ),
        ];
  }

  int _countStatus(
    List<MetadataEditResultItem> results,
    MetadataEditItemStatus status,
  ) {
    return results
        .where((MetadataEditResultItem item) => item.status == status)
        .length;
  }
}

class _FakeUnlockMusicTaskBridge implements UnlockMusicTaskBridge {
  _FakeUnlockMusicTaskBridge({
    this.skippedPathsByBatch = const <String, List<String>>{},
    this.errorToThrow,
    this.outputDirectory = '/output',
  });

  int _seed = 0;
  final Set<String> _emitted = <String>{};
  final Map<String, List<String>> skippedPathsByBatch;
  final UnlockMusicBridgeException? errorToThrow;
  final String outputDirectory;
  String? lockedOutputDir;
  bool lockedOverwrite = false;
  bool lockedKeepSource = true;
  List<String> _loaded = <String>[];

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<UnlockMusicLoadResult> loadTargets(
    List<String> filePaths, {
    bool append = false,
  }) async {
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    final List<String> skipped = <String>[];
    final List<String> accepted = <String>[];
    for (final String path in filePaths) {
      final List<String>? configuredSkip = skippedPathsByBatch[path];
      if (configuredSkip != null) {
        skipped.addAll(configuredSkip);
        continue;
      }
      accepted.add(path);
    }
    if (append) {
      final List<String> merged = <String>[..._loaded];
      final Set<String> seen = _loaded.toSet();
      final List<String> addedPaths = <String>[];
      for (final String path in accepted) {
        if (seen.add(path)) {
          merged.add(path);
          addedPaths.add(path);
        }
      }
      _loaded = merged;
      return UnlockMusicLoadResult(
        filePaths: List<String>.from(_loaded),
        addedPaths: addedPaths,
        skippedPaths: skipped,
      );
    }
    _loaded = List<String>.from(accepted);
    return UnlockMusicLoadResult(
      filePaths: List<String>.from(_loaded),
      addedPaths: List<String>.from(_loaded),
      skippedPaths: skipped,
    );
  }

  @override
  Future<UnlockMusicLoadResult> removeTarget(String filePath) async {
    _loaded = _loaded.where((String item) => item != filePath).toList();
    return UnlockMusicLoadResult(
      filePaths: List<String>.from(_loaded),
      addedPaths: const <String>[],
      skippedPaths: const <String>[],
    );
  }

  @override
  Future<UnlockMusicLoadResult> clearTargets() async {
    _loaded = <String>[];
    return const UnlockMusicLoadResult(
      filePaths: <String>[],
      addedPaths: <String>[],
      skippedPaths: <String>[],
    );
  }

  @override
  Future<void> lockConfig(Map<String, Object?> config) async {
    lockedOutputDir = config['output_dir'] as String?;
    lockedOverwrite = config['overwrite'] as bool? ?? false;
    lockedKeepSource = config['keep_source'] as bool? ?? true;
  }

  @override
  Future<UnlockMusicTaskSnapshot> startUnlockTask() async {
    final String taskId = 'task_unlock_${++_seed}';
    final int fileCount = _loaded.length;
    final UnlockMusicTaskSnapshot snapshot = UnlockMusicTaskSnapshot(
      taskId: taskId,
      status: UnlockMusicStatus.running,
      progress: 0.12,
      progressHintText: '正在解锁... 0/$fileCount',
      fileCount: fileCount,
      successCount: 0,
      failedCount: 0,
    );
    return snapshot;
  }

  @override
  Future<UnlockMusicTaskSnapshot> stopTask(String taskId) async {
    return UnlockMusicTaskSnapshot(
      taskId: taskId,
      status: UnlockMusicStatus.cancelled,
      progress: 0.3,
      progressHintText: '任务已由用户手动停止。',
      fileCount: _loaded.length,
      successCount: 0,
      failedCount: 0,
    );
  }

  @override
  Future<List<UnlockMusicTaskEvent>> subscribeTaskEvents({
    String? taskId,
  }) async {
    if (taskId == null || _emitted.contains(taskId)) {
      return <UnlockMusicTaskEvent>[];
    }
    _emitted.add(taskId);
    final int fileCount = _loaded.length;
    final int successCount = fileCount > 0 ? 1 : 0;
    final int failedCount = fileCount > 1 ? 1 : 0;
    return <UnlockMusicTaskEvent>[
      UnlockMusicTaskEvent(
        event: 'task_progress',
        taskId: taskId,
        snapshot: UnlockMusicTaskSnapshot(
          taskId: taskId,
          status: UnlockMusicStatus.running,
          progress: fileCount == 0 ? 0 : 0.5,
          progressHintText: '正在解锁... ${fileCount > 0 ? 1 : 0}/$fileCount',
          fileCount: fileCount,
          successCount: successCount,
          failedCount: 0,
        ),
      ),
      UnlockMusicTaskEvent(
        event: 'task_finished',
        taskId: taskId,
        snapshot: UnlockMusicTaskSnapshot(
          taskId: taskId,
          status: UnlockMusicStatus.success,
          progress: 1,
          progressHintText: '解锁任务执行完毕。',
          fileCount: fileCount,
          successCount: successCount,
          failedCount: failedCount,
        ),
      ),
    ];
  }

  @override
  Future<UnlockMusicResult> fetchUnlockResult(String taskId) async {
    final List<UnlockMusicResultItem> results = <UnlockMusicResultItem>[
      if (_loaded.isNotEmpty)
        UnlockMusicResultItem(
          inputPath: _loaded.first,
          outputPath:
              '$outputDirectory/${p.basenameWithoutExtension(_loaded.first)}.mp3',
          success: true,
          format: 'mp3',
          error: null,
        ),
      if (_loaded.length > 1)
        UnlockMusicResultItem(
          inputPath: _loaded[1],
          outputPath: null,
          success: false,
          format: null,
          error: 'invalid ncm header',
        ),
    ];
    return UnlockMusicResult(
      taskId: taskId,
      status: UnlockMusicStatus.success,
      successCount: results
          .where((UnlockMusicResultItem item) => item.success)
          .length,
      failedCount: results
          .where((UnlockMusicResultItem item) => !item.success)
          .length,
      results: results,
    );
  }

  @override
  Future<void> close() async {}
}

class _FakeCleanupDupTaskBridge implements CleanupDupTaskBridge {
  int _seed = 0;
  final Set<String> _emitted = <String>{};
  final Map<CleanupDupPanelKind, Map<String, Object?>> _lockedConfigs =
      <CleanupDupPanelKind, Map<String, Object?>>{};
  List<String> _titleLoaded = <String>[];
  List<String> _duplicateLoaded = <String>[];
  String? lastLockedTitleDeleteText;

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<List<String>> loadTargets(
    CleanupDupPanelKind panel,
    List<String> filePaths,
  ) async {
    switch (panel) {
      case CleanupDupPanelKind.titleClean:
        _titleLoaded = List<String>.from(filePaths);
      case CleanupDupPanelKind.duplicateSearch:
        _duplicateLoaded = List<String>.from(filePaths);
    }
    return List<String>.from(filePaths);
  }

  @override
  Future<void> lockConfig(
    CleanupDupPanelKind panel,
    Map<String, Object?> config,
  ) async {
    if (panel == CleanupDupPanelKind.titleClean) {
      final String deleteText = (config['delete_text'] as String? ?? '').trim();
      if (deleteText.isEmpty) {
        throw const CleanupDupBridgeException('INVALID_CONFIG', '请输入要清除的文本内容。');
      }
      lastLockedTitleDeleteText = deleteText;
    }
    _lockedConfigs[panel] = Map<String, Object?>.from(config);
  }

  @override
  Future<CleanupDupTaskSnapshot> startTitleCleanTask() async {
    final String deleteText =
        (_lockedConfigs[CleanupDupPanelKind.titleClean]?['delete_text']
                    as String? ??
                '')
            .trim();
    if (deleteText.isEmpty) {
      throw const CleanupDupBridgeException('INVALID_CONFIG', '请输入要清除的文本内容。');
    }
    final String taskId = 'task_title_${++_seed}';
    return CleanupDupTaskSnapshot(
      taskId: taskId,
      panel: CleanupDupPanelKind.titleClean,
      taskType: CleanupDupTaskType.titleClean,
      status: CleanupDupStatus.running,
      progress: 0.12,
      progressHintText: '正在高速扫描扇区数据...',
      fileCount: _titleLoaded.length,
      duplicateCount: 0,
    );
  }

  @override
  Future<CleanupDupTaskSnapshot> startDuplicateCheckTask() async {
    final String taskId = 'task_dup_${++_seed}';
    return CleanupDupTaskSnapshot(
      taskId: taskId,
      panel: CleanupDupPanelKind.duplicateSearch,
      taskType: CleanupDupTaskType.duplicateCheck,
      status: CleanupDupStatus.running,
      progress: 0.12,
      progressHintText: '正在高速扫描扇区数据...',
      fileCount: _duplicateLoaded.length,
      duplicateCount: 0,
    );
  }

  @override
  Future<CleanupDupTaskSnapshot> stopTask(String taskId) async {
    final bool isTitleTask = taskId.startsWith('task_title_');
    return CleanupDupTaskSnapshot(
      taskId: taskId,
      panel: isTitleTask
          ? CleanupDupPanelKind.titleClean
          : CleanupDupPanelKind.duplicateSearch,
      taskType: isTitleTask
          ? CleanupDupTaskType.titleClean
          : CleanupDupTaskType.duplicateCheck,
      status: CleanupDupStatus.cancelled,
      progress: 0.5,
      progressHintText: '任务已由用户手动停止。',
      fileCount: isTitleTask ? _titleLoaded.length : _duplicateLoaded.length,
      duplicateCount: 0,
    );
  }

  @override
  Future<CleanupDupReviewResult> fetchReviewResult(String taskId) async {
    return CleanupDupReviewResult(
      taskId: taskId,
      panel: CleanupDupPanelKind.duplicateSearch,
      status: CleanupDupStatus.reviewReady,
      duplicateCount: 2,
      groups: <DuplicateGroup>[
        DuplicateGroup(
          groupName: 'Duplicate 001 Master',
          entries: const <DuplicateEntry>[
            DuplicateEntry(
              file: FileItem(
                path: '/music/Duplicate_001_Master.mp3',
                name: 'Duplicate_001_Master.mp3',
                size: '8.0 MB',
              ),
              isAutoKeep: true,
            ),
            DuplicateEntry(
              file: FileItem(
                path: '/music/Duplicate_001_Copy.mp3',
                name: 'Duplicate_001_Copy.mp3',
                size: '7.9 MB',
              ),
              isSelectedToDelete: true,
            ),
          ],
        ),
        DuplicateGroup(
          groupName: 'Duplicate 002 Master',
          entries: const <DuplicateEntry>[
            DuplicateEntry(
              file: FileItem(
                path: '/music/Duplicate_002_Master.mp3',
                name: 'Duplicate_002_Master.mp3',
                size: '8.1 MB',
              ),
              isAutoKeep: true,
            ),
            DuplicateEntry(
              file: FileItem(
                path: '/music/Duplicate_002_Copy.mp3',
                name: 'Duplicate_002_Copy.mp3',
                size: '8.0 MB',
              ),
              isSelectedToDelete: true,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<CleanupDupDeleteResult> executeDelete({
    required String taskId,
    required bool moveToRecycleBin,
    required List<FileItem> selectedFiles,
  }) async {
    return CleanupDupDeleteResult(
      taskId: taskId,
      deletedCount: selectedFiles.length,
      moveToRecycleBin: moveToRecycleBin,
      status: CleanupDupStatus.success,
    );
  }

  @override
  Future<List<CleanupDupTaskEvent>> subscribeTaskEvents({
    String? taskId,
  }) async {
    if (taskId == null || _emitted.contains(taskId)) {
      return <CleanupDupTaskEvent>[];
    }
    _emitted.add(taskId);
    if (taskId.startsWith('task_title_')) {
      return <CleanupDupTaskEvent>[
        CleanupDupTaskEvent(
          event: 'task_finished',
          taskId: taskId,
          snapshot: CleanupDupTaskSnapshot(
            taskId: taskId,
            panel: CleanupDupPanelKind.titleClean,
            taskType: CleanupDupTaskType.titleClean,
            status: CleanupDupStatus.success,
            progress: 1,
            progressHintText: '任务执行完毕。',
            fileCount: _titleLoaded.length,
            duplicateCount: 0,
          ),
        ),
      ];
    }
    return <CleanupDupTaskEvent>[
      CleanupDupTaskEvent(
        event: 'review_ready',
        taskId: taskId,
        snapshot: CleanupDupTaskSnapshot(
          taskId: taskId,
          panel: CleanupDupPanelKind.duplicateSearch,
          taskType: CleanupDupTaskType.duplicateCheck,
          status: CleanupDupStatus.reviewReady,
          progress: 1,
          progressHintText: '发现重复项，请审阅确认。',
          fileCount: _duplicateLoaded.length,
          duplicateCount: 2,
        ),
      ),
    ];
  }

  @override
  Future<void> close() async {}
}

Future<void> _pumpCleanupDupModule(
  WidgetTester tester, {
  required CleanupDupTaskBridge bridge,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(child: CleanupDupEntryPage(bridge: bridge)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'login card shows expired subscribe glow and hides guest button',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 650);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LoginCard())),
      );
      await tester.pump();

      final dynamic state = tester.state(find.byType(LoginCard));
      state.debugSetUserState('expired');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('免费体验'), findsNothing);

      final Text subscribeText = tester.widget<Text>(find.text('去开通'));
      expect(subscribeText.style?.fontWeight, FontWeight.bold);
      expect(subscribeText.style?.shadows?.isNotEmpty ?? false, isTrue);
    },
  );

  testWidgets('guest button remains visible while trial has not expired', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 650);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LoginCard(
            guestTrial: GuestTrialSnapshot(
              state: GuestTrialState.active,
              remainingTime: '05:30:00',
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.textContaining('体验剩余 05:30:00'), findsOneWidget);
    expect(find.text('免费体验'), findsNothing);
  });

  testWidgets(
    'login card error banner shakes and login button drops on press',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 650);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LoginCard())),
      );
      await tester.pump();

      final dynamic state = tester.state(find.byType(LoginCard));
      state.debugSetHideDisclaimer(true);
      await tester.pump();
      await tester.tap(find.text('登 录'));
      await tester.pump();

      expect(find.text('请输入完整的账号和密码。'), findsOneWidget);

      final Finder errorBanner = find.text('请输入完整的账号和密码。');
      final Offset start = tester.getTopLeft(errorBanner);
      await tester.pump(const Duration(milliseconds: 100));
      final Offset mid = tester.getTopLeft(errorBanner);
      expect(mid.dx, isNot(start.dx));
      await tester.pump(const Duration(milliseconds: 350));
      final Offset end = tester.getTopLeft(errorBanner);
      expect(end.dx, closeTo(start.dx, 1));
    },
  );

  testWidgets('login card persists hide disclaimer for login only', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(420, 650);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoginCard())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('登 录'));
    await tester.pump();
    await tester.tap(find.text('下次不再弹出'));
    await tester.pump();
    await tester.tap(find.text('我已阅读并同意'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('hideDisclaimer'), isTrue);

    await tester.tap(find.text('免责协议'));
    await tester.pump();
    expect(find.text('下次不再弹出'), findsNothing);
  });

  testWidgets('login card disclaimer uses hardware dialog layout', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(420, 650);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoginCard())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('登 录'));
    await tester.pump();

    expect(find.byType(HardwareDialog), findsOneWidget);
    expect(find.text('用户免责协议'), findsOneWidget);
    expect(find.text('下次不再弹出'), findsOneWidget);
    expect(find.text('我已阅读并同意'), findsOneWidget);
  });

  testWidgets('login card persists history and remembered password', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final _FakeLoginCredentialStore credentialStore =
        _FakeLoginCredentialStore();

    tester.view.physicalSize = const Size(420, 650);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginCard(
            credentialStore: credentialStore,
            onLogin: (_, _) async => AuthSessionSnapshot(
              kind: AuthSessionKind.user,
              token: 'mock-token',
              tokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(LoginCard));
    state.debugSetHideDisclaimer(true);
    await tester.pump();

    final Finder fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'tester@example.com');
    await tester.enterText(fields.at(1), 'password123');
    await tester.tap(find.text('登 录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(credentialStore.passwords['tester@example.com'], 'password123');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LoginCard(credentialStore: credentialStore)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final List<EditableText> restoredFields = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .toList();
    expect(restoredFields[0].controller.text, 'tester@example.com');
    expect(restoredFields[1].controller.text, 'password123');

    await tester.tap(find.text('▼'));
    await tester.pump();

    expect(find.text('tester@example.com'), findsWidgets);
  });

  testWidgets('login card keeps history but clears remembered password', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final _FakeLoginCredentialStore credentialStore =
        _FakeLoginCredentialStore();

    tester.view.physicalSize = const Size(420, 650);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginCard(
            credentialStore: credentialStore,
            onLogin: (_, _) async => AuthSessionSnapshot(
              kind: AuthSessionKind.user,
              token: 'mock-token',
              tokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(LoginCard));
    state.debugSetHideDisclaimer(true);
    await tester.pump();

    final Finder fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'tester@example.com');
    await tester.enterText(fields.at(1), 'password123');
    await tester.tap(find.text('记住密码'));
    await tester.pump();
    await tester.tap(find.text('登 录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      credentialStore.passwords.containsKey('tester@example.com'),
      isFalse,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LoginCard(credentialStore: credentialStore)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final List<EditableText> restoredFields = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .toList();
    expect(restoredFields[0].controller.text, 'tester@example.com');
    expect(restoredFields[1].controller.text, isEmpty);

    await tester.tap(find.text('▼'));
    await tester.pump();

    expect(find.text('tester@example.com'), findsWidgets);
  });

  testWidgets('login card auto logs in with saved credentials', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'hideDisclaimer': true,
      'rememberPassword': true,
      'autoLogin': true,
      'lastLoginAccount': 'tester@example.com',
      'loginHistoryAccounts': <String>['tester@example.com'],
      'hasSuccessfulAccountLogin': true,
    });
    final _FakeLoginCredentialStore credentialStore =
        _FakeLoginCredentialStore()
          ..passwords['tester@example.com'] = 'password123';
    final List<String> submitted = <String>[];

    tester.view.physicalSize = const Size(420, 650);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginCard(
            credentialStore: credentialStore,
            onLogin: (String loginName, String password) async {
              submitted.add('$loginName|$password');
              return AuthSessionSnapshot(
                kind: AuthSessionKind.user,
                token: 'mock-token',
                tokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(submitted, <String>['tester@example.com|password123']);
  });

  testWidgets('tactical input uses overlay suffix positioning', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TacticalInput(
            label: '账号',
            placeholder: '请输入邮箱',
            suffixIcon: const Icon(Icons.arrow_drop_down, size: 18),
          ),
        ),
      ),
    );
    await tester.pump();

    final Finder textField = find.byType(EditableText);
    final Finder icon = find.byIcon(Icons.arrow_drop_down);
    expect(icon, findsOneWidget);
    expect(
      tester.getCenter(icon).dx,
      greaterThan(tester.getTopRight(textField).dx - 24),
    );
  });

  testWidgets('history dropdown delete action uses tactical text button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HistoryDropdown(
              width: 320,
              items: const [
                {'account': 'tester@example.com', 'password': 'password123'},
              ],
              onSelect: (_, _) {},
              onDelete: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('删除'), findsOneWidget);
    expect(find.text('🗑️'), findsNothing);
  });

  testWidgets('footer links brighten on hover with html spacing', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 650);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoginCard())),
    );
    await tester.pump();

    final Finder disclaimerText = find.text('免责协议');
    final Text beforeHover = tester.widget<Text>(disclaimerText);
    expect(beforeHover.style?.color, const Color(0xFF6B7280));

    final Finder disclaimerGesture = find
        .ancestor(of: disclaimerText, matching: find.byType(GestureDetector))
        .first;
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(disclaimerGesture));
    await mouse.moveTo(tester.getCenter(disclaimerGesture));
    await tester.pump();

    final Text afterHover = tester.widget<Text>(disclaimerText);
    expect(afterHover.style?.color, const Color(0xFFD1D5DB));

    final Finder leftSep = find.text('|').first;
    final Finder subscribeText = find.text('去开通');
    final double gap =
        tester.getCenter(subscribeText).dx - tester.getCenter(leftSep).dx;
    expect(gap, greaterThan(24));
    expect(gap, lessThan(48));
  });

  testWidgets('login page shows remaining guest trial time after reopen', (
    WidgetTester tester,
  ) async {
    await _pumpLoginPageWithMockScope(
      tester,
      restoredGuestSession: SavedGuestSession(
        trialState: GuestTrialState.active,
        machineHash: 'mock_machine_hash',
        expiresAt:
            DateTime.now()
                .add(const Duration(hours: 6))
                .millisecondsSinceEpoch ~/
            1000,
        remainingHours: 5.5,
        valid: true,
      ),
    );

    expect(find.textContaining('体验剩余'), findsOneWidget);
    expect(find.text('免费体验'), findsNothing);
  });

  testWidgets(
    'login page hides guest button and blinks subscribe after trial expired',
    (WidgetTester tester) async {
      await _pumpLoginPageWithMockScope(
        tester,
        restoredGuestSession: const SavedGuestSession(
          trialState: GuestTrialState.expired,
          machineHash: 'mock_machine_hash',
          valid: false,
          reason: 'expired',
        ),
      );

      expect(find.text('免费体验'), findsNothing);
      expect(find.text('去开通'), findsOneWidget);
    },
  );

  test('guest revalidation required does not mark trial as expired', () async {
    final AuthController controller = AuthController(
      authBridge: _FakeAuthTaskBridge(),
      guestBridge: _FakeGuestTaskBridge(
        restoredGuestSession: const SavedGuestSession(
          trialState: GuestTrialState.unknown,
          machineHash: 'mock_machine_hash',
          valid: false,
          reason: '免费体验需要联网校验，请联网后重试。',
          needNetworkValidation: true,
        ),
      ),
    );

    final AuthSessionSnapshot snapshot = await controller.restoreSession();

    expect(snapshot.kind, AuthSessionKind.anonymous);
    expect(snapshot.guestTrial.state, GuestTrialState.unknown);
    expect(snapshot.needNetworkValidation, isTrue);
  });

  testWidgets(
    'expired login page stops blinking after successful login history',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'hasSuccessfulAccountLogin': true,
      });
      tester.view.physicalSize = const Size(420, 650);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoginCard(
              guestTrial: GuestTrialSnapshot(state: GuestTrialState.expired),
              hasSuccessfulLoginHistory: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final Text subscribeText = tester.widget<Text>(find.text('去开通'));
      expect(subscribeText.style?.shadows?.isNotEmpty ?? false, isFalse);
    },
  );

  test(
    'auth controller restoreSession reuses runtime snapshot without refetch',
    () async {
      final _FakeAuthTaskBridge authBridge = _FakeAuthTaskBridge(
        restoredSession: SavedSession(
          token: 'restored-token',
          userId: 'user-001',
          loginName: 'vip@example.com',
          expiresAt: DateTime.now().add(const Duration(hours: 2)),
          isVip: true,
          vipExpiresAt: DateTime.now().add(const Duration(days: 30)),
          stageName: '恢复账号',
          avatarType: 'female',
          avatarUrl: 'https://example.com/avatar.png',
          needNetworkValidation: true,
        ),
      );
      final AuthController controller = AuthController(
        authBridge: authBridge,
        guestBridge: _FakeGuestTaskBridge(),
      );

      final AuthSessionSnapshot snapshot = await controller.restoreSession();

      expect(snapshot.kind, AuthSessionKind.user);
      expect(snapshot.loginName, 'vip@example.com');
      expect(snapshot.stageName, '恢复账号');
      expect(snapshot.isVip, isTrue);
      expect(snapshot.needNetworkValidation, isTrue);
      expect(authBridge.checkEntitlementCallCount, 0);
      expect(authBridge.getProfileCallCount, 0);
    },
  );

  testWidgets('anonymous shell route redirects back to login page', (
    WidgetTester tester,
  ) async {
    await _pumpRoutedAppWithMockScope(
      tester,
      initialSnapshot: AuthSessionSnapshot.anonymous,
      initialRoute: AppRouter.shellPath,
    );

    expect(find.text('账号'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
  });

  testWidgets('login page keeps transition wrapper visible at idle', (
    WidgetTester tester,
  ) async {
    await _pumpLoginPageWithMockScope(tester);

    final AnimatedOpacity transition = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey<String>('login_page_transition')),
    );
    expect(transition.opacity, 1);
  });

  testWidgets('shell page fades in after first frame', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AuthSessionStore sessionStore = AuthSessionStore();
    sessionStore.update(
      AuthSessionSnapshot(
        kind: AuthSessionKind.user,
        token: 'mock_token',
        userId: 'fade_user',
        loginName: 'fade@example.com',
        stageName: 'Fade User',
        tokenExpiresAt: DateTime.now().add(const Duration(hours: 6)),
        isVip: true,
      ),
    );
    addTearDown(sessionStore.dispose);

    final AuthTaskBridge authBridge = _FakeAuthTaskBridge();
    final GuestTaskBridge guestBridge = _FakeGuestTaskBridge();
    final AuthController authController = AuthController(
      authBridge: authBridge,
      guestBridge: guestBridge,
    );

    await tester.pumpWidget(
      DjAppScope(
        sessionStore: sessionStore,
        authController: authController,
        authBridge: authBridge,
        guestBridge: guestBridge,
        taskRunningNotifier: TaskRunningNotifier(),
        child: MaterialApp(
          home: const AppShellPage(initialSection: AppShellSection.overview),
        ),
      ),
    );

    AnimatedOpacity transition = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey<String>('shell_page_transition')),
    );
    expect(transition.opacity, 0);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    transition = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey<String>('shell_page_transition')),
    );
    expect(transition.opacity, 1);
  });

  testWidgets('renders shell placeholder layout', (WidgetTester tester) async {
    await _pumpDjFlutterAppWithMockScope(
      tester,
      AuthSessionSnapshot(
        kind: AuthSessionKind.user,
        token: 'mock_token',
        userId: 'layout_user',
        loginName: 'layout@example.com',
        stageName: 'Layout User',
        tokenExpiresAt: DateTime.now().add(const Duration(hours: 6)),
        isVip: true,
      ),
    );

    expect(find.byType(GlassCard), findsNWidgets(6));
    expect(find.text('解锁工具'), findsOneWidget);
    expect(find.text('音频转码'), findsOneWidget);
    expect(find.text('首拼生成'), findsOneWidget);
    expect(find.text('曲库整理'), findsOneWidget);
    expect(find.text('信息修改'), findsOneWidget);
    expect(find.text('U盘备份'), findsOneWidget);
    expect(find.text('工作区'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('shell_window_control_close')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bottom_version_label')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('gift_widget_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('user_center_trigger')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bottom_led_group')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bottom_led_dot_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bottom_led_dot_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('bottom_led_dot_2')),
      findsOneWidget,
    );

    final Offset giftTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('gift_widget_button')),
    );
    final Size giftSize = tester.getSize(
      find.byKey(const ValueKey<String>('gift_widget_button')),
    );
    final Offset versionTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('bottom_version_label')),
    );
    expect(giftTopLeft.dx, lessThan(versionTopLeft.dx));
    expect(
      giftSize.height,
      lessThanOrEqualTo(AppLayoutContract.bottomStatusBarHeight),
    );

    final Offset userCenterTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('user_center_trigger')),
    );
    final Offset minimizeTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('shell_window_control_minimize')),
    );
    expect(userCenterTopLeft.dx, lessThan(minimizeTopLeft.dx));
    expect(minimizeTopLeft.dx - (userCenterTopLeft.dx + 28), closeTo(8, 0.1));

    final AnimatedContainer userCenterTrigger = tester
        .widget<AnimatedContainer>(
          find.byKey(const ValueKey<String>('user_center_trigger')),
        );
    final BoxDecoration userCenterDecoration =
        userCenterTrigger.decoration! as BoxDecoration;
    expect(userCenterDecoration.gradient, isNotNull);
  });

  testWidgets('guest shell hides user center trigger', (
    WidgetTester tester,
  ) async {
    await _pumpDjFlutterAppWithMockScope(
      tester,
      AuthSessionSnapshot(
        kind: AuthSessionKind.guest,
        guestToken: 'mock_token',
        tokenExpiresAt: DateTime.now().add(const Duration(hours: 6)),
        remainingTime: '6:00:00',
        isVip: false,
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('user_center_trigger')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('user_center_panel')),
      findsNothing,
    );
  });

  testWidgets('user center opens and closes from top trigger', (
    WidgetTester tester,
  ) async {
    await _pumpDjFlutterAppWithMockScope(
      tester,
      AuthSessionSnapshot(
        kind: AuthSessionKind.user,
        token: 'mock_token',
        userId: 'user_001',
        loginName: 'vip@example.com',
        stageName: 'VIP User',
        avatarType: 'male',
        isVip: true,
        vipExpiresAt: DateTime.now().add(const Duration(days: 365)),
        entitlements: const [
          EntitlementInfo(
            entitlementType: 'web_vip',
            status: 'active',
            daysLeft: 29,
          ),
          EntitlementInfo(
            entitlementType: 'dj_tool',
            status: 'active',
            daysLeft: 12,
          ),
        ],
      ),
    );

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('user_center_trigger')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(
      find.byKey(const ValueKey<String>('user_center_panel')),
      findsOneWidget,
    );
    expect(find.text('个人中心'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('艺名：'), findsOneWidget);
    expect(find.text('VIP User'), findsOneWidget);
    expect(find.text('账号：'), findsOneWidget);
    expect(find.text('vip@example.com'), findsOneWidget);
    expect(find.text('VIP会员'), findsOneWidget);
    expect(find.text('DJ工具'), findsOneWidget);
    expect(find.text('29天'), findsOneWidget);
    expect(find.text('12天'), findsOneWidget);

    await mouse.moveTo(const Offset(0, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(
      find.byKey(const ValueKey<String>('user_center_panel')),
      findsNothing,
    );
  });

  testWidgets(
    'user center header uses mystery name when stage matches account',
    (WidgetTester tester) async {
      await _pumpDjFlutterAppWithMockScope(
        tester,
        AuthSessionSnapshot(
          kind: AuthSessionKind.user,
          token: 'mock_token',
          userId: 'user_001',
          loginName: 'same@example.com',
          stageName: 'same@example.com',
          avatarType: 'female',
          isVip: false,
        ),
      );

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey<String>('user_center_trigger')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      expect(find.text('艺名：'), findsOneWidget);
      expect(find.text('这个神秘人还没有名字'), findsOneWidget);
      expect(find.text('账号：'), findsOneWidget);
      expect(find.text('same@example.com'), findsOneWidget);
    },
  );

  testWidgets('logout navigates to login before background cleanup completes', (
    WidgetTester tester,
  ) async {
    _mockWindowManager();
    bool logoutCompleted = false;
    final AuthTaskBridge authBridge = _FakeAuthTaskBridge(
      logoutDelay: const Duration(seconds: 5),
      onLogout: (_) async {
        logoutCompleted = true;
      },
    );

    await _pumpDjFlutterAppWithMockScope(
      tester,
      const AuthSessionSnapshot(
        kind: AuthSessionKind.user,
        token: 'mock_token',
        userId: 'user_001',
        loginName: 'vip@example.com',
        stageName: 'VIP User',
        avatarType: 'male',
        isVip: true,
      ),
      authBridge: authBridge,
      useRouter: true,
    );
    expect(
      find.byKey(const ValueKey<String>('user_center_trigger')),
      findsOneWidget,
    );

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('user_center_trigger')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    final Offset logoutCenter = tester.getCenter(find.text('退出登录'));
    await mouse.moveTo(logoutCenter);
    await tester.pump();
    await mouse.down(logoutCenter);
    await tester.pump();
    await mouse.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(logoutCompleted, isFalse);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(logoutCompleted, isTrue);
  });

  testWidgets('logout still navigates to login when local cleanup throws', (
    WidgetTester tester,
  ) async {
    _mockWindowManager();
    final AuthTaskBridge authBridge = _FakeAuthTaskBridge(
      onClearLocalSession: () async {
        throw Exception('mock clear failure');
      },
    );

    await _pumpDjFlutterAppWithMockScope(
      tester,
      const AuthSessionSnapshot(
        kind: AuthSessionKind.user,
        token: 'mock_token',
        userId: 'user_001',
        loginName: 'vip@example.com',
        stageName: 'VIP User',
        avatarType: 'male',
        isVip: true,
      ),
      authBridge: authBridge,
      useRouter: true,
    );

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('user_center_trigger')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    final Offset logoutCenter = tester.getCenter(find.text('退出登录'));
    await mouse.moveTo(logoutCenter);
    await tester.pump();
    await mouse.down(logoutCenter);
    await tester.pump();
    await mouse.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();

    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('logout shows confirmation dialog when tasks are running', (
    WidgetTester tester,
  ) async {
    _mockWindowManager();
    final TaskRunningNotifier taskRunningNotifier = TaskRunningNotifier()
      ..setRunning(AppShellSection.audioTranscode, true);

    await _pumpDjFlutterAppWithMockScope(
      tester,
      const AuthSessionSnapshot(
        kind: AuthSessionKind.user,
        token: 'mock_token',
        userId: 'user_001',
        loginName: 'vip@example.com',
        stageName: 'VIP User',
        avatarType: 'male',
        isVip: true,
      ),
      taskRunningNotifier: taskRunningNotifier,
      useRouter: true,
    );

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('user_center_trigger')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    final Offset logoutCenter = tester.getCenter(find.text('退出登录'));
    await mouse.moveTo(logoutCenter);
    await tester.pump();
    await mouse.down(logoutCenter);
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect(find.text('退出登录会中断正在运行的任务'), findsOneWidget);
    expect(find.text('音频转码任务正在运行，继续退出会中断任务。是否继续？'), findsOneWidget);
    expect(find.text('暂不退出'), findsOneWidget);
    expect(find.text('坚持退出'), findsOneWidget);
  });

  testWidgets(
    'logout stays on shell after choosing cancel with running tasks',
    (WidgetTester tester) async {
      _mockWindowManager();
      final TaskRunningNotifier taskRunningNotifier = TaskRunningNotifier()
        ..setRunning(AppShellSection.audioTranscode, true);

      await _pumpDjFlutterAppWithMockScope(
        tester,
        const AuthSessionSnapshot(
          kind: AuthSessionKind.user,
          token: 'mock_token',
          userId: 'user_001',
          loginName: 'vip@example.com',
          stageName: 'VIP User',
          avatarType: 'male',
          isVip: true,
        ),
        taskRunningNotifier: taskRunningNotifier,
        useRouter: true,
      );

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey<String>('user_center_trigger')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      final Offset logoutCenter = tester.getCenter(find.text('退出登录'));
      await mouse.moveTo(logoutCenter);
      await tester.pump();
      await mouse.down(logoutCenter);
      await tester.pump();
      await mouse.up();
      await tester.pump();

      await tester.tap(find.text('暂不退出'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      expect(find.byType(LoginPage), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('user_center_trigger')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'logout navigates to login after choosing confirm with running tasks',
    (WidgetTester tester) async {
      _mockWindowManager();
      final TaskRunningNotifier taskRunningNotifier = TaskRunningNotifier()
        ..setRunning(AppShellSection.audioTranscode, true);

      await _pumpDjFlutterAppWithMockScope(
        tester,
        const AuthSessionSnapshot(
          kind: AuthSessionKind.user,
          token: 'mock_token',
          userId: 'user_001',
          loginName: 'vip@example.com',
          stageName: 'VIP User',
          avatarType: 'male',
          isVip: true,
        ),
        taskRunningNotifier: taskRunningNotifier,
        useRouter: true,
      );

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey<String>('user_center_trigger')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      final Offset logoutCenter = tester.getCenter(find.text('退出登录'));
      await mouse.moveTo(logoutCenter);
      await tester.pump();
      await mouse.down(logoutCenter);
      await tester.pump();
      await mouse.up();
      await tester.pump();

      await tester.tap(find.text('坚持退出'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump();

      expect(find.byType(LoginPage), findsOneWidget);
    },
  );

  testWidgets('switch confirmation dialog shows running module name', (
    WidgetTester tester,
  ) async {
    final TaskRunningNotifier taskRunningNotifier = TaskRunningNotifier()
      ..setRunning(AppShellSection.audioTranscode, true);

    await _pumpDjFlutterAppWithMockScope(
      tester,
      const AuthSessionSnapshot(
        kind: AuthSessionKind.user,
        token: 'mock_token',
        userId: 'user_001',
        loginName: 'vip@example.com',
        stageName: 'VIP User',
        avatarType: 'male',
        isVip: true,
      ),
      taskRunningNotifier: taskRunningNotifier,
    );

    await tester.tap(find.text('解锁工具').first);
    await tester.pump();

    expect(find.text('切换页面会中断正在运行的模块'), findsOneWidget);
    expect(find.text('音频转码任务正在运行，继续切换会中断任务。是否继续？'), findsOneWidget);
    expect(find.text('暂不切换'), findsOneWidget);
    expect(find.text('切换'), findsOneWidget);
  });

  testWidgets('gift bubble opens and closes from bottom status bar', (
    WidgetTester tester,
  ) async {
    await _pumpDjFlutterAppWithMockScope(
      tester,
      AuthSessionSnapshot(
        kind: AuthSessionKind.guest,
        guestToken: 'mock_token',
        tokenExpiresAt: DateTime.now().add(const Duration(hours: 6)),
        remainingTime: '6:00:00',
        isVip: false,
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('gift_widget_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(
      find.byKey(const ValueKey<String>('gift_bubble_panel')),
      findsOneWidget,
    );
    expect(find.text('请输入兑换码'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('gift_redeem_input')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('gift_bubble_close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(
      find.byKey(const ValueKey<String>('gift_bubble_panel')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey<String>('gift_widget_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  });

  testWidgets('audio transcode page shows Chinese fatal error summary', (
    WidgetTester tester,
  ) async {
    final _FakeAudioTranscodeTaskBridge bridge = _FakeAudioTranscodeTaskBridge()
      ..shouldEmitError = true;
    await _pumpAudioTranscodeModule(tester, bridge: bridge);

    final dynamic state = tester.state(find.byType(AudioTranscodeEntryPage));
    await state.debugController.loadTargets(<String>['/music/Broken.wav']);
    await tester.pumpAndSettle();

    await tester.tap(find.text('▶ 开始转码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('转码已结束'), findsOneWidget);
    expect(find.textContaining('失败数量：1'), findsOneWidget);
  });

  testWidgets('audio transcode empty state matches unlock style', (
    WidgetTester tester,
  ) async {
    await _pumpAudioTranscodeModule(
      tester,
      bridge: _FakeAudioTranscodeTaskBridge(),
    );

    expect(find.text('点击选择或拖入文件文件夹'), findsOneWidget);
    expect(find.text('选择音频文件'), findsNothing);
    expect(find.text('选择文件夹'), findsNothing);
  });

  testWidgets('metadata edit panels empty state match unlock style', (
    WidgetTester tester,
  ) async {
    await _pumpMetadataEditModule(
      tester,
      bridge: _FakeMetadataEditTaskBridge(),
    );

    final Finder filenamePanel = find.byType(FilenameInjectionPanel);
    final Finder coverPanel = find.byType(CoverInjectionPanel);

    expect(
      find.descendant(of: filenamePanel, matching: find.text('点击选择或拖入文件文件夹')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: coverPanel, matching: find.text('点击选择或拖入文件文件夹')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: filenamePanel, matching: find.text('选择音频文件')),
      findsNothing,
    );
    expect(
      find.descendant(of: coverPanel, matching: find.text('选择文件夹')),
      findsNothing,
    );
  });

  testWidgets(
    'metadata filename panel supports append remove failure filter and history',
    (WidgetTester tester) async {
      final _FakeMetadataEditTaskBridge bridge = _FakeMetadataEditTaskBridge()
        ..filenameResultItems = const <MetadataEditResultItem>[
          MetadataEditResultItem(
            status: MetadataEditItemStatus.ok,
            inputPath: '/music/夜曲.mp3',
            outputPath: '/music/夜曲-Remix.mp3',
            changed: true,
            backupPath: null,
            message: '文件名注入成功。',
          ),
          MetadataEditResultItem(
            status: MetadataEditItemStatus.fail,
            inputPath: '/music/Broken.mp3',
            outputPath: '/music/Broken.mp3',
            changed: false,
            backupPath: null,
            message: '文件名重命名失败。',
          ),
          MetadataEditResultItem(
            status: MetadataEditItemStatus.skip,
            inputPath: '/music/Fade.mp3',
            outputPath: '/music/Fade.mp3',
            changed: false,
            backupPath: null,
            message: '无需修改，已跳过。',
          ),
        ];
      await _pumpMetadataEditModule(tester, bridge: bridge);

      final dynamic entryState = tester.state(
        find.byType(MetadataEditEntryPage),
      );
      final MetadataEditController controller = entryState.debugController;

      await controller.loadTargets(MetadataEditPanelKind.filename, <String>[
        '/music/夜曲.mp3',
      ]);
      await tester.pumpAndSettle();
      await controller.loadTargets(MetadataEditPanelKind.filename, <String>[
        '/music/Broken.mp3',
        '/music/Fade.mp3',
      ], append: true);
      await tester.pumpAndSettle();

      expect(controller.filenameFiles.length, 3);

      await controller.removeTarget(
        MetadataEditPanelKind.filename,
        '/music/夜曲.mp3',
      );
      await tester.pumpAndSettle();
      expect(controller.filenameFiles.length, 2);

      await controller.loadTargets(MetadataEditPanelKind.filename, <String>[
        '/music/夜曲.mp3',
        '/music/Broken.mp3',
        '/music/Fade.mp3',
      ]);
      await tester.pumpAndSettle();
      controller.updateAppendText('(Remix版)');
      await tester.pumpAndSettle();

      await controller.startTask(MetadataEditPanelKind.filename);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      final Finder filenamePanel = find.byType(FilenameInjectionPanel);
      final dynamic panelState = tester.state(filenamePanel);
      panelState.debugSetShowOnlyFailures(true);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: filenamePanel, matching: find.text('Broken.mp3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: filenamePanel, matching: find.text('夜曲-Remix.mp3')),
        findsNothing,
      );
      expect(
        find.descendant(of: filenamePanel, matching: find.text('Fade.mp3')),
        findsNothing,
      );

      panelState.debugShowLastCompletedTaskDialog();
      await tester.pumpAndSettle();
      expect(find.text('最近一次完成任务'), findsNWidgets(2));
      expect(find.textContaining('文件名重命名失败。'), findsWidgets);
      await tester.tap(find.text('关闭并返回').last);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'metadata cover panel supports append remove failure filter and history',
    (WidgetTester tester) async {
      final _FakeMetadataEditTaskBridge bridge = _FakeMetadataEditTaskBridge()
        ..coverResultItems = const <MetadataEditResultItem>[
          MetadataEditResultItem(
            status: MetadataEditItemStatus.ok,
            inputPath: '/music/夜曲.mp3',
            outputPath: '/music/夜曲.mp3',
            changed: true,
            backupPath: null,
            message: '封面注入成功。',
          ),
          MetadataEditResultItem(
            status: MetadataEditItemStatus.fail,
            inputPath: '/music/Broken.mp3',
            outputPath: '/music/Broken.mp3',
            changed: false,
            backupPath: null,
            message: '封面写入失败。',
          ),
          MetadataEditResultItem(
            status: MetadataEditItemStatus.need,
            inputPath: '/music/Need.flac',
            outputPath: '/music/Need.flac',
            changed: false,
            backupPath: null,
            message: '需先转码。',
          ),
        ];
      await _pumpMetadataEditModule(tester, bridge: bridge);

      final dynamic entryState = tester.state(
        find.byType(MetadataEditEntryPage),
      );
      final MetadataEditController controller = entryState.debugController;
      controller.updateCoverImagePath('/tmp/cover.jpg');

      await controller.loadTargets(MetadataEditPanelKind.cover, <String>[
        '/music/夜曲.mp3',
      ]);
      await tester.pumpAndSettle();
      await controller.loadTargets(MetadataEditPanelKind.cover, <String>[
        '/music/Broken.mp3',
        '/music/Need.flac',
      ], append: true);
      await tester.pumpAndSettle();

      expect(controller.coverFiles.length, 3);

      await controller.removeTarget(
        MetadataEditPanelKind.cover,
        '/music/夜曲.mp3',
      );
      await tester.pumpAndSettle();
      expect(controller.coverFiles.length, 2);

      await controller.loadTargets(MetadataEditPanelKind.cover, <String>[
        '/music/夜曲.mp3',
        '/music/Broken.mp3',
        '/music/Need.flac',
      ]);
      await tester.pumpAndSettle();

      await controller.startTask(MetadataEditPanelKind.cover);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      final Finder coverPanel = find.byType(CoverInjectionPanel);
      final dynamic panelState = tester.state(coverPanel);
      panelState.debugSetShowOnlyFailures(true);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: coverPanel, matching: find.text('Broken.mp3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: coverPanel, matching: find.text('夜曲.mp3')),
        findsNothing,
      );
      expect(
        find.descendant(of: coverPanel, matching: find.text('Need.flac')),
        findsNothing,
      );

      panelState.debugSetShowOnlyFailures(false);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: coverPanel, matching: find.text('Need.flac')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: coverPanel, matching: find.text('! 需转码')),
        findsWidgets,
      );

      panelState.debugShowLastCompletedTaskDialog();
      await tester.pumpAndSettle();
      expect(find.text('最近一次完成任务'), findsNWidgets(2));
      expect(
        find.textContaining('共 3 项 · 成功 1 · 跳过 0 · 需转码 1 · 失败 1'),
        findsWidgets,
      );
      expect(find.text('待处理'), findsWidgets);
      expect(find.textContaining('需先转码。'), findsWidgets);
      expect(find.textContaining('封面写入失败。'), findsWidgets);
      await tester.tap(find.text('关闭并返回').last);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'usb backup page shows latest three versions and capacity block',
    (WidgetTester tester) async {
      final _FakeUsbBackupTaskBridge bridge = _FakeUsbBackupTaskBridge();
      await _pumpUsbBackupModule(tester, bridge: bridge);

      expect(find.byType(UsbBackupEntryPage), findsOneWidget);

      // 1. 验证备份模式下的内容
      expect(find.textContaining('未完成备份'), findsOneWidget);

      // 2. 切换到恢复模式
      await tester.tap(find.text('从备份恢复 U 盘'));
      await tester.pumpAndSettle();

      expect(find.text('恢复推荐'), findsOneWidget);
      expect(find.text('查看恢复包详情'), findsOneWidget);
      expect(find.text('旧版本'), findsNothing);
      expect(find.byType(DropdownButton<String>), findsWidgets);

      await tester.tap(find.text('查看恢复包详情'));
      await tester.pumpAndSettle();

      expect(find.text('恢复包详情'), findsWidgets);
      expect(find.text('歌曲数量'), findsOneWidget);
      expect(find.text('波纹数量'), findsOneWidget);
      expect(find.text('热点数量'), findsOneWidget);
    },
  );

  testWidgets('usb backup page blocks unsupported filesystem restore target', (
    WidgetTester tester,
  ) async {
    final _FakeUsbBackupTaskBridge bridge = _FakeUsbBackupTaskBridge();
    await _pumpUsbBackupModule(tester, bridge: bridge);

    await tester.tap(find.text('从备份恢复 U 盘'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.textContaining('BAD_USB').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    final dynamic pageState = tester.state(find.byType(UsbBackupEntryPage));
    expect(pageState.debugController.dialogData?.title, '目标U盘格式不支持');
    expect(
      pageState.debugController.dialogData?.message,
      contains('CDJ 仅支持 FAT32 或 ExFAT'),
    );
    expect(
      pageState.debugController.dialogData?.message,
      contains('请先格式化后再恢复'),
    );
  });

  testWidgets('usb backup page requires confirmation before restore', (
    WidgetTester tester,
  ) async {
    final _FakeUsbBackupTaskBridge bridge = _FakeUsbBackupTaskBridge();
    await _pumpUsbBackupModule(tester, bridge: bridge);

    await tester.tap(find.text('从备份恢复 U 盘'));
    await tester.pumpAndSettle();

    expect(find.text('一键开始恢复'), findsOneWidget);
    expect(find.textContaining('我已确认将清空目标 U 盘现有内容'), findsNothing);
    expect(bridge.restoreStartCount, 0);
  });

  testWidgets('usb backup page can delete version after confirmation', (
    WidgetTester tester,
  ) async {
    final _FakeUsbBackupTaskBridge bridge = _FakeUsbBackupTaskBridge();
    await _pumpUsbBackupModule(tester, bridge: bridge);

    await tester.tap(find.text('从备份恢复 U 盘'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看恢复包详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除版本'));
    await tester.pumpAndSettle();

    expect(find.text('确认删除备份版本'), findsOneWidget);
    expect(bridge.deleteCount, 0);

    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();

    expect(bridge.deleteCount, 1);
  });

  testWidgets('usb backup page can cleanup repository from header', (
    WidgetTester tester,
  ) async {
    final _FakeUsbBackupTaskBridge bridge = _FakeUsbBackupTaskBridge();
    await _pumpUsbBackupModule(tester, bridge: bridge);

    await tester.tap(find.text('清理仓库'));
    await tester.pumpAndSettle();

    expect(find.text('确认清理仓库'), findsOneWidget);
    expect(bridge.cleanupCount, 0);

    await tester.tap(find.text('开始清理'));
    await tester.pumpAndSettle();

    expect(bridge.cleanupCount, 1);
  });

  testWidgets('usb backup backup mode format uses selected source volume', (
    WidgetTester tester,
  ) async {
    final _FakeUsbBackupTaskBridge bridge = _FakeUsbBackupTaskBridge();
    await _pumpUsbBackupModule(tester, bridge: bridge);

    await tester.tap(find.text('格式化'));
    await tester.pumpAndSettle();

    expect(find.text('确认格式化 U 盘'), findsOneWidget);
    expect(find.textContaining('请关闭 Finder 中该 U 盘窗口'), findsOneWidget);
    expect(find.textContaining('会先尝试卸载磁盘'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'DJ_USB');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ExFAT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认格式化'));
    await tester.pumpAndSettle();

    expect(bridge.formatStartCount, 1);
    expect(bridge.lastFormatTargetPath, '/Volumes/PIONEER');
    expect(bridge.lastFormatFilesystem, 'exfat');
    expect(bridge.lastFormatVolumeLabel, 'DJ_USB');
  });

  testWidgets('usb backup restore dropdown drives main restore action', (
    WidgetTester tester,
  ) async {
    final _FakeUsbBackupTaskBridge bridge = _FakeUsbBackupTaskBridge();
    await _pumpUsbBackupModule(tester, bridge: bridge);

    await tester.tap(find.text('从备份恢复 U 盘'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('NEW_USB').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('店内常驻盘').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('一键开始恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('我已确认将清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认恢复'));
    await tester.pumpAndSettle();

    expect(bridge.restoreStartCount, 1);
    expect(bridge.lastRestoreSnapshotId, 'snapshot_002');
  });

  testWidgets(
    'usb backup restore package selection resets after target change',
    (WidgetTester tester) async {
      final _TargetAwareUsbBackupTaskBridge bridge =
          _TargetAwareUsbBackupTaskBridge();
      await _pumpUsbBackupModule(tester, bridge: bridge);

      await tester.tap(find.text('从备份恢复 U 盘'));
      await tester.pumpAndSettle();

      DropdownButton<String> restoreDropdown = tester
          .widget<DropdownButton<String>>(
            find.byType(DropdownButton<String>).last,
          );
      expect(restoreDropdown.value, 'snapshot_002');

      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('PIONEER').last);
      await tester.pumpAndSettle();

      restoreDropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>).last,
      );
      expect(restoreDropdown.value, 'snapshot_003');

      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('NEW_USB').last);
      await tester.pumpAndSettle();

      restoreDropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>).last,
      );
      expect(restoreDropdown.value, 'snapshot_002');
    },
  );

  testWidgets('usb backup page ejects selected source volume', (
    WidgetTester tester,
  ) async {
    final _FakeUsbBackupTaskBridge bridge = _FakeUsbBackupTaskBridge();
    await _pumpUsbBackupModule(tester, bridge: bridge);

    await tester.tap(find.text('⏏ 弹出'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(bridge.ejectCount, 1);
    expect(bridge.lastEjectTargetPath, '/Volumes/PIONEER');
  });

  test('usb backup controller keeps detailed backup failure reason', () async {
    final _FormatPollingUsbBackupTaskBridge bridge =
        _FormatPollingUsbBackupTaskBridge(
          volumeSnapshots: const <List<UsbBackupVolume>>[
            <UsbBackupVolume>[
              UsbBackupVolume(
                path: '/Volumes/PIONEER',
                volumeName: 'PIONEER',
                filesystem: 'msdos',
                normalizedFilesystem: 'fat32',
                totalBytes: 128000000000,
                freeBytes: 64000000000,
                busProtocol: 'USB',
                serialNumber: 'serial-001',
                rekordboxDetected: true,
                isCdjSupportedFs: true,
                requiresFormatBeforeRestore: false,
                diskIdentifier: 'disk4s1',
                wholeDiskIdentifier: 'disk4',
              ),
            ],
          ],
          polledEvents: const <List<UsbBackupTaskEvent>>[
            <UsbBackupTaskEvent>[
              UsbBackupTaskEvent(
                event: 'task_finished',
                taskId: 'usb_task_001',
                snapshot: UsbBackupTaskSnapshot(
                  taskId: 'usb_task_001',
                  taskType: 'backup',
                  status: UsbBackupTaskStatus.error,
                  progress: 0.03,
                  progressHintText: '检测到旧断点已失效，正在重新扫描并发起完整备份...',
                  displayName: '测试',
                  snapshotId: null,
                  totalFiles: 0,
                  totalBytes: 0,
                  restoredFiles: 0,
                  validatedFiles: 0,
                  errorMessage: '读取 U 盘系统目录失败，请关闭系统占用后重试。',
                  resumedFromCheckpoint: false,
                  checkpointId: null,
                  restoreValidation: null,
                ),
              ),
            ],
          ],
        );
    final UsbBackupController controller = UsbBackupController(bridge: bridge);
    addTearDown(controller.close);

    await controller.initialize();
    await controller.startBackup();
    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(controller.snapshot.status, UsbBackupTaskStatus.error);
    expect(controller.snapshot.errorMessage, '读取 U 盘系统目录失败，请关闭系统占用后重试。');
  });

  test(
    'usb backup controller keeps selected volumes across mount path changes',
    () async {
      final _ChangingUsbBackupTaskBridge bridge = _ChangingUsbBackupTaskBridge(
        volumeSnapshots: <List<UsbBackupVolume>>[
          const <UsbBackupVolume>[
            UsbBackupVolume(
              path: '/Volumes/PIONEER',
              volumeName: 'PIONEER',
              filesystem: 'exfat',
              normalizedFilesystem: 'exfat',
              totalBytes: 128000000000,
              freeBytes: 64000000000,
              busProtocol: 'USB',
              serialNumber: 'serial-001',
              rekordboxDetected: true,
              isCdjSupportedFs: true,
              requiresFormatBeforeRestore: false,
              diskIdentifier: 'disk4s1',
              wholeDiskIdentifier: 'disk4',
            ),
            UsbBackupVolume(
              path: '/Volumes/NEW_USB',
              volumeName: 'NEW_USB',
              filesystem: 'exfat',
              normalizedFilesystem: 'exfat',
              totalBytes: 64000000000,
              freeBytes: 8000000000,
              busProtocol: 'USB',
              serialNumber: 'serial-002',
              rekordboxDetected: false,
              isCdjSupportedFs: true,
              requiresFormatBeforeRestore: false,
              diskIdentifier: 'disk5s1',
              wholeDiskIdentifier: 'disk5',
            ),
          ],
          const <UsbBackupVolume>[
            UsbBackupVolume(
              path: '/Volumes/NEW_USB',
              volumeName: 'NEW_USB',
              filesystem: 'exfat',
              normalizedFilesystem: 'exfat',
              totalBytes: 64000000000,
              freeBytes: 8000000000,
              busProtocol: 'USB',
              serialNumber: 'serial-002',
              rekordboxDetected: false,
              isCdjSupportedFs: true,
              requiresFormatBeforeRestore: false,
              diskIdentifier: 'disk5s1',
              wholeDiskIdentifier: 'disk5',
            ),
            UsbBackupVolume(
              path: '/Volumes/PIONEER 1',
              volumeName: 'PIONEER',
              filesystem: 'exfat',
              normalizedFilesystem: 'exfat',
              totalBytes: 128000000000,
              freeBytes: 64000000000,
              busProtocol: 'USB',
              serialNumber: 'serial-001',
              rekordboxDetected: true,
              isCdjSupportedFs: true,
              requiresFormatBeforeRestore: false,
              diskIdentifier: 'disk4s1',
              wholeDiskIdentifier: 'disk4',
            ),
          ],
        ],
      );
      final UsbBackupController controller = UsbBackupController(
        bridge: bridge,
      );
      addTearDown(controller.close);

      await controller.initialize();
      await controller.selectTargetPath('/Volumes/PIONEER');

      expect(controller.selectedSourcePath, '/Volumes/PIONEER');
      expect(controller.selectedTargetPath, '/Volumes/PIONEER');

      await controller.refreshVolumes(forceRefresh: true);

      expect(controller.selectedSourcePath, '/Volumes/PIONEER 1');
      expect(controller.selectedTargetPath, '/Volumes/PIONEER 1');
    },
  );

  test(
    'usb backup controller refreshAll forces volume reload and versions sync',
    () async {
      final _FakeUsbBackupTaskBridge bridge = _FakeUsbBackupTaskBridge();
      final UsbBackupController controller = UsbBackupController(
        bridge: bridge,
      );
      addTearDown(controller.close);

      await controller.initialize();
      bridge.listUsbVolumesCount = 0;
      bridge.listBackupVersionsCount = 0;

      await controller.refreshAll(forceRefresh: true);

      expect(bridge.listUsbVolumesCount, 1);
      expect(bridge.listBackupVersionsCount, 1);
      expect(bridge.lastForceRefresh, isTrue);
    },
  );

  test(
    'usb backup controller keeps source selection null after removed volume refresh',
    () async {
      final _ChangingUsbBackupTaskBridge bridge = _ChangingUsbBackupTaskBridge(
        volumeSnapshots: <List<UsbBackupVolume>>[
          const <UsbBackupVolume>[
            UsbBackupVolume(
              path: '/Volumes/PIONEER',
              volumeName: 'PIONEER',
              filesystem: 'exfat',
              normalizedFilesystem: 'exfat',
              totalBytes: 128000000000,
              freeBytes: 64000000000,
              busProtocol: 'USB',
              serialNumber: 'serial-001',
              rekordboxDetected: true,
              isCdjSupportedFs: true,
              requiresFormatBeforeRestore: false,
              diskIdentifier: 'disk4s1',
              wholeDiskIdentifier: 'disk4',
            ),
            UsbBackupVolume(
              path: '/Volumes/NEW_USB',
              volumeName: 'NEW_USB',
              filesystem: 'exfat',
              normalizedFilesystem: 'exfat',
              totalBytes: 64000000000,
              freeBytes: 8000000000,
              busProtocol: 'USB',
              serialNumber: 'serial-002',
              rekordboxDetected: false,
              isCdjSupportedFs: true,
              requiresFormatBeforeRestore: false,
              diskIdentifier: 'disk5s1',
              wholeDiskIdentifier: 'disk5',
            ),
          ],
          const <UsbBackupVolume>[
            UsbBackupVolume(
              path: '/Volumes/NEW_USB',
              volumeName: 'NEW_USB',
              filesystem: 'exfat',
              normalizedFilesystem: 'exfat',
              totalBytes: 64000000000,
              freeBytes: 8000000000,
              busProtocol: 'USB',
              serialNumber: 'serial-002',
              rekordboxDetected: false,
              isCdjSupportedFs: true,
              requiresFormatBeforeRestore: false,
              diskIdentifier: 'disk5s1',
              wholeDiskIdentifier: 'disk5',
            ),
          ],
        ],
      );
      final UsbBackupController controller = UsbBackupController(
        bridge: bridge,
      );
      addTearDown(controller.close);

      await controller.initialize();
      await controller.selectSourcePath('/Volumes/PIONEER');
      await controller.refreshVolumes(forceRefresh: true);

      expect(controller.selectedSourcePath, isNull);
    },
  );

  test(
    'usb backup controller keeps latest versions aligned with selected target',
    () async {
      final _TargetAwareUsbBackupTaskBridge bridge =
          _TargetAwareUsbBackupTaskBridge();
      final UsbBackupController controller = UsbBackupController(
        bridge: bridge,
      );
      addTearDown(controller.close);

      await controller.initialize();
      await controller.selectTargetPath('/Volumes/PIONEER');
      expect(controller.latestVersions.first.snapshotId, 'snapshot_003');

      await controller.selectTargetPath('/Volumes/NEW_USB');

      expect(controller.selectedTargetPath, '/Volumes/NEW_USB');
      expect(controller.latestVersions.first.snapshotId, 'snapshot_002');
      expect(controller.latestVersions.first.canRestore, isTrue);
    },
  );

  test(
    'usb backup controller refreshes volumes while backup is running',
    () async {
      final _FormatPollingUsbBackupTaskBridge bridge =
          _FormatPollingUsbBackupTaskBridge(
            volumeSnapshots: const <List<UsbBackupVolume>>[
              <UsbBackupVolume>[
                UsbBackupVolume(
                  path: '/Volumes/PIONEER',
                  volumeName: 'PIONEER',
                  filesystem: 'exfat',
                  normalizedFilesystem: 'exfat',
                  totalBytes: 128000000000,
                  freeBytes: 64000000000,
                  busProtocol: 'USB',
                  serialNumber: 'serial-001',
                  rekordboxDetected: true,
                  isCdjSupportedFs: true,
                  requiresFormatBeforeRestore: false,
                  diskIdentifier: 'disk4s1',
                  wholeDiskIdentifier: 'disk4',
                ),
              ],
              <UsbBackupVolume>[
                UsbBackupVolume(
                  path: '/Volumes/PIONEER',
                  volumeName: 'PIONEER',
                  filesystem: 'exfat',
                  normalizedFilesystem: 'exfat',
                  totalBytes: 128000000000,
                  freeBytes: 62000000000,
                  busProtocol: 'USB',
                  serialNumber: 'serial-001',
                  rekordboxDetected: true,
                  isCdjSupportedFs: true,
                  requiresFormatBeforeRestore: false,
                  diskIdentifier: 'disk4s1',
                  wholeDiskIdentifier: 'disk4',
                ),
              ],
            ],
            polledEvents: const <List<UsbBackupTaskEvent>>[
              <UsbBackupTaskEvent>[
                UsbBackupTaskEvent(
                  event: 'task_progress',
                  taskId: 'usb_task_001',
                  snapshot: UsbBackupTaskSnapshot(
                    taskId: 'usb_task_001',
                    taskType: 'backup',
                    status: UsbBackupTaskStatus.running,
                    progress: 0.42,
                    progressHintText: '正在编译 rekordbox 文件...',
                    displayName: '主演出盘',
                    snapshotId: null,
                    totalFiles: 2048,
                    totalBytes: 24000000000,
                    restoredFiles: 0,
                    validatedFiles: 0,
                    errorMessage: null,
                    resumedFromCheckpoint: false,
                    checkpointId: null,
                    restoreValidation: null,
                  ),
                ),
              ],
              <UsbBackupTaskEvent>[
                UsbBackupTaskEvent(
                  event: 'task_finished',
                  taskId: 'usb_task_001',
                  snapshot: UsbBackupTaskSnapshot(
                    taskId: 'usb_task_001',
                    taskType: 'backup',
                    status: UsbBackupTaskStatus.success,
                    progress: 1.0,
                    progressHintText: '备份完成。',
                    displayName: '主演出盘',
                    snapshotId: 'snapshot_003',
                    totalFiles: 2048,
                    totalBytes: 24000000000,
                    restoredFiles: 0,
                    validatedFiles: 0,
                    errorMessage: null,
                    resumedFromCheckpoint: false,
                    checkpointId: null,
                    restoreValidation: null,
                  ),
                ),
              ],
            ],
          );
      final UsbBackupController controller = UsbBackupController(
        bridge: bridge,
      );
      addTearDown(controller.close);

      await controller.initialize();
      bridge.listUsbVolumesCount = 0;

      await controller.startBackup();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(bridge.listUsbVolumesCount, greaterThanOrEqualTo(2));
      expect(bridge.lastForceRefresh, isTrue);
    },
  );

  test('usb backup controller shows dialog when backup completes', () async {
    final _FormatPollingUsbBackupTaskBridge bridge =
        _FormatPollingUsbBackupTaskBridge(
          volumeSnapshots: const <List<UsbBackupVolume>>[
            <UsbBackupVolume>[
              UsbBackupVolume(
                path: '/Volumes/PIONEER',
                volumeName: 'PIONEER',
                filesystem: 'exfat',
                normalizedFilesystem: 'exfat',
                totalBytes: 128000000000,
                freeBytes: 64000000000,
                busProtocol: 'USB',
                serialNumber: 'serial-001',
                rekordboxDetected: true,
                isCdjSupportedFs: true,
                requiresFormatBeforeRestore: false,
                diskIdentifier: 'disk4s1',
                wholeDiskIdentifier: 'disk4',
              ),
            ],
          ],
          polledEvents: const <List<UsbBackupTaskEvent>>[
            <UsbBackupTaskEvent>[
              UsbBackupTaskEvent(
                event: 'task_finished',
                taskId: 'usb_task_001',
                snapshot: UsbBackupTaskSnapshot(
                  taskId: 'usb_task_001',
                  taskType: 'backup',
                  status: UsbBackupTaskStatus.success,
                  progress: 1.0,
                  progressHintText: '备份完成。',
                  displayName: '示例备份盘',
                  snapshotId: 'snapshot_003',
                  totalFiles: 1024,
                  totalBytes: 6000000000,
                  restoredFiles: 0,
                  validatedFiles: 0,
                  errorMessage: null,
                  resumedFromCheckpoint: false,
                  checkpointId: null,
                  restoreValidation: null,
                ),
              ),
            ],
          ],
        );
    final UsbBackupController controller = UsbBackupController(bridge: bridge);
    addTearDown(controller.close);

    await controller.initialize();
    await controller.startBackup();
    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(controller.dialogData?.title, '备份完成');
    expect(controller.dialogData?.message, contains('备份名称: 示例备份盘'));
    expect(controller.dialogData?.message, contains('文件数: 1024'));
  });

  test(
    'usb backup controller clears completed snapshot after dialog closes',
    () async {
      final _FormatPollingUsbBackupTaskBridge bridge =
          _FormatPollingUsbBackupTaskBridge(
            volumeSnapshots: const <List<UsbBackupVolume>>[
              <UsbBackupVolume>[
                UsbBackupVolume(
                  path: '/Volumes/PIONEER',
                  volumeName: 'PIONEER',
                  filesystem: 'exfat',
                  normalizedFilesystem: 'exfat',
                  totalBytes: 128000000000,
                  freeBytes: 64000000000,
                  busProtocol: 'USB',
                  serialNumber: 'serial-001',
                  rekordboxDetected: true,
                  isCdjSupportedFs: true,
                  requiresFormatBeforeRestore: false,
                  diskIdentifier: 'disk4s1',
                  wholeDiskIdentifier: 'disk4',
                ),
              ],
            ],
            polledEvents: const <List<UsbBackupTaskEvent>>[
              <UsbBackupTaskEvent>[
                UsbBackupTaskEvent(
                  event: 'task_finished',
                  taskId: 'usb_task_001',
                  snapshot: UsbBackupTaskSnapshot(
                    taskId: 'usb_task_001',
                    taskType: 'backup',
                    status: UsbBackupTaskStatus.success,
                    progress: 1.0,
                    progressHintText: '备份完成。',
                    displayName: '示例备份盘',
                    snapshotId: 'snapshot_003',
                    totalFiles: 1024,
                    totalBytes: 6000000000,
                    restoredFiles: 0,
                    validatedFiles: 0,
                    errorMessage: null,
                    resumedFromCheckpoint: false,
                    checkpointId: null,
                    restoreValidation: null,
                  ),
                ),
              ],
            ],
          );
      final UsbBackupController controller = UsbBackupController(
        bridge: bridge,
      );
      addTearDown(controller.close);

      await controller.initialize();
      await controller.startBackup();
      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(controller.dialogData?.title, '备份完成');
      expect(controller.snapshot.status, UsbBackupTaskStatus.success);

      controller.clearDialog();

      expect(controller.dialogData, isNull);
      expect(controller.snapshot.status, UsbBackupTaskStatus.idle);
      expect(controller.snapshot.progress, 0);
    },
  );

  test(
    'usb backup controller shows validation result when restore completes',
    () async {
      final _FormatPollingUsbBackupTaskBridge bridge =
          _FormatPollingUsbBackupTaskBridge(
            volumeSnapshots: const <List<UsbBackupVolume>>[
              <UsbBackupVolume>[
                UsbBackupVolume(
                  path: '/Volumes/PIONEER',
                  volumeName: 'PIONEER',
                  filesystem: 'exfat',
                  normalizedFilesystem: 'exfat',
                  totalBytes: 128000000000,
                  freeBytes: 64000000000,
                  busProtocol: 'USB',
                  serialNumber: 'serial-001',
                  rekordboxDetected: true,
                  isCdjSupportedFs: true,
                  requiresFormatBeforeRestore: false,
                  diskIdentifier: 'disk4s1',
                  wholeDiskIdentifier: 'disk4',
                ),
                UsbBackupVolume(
                  path: '/Volumes/NEW_USB',
                  volumeName: 'NEW_USB',
                  filesystem: 'exfat',
                  normalizedFilesystem: 'exfat',
                  totalBytes: 64000000000,
                  freeBytes: 8000000000,
                  busProtocol: 'USB',
                  serialNumber: 'serial-002',
                  rekordboxDetected: false,
                  isCdjSupportedFs: true,
                  requiresFormatBeforeRestore: false,
                  diskIdentifier: 'disk5s1',
                  wholeDiskIdentifier: 'disk5',
                ),
              ],
            ],
            polledEvents: const <List<UsbBackupTaskEvent>>[
              <UsbBackupTaskEvent>[
                UsbBackupTaskEvent(
                  event: 'task_finished',
                  taskId: 'usb_task_002',
                  snapshot: UsbBackupTaskSnapshot(
                    taskId: 'usb_task_002',
                    taskType: 'restore',
                    status: UsbBackupTaskStatus.success,
                    progress: 1.0,
                    progressHintText: '恢复完成。',
                    displayName: '示例备份盘',
                    snapshotId: 'snapshot_003',
                    totalFiles: 1024,
                    totalBytes: 6000000000,
                    restoredFiles: 1024,
                    validatedFiles: 1024,
                    errorMessage: null,
                    resumedFromCheckpoint: false,
                    checkpointId: null,
                    restoreValidation: UsbBackupRestoreValidation(
                      checkedAt: '2026-04-07T20:00:00Z',
                      targetRoot: '/Volumes/NEW_USB',
                      filesPresentOk: true,
                      rekordboxLayoutOk: true,
                      missingFiles: 0,
                      mismatchedFiles: 0,
                      message: '恢复后校验通过：音频 128 个，封面 24 个，分析文件 96 个。',
                      rekordboxSummary: UsbBackupRekordboxSummary(
                        hasPioneerDir: true,
                        hasDotPioneerDir: false,
                        hasContentsDir: true,
                        hasExportLibraryDb: true,
                        audioFileCount: 128,
                        artworkFileCount: 24,
                        analysisFileCount: 96,
                        playlistSyncCount: 4,
                        databaseFileCount: 1,
                        musicBytes: 6000000000,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
      final UsbBackupController controller = UsbBackupController(
        bridge: bridge,
      );
      addTearDown(controller.close);

      await controller.initialize();
      await controller.selectTargetPath('/Volumes/NEW_USB');
      await controller.restoreVersion(
        controller.latestVersions.firstWhere(
          (v) => v.snapshotId == 'snapshot_003',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(controller.dialogData?.title, '恢复完成');
      expect(controller.dialogData?.message, contains('目标 U 盘现在可以继续操作'));
      expect(controller.dialogData?.message, contains('恢复后校验通过'));
      expect(controller.hasActiveTask, isFalse);
      expect(controller.canStartBackup, isTrue);
    },
  );

  test(
    'usb backup controller shows unplugged volume dialog during restore',
    () async {
      final _FormatPollingUsbBackupTaskBridge
      bridge = _FormatPollingUsbBackupTaskBridge(
        volumeSnapshots: const <List<UsbBackupVolume>>[
          <UsbBackupVolume>[
            UsbBackupVolume(
              path: '/Volumes/PIONEER',
              volumeName: 'PIONEER',
              filesystem: 'exfat',
              normalizedFilesystem: 'exfat',
              totalBytes: 128000000000,
              freeBytes: 64000000000,
              busProtocol: 'USB',
              serialNumber: 'serial-001',
              rekordboxDetected: true,
              isCdjSupportedFs: true,
              requiresFormatBeforeRestore: false,
              diskIdentifier: 'disk4s1',
              wholeDiskIdentifier: 'disk4',
            ),
            UsbBackupVolume(
              path: '/Volumes/NEW_USB',
              volumeName: 'NEW_USB',
              filesystem: 'exfat',
              normalizedFilesystem: 'exfat',
              totalBytes: 64000000000,
              freeBytes: 8000000000,
              busProtocol: 'USB',
              serialNumber: 'serial-002',
              rekordboxDetected: false,
              isCdjSupportedFs: true,
              requiresFormatBeforeRestore: false,
              diskIdentifier: 'disk5s1',
              wholeDiskIdentifier: 'disk5',
            ),
          ],
        ],
        polledEvents: const <List<UsbBackupTaskEvent>>[
          <UsbBackupTaskEvent>[
            UsbBackupTaskEvent(
              event: 'task_finished',
              taskId: 'usb_task_002',
              snapshot: UsbBackupTaskSnapshot(
                taskId: 'usb_task_002',
                taskType: 'restore',
                status: UsbBackupTaskStatus.error,
                progress: 0.73,
                progressHintText:
                    '切换恢复结果到目标路径失败:/Volumes/NEW_USB/._Contents (No such file or directory (os error 2))',
                displayName: '示例备份盘',
                snapshotId: 'snapshot_003',
                totalFiles: 1024,
                totalBytes: 6000000000,
                restoredFiles: 768,
                validatedFiles: 0,
                errorMessage:
                    '切换恢复结果到目标路径失败:/Volumes/NEW_USB/._Contents (No such file or directory (os error 2))',
                resumedFromCheckpoint: false,
                checkpointId: null,
                restoreValidation: null,
              ),
            ),
          ],
        ],
      );
      final UsbBackupController controller = UsbBackupController(
        bridge: bridge,
      );
      addTearDown(controller.close);

      await controller.initialize();
      await controller.selectTargetPath('/Volumes/NEW_USB');
      await controller.restoreVersion(
        controller.latestVersions.firstWhere(
          (v) => v.snapshotId == 'snapshot_003',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(controller.dialogData?.title, '恢复中断：U 盘已断开');
      expect(controller.dialogData?.message, contains('请重新插入 U 盘并点击刷新后再试'));
    },
  );

  testWidgets('pinyin generator card opens entry page', (
    WidgetTester tester,
  ) async {
    await _pumpDjFlutterAppWithMockScope(
      tester,
      AuthSessionSnapshot(
        kind: AuthSessionKind.user,
        token: 'mock_token',
        userId: 'user_001',
        loginName: 'vip@example.com',
        stageName: 'VIP User',
        isVip: true,
        vipExpiresAt: DateTime.now().add(const Duration(days: 365)),
      ),
    );

    await tester.tap(find.text('首拼生成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byType(PinyinGeneratorEntryPage), findsOneWidget);
    expect(find.text('一键生成中文歌曲首拼写入专辑栏'), findsOneWidget);
    expect(find.text('开始处理'), findsOneWidget);
  });

  testWidgets('pinyin generator empty state matches unlock style', (
    WidgetTester tester,
  ) async {
    await _pumpPinyinGeneratorModule(
      tester,
      bridge: _FakePinyinGeneratorTaskBridge(),
    );

    expect(find.text('点击选择或拖入文件文件夹'), findsOneWidget);
    expect(find.text('选择音频文件'), findsNothing);
    expect(find.text('选择文件夹'), findsNothing);
  });

  testWidgets('pinyin generator page processes result states', (
    WidgetTester tester,
  ) async {
    final _FakePinyinGeneratorTaskBridge bridge =
        _FakePinyinGeneratorTaskBridge();
    await _pumpPinyinGeneratorModule(tester, bridge: bridge);

    final dynamic state = tester.state(find.byType(PinyinGeneratorEntryPage));
    await state.debugController.loadTargets(<String>[
      '/music/夜曲.mp3',
      '/music/Fade.mp3',
    ]);
    await tester.pumpAndSettle();

    expect(find.text('夜曲.mp3'), findsWidgets);
    expect(find.text('Fade.mp3'), findsWidgets);
    expect(find.text('⏳ 待处理'), findsNWidgets(2));
    expect(find.text('✓ 写入：YQ'), findsNothing);
    expect(find.text('追加目标 (文件/目录)'), findsOneWidget);
    expect(find.text('仅看失败项'), findsOneWidget);

    expect(state.debugController.writeMode, PinyinGeneratorWriteMode.overwrite);
    await state.debugController.updateWriteMode(
      PinyinGeneratorWriteMode.append,
    );
    await tester.pumpAndSettle();
    expect(state.debugController.writeMode, PinyinGeneratorWriteMode.append);

    await state.debugController.startPinyinGeneratorTask();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('首拼生成已完成'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pinyin_generator_history_entry')),
      findsOneWidget,
    );
    expect(find.text('查看首拼生成结果'), findsWidgets);
    await tester.tap(find.text('查看首拼生成结果').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('首拼生成结果审阅'), findsOneWidget);
    expect(find.text('✓ 写入：YQ'), findsOneWidget);
    expect(find.text('⏭ 跳过'), findsOneWidget);
  });

  testWidgets('pinyin generator blocks wav targets', (
    WidgetTester tester,
  ) async {
    final _FakePinyinGeneratorTaskBridge wavBridge =
        _FakePinyinGeneratorTaskBridge()
          ..loadTargetsErrorMessage = '不支持 WAV 文件，请先转码后再使用首拼生成功能。';
    await _pumpPinyinGeneratorModule(tester, bridge: wavBridge);

    final dynamic wavState = tester.state(
      find.byType(PinyinGeneratorEntryPage),
    );
    await wavState.debugController.loadTargets(<String>['/music/test.wav']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('导入提醒'), findsOneWidget);
    expect(find.text('不支持 WAV 文件，请先转码后再使用首拼生成功能。'), findsOneWidget);
    expect(find.text('test.wav'), findsNothing);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
  });

  testWidgets('pinyin generator blocks non-audio targets', (
    WidgetTester tester,
  ) async {
    final _FakePinyinGeneratorTaskBridge nonAudioBridge =
        _FakePinyinGeneratorTaskBridge()
          ..loadTargetsErrorMessage = '该文件不是支持的音频格式，无法加入处理列表。';
    await _pumpPinyinGeneratorModule(tester, bridge: nonAudioBridge);

    final dynamic nonAudioState = tester.state(
      find.byType(PinyinGeneratorEntryPage),
    );
    await nonAudioState.debugController.loadTargets(<String>[
      '/music/readme.txt',
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('导入提醒'), findsOneWidget);
    expect(find.text('该文件不是支持的音频格式，无法加入处理列表。'), findsOneWidget);
    expect(find.text('readme.txt'), findsNothing);
  });

  testWidgets('pinyin generator resumes after manual stop', (
    WidgetTester tester,
  ) async {
    final _FakePinyinGeneratorTaskBridge bridge =
        _FakePinyinGeneratorTaskBridge()..supportsResume = true;
    await _pumpPinyinGeneratorModule(tester, bridge: bridge);

    final dynamic state = tester.state(find.byType(PinyinGeneratorEntryPage));
    await state.debugController.loadTargets(<String>[
      '/music/夜曲.mp3',
      '/music/稻香.mp3',
    ]);
    await tester.pumpAndSettle();

    await state.debugController.startPinyinGeneratorTask();
    final String firstTaskId = state.debugController.snapshot.taskId as String;
    await state.debugController.stopTask();
    await tester.pumpAndSettle();

    expect(
      state.debugController.snapshot.status,
      PinyinGeneratorStatus.cancelled,
    );
    expect(find.text('继续处理'), findsOneWidget);

    await state.debugController.startPinyinGeneratorTask();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(state.debugController.snapshot.taskId, firstTaskId);
    expect(
      state.debugController.snapshot.status,
      PinyinGeneratorStatus.success,
    );
    expect(find.text('查看首拼生成结果'), findsWidgets);
  });

  testWidgets(
    'pinyin generator supports append remove failure filter and history',
    (WidgetTester tester) async {
      final _FakePinyinGeneratorTaskBridge bridge =
          _FakePinyinGeneratorTaskBridge()
            ..resultItems = <PinyinGeneratorResultItem>[
              const PinyinGeneratorResultItem(
                inputPath: '/music/夜曲.mp3',
                inputName: '夜曲.mp3',
                titleSource: 'tag',
                sourceTitle: '夜曲',
                containsChinese: true,
                generatedInitials: 'YQ',
                albumBefore: '',
                albumAfter: 'YQ',
                status: PinyinGeneratorItemStatus.success,
                message: '写入成功。',
              ),
              const PinyinGeneratorResultItem(
                inputPath: '/music/Broken.mp3',
                inputName: 'Broken.mp3',
                titleSource: 'filename',
                sourceTitle: 'Broken',
                containsChinese: true,
                generatedInitials: null,
                albumBefore: null,
                albumAfter: null,
                status: PinyinGeneratorItemStatus.failed,
                message: '标签写入失败。',
              ),
              const PinyinGeneratorResultItem(
                inputPath: '/music/Fade.mp3',
                inputName: 'Fade.mp3',
                titleSource: 'filename',
                sourceTitle: 'Fade',
                containsChinese: false,
                generatedInitials: null,
                albumBefore: 'Alan Walker',
                albumAfter: 'Alan Walker',
                status: PinyinGeneratorItemStatus.skipped,
                message: '标题不含中文，已跳过。',
              ),
            ];
      await _pumpPinyinGeneratorModule(tester, bridge: bridge);

      final dynamic state = tester.state(find.byType(PinyinGeneratorEntryPage));
      await state.debugController.loadTargets(<String>['/music/夜曲.mp3']);
      await tester.pumpAndSettle();
      await state.debugController.loadTargets(<String>[
        '/music/Broken.mp3',
        '/music/Fade.mp3',
      ], append: true);
      await tester.pumpAndSettle();

      expect(state.debugController.loadedFiles.length, 3);
      expect(find.text('Broken.mp3'), findsWidgets);

      await state.debugController.removeTarget('/music/夜曲.mp3');
      await tester.pumpAndSettle();
      expect(state.debugController.loadedFiles.length, 2);

      await state.debugController.loadTargets(<String>[
        '/music/夜曲.mp3',
        '/music/Broken.mp3',
        '/music/Fade.mp3',
      ]);
      await tester.pumpAndSettle();

      await state.debugController.startPinyinGeneratorTask();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Broken.mp3'), findsWidgets);
      final dynamic pageState = tester.state(
        find.byType(PinyinGeneratorEntryPage),
      );
      pageState.debugSetShowOnlyFailures(true);
      await tester.pumpAndSettle();
      expect(find.text('Broken.mp3'), findsOneWidget);
      expect(find.text('夜曲.mp3'), findsNothing);
      expect(find.text('Fade.mp3'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('pinyin_generator_history_entry')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('最近一次完成任务'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Broken.mp3 -> 标签写入失败。'), findsOneWidget);
      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('unlock tool card opens unlock music entry page', (
    WidgetTester tester,
  ) async {
    await _pumpDjFlutterAppWithMockScope(
      tester,
      AuthSessionSnapshot(
        kind: AuthSessionKind.guest,
        guestToken: 'mock_token',
        tokenExpiresAt: DateTime.now().add(const Duration(hours: 6)),
        remainingTime: '6:00:00',
        isVip: false,
      ),
    );

    await tester.tap(find.text('解锁工具'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byType(UnlockMusicEntryPage), findsOneWidget);
    expect(find.text('音乐解锁'), findsOneWidget);
    expect(find.text('🔓 音乐解锁引擎'), findsOneWidget);
    expect(find.text('▶ 开始批量解锁'), findsOneWidget);
  });

  testWidgets('unlock music page loads files and matches unified list ui', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: UnlockMusicEntryPage(bridge: _FakeUnlockMusicTaskBridge()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(UnlockMusicEntryPage));
    await state.debugLoadTargets(<String>[
      '/music/Fade.qmc0',
      '/music/Broken.ncm',
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.textContaining('输入: /music/Fade.qmc0'), findsOneWidget);
    expect(find.text('📄 追加目标 (文件/目录)'), findsOneWidget);
    expect(find.text('🗑️ 清空列表'), findsOneWidget);
    expect(find.text('仅看失败项'), findsOneWidget);
    expect(find.text('输出目录'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);

    await tester.tap(find.text('▶ 开始批量解锁'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('解锁任务执行完毕。'), findsOneWidget);
    expect(find.textContaining('↳ Fade.mp3'), findsOneWidget);
    expect(find.text('invalid ncm header'), findsOneWidget);

    await tester.tap(find.text('仅看失败项'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Broken.ncm'), findsOneWidget);
  });

  testWidgets('unlock music page opens completion dialog and output folder', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<String> openedDirectories = <String>[];
    final Directory outputDirectory = await Directory.systemTemp.createTemp(
      'unlock_output_',
    );
    addTearDown(() => outputDirectory.delete(recursive: true));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: UnlockMusicEntryPage(
              bridge: _FakeUnlockMusicTaskBridge(
                outputDirectory: outputDirectory.path,
              ),
              onOpenOutputDirectory: (String directory) async {
                openedDirectories.add(directory);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final dynamic state = tester.state(find.byType(UnlockMusicEntryPage));
    state.debugShowCompletionDialog(
      title: '解锁完成',
      successCount: 1,
      failedCount: 1,
      outputDirectory: outputDirectory.path,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('解锁完成'), findsOneWidget);
    expect(find.text('打开输出目录'), findsOneWidget);
    expect(find.textContaining('输出目录：'), findsOneWidget);

    await tester.tap(find.text('打开输出目录').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(openedDirectories, hasLength(1));
    expect(openedDirectories.single, outputDirectory.path);
    expect(find.text('解锁完成'), findsNothing);
  });

  testWidgets('unlock music keeps last completed task history entry', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<String> openedDirectories = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: UnlockMusicEntryPage(
              bridge: _FakeUnlockMusicTaskBridge(),
              onOpenOutputDirectory: (String directory) async {
                openedDirectories.add(directory);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(UnlockMusicEntryPage));
    await state.debugLoadTargets(<String>[
      '/music/Fade.qmc0',
      '/music/Broken.ncm',
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('▶ 开始批量解锁'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    await state.debugLoadTargets(<String>['/music/NewSong.ncm'], append: false);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('unlock_music_history_entry')),
      findsOneWidget,
    );
    expect(find.text('最近一次完成任务'), findsOneWidget);
    expect(find.textContaining('共 2 首 · 成功 1 · 失败 1'), findsOneWidget);
    expect(find.textContaining('-'), findsOneWidget);
    expect(find.textContaining(':'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey<String>('unlock_music_history_entry')),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近一次完成任务'), findsNWidgets(2));
    expect(find.text('全部结果'), findsOneWidget);
    expect(find.text('仅成功项'), findsOneWidget);
    expect(find.text('仅失败项'), findsOneWidget);
    expect(
      find.textContaining('Fade.qmc0 -> /output/Fade.mp3'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Broken.ncm -> invalid ncm header'),
      findsOneWidget,
    );

    await tester.tap(find.text('仅成功项'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Fade.qmc0 -> /output/Fade.mp3'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Broken.ncm -> invalid ncm header'),
      findsNothing,
    );

    await tester.tap(find.text('仅失败项'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fade.qmc0 -> /output/Fade.mp3'), findsNothing);
    expect(
      find.textContaining('Broken.ncm -> invalid ncm header'),
      findsOneWidget,
    );

    await tester.tap(find.text('全部结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('unlock_music_history_clear')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('unlock_music_history_entry')),
      findsNothing,
    );
    expect(find.text('已清除最近一次完成任务记录。'), findsOneWidget);
  });

  testWidgets('unlock music history checks output directory existence', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<String> openedDirectories = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: UnlockMusicEntryPage(
              bridge: _FakeUnlockMusicTaskBridge(),
              onOpenOutputDirectory: (String directory) async {
                openedDirectories.add(directory);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(UnlockMusicEntryPage));
    await state.debugLoadTargets(<String>['/music/CurrentSong.ncm']);
    await tester.pumpAndSettle();
    state.debugSetLastCompletedTask(
      UnlockMusicCompletedTaskRecord(
        taskId: 'history_1',
        status: UnlockMusicStatus.success,
        finishedAt: DateTime(2026, 4, 10, 12, 34, 56),
        outputDirectory: '/definitely/not/exist',
        inputFiles: const <UnlockMusicFileItem>[
          UnlockMusicFileItem(path: '/music/Fade.qmc0', name: 'Fade.qmc0'),
        ],
        successCount: 1,
        failedCount: 0,
        results: const <UnlockMusicResultItem>[
          UnlockMusicResultItem(
            inputPath: '/music/Fade.qmc0',
            outputPath: '/definitely/not/exist/Fade.mp3',
            success: true,
            format: 'mp3',
            error: null,
          ),
        ],
        message: '解锁任务执行完毕。',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('unlock_music_history_entry')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2026-04-10'), findsWidgets);
    expect(find.textContaining('12:34:56'), findsWidgets);

    await tester.tap(find.text('打开输出文件夹').last);
    await tester.pumpAndSettle();

    expect(openedDirectories, isEmpty);
  });

  testWidgets(
    'unlock music creates fallback output directory in source folder',
    (WidgetTester tester) async {
      tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final Directory sourceDirectory = await Directory.systemTemp.createTemp(
        'unlock_source_',
      );
      addTearDown(() => sourceDirectory.delete(recursive: true));
      final Directory missingOutputDirectory = Directory(
        p.join(sourceDirectory.path, 'missing-output'),
      );
      final _FakeUnlockMusicTaskBridge bridge = _FakeUnlockMusicTaskBridge();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(child: UnlockMusicEntryPage(bridge: bridge)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(UnlockMusicEntryPage));
      state.debugSetOutputDirectory(missingOutputDirectory.path);
      await state.debugLoadTargets(<String>[
        p.join(sourceDirectory.path, 'Fade.qmc0'),
        p.join(sourceDirectory.path, 'Broken.ncm'),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.text('▶ 开始批量解锁'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(bridge.lockedOutputDir, isNotNull);
      expect(bridge.lockedOutputDir, isNot(missingOutputDirectory.path));
      expect(Directory(bridge.lockedOutputDir!).existsSync(), isTrue);
      expect(p.dirname(bridge.lockedOutputDir!), sourceDirectory.path);
      expect(
        p.basename(bridge.lockedOutputDir!),
        matches(RegExp(r'^解锁输出-\d{8}-\d{6}$')),
      );
    },
  );

  testWidgets('unlock music add target button appends without replacing', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: UnlockMusicEntryPage(
              bridge: _FakeUnlockMusicTaskBridge(),
              targetPicker: () async => <String>[
                '/music/a.ncm',
                '/music/folder',
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(UnlockMusicEntryPage));
    await state.debugLoadTargets(<String>['/music/initial.ncm']);
    await tester.pumpAndSettle();

    await tester.tap(find.text('📄 追加目标 (文件/目录)'));
    await tester.pumpAndSettle();

    expect(find.text('initial.ncm'), findsOneWidget);
    expect(find.text('a.ncm'), findsOneWidget);
    expect(find.text('folder'), findsOneWidget);
    expect(find.text('已追加 2 个目标。'), findsOneWidget);
  });

  testWidgets('unlock music remove and clear keep bridge state in sync', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: UnlockMusicEntryPage(bridge: _FakeUnlockMusicTaskBridge()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(UnlockMusicEntryPage));
    await state.debugLoadTargets(<String>[
      '/music/Fade.qmc0',
      '/music/Broken.ncm',
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('×').first);
    await tester.pumpAndSettle();

    expect(find.text('Fade.qmc0'), findsNothing);
    expect(find.text('Broken.ncm'), findsOneWidget);
    expect(find.text('已移除目标。'), findsOneWidget);

    await tester.tap(find.text('🗑️ 清空列表'));
    await tester.pumpAndSettle();

    expect(find.text('Broken.ncm'), findsNothing);
    expect(find.text('已清空导入列表。'), findsOneWidget);
    expect(find.text('点击选择或拖入文件文件夹'), findsOneWidget);
  });

  testWidgets('unlock music shows skipped target feedback', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: UnlockMusicEntryPage(
              bridge: _FakeUnlockMusicTaskBridge(
                skippedPathsByBatch: const <String, List<String>>{
                  '/music/unsupported-folder': <String>[
                    '/music/unsupported-folder/readme.txt',
                    '/music/unsupported-folder/cover.jpg',
                  ],
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(UnlockMusicEntryPage));
    await state.debugLoadTargets(<String>[
      '/music/Fade.qmc0',
      '/music/unsupported-folder',
    ]);
    await tester.pumpAndSettle();

    expect(find.text('已载入 1 个目标，忽略 2 个不支持项。'), findsOneWidget);
    expect(
      state.debugSkippedTargets,
      containsAll(<String>[
        '/music/unsupported-folder/readme.txt',
        '/music/unsupported-folder/cover.jpg',
      ]),
    );
  });

  testWidgets('unlock music surfaces target limit errors', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: UnlockMusicEntryPage(
              bridge: _FakeUnlockMusicTaskBridge(
                errorToThrow: const UnlockMusicBridgeException(
                  'TARGET_LIMIT_EXCEEDED',
                  '扫描目录过大，请缩小导入范围后重试（最多扫描 20000 个节点）。',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(UnlockMusicEntryPage));
    await state.debugLoadTargets(<String>['/music/huge-folder']);
    await tester.pumpAndSettle();

    expect(find.text('扫描目录过大，请缩小导入范围后重试（最多扫描 20000 个节点）。'), findsOneWidget);
  });

  testWidgets(
    'unlock music page accepts dropped targets and switches search tab',
    (WidgetTester tester) async {
      tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: UnlockMusicEntryPage(
                bridge: _FakeUnlockMusicTaskBridge(),
                searchBridge: _FakeSearchDownloadTaskBridge(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic dropTarget = tester.widget(find.byType(DropTarget));
      await dropTarget.onDragDone(
        DropDoneDetails(
          files: <DropItem>[
            DropItemFile('/music/B.qmc0'),
            DropItemFile('/music/A.ncm'),
          ],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('B.qmc0'), findsOneWidget);
      expect(find.text('A.ncm'), findsOneWidget);

      await tester.tap(find.text('🌐 全网搜索下载'));
      await tester.pumpAndSettle();

      expect(find.text('全网搜索下载'), findsWidgets);
      expect(find.text('引掣就绪'), findsOneWidget);
      expect(find.text('🔍 搜索 / 解析'), findsOneWidget);
      expect(find.text('更多平台选项 ▼'), findsOneWidget);
      expect(find.text('歌曲名称'), findsOneWidget);
      expect(find.text('歌手'), findsOneWidget);
      expect(find.text('来源'), findsOneWidget);
      expect(find.text('大小'), findsOneWidget);
      expect(find.text('音质'), findsOneWidget);
      expect(find.text('📡 等待检索信号输入...'), findsOneWidget);
      expect(find.textContaining('[System] 全网搜索下载挂载完毕.'), findsOneWidget);
      expect(find.text('▶ 开始下载选中项'), findsOneWidget);
      expect(find.text('■ 终止'), findsOneWidget);
    },
  );

  testWidgets('search tab can search select and start download', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _FakeSearchDownloadTaskBridge bridge =
        _FakeSearchDownloadTaskBridge();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: UnlockMusicEntryPage(
              bridge: _FakeUnlockMusicTaskBridge(),
              searchBridge: bridge,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('🌐 全网搜索下载'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, 'fade');
    await tester.tap(find.text('🔍 搜索 / 解析'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('Fade'), findsOneWidget);
    expect(find.text('Spectre'), findsOneWidget);
    expect(find.text('Alan Walker'), findsNWidgets(2));
    expect(find.textContaining('[System] 搜索完成，共 2 条结果。'), findsWidgets);
    expect(find.text('请先勾选待下载曲目。'), findsNothing);

    await tester.tap(find.text('Fade'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('▶ 开始下载选中项'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.textContaining('[System] 下载完成，共 2 项。'), findsOneWidget);
    expect(find.text('下载完成'), findsWidgets);
  });

  testWidgets(
    'search download shows completion dialog and opens output folder',
    (WidgetTester tester) async {
      tester.view.physicalSize = AppLayoutContract.defaultWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final Directory outputDirectory = await Directory.systemTemp.createTemp(
        'search_download_output_',
      );
      addTearDown(() => outputDirectory.delete(recursive: true));

      final _FakeSearchDownloadTaskBridge bridge =
          _FakeSearchDownloadTaskBridge(outputDirectory: outputDirectory.path);
      final List<String> openedDirectories = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: UnlockMusicEntryPage(
                bridge: _FakeUnlockMusicTaskBridge(),
                searchBridge: bridge,
                onOpenOutputDirectory: (String directory) async {
                  openedDirectories.add(directory);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('🌐 全网搜索下载'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText).first, 'fade');
      await tester.tap(find.text('🔍 搜索 / 解析'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fade'));
      await tester.pumpAndSettle();

      final Finder downloadButton = find.text('▶ 开始下载选中项');
      await tester.ensureVisible(downloadButton);
      await tester.tap(downloadButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('下载完成'), findsWidgets);
      expect(find.text('打开输出目录'), findsOneWidget);

      await tester.tap(find.text('打开输出目录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(openedDirectories, hasLength(1));
      expect(openedDirectories.single, outputDirectory.path);
    },
  );

  testWidgets('more platform selection updates real search sources', (
    WidgetTester tester,
  ) async {
    final _FakeSearchDownloadTaskBridge bridge =
        _FakeSearchDownloadTaskBridge();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: UnlockMusicEntryPage(
              bridge: _FakeUnlockMusicTaskBridge(),
              searchBridge: bridge,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('🌐 全网搜索下载'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('更多平台选项 ▼'));
    await tester.pumpAndSettle();
    expect(find.text('酷我音乐'), findsOneWidget);

    await tester.tap(find.text('酷我音乐'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, 'fade');
    await tester.tap(find.text('🔍 搜索 / 解析'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(bridge.lastLockedSources, contains('酷我音乐'));
  });

  testWidgets('cleanup dup requires targets before start', (
    WidgetTester tester,
  ) async {
    await _pumpCleanupDupModule(tester, bridge: _FakeCleanupDupTaskBridge());

    expect(find.text('曲目标题广告清理'), findsOneWidget);
    await tester.tap(find.text('开始清理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请先拖入或选择目标文件库！'), findsOneWidget);

    final dynamic entryPageState = tester.state(
      find.byType(CleanupDupEntryPage),
    );
    final CleanupDupController controller =
        entryPageState.debugController as CleanupDupController;
    await controller.loadTargets(CleanupDupPanelKind.titleClean, <String>[
      'Track_001_Master.mp3',
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始清理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('请输入要清除的文本内容！'), findsOneWidget);
  });

  testWidgets('cleanup dup title flow locks config loads files and completes', (
    WidgetTester tester,
  ) async {
    final _FakeCleanupDupTaskBridge bridge = _FakeCleanupDupTaskBridge();
    await _pumpCleanupDupModule(tester, bridge: bridge);

    final dynamic entryPageState = tester.state(
      find.byType(CleanupDupEntryPage),
    );
    final CleanupDupController controller =
        entryPageState.debugController as CleanupDupController;
    await controller.loadTargets(CleanupDupPanelKind.titleClean, <String>[
      'Track_001_Master.mp3',
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Track_001_Master.mp3'), findsOneWidget);
    expect(find.text('目标就绪，等待执行。'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, '微信');
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始清理'));
    await tester.pump();
    expect(bridge.lastLockedTitleDeleteText, '微信');
    expect(find.text('处理中'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('任务执行完毕。'), findsOneWidget);
  });

  testWidgets('cleanup dup duplicate flow opens review modal and executes', (
    WidgetTester tester,
  ) async {
    await _pumpCleanupDupModule(tester, bridge: _FakeCleanupDupTaskBridge());

    final Finder confirmButtons = find.text('确定');
    await tester.tap(confirmButtons.at(1));
    await tester.pumpAndSettle();

    final dynamic entryPageState = tester.state(
      find.byType(CleanupDupEntryPage),
    );
    final CleanupDupController controller =
        entryPageState.debugController as CleanupDupController;
    await controller.loadTargets(CleanupDupPanelKind.duplicateSearch, <String>[
      'Duplicate_001_Master.mp3',
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Duplicate_001_Master.mp3'), findsOneWidget);

    await tester.tap(find.text('开始查重'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('🔍 展开全屏审阅'), findsOneWidget);
    await tester.tap(find.text('🔍 展开全屏审阅'));
    await tester.pumpAndSettle();

    expect(find.text('🔍 查重结果全屏审阅'), findsOneWidget);
    expect(find.text('自动保留'), findsNWidgets(2));

    await tester.tap(find.text('💣 确认并删除已选 (2项)'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('🔍 查重结果全屏审阅'), findsNothing);
    expect(find.text('点击选择或拖入文件文件夹'), findsOneWidget);
  });

  test(
    'python cleanup bridge roundtrip matches frozen protocol',
    () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'cleanup_dup_bridge_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final File keep = File(p.join(tempDir.path, 'Fade.mp3'));
      final File dup = File(p.join(tempDir.path, 'Fade 副本.mp3'));
      await keep.writeAsBytes(<int>[1, 2, 3, 4, 5, 6]);
      await dup.writeAsBytes(<int>[1, 2, 3]);

      final CleanupDupTaskBridge bridge = PythonCleanupDupTaskBridge(
        pythonExecutable: _pythonRuntimeExecutable(),
        workingDirectory: _pythonRuntimeDirectory(),
        scriptModule: 'dj_runtime_py',
      );
      addTearDown(bridge.close);

      final List<String> loadedPaths = await bridge.loadTargets(
        CleanupDupPanelKind.duplicateSearch,
        <String>[tempDir.path],
      );
      expect(loadedPaths, hasLength(2));

      await bridge.lockConfig(
        CleanupDupPanelKind.duplicateSearch,
        <String, Object?>{
          'matching_mode': '极速比对',
          'move_to_recycle_bin': false,
        },
      );

      final CleanupDupTaskSnapshot task = await bridge
          .startDuplicateCheckTask();
      expect(task.taskId, startsWith('task_dup_'));
      expect(task.status, CleanupDupStatus.running);

      final List<CleanupDupTaskEvent> events = await bridge.subscribeTaskEvents(
        taskId: task.taskId,
      );
      expect(
        events.any(
          (CleanupDupTaskEvent event) => event.event == 'review_ready',
        ),
        isTrue,
      );

      final CleanupDupReviewResult review = await bridge.fetchReviewResult(
        task.taskId,
      );
      expect(review.status, CleanupDupStatus.reviewReady);
      expect(review.groups, isNotEmpty);

      final DuplicateEntry selectedEntry = review.groups.first.entries
          .firstWhere((DuplicateEntry entry) => entry.isSelectedToDelete);

      final CleanupDupDeleteResult deleteResult = await bridge.executeDelete(
        taskId: task.taskId,
        moveToRecycleBin: false,
        selectedFiles: <FileItem>[selectedEntry.file],
      );
      expect(deleteResult.status, CleanupDupStatus.success);
      expect(deleteResult.deletedCount, 1);
      expect(keep.existsSync(), isTrue);
      expect(dup.existsSync(), isFalse);
    },
    skip: 'Requires properly configured Python runtime with SecureStorage key',
  );
}
