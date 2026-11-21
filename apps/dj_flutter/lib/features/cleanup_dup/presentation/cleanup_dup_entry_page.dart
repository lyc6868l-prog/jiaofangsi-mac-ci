import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/dj_app_scope.dart';
import '../../../app/router/app_router.dart';
import '../../../shared/platform_utils.dart' as platform_utils;
import '../../../shared/task_runtime/task_running_notifier.dart'
    show TaskRunningNotifier, TaskEndState;
import 'controllers/cleanup_dup_controller.dart';
import 'controllers/python_cleanup_dup_task_bridge.dart';
import 'models/cleanup_dup_models.dart';
import 'widgets/duplicate_review_modal.dart';
import 'widgets/duplicate_search_panel.dart';
import 'widgets/hardware_widgets.dart';
import 'widgets/title_cleanup_panel.dart';

class CleanupDupEntryPage extends StatefulWidget {
  const CleanupDupEntryPage({
    super.key,
    this.bridge,
    this.isFeatureLocked = false,
    this.onLockedStartPressed,
  });

  final CleanupDupTaskBridge? bridge;
  final bool isFeatureLocked;
  final VoidCallback? onLockedStartPressed;

  @override
  State<CleanupDupEntryPage> createState() => _CleanupDupEntryPageState();
}

class _CleanupDupEntryPageState extends State<CleanupDupEntryPage> {
  late final CleanupDupController _controller = CleanupDupController(
    bridge: widget.bridge ?? _createDefaultBridge(),
  );
  TaskRunningNotifier? _taskRunningNotifier;
  bool _lastReportedRunning = false;

  @visibleForTesting
  CleanupDupController get debugController => _controller;

  PythonCleanupDupTaskBridge _createDefaultBridge() {
    final Directory projectRoot = _resolveProjectRoot();
    final String workingDirectory = p.join(
      projectRoot.path,
      'runtime',
      'dj_runtime_py',
    );
    final String pythonExecutable = _resolvePythonExecutable(projectRoot);
    return PythonCleanupDupTaskBridge(
      pythonExecutable: pythonExecutable,
      workingDirectory: workingDirectory,
      scriptModule: 'dj_runtime_py',
    );
  }

  Directory _resolveProjectRoot() {
    return platform_utils.resolveProjectRoot();
  }

  String _resolvePythonExecutable(Directory projectRoot) {
    return platform_utils.resolvePythonExecutable(projectRoot);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _taskRunningNotifier = DjAppScope.maybeOf(context)?.taskRunningNotifier;
    _controller.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    final bool isRunning =
        _controller.titleRunning || _controller.duplicateRunning;
    if (_taskRunningNotifier == null) {
      return;
    }
    if (isRunning != _lastReportedRunning) {
      _taskRunningNotifier!.setRunning(AppShellSection.cleanupDup, isRunning);
      _lastReportedRunning = isRunning;
    }
    if (!isRunning) {
      final CleanupDupStatus titleStatus = _controller.titleCleanStatus;
      final CleanupDupStatus duplicateStatus =
          _controller.duplicateSearchStatus;
      TaskEndState endState = TaskEndState.none;
      if (titleStatus == CleanupDupStatus.success ||
          duplicateStatus == CleanupDupStatus.success) {
        endState = TaskEndState.success;
      } else if (titleStatus == CleanupDupStatus.error ||
          duplicateStatus == CleanupDupStatus.error) {
        endState = TaskEndState.error;
      } else if (titleStatus == CleanupDupStatus.cancelled ||
          duplicateStatus == CleanupDupStatus.cancelled) {
        endState = TaskEndState.aborted;
      }
      _taskRunningNotifier!.setEndState(AppShellSection.cleanupDup, endState);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    if (_taskRunningNotifier != null && _lastReportedRunning) {
      _taskRunningNotifier!.setRunning(AppShellSection.cleanupDup, false);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, _) {
        final String? titleToast = _controller.toastFor(
          CleanupDupPanelKind.titleClean,
        );
        final String? duplicateToast = _controller.toastFor(
          CleanupDupPanelKind.duplicateSearch,
        );

        return CleanupDupGridBackground(
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    if (titleToast != null || duplicateToast != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A0A13),
                              border: Border.all(
                                color: const Color(
                                  0xFFE11D48,
                                ).withValues(alpha: 0.4),
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              titleToast ?? duplicateToast!,
                              style: const TextStyle(
                                color: Color(0xFFF3F4F6),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: TitleCleanupPanel(
                              controller: _controller,
                              isFeatureLocked: widget.isFeatureLocked,
                              onLockedStartPressed: widget.onLockedStartPressed,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DuplicateSearchPanel(
                              controller: _controller,
                              isFeatureLocked: widget.isFeatureLocked,
                              onLockedStartPressed: widget.onLockedStartPressed,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              DuplicateReviewModal(controller: _controller),
            ],
          ),
        );
      },
    );
  }
}
