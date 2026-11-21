import 'package:flutter/foundation.dart';

import '../../app/router/app_router.dart';

enum TaskEndState { none, success, error, aborted }

class TaskRunningNotifier extends ChangeNotifier {
  final Set<AppShellSection> _runningSections = <AppShellSection>{};
  final Map<AppShellSection, TaskEndState> _endStates =
      <AppShellSection, TaskEndState>{};

  bool hasRunningTask() => _runningSections.isNotEmpty;

  String? get firstRunningSectionTitle {
    final AppShellSection? section = firstRunningSection;
    if (section == null) {
      return null;
    }
    return switch (section) {
      AppShellSection.overview => '总览',
      AppShellSection.unlockTool => '全网搜索下载',
      AppShellSection.audioTranscode => '音频转码',
      AppShellSection.pinyinGenerator => '首拼生成',
      AppShellSection.cleanupDup => '曲库整理',
      AppShellSection.metadataEdit => '信息修改',
      AppShellSection.usbBackup => 'U盘备份',
    };
  }

  bool isSectionRunning(AppShellSection section) =>
      _runningSections.contains(section);

  AppShellSection? get firstRunningSection =>
      _runningSections.isNotEmpty ? _runningSections.first : null;

  TaskEndState getEndState(AppShellSection section) =>
      _endStates[section] ?? TaskEndState.none;

  bool hasAnyError() => _endStates.values.contains(TaskEndState.error);

  bool hasAnyAborted() => _endStates.values.contains(TaskEndState.aborted);

  bool hasAnySuccess() => _endStates.values.contains(TaskEndState.success);

  bool hasAnyEnded() => _endStates.values.any(
    (TaskEndState state) =>
        state == TaskEndState.success ||
        state == TaskEndState.error ||
        state == TaskEndState.aborted,
  );

  void setRunning(AppShellSection section, bool isRunning) {
    if (isRunning) {
      if (_runningSections.add(section)) {
        notifyListeners();
      }
    } else {
      if (_runningSections.remove(section)) {
        notifyListeners();
      }
    }
  }

  void setEndState(AppShellSection section, TaskEndState state) {
    if (_endStates[section] != state) {
      _endStates[section] = state;
      notifyListeners();
    }
  }

  void clearEndState(AppShellSection section) {
    if (_endStates.remove(section) != null) {
      notifyListeners();
    }
  }

  void clearAllEndStates() {
    if (_endStates.isNotEmpty) {
      _endStates.clear();
      notifyListeners();
    }
  }
}
