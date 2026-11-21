import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/dj_app_scope.dart';
import '../../../app/router/app_router.dart';
import '../../../shared/platform_utils.dart' as platform_utils;
import '../../../shared/task_runtime/task_running_notifier.dart'
    show TaskRunningNotifier, TaskEndState;
import 'controllers/metadata_edit_controller.dart';
import 'controllers/python_metadata_edit_task_bridge.dart';
import 'models/metadata_edit_models.dart';
import 'widgets/cover_injection_panel.dart';
import 'widgets/filename_injection_panel.dart';

class MetadataEditEntryPage extends StatefulWidget {
  const MetadataEditEntryPage({
    super.key,
    MetadataEditController? controller,
    this.isFeatureLocked = false,
    this.onLockedStartPressed,
  }) : _controller = controller;

  final MetadataEditController? _controller;
  final bool isFeatureLocked;
  final VoidCallback? onLockedStartPressed;

  @override
  State<MetadataEditEntryPage> createState() => _MetadataEditEntryPageState();
}

class _MetadataEditEntryPageState extends State<MetadataEditEntryPage> {
  @visibleForTesting
  MetadataEditController get debugController => _controller;

  PythonMetadataEditTaskBridge? _bridge;
  late final MetadataEditController _controller;
  TaskRunningNotifier? _taskRunningNotifier;
  bool _lastReportedRunning = false;

  @override
  void initState() {
    super.initState();
    if (widget._controller != null) {
      _controller = widget._controller!;
    } else {
      final Directory projectRoot =
          MetadataEditEnvironmentPaths.resolveProjectRoot();
      _bridge = PythonMetadataEditTaskBridge(
        pythonExecutable: MetadataEditEnvironmentPaths.resolvePythonExecutable(
          projectRoot,
        ),
        workingDirectory: p.join(projectRoot.path, 'runtime', 'dj_runtime_py'),
        scriptModule: 'dj_runtime_py',
      );
      _controller = MetadataEditController(
        bridge: _bridge!,
        ffmpegPath: MetadataEditEnvironmentPaths.resolveFfBinaryPath(
          projectRoot,
          'ffmpeg',
        ),
        ffprobePath: MetadataEditEnvironmentPaths.resolveFfBinaryPath(
          projectRoot,
          'ffprobe',
        ),
      );
    }
    _controller.addListener(_handleControllerChanged);
    _controller.initialize();
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
      _taskRunningNotifier!.setRunning(AppShellSection.metadataEdit, false);
    }
    _controller.close();
    super.dispose();
  }

  void _handleControllerChanged() {
    final MetadataEditStatus coverStatus = _controller.coverSnapshot.status;
    final MetadataEditStatus filenameStatus =
        _controller.filenameSnapshot.status;
    final bool isRunning =
        coverStatus == MetadataEditStatus.running ||
        filenameStatus == MetadataEditStatus.running;
    if (_taskRunningNotifier == null) {
      return;
    }
    if (isRunning != _lastReportedRunning) {
      _taskRunningNotifier!.setRunning(AppShellSection.metadataEdit, isRunning);
      _lastReportedRunning = isRunning;
    }
    if (!isRunning) {
      TaskEndState endState = TaskEndState.none;
      if (coverStatus == MetadataEditStatus.success ||
          filenameStatus == MetadataEditStatus.success) {
        endState = TaskEndState.success;
      } else if (coverStatus == MetadataEditStatus.error ||
          filenameStatus == MetadataEditStatus.error) {
        endState = TaskEndState.error;
      } else if (coverStatus == MetadataEditStatus.cancelled ||
          filenameStatus == MetadataEditStatus.cancelled) {
        endState = TaskEndState.aborted;
      }
      _taskRunningNotifier!.setEndState(AppShellSection.metadataEdit, endState);
    }

    final String? toastMessage = _controller.toastMessage;
    if (!mounted || toastMessage == null || toastMessage.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFE11D48),
          content: Text(toastMessage),
        ),
      );
    _controller.clearToast();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(color: Color(0xFF030303)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 50,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: CoverInjectionPanel(
                        controller: _controller,
                        isFeatureLocked: widget.isFeatureLocked,
                        onLockedStartPressed: widget.onLockedStartPressed,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilenameInjectionPanel(
                        controller: _controller,
                        isFeatureLocked: widget.isFeatureLocked,
                        onLockedStartPressed: widget.onLockedStartPressed,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class MetadataEditEnvironmentPaths {
  static Directory resolveProjectRoot({
    Directory? currentDirectory,
    String? resolvedExecutablePath,
  }) {
    return platform_utils.resolveProjectRoot(
      currentDirectory: currentDirectory,
      resolvedExecutablePath: resolvedExecutablePath,
    );
  }

  static String resolvePythonExecutable(Directory projectRoot) {
    return platform_utils.resolvePythonExecutable(projectRoot);
  }

  static String? resolveFfBinaryPath(
    Directory projectRoot,
    String executableName, {
    String? resolvedExecutablePath,
  }) {
    return platform_utils.resolveFfBinaryPath(projectRoot, executableName);
  }
}
