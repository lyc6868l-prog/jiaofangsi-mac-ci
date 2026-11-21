import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../app/dj_app_scope.dart';
import '../../../../app/layout/app_layout_contract.dart';
import '../../../../app/router/app_router.dart';
import '../controllers/unified_account_service.dart';
import '../models/auth_models.dart';
import '../models/auth_session_snapshot.dart';
import '../widgets/login_credential_store.dart';
import '../widgets/python_login_credential_store.dart';
import '../widgets/new_login_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Duration _loginFadeDuration = Duration(milliseconds: 180);

  String _humanizeAuthError(Object error, {required String fallback}) {
    if (error is AuthBridgeException) {
      final String message = error.message.trim();
      if (message.isNotEmpty) {
        return message;
      }
    }
    return fallback;
  }

  bool _surfaceStateLoaded = false;
  bool _isTransitioningToShell = false;
  static const Set<String> _vipEntitlementTypes = <String>{
    'vip',
    'dj_tool',
    'web_vip',
    'web_mvp',
    'web_ceo',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyLoginWindowLayout();
      unawaited(_tryAutoLogin());
    });
  }

  Future<void> _applyLoginWindowLayout() async {
    const Size loginWindowSize = Size(980, 700);
    await windowManager.setMinimumSize(loginWindowSize);
    await windowManager.setMaximumSize(loginWindowSize);
    await windowManager.setSize(loginWindowSize);
    await windowManager.setResizable(false);
    await windowManager.center();
  }

  Future<void> _switchToShellWindowLayout() async {
    await windowManager.setMaximumSize(const Size(100000, 100000));
    await windowManager.setMinimumSize(AppLayoutContract.minWindowSize);
    await windowManager.setSize(AppLayoutContract.defaultWindowSize);
    await windowManager.setResizable(true);
  }

  Future<void> _enterShell(AppShellSection section) async {
    if (_isTransitioningToShell || !mounted) {
      return;
    }
    setState(() {
      _isTransitioningToShell = true;
    });
    await Future<void>.delayed(_loginFadeDuration);
    await _switchToShellWindowLayout();
    if (!mounted) {
      return;
    }
    Navigator.of(
      context,
    ).pushReplacementNamed(AppRouter.shellPath, arguments: section);
  }

  Future<void> _tryAutoLogin() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool autoLogin = prefs.getBool('autoLogin') ?? false;
    if (!autoLogin) {
      if (mounted) setState(() => _surfaceStateLoaded = true);
      return;
    }

    final DjAppScope scope = DjAppScope.of(context);
    try {
      final AuthSessionSnapshot saved = await scope.authController
          .restoreSession();
      if (saved.isUser && saved.hasValidToken) {
        scope.sessionStore.update(saved);
        if (!mounted) return;
        await _enterShell(AppShellSection.overview);
        return;
      }
    } catch (_) {
      // Fall back to saved account/password below.
    }

    // Password auto-login: only when the user explicitly chose it and the
    // remembered password is still available.
    final bool rememberPassword = prefs.getBool('rememberPassword') ?? true;
    final String? account = prefs.getString('lastLoginAccount');
    if (rememberPassword && account != null && account.isNotEmpty) {
      String? password;
      try {
        password = await PythonLoginCredentialStore(
          scope.authController.authBridge,
        ).readPassword(account);
      } catch (_) {
        password = null;
      }
      if (password != null && password.isNotEmpty) {
        final AuthSessionSnapshot snapshot = await _handleLogin(
          account,
          password,
        );
        if (snapshot.canEnterShell) {
          return;
        }
      }
    }

    if (mounted) setState(() => _surfaceStateLoaded = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050607),
      body: AbsorbPointer(
        absorbing: _isTransitioningToShell,
        child: AnimatedOpacity(
          key: const ValueKey<String>('login_page_transition'),
          opacity: _isTransitioningToShell ? 0 : 1,
          duration: _loginFadeDuration,
          curve: Curves.easeOutCubic,
          child: Stack(
            children: [
              Center(
                child: SizedBox(
                  width: 960,
                  child: _surfaceStateLoaded
                      ? NewLoginScreen(
                          onLogin: _handleLogin,
                          onUnifiedLogin: _handleUnifiedLogin,
                          onDisclaimer: _handleDisclaimer,
                          credentialStore: PythonLoginCredentialStore(
                            DjAppScope.of(context).authController.authBridge,
                          ),
                        )
                      : const SizedBox(
                          width: 480,
                          height: 680,
                          child: Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                color: Color(0xFF0F766E),
                                strokeWidth: 3,
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: DragToMoveArea(child: SizedBox(height: 84)),
              ),
              Positioned(
                top: 16,
                right: 18,
                child: Row(
                  children: [
                    _WindowBtn(type: _WindowBtnType.min),
                    const SizedBox(width: 12),
                    _WindowBtn(type: _WindowBtnType.close),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<AuthSessionSnapshot> _handleLogin(
    String loginName,
    String password,
  ) async {
    final DjAppScope scope = DjAppScope.of(context);
    final controller = scope.authController;
    final store = scope.sessionStore;

    try {
      final snapshot = await controller.login(
        loginName: loginName,
        password: password,
      );

      if (!mounted) return snapshot;

      if (!snapshot.canEnterShell) {
        store.update(snapshot);
        return snapshot;
      }

      store.update(snapshot);
      await _enterShell(AppShellSection.overview);
      return snapshot;
    } catch (error) {
      final AuthSessionSnapshot snapshot = AuthSessionSnapshot(
        errorMessage: _humanizeAuthError(error, fallback: '登录失败，请稍后重试。'),
        needNetworkValidation: true,
      );
      if (!mounted) return snapshot;
      store.update(snapshot);
      return snapshot;
    }
  }

  Future<void> _handleUnifiedLogin(UnifiedSession session) async {
    final service = UnifiedAccountService();
    try {
      final UnifiedProfile profile = await service.profile(session.accessToken);
      final List<EntitlementInfo> entitlements = await service.entitlements(
        session.accessToken,
      );
      final bool isVip = entitlements.any(
        (EntitlementInfo item) =>
            item.isActive &&
            _vipEntitlementTypes.contains(item.entitlementType),
      );
      DateTime? vipExpiresAt;
      for (final EntitlementInfo item in entitlements) {
        if (item.isActive &&
            _vipEntitlementTypes.contains(item.entitlementType)) {
          vipExpiresAt = item.expireAt;
          break;
        }
      }
      final AuthSessionSnapshot snapshot = AuthSessionSnapshot(
        kind: AuthSessionKind.user,
        authMode: 'unified',
        token: session.accessToken,
        userId: session.accountId,
        loginName: profile.boundEmail ?? session.displayName,
        stageName: profile.stageName ?? session.displayName,
        avatarType: profile.avatarType ?? 'male',
        avatarUrl: profile.avatarUrl ?? session.avatarUrl,
        isVip: isVip,
        tokenExpiresAt:
            session.accessExpiresAt ??
            DateTime.now().add(const Duration(hours: 1)),
        refreshToken: session.refreshToken,
        refreshExpiresAt: session.refreshExpiresAt,
        vipExpiresAt: vipExpiresAt,
        entitlements: entitlements,
      );
      if (!mounted) return;
      final DjAppScope scope = DjAppScope.of(context);
      await scope.authController.importUnifiedSession(
        snapshot,
        refreshToken: session.refreshToken,
        refreshExpiresAt: session.refreshExpiresAt,
      );
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('autoLogin', true);
      scope.sessionStore.update(snapshot);
      await _enterShell(AppShellSection.overview);
    } finally {
      service.close();
    }
  }

  void _handleDisclaimer() {}
}

enum _WindowBtnType { min, close }

class _WindowBtn extends StatefulWidget {
  final _WindowBtnType type;

  const _WindowBtn({required this.type});

  @override
  State<_WindowBtn> createState() => _WindowBtnState();
}

class _WindowBtnState extends State<_WindowBtn> {
  bool _isHovered = false;
  bool _isPressed = false;

  Future<void> _handlePress() async {
    if (widget.type == _WindowBtnType.min) {
      await windowManager.minimize();
      return;
    }
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    final bool isClose = widget.type == _WindowBtnType.close;
    final Color baseColor = const Color(0xFF4B5563);
    final Color activeColor = isClose ? const Color(0xFFF43F5E) : Colors.white;
    final Color lineColor = _isHovered ? activeColor : baseColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) => setState(() => _isPressed = false),
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: GestureDetector(
          onTap: _handlePress,
          behavior: HitTestBehavior.opaque,
          child: Semantics(
            button: true,
            label: isClose ? '关闭登录窗口' : '最小化登录窗口',
            child: Transform.translate(
              offset: Offset(0, _isPressed ? 1.5 : 0),
              child: Container(
                key: ValueKey<String>(
                  isClose
                      ? 'login_window_control_close'
                      : 'login_window_control_minimize',
                ),
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: _isHovered
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.transparent,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: isClose
                      ? [_line(45, lineColor), _line(-45, lineColor)]
                      : [
                          Container(
                            width: 12,
                            height: 2,
                            decoration: BoxDecoration(
                              color: lineColor,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: _isHovered
                                  ? [
                                      BoxShadow(
                                        color: lineColor.withValues(alpha: 0.8),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(double angle, Color color) {
    return Transform.rotate(
      angle: angle * 0.0174533,
      child: Container(
        width: 14,
        height: 2,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          boxShadow: _isHovered
              ? [BoxShadow(color: color.withValues(alpha: 0.9), blurRadius: 10)]
              : null,
        ),
      ),
    );
  }
}
