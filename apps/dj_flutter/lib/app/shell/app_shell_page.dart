import 'dart:async';

import 'package:flutter/material.dart' hide BoxDecoration, BoxShadow;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart';
import 'package:window_manager/window_manager.dart';

import '../dj_app_scope.dart';
import '../layout/app_layout_contract.dart';
import '../router/app_router.dart';
import '../../features/auth/presentation/models/auth_session_snapshot.dart';
import '../../features/auth/presentation/models/auth_session_store.dart';
import '../../shared/hardware_ui/hardware_ui.dart';
import '../../shared/task_runtime/task_running_notifier.dart';
import 'app_shell_top_bar.dart';
import 'bottom_status_bar.dart';
import 'feature_card/glass_card.dart';
import 'gift_redeem_bubble.dart';
import 'user_center_panel_ui.dart';
import 'workspace_module.dart';
import '../update/app_update_service.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({super.key, required this.initialSection});

  final AppShellSection initialSection;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage> {
  static const Duration _shellFadeDuration = Duration(milliseconds: 220);
  static const Duration _logoutFadeDuration = Duration(milliseconds: 180);
  static const Size _loginWindowSize = Size(980, 700);

  late AppShellSection _currentSection;
  AuthSessionSnapshot _sessionSnapshot = AuthSessionSnapshot.anonymous;
  AuthSessionStore? _sessionStore;
  TaskRunningNotifier? _taskRunningNotifier;
  final TextEditingController _giftRedeemController = TextEditingController();
  final FocusNode _giftRedeemFocusNode = FocusNode();
  bool _isGiftBubbleVisible = false;
  bool _hasUnreadGiftSignal = true;
  String? _giftRedeemErrorText;
  bool _shellVisible = false;
  bool _isLoggingOut = false;
  bool _isUserCenterPinned = false;
  bool _isUserCenterHovering = false;
  Timer? _userCenterHideTimer;
  bool _sessionInitialized = false;
  final AppUpdateService _updateService = AppUpdateService();
  bool _redirectingToLogin = false;

  bool get _isUserCenterVisible => _isUserCenterPinned || _isUserCenterHovering;
  AppShellLedState get _bottomLedState {
    if (_taskRunningNotifier == null) {
      return AppShellLedState.init;
    }
    if (_hasUnreadGiftSignal) {
      return AppShellLedState.warning;
    }
    if (_taskRunningNotifier!.hasRunningTask()) {
      return AppShellLedState.running;
    }
    if (_taskRunningNotifier!.hasAnyError()) {
      return AppShellLedState.error;
    }
    if (_taskRunningNotifier!.hasAnyAborted()) {
      return AppShellLedState.aborted;
    }
    if (_taskRunningNotifier!.hasAnySuccess()) {
      return AppShellLedState.complete;
    }
    if (_isGiftBubbleVisible || _isUserCenterVisible) {
      return AppShellLedState.running;
    }
    if (_currentSection == AppShellSection.overview) {
      return AppShellLedState.init;
    }
    return AppShellLedState.complete;
  }

  @override
  void initState() {
    super.initState();
    _currentSection = widget.initialSection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _shellVisible = true;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sessionInitialized) {
      final DjAppScope scope = DjAppScope.of(context);
      _sessionStore = scope.sessionStore;
      _taskRunningNotifier = scope.taskRunningNotifier;
      _sessionSnapshot = _sessionStore!.snapshot;
      _sessionStore!.addListener(_onSessionChanged);
      _taskRunningNotifier!.addListener(_onTaskStateChanged);
      _sessionInitialized = true;
      _redirectToLoginIfNeeded();
    }
  }

  @override
  void dispose() {
    _sessionStore?.removeListener(_onSessionChanged);
    _taskRunningNotifier?.removeListener(_onTaskStateChanged);
    _userCenterHideTimer?.cancel();
    _giftRedeemController.dispose();
    _giftRedeemFocusNode.dispose();
    _updateService.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    final AuthSessionSnapshot newSnapshot = DjAppScope.of(
      context,
    ).sessionStore.snapshot;
    if (newSnapshot != _sessionSnapshot) {
      setState(() {
        _sessionSnapshot = newSnapshot;
      });
      _redirectToLoginIfNeeded();
    }
  }

  void _onTaskStateChanged() {
    setState(() {
      _taskRunningNotifier = _taskRunningNotifier;
    });
  }

  void _redirectToLoginIfNeeded() {
    if (_redirectingToLogin || !_sessionSnapshot.isAnonymous || !mounted) {
      return;
    }
    _redirectingToLogin = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRouter.loginPath, (route) => false);
    });
  }

  Future<void> _handleSectionChangeRequest(AppShellSection newSection) async {
    if (newSection == _currentSection) {
      return;
    }
    if (_taskRunningNotifier != null &&
        _taskRunningNotifier!.hasRunningTask()) {
      final String moduleName =
          _taskRunningNotifier!.firstRunningSectionTitle ?? '当前模块';
      final bool confirmed = await _showTaskInterruptionConfirmationDialog(
        title: '切换页面会中断正在运行的模块',
        content: '$moduleName任务正在运行，继续切换会中断任务。是否继续？',
        cancelLabel: '暂不切换',
        confirmLabel: '切换',
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    setState(() {
      _currentSection = newSection;
    });
  }

  Future<bool> _showTaskInterruptionConfirmationDialog({
    required String title,
    required String content,
    required String cancelLabel,
    required String confirmLabel,
  }) async {
    return showHardwareConfirmDialog(
      context: context,
      title: title,
      message: content,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
    );
  }

  void _showUserCenterHover() {
    _userCenterHideTimer?.cancel();
    if (_isUserCenterHovering) {
      return;
    }
    setState(() {
      _isUserCenterHovering = true;
    });
  }

  void _hideUserCenterHover() {
    _userCenterHideTimer?.cancel();
    _userCenterHideTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || _isUserCenterPinned) {
        return;
      }
      setState(() {
        _isUserCenterHovering = false;
      });
    });
  }

  void _toggleUserCenterPinned() {
    _userCenterHideTimer?.cancel();
    setState(() {
      _isUserCenterPinned = !_isUserCenterPinned;
      _isUserCenterHovering = _isUserCenterPinned;
    });
  }

  void _closeUserCenter() {
    _userCenterHideTimer?.cancel();
    if (!_isUserCenterVisible) {
      return;
    }
    setState(() {
      _isUserCenterPinned = false;
      _isUserCenterHovering = false;
    });
  }

  Future<void> _switchToLoginWindowLayout() async {
    await windowManager.setMinimumSize(_loginWindowSize);
    await windowManager.setMaximumSize(_loginWindowSize);
    await windowManager.setSize(_loginWindowSize);
    await windowManager.setResizable(false);
    await windowManager.center();
  }

  Future<void> _switchToLoginWindowLayoutSafely() async {
    try {
      await _switchToLoginWindowLayout();
    } on Object {
      return;
    }
  }

  Future<void> _clearLocalSessionInBackground(
    DjAppScope scope,
    AuthSessionSnapshot snapshot,
  ) async {
    try {
      await scope.authController.clearLocalSession(snapshot);
    } on Object {
      return;
    }
  }

  Future<void> _completeLogoutInBackground(
    DjAppScope scope,
    AuthSessionSnapshot snapshot,
  ) async {
    try {
      await scope.authController.logout(snapshot);
    } on Object {
      return;
    }
  }

  Future<void> _handleLogout() async {
    if (_isLoggingOut || !mounted) {
      return;
    }
    if (_taskRunningNotifier != null &&
        _taskRunningNotifier!.hasRunningTask()) {
      final String moduleName =
          _taskRunningNotifier!.firstRunningSectionTitle ?? '当前模块';
      final bool confirmed = await _showTaskInterruptionConfirmationDialog(
        title: '退出登录会中断正在运行的任务',
        content: '$moduleName任务正在运行，继续退出会中断任务。是否继续？',
        cancelLabel: '暂不退出',
        confirmLabel: '坚持退出',
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    final DjAppScope scope = DjAppScope.of(context);
    final AuthSessionSnapshot snapshot = _sessionSnapshot;
    _redirectingToLogin = true;
    setState(() {
      _isLoggingOut = true;
      _shellVisible = false;
      _isGiftBubbleVisible = false;
      _giftRedeemErrorText = null;
      _isUserCenterPinned = false;
      _isUserCenterHovering = false;
    });
    await Future<void>.delayed(_logoutFadeDuration);
    await _switchToLoginWindowLayoutSafely();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoLogin', false);
    scope.authController.enterLoggedOutState();
    scope.sessionStore.clear();
    unawaited(_clearLocalSessionInBackground(scope, snapshot));
    unawaited(_completeLogoutInBackground(scope, snapshot));
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRouter.loginPath,
      (Route<dynamic> route) => false,
    );
  }

  void _toggleGiftBubble() {
    if (_isGiftBubbleVisible) {
      _closeGiftBubble();
      return;
    }

    setState(() {
      _hasUnreadGiftSignal = false;
      _isGiftBubbleVisible = true;
      _giftRedeemErrorText = null;
      _giftRedeemController.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _giftRedeemFocusNode.requestFocus();
    });
  }

  void _closeGiftBubble() {
    _giftRedeemFocusNode.unfocus();
    setState(() {
      _isGiftBubbleVisible = false;
      _giftRedeemErrorText = null;
    });
  }

  void _submitGiftRedeemCode() {
    if (_giftRedeemController.text.length < 19) {
      setState(() {
        _giftRedeemErrorText = '兑换码长度不足，请检查后重新输入';
      });
      return;
    }

    _closeGiftBubble();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionSnapshot.isUser) {
      return const Scaffold(backgroundColor: Colors.transparent);
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size windowSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final AppShellMetrics metrics = AppLayoutContract.resolve(windowSize);

        if (metrics.isBlocked) {
          return _ShellBreakpointBlockedView(metrics: metrics);
        }
        final double shellHorizontalMargin =
            AppLayoutContract.outerHorizontalMargin;
        final double shellVerticalMargin =
            AppLayoutContract.outerVerticalMargin;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: AbsorbPointer(
            absorbing: _isLoggingOut,
            child: AnimatedOpacity(
              key: const ValueKey<String>('shell_page_transition'),
              opacity: _shellVisible ? 1 : 0,
              duration: _shellFadeDuration,
              curve: Curves.easeOutCubic,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: shellHorizontalMargin,
                  vertical: shellVerticalMargin,
                ),
                child: _ShellGlassPanel(
                  metrics: metrics,
                  isFullscreen: false,
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          DragToMoveArea(
                            child: AppShellTopBar(
                              isUserCenterActive: _isUserCenterVisible,
                              showUserCenterTrigger: !_sessionSnapshot.isGuest,
                              userCenterAvatarType: _sessionSnapshot.avatarType,
                              onUserCenterEnter: _showUserCenterHover,
                              onUserCenterExit: _hideUserCenterHover,
                              onUserCenterTap: _toggleUserCenterPinned,
                              updateService: _updateService,
                            ),
                          ),
                          const SizedBox(
                            height: AppLayoutContract.gapTopBarToCards,
                          ),
                          _FeatureCardZone(
                            currentSection: _currentSection,
                            sessionSnapshot: _sessionSnapshot,
                            onSectionChanged: _handleSectionChangeRequest,
                          ),
                          const SizedBox(
                            height: AppLayoutContract.gapCardsToWorkspace,
                          ),
                          WorkspaceFrame(
                            metrics: metrics,
                            section: _currentSection,
                            sessionSnapshot: _sessionSnapshot,
                          ),
                          const SizedBox(
                            height: AppLayoutContract.gapWorkspaceToBottomBar,
                          ),
                          BottomStatusBar(
                            onGiftTap: _toggleGiftBubble,
                            hasUnreadGiftSignal: _hasUnreadGiftSignal,
                            ledState: _bottomLedState,
                          ),
                        ],
                      ),
                      if (_isGiftBubbleVisible)
                        Positioned.fill(
                          child: GestureDetector(
                            key: const ValueKey<String>('gift_bubble_scrim'),
                            behavior: HitTestBehavior.opaque,
                            onTap: _closeGiftBubble,
                            child: const ColoredBox(color: Colors.transparent),
                          ),
                        ),
                      if (_isGiftBubbleVisible)
                        Positioned(
                          right: 76,
                          bottom: 36,
                          child: GiftRedeemBubble(
                            controller: _giftRedeemController,
                            focusNode: _giftRedeemFocusNode,
                            errorText: _giftRedeemErrorText,
                            onClose: _closeGiftBubble,
                            onSubmit: _submitGiftRedeemCode,
                          ),
                        ),
                      if (!_sessionSnapshot.isGuest && _isUserCenterPinned)
                        Positioned.fill(
                          child: GestureDetector(
                            key: const ValueKey<String>('user_center_scrim'),
                            behavior: HitTestBehavior.opaque,
                            onTap: _closeUserCenter,
                            child: const ColoredBox(color: Colors.transparent),
                          ),
                        ),
                      if (!_sessionSnapshot.isGuest && _isUserCenterVisible)
                        Positioned(
                          top: 42,
                          right: userCenterPanelRightOffset,
                          child: MouseRegion(
                            onEnter: (_) => _showUserCenterHover(),
                            onExit: (_) => _hideUserCenterHover(),
                            child: UserCenterPanel(onLogout: _handleLogout),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShellBreakpointBlockedView extends StatelessWidget {
  const _ShellBreakpointBlockedView({required this.metrics});

  final AppShellMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('窗口宽度低于布局契约下限', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(
                  '当前尺寸 '
                  '${metrics.windowSize.width.toStringAsFixed(0)} × '
                  '${metrics.windowSize.height.toStringAsFixed(0)}，低于最小允许尺寸 '
                  '${AppLayoutContract.minWindowSize.width.toStringAsFixed(0)} × '
                  '${AppLayoutContract.minWindowSize.height.toStringAsFixed(0)}。',
                ),
                const SizedBox(height: 8),
                Text('本阶段主壳进入阻断态，不继续压缩内容布局。'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCardZone extends StatelessWidget {
  const _FeatureCardZone({
    required this.currentSection,
    required this.sessionSnapshot,
    required this.onSectionChanged,
  });

  final AppShellSection currentSection;
  final AuthSessionSnapshot sessionSnapshot;
  final ValueChanged<AppShellSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    return GlassCardGrid(
      currentSection: currentSection,
      sessionSnapshot: sessionSnapshot,
      onSectionChanged: onSectionChanged,
    );
  }
}

class _ShellGlassPanel extends StatelessWidget {
  const _ShellGlassPanel({
    required this.child,
    required this.metrics,
    required this.isFullscreen,
  });

  final Widget child;
  final AppShellMetrics metrics;
  final bool isFullscreen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: metrics.shellSize.width,
      height: metrics.shellSize.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isFullscreen ? 0 : 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            borderRadius: BorderRadius.circular(isFullscreen ? 0 : 20),
          ),
          child: child,
        ),
      ),
    );
  }
}



