import 'package:flutter/widgets.dart';

import '../features/auth/presentation/controllers/auth_controller.dart';
import '../features/auth/presentation/controllers/python_auth_task_bridge.dart';
import '../features/auth/presentation/controllers/python_guest_task_bridge.dart';
import '../features/auth/presentation/models/auth_session_store.dart';
import '../shared/task_runtime/task_running_notifier.dart';

class DjAppScope extends InheritedWidget {
  const DjAppScope({
    super.key,
    required super.child,
    required this.sessionStore,
    required this.authController,
    required this.authBridge,
    required this.guestBridge,
    required this.taskRunningNotifier,
  });

  final AuthSessionStore sessionStore;
  final AuthController authController;
  final AuthTaskBridge authBridge;
  final GuestTaskBridge guestBridge;
  final TaskRunningNotifier taskRunningNotifier;

  static DjAppScope of(BuildContext context) {
    final DjAppScope? scope = context
        .dependOnInheritedWidgetOfExactType<DjAppScope>();
    assert(scope != null, 'DjAppScope not found in widget tree');
    return scope!;
  }

  static DjAppScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DjAppScope>();
  }

  @override
  bool updateShouldNotify(DjAppScope oldWidget) {
    return sessionStore != oldWidget.sessionStore ||
        authController != oldWidget.authController ||
        authBridge != oldWidget.authBridge ||
        guestBridge != oldWidget.guestBridge ||
        taskRunningNotifier != oldWidget.taskRunningNotifier;
  }
}
