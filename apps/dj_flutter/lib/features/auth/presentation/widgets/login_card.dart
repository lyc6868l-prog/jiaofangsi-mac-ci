import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dj_flutter/shared/hardware_ui/hardware_ui.dart';
import 'package:dj_flutter/shared/platform_utils.dart';
import '../models/auth_models.dart';
import '../models/auth_session_snapshot.dart';
import 'giant_button.dart';
import 'glass_container.dart';
import 'history_dropdown.dart';
import 'login_credential_store.dart';
import 'tactical_input.dart';

class LoginCard extends StatefulWidget {
  final double width;
  final Future<AuthSessionSnapshot> Function(String loginName, String password)?
  onLogin;
  final Future<AuthSessionSnapshot> Function()? onGuest;
  final VoidCallback? onDisclaimer;
  final GuestTrialSnapshot guestTrial;
  final bool hasSuccessfulLoginHistory;
  final LoginCredentialStore? credentialStore;

  const LoginCard({
    super.key,
    this.width = 520,
    this.onLogin,
    this.onGuest,
    this.onDisclaimer,
    this.guestTrial = GuestTrialSnapshot.neverStarted,
    this.hasSuccessfulLoginHistory = false,
    this.credentialStore,
  });

  @override
  State<LoginCard> createState() => _LoginCardState();
}

enum _UserState { newUser, expired, loggedIn }

class _LoginCardState extends State<LoginCard> {
  static const String _loadingLoginText = '正在验证...';
  static final String _titleImagePath = _resolveImagePath('denlulogo.png');
  static final String _subtitleImagePath = _resolveImagePath(
    'a3ee22ebdae68c52f43688042d492994.png',
  );
  static const String _subtitleAssetPath =
      'assets/brand/a3ee22ebdae68c52f43688042d492994.png';

  static String _resolveImagePath(String filename) {
    final List<Directory> seeds = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];
    for (final Directory seed in seeds) {
      Directory current = seed;
      while (true) {
        final String candidate = p.join(current.path, '图片', filename);
        if (File(candidate).existsSync()) {
          return candidate;
        }
        final Directory parent = current.parent;
        if (parent.path == current.path) {
          break;
        }
        current = parent;
      }
    }
    return '';
  }

  static const String _loginButtonText = '登 录';
  static const String _loadingGuestText = '正在分配试用凭证...';
  static const String _guestTrialText = '免费体验剩余 23:59:59';
  static const String _hideDisclaimerKey = 'hideDisclaimer';
  static const String _hasSuccessfulLoginKey = 'hasSuccessfulAccountLogin';
  static const String _historyAccountsKey = 'loginHistoryAccounts';
  static const String _lastLoginAccountKey = 'lastLoginAccount';
  static const String _rememberPasswordKey = 'rememberPassword';
  static const String _autoLoginKey = 'autoLogin';
  static const int _historyAccountLimit = 10;
  static const String _registerUrl = 'https://www.jiaofangsi.top';
  static const String _purchaseUrl =
      'https://www.jiaofangsi.top/software-purchase';
  static const String _accountSecurityUrl =
      'https://www.jiaofangsi.top/account-security';
  static final RegExp _emailPattern = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey _accountInputKey = GlobalKey();

  final List<Map<String, String>> _historyAccounts = [];

  OverlayEntry? _dropdownOverlay;
  String? _errorMessage;
  int _errorVersion = 0;
  bool _isLoading = false;
  String? _guestButtonText;
  String? _guestStatusMessage;
  bool _showDisclaimer = false;
  bool _hideDisclaimer = false;
  bool _rememberPassword = true;
  bool _autoLogin = false;
  _UserState _userState = _UserState.newUser;
  String? _pendingAction;
  bool _hasSuccessfulLoginHistory = false;
  bool _autoLoginTriggered = false;
  Timer? _guestCountdownTimer;

  LoginCredentialStore get _credentialStore =>
      widget.credentialStore ?? const SharedPreferencesLoginCredentialStore();

  @override
  void initState() {
    super.initState();
    _loadPersistentUiState();
    _syncGuestTrialState();
  }

  @override
  void didUpdateWidget(covariant LoginCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guestTrial != widget.guestTrial ||
        oldWidget.hasSuccessfulLoginHistory !=
            widget.hasSuccessfulLoginHistory) {
      _syncGuestTrialState();
    }
  }

  Future<void> _loadPersistentUiState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool hideDisclaimer = prefs.getBool(_hideDisclaimerKey) ?? false;
    final bool hasSuccessfulLogin =
        prefs.getBool(_hasSuccessfulLoginKey) ??
        widget.hasSuccessfulLoginHistory;
    final bool rememberPassword = prefs.getBool(_rememberPasswordKey) ?? true;
    final bool autoLogin = prefs.getBool(_autoLoginKey) ?? false;
    final List<String> historyAccounts =
        prefs.getStringList(_historyAccountsKey) ?? <String>[];
    final String? lastLoginAccount = prefs.getString(_lastLoginAccountKey);
    final List<Map<String, String>> restoredHistory =
        await _restoreHistoryAccounts(historyAccounts);
    final String? restoredPassword =
        rememberPassword &&
            lastLoginAccount != null &&
            lastLoginAccount.isNotEmpty
        ? await _credentialStore.readPassword(lastLoginAccount)
        : null;
    if (!mounted) return;
    setState(() {
      _hideDisclaimer = hideDisclaimer;
      _hasSuccessfulLoginHistory = hasSuccessfulLogin;
      _rememberPassword = rememberPassword;
      _autoLogin = autoLogin;
      _historyAccounts
        ..clear()
        ..addAll(restoredHistory);
    });
    if (lastLoginAccount != null && lastLoginAccount.isNotEmpty) {
      _accountController.text = lastLoginAccount;
    }
    _passwordController.text = restoredPassword ?? '';
    _syncGuestTrialState();
    unawaited(_tryAutoLoginIfNeeded());
  }

  Future<void> _tryAutoLoginIfNeeded() async {
    if (_autoLoginTriggered ||
        !_autoLogin ||
        !_rememberPassword ||
        !_hideDisclaimer ||
        widget.onLogin == null) {
      return;
    }
    final String loginName = _accountController.text.trim();
    final String password = _passwordController.text;
    if (loginName.isEmpty || password.isEmpty) {
      return;
    }
    _autoLoginTriggered = true;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    _executeLogin();
  }

  Future<List<Map<String, String>>> _restoreHistoryAccounts(
    List<String> accounts,
  ) async {
    final List<Map<String, String>> items = <Map<String, String>>[];
    for (final String account in accounts) {
      if (account.isEmpty) {
        continue;
      }
      items.add(<String, String>{'account': account, 'password': ''});
    }
    return items;
  }

  Future<void> _persistHideDisclaimer(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setBool(_hideDisclaimerKey, true);
      return;
    }
    await prefs.remove(_hideDisclaimerKey);
  }

  Future<void> _persistSuccessfulLogin() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSuccessfulLoginKey, true);
  }

  Future<void> _persistLoginPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberPasswordKey, _rememberPassword);
    await prefs.setBool(_autoLoginKey, _autoLogin);
  }

  Future<void> _persistLoginHistory(String loginName, String password) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> accounts =
        prefs.getStringList(_historyAccountsKey) ?? <String>[];
    accounts.remove(loginName);
    accounts.insert(0, loginName);
    if (accounts.length > _historyAccountLimit) {
      final List<String> removedAccounts = accounts.sublist(
        _historyAccountLimit,
      );
      for (final String account in removedAccounts) {
        await _credentialStore.deletePassword(account);
      }
      accounts.removeRange(_historyAccountLimit, accounts.length);
    }
    await prefs.setStringList(_historyAccountsKey, accounts);
    await prefs.setString(_lastLoginAccountKey, loginName);
    await _persistLoginPreferences();
    if (_rememberPassword) {
      await _credentialStore.savePassword(loginName, password);
      return;
    }
    await _credentialStore.deletePassword(loginName);
  }

  Future<void> _removeHistoryAccount(String account) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> accounts =
        prefs.getStringList(_historyAccountsKey) ?? <String>[];
    accounts.remove(account);
    if (accounts.isEmpty) {
      await prefs.remove(_historyAccountsKey);
    } else {
      await prefs.setStringList(_historyAccountsKey, accounts);
    }
    final String? lastLoginAccount = prefs.getString(_lastLoginAccountKey);
    if (lastLoginAccount == account) {
      if (accounts.isEmpty) {
        await prefs.remove(_lastLoginAccountKey);
      } else {
        await prefs.setString(_lastLoginAccountKey, accounts.first);
      }
    }
    await _credentialStore.deletePassword(account);
  }

  Future<void> _clearRememberedPasswords() async {
    for (final Map<String, String> item in _historyAccounts) {
      final String account = item['account'] ?? '';
      await _credentialStore.deletePassword(account);
    }
  }

  String _formatCountdown(Duration remaining) {
    final int totalHours = remaining.inHours;
    final int minutes = remaining.inMinutes.remainder(60);
    final int seconds = remaining.inSeconds.remainder(60);
    final String hh = totalHours.toString().padLeft(2, '0');
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  void _syncGuestTrialState() {
    _guestCountdownTimer?.cancel();
    final GuestTrialSnapshot trial = widget.guestTrial;
    if (!mounted) return;

    if (trial.state == GuestTrialState.expired) {
      setState(() {
        _userState = _UserState.expired;
        _guestButtonText = null;
        _guestStatusMessage = null;
      });
      return;
    }

    if (trial.state == GuestTrialState.unknown) {
      setState(() {
        _userState = _hasSuccessfulLoginHistory
            ? _UserState.loggedIn
            : _UserState.newUser;
        _guestButtonText = null;
        _guestStatusMessage = trial.errorMessage ?? '正在校验试用状态，请联网后重试。';
      });
      return;
    }

    if (trial.state == GuestTrialState.active && trial.expiresAt != null) {
      void updateCountdown() {
        final Duration remaining = trial.expiresAt!.difference(DateTime.now());
        if (!mounted) {
          _guestCountdownTimer?.cancel();
          return;
        }
        if (remaining <= Duration.zero) {
          _guestCountdownTimer?.cancel();
          setState(() {
            _userState = _UserState.expired;
            _guestButtonText = null;
            _guestStatusMessage = null;
          });
          return;
        }
        setState(() {
          _userState = _UserState.newUser;
          _guestButtonText = '体验剩余 ${_formatCountdown(remaining)}';
          _guestStatusMessage = null;
        });
      }

      updateCountdown();
      _guestCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        updateCountdown();
      });
      return;
    }

    if (trial.state == GuestTrialState.active &&
        trial.remainingTime != null &&
        trial.remainingTime!.isNotEmpty) {
      setState(() {
        _userState = _UserState.newUser;
        _guestButtonText = '体验剩余 ${trial.remainingTime!}';
        _guestStatusMessage = null;
      });
      return;
    }

    setState(() {
      _userState = _hasSuccessfulLoginHistory
          ? _UserState.loggedIn
          : _UserState.newUser;
      _guestButtonText = null;
      _guestStatusMessage = null;
    });
  }

  Widget _buildTitleImage({
    required String filePath,
    required String assetPath,
    required double height,
    required double width,
  }) {
    if (filePath.isNotEmpty) {
      final File file = File(filePath);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        );
      }
    }
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }

  Future<void> _openExternalUrl(String url) async {
    try {
      await openUrl(url);
    } catch (_) {
      if (!mounted) return;
      _showError('打开链接失败，请稍后重试。');
    }
  }

  void _handleLogin() {
    _removeDropdown();
    if (!_hideDisclaimer && _userState != _UserState.loggedIn) {
      setState(() {
        _pendingAction = 'login';
        _showDisclaimer = true;
      });
      return;
    }
    _executeLogin();
  }

  void _handleGuest() {
    _removeDropdown();
    if (!_hideDisclaimer) {
      setState(() {
        _pendingAction = 'guest';
        _showDisclaimer = true;
      });
      return;
    }
    _executeGuest();
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
      _errorVersion += 1;
    });
  }

  void _clearError() {
    if (_errorMessage == null) return;
    setState(() => _errorMessage = null);
  }

  void _setUserState(_UserState state) {
    setState(() {
      _userState = state;
      if (state != _UserState.newUser) {
        _guestButtonText = null;
      }
    });
  }

  void _executeLogin() async {
    final String loginName = _accountController.text.trim();
    final String password = _passwordController.text;
    if (loginName.isEmpty || password.isEmpty) {
      _showError('请输入完整的账号和密码。');
      return;
    }
    if (!_emailPattern.hasMatch(loginName)) {
      _showError('请输入有效的邮箱地址。');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      AuthSessionSnapshot snapshot = AuthSessionSnapshot.anonymous;
      if (widget.onLogin != null) {
        snapshot = await widget.onLogin!(loginName, password);
      }
      if (!mounted) return;
      if (!snapshot.canEnterShell) {
        setState(() => _isLoading = false);
        _showError(snapshot.errorMessage ?? '登录失败，请稍后重试。');
        return;
      }
      await _persistSuccessfulLogin();
      await _persistLoginHistory(loginName, password);
      setState(() {
        _isLoading = false;
        _hasSuccessfulLoginHistory = true;
        _userState = _UserState.loggedIn;
      });
    } on AuthBridgeException catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('登录失败，请稍后重试。');
    }
  }

  void _executeGuest() async {
    _clearError();
    setState(() => _guestButtonText = _loadingGuestText);

    try {
      AuthSessionSnapshot snapshot = AuthSessionSnapshot.anonymous;
      if (widget.onGuest != null) {
        snapshot = await widget.onGuest!();
      }
      if (!mounted) return;
      if (!snapshot.canEnterShell) {
        _syncGuestTrialState();
        _showError(snapshot.errorMessage ?? '免费体验暂时不可用，请稍后重试。');
        return;
      }
      setState(() {
        _userState = _UserState.newUser;
        _guestButtonText = snapshot.guestTrial.remainingTime != null
            ? '体验剩余 ${snapshot.guestTrial.remainingTime!}'
            : _guestTrialText;
        _guestStatusMessage = null;
      });
    } on AuthBridgeException catch (error) {
      if (!mounted) return;
      _syncGuestTrialState();
      _showError(error.message);
    } catch (_) {
      if (!mounted) return;
      _syncGuestTrialState();
      _showError('免费体验暂时不可用，请稍后重试。');
    }
  }

  bool get _showGuestButton {
    if (_userState == _UserState.expired) {
      return false;
    }
    final GuestTrialState state = widget.guestTrial.state;
    return state == GuestTrialState.neverStarted ||
        state == GuestTrialState.active;
  }

  bool get _subscribeShouldBlink =>
      _userState == _UserState.expired && !_hasSuccessfulLoginHistory;

  void debugSetUserState(String value) {
    switch (value) {
      case 'expired':
        _setUserState(_UserState.expired);
        return;
      case 'logged_in':
        _setUserState(_UserState.loggedIn);
        return;
      default:
        _setUserState(_UserState.newUser);
    }
  }

  Future<void> debugAgreeDisclaimer(bool noPrompt) {
    return _agreeDisclaimer(noPrompt);
  }

  void debugSetHideDisclaimer(bool value) {
    setState(() => _hideDisclaimer = value);
  }

  void _openManualDisclaimer() {
    _removeDropdown();
    setState(() {
      _pendingAction = 'manual';
      _showDisclaimer = true;
    });
    widget.onDisclaimer?.call();
  }

  void _closeDisclaimer() {
    setState(() {
      _showDisclaimer = false;
      _pendingAction = null;
    });
  }

  Future<void> _agreeDisclaimer(bool noPrompt) async {
    final String? action = _pendingAction;
    final bool persistHide = action == 'login' && noPrompt;

    setState(() {
      if (action == 'login') {
        _hideDisclaimer = persistHide;
      }
      _showDisclaimer = false;
      _pendingAction = null;
    });

    if (action == 'login') {
      await _persistHideDisclaimer(persistHide);
      _executeLogin();
      return;
    }
    if (action == 'guest') {
      _executeGuest();
    }
  }

  void _toggleHistory() {
    if (_dropdownOverlay != null) {
      _removeDropdown();
    } else {
      _showDropdown();
    }
  }

  void _showDropdown() {
    _removeDropdown();
    final OverlayState overlay = Overlay.of(context);
    final RenderBox? renderBox =
        _accountInputKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Size size = renderBox.size;
    final Offset offset = renderBox.localToGlobal(Offset.zero);

    _dropdownOverlay = OverlayEntry(
      builder: (context) => GestureDetector(
        onTap: _removeDropdown,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.transparent)),
            Positioned(
              left: offset.dx,
              top: offset.dy + size.height + 4,
              child: HistoryDropdown(
                width: size.width,
                items: _historyAccounts,
                onSelect: _selectHistory,
                onDelete: _deleteHistory,
              ),
            ),
          ],
        ),
      ),
    );

    overlay.insert(_dropdownOverlay!);
  }

  void _removeDropdown() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  void _selectHistory(String account, String password) async {
    _removeDropdown();
    final String resolvedPassword = password.isNotEmpty
        ? password
        : await _credentialStore.readPassword(account) ?? '';
    if (!mounted) return;
    setState(() {
      _accountController.text = account;
      _passwordController.text = resolvedPassword;
      _rememberPassword = resolvedPassword.isNotEmpty;
    });
  }

  void _deleteHistory(int index) async {
    final String account = _historyAccounts[index]['account'] ?? '';
    setState(() => _historyAccounts.removeAt(index));
    if (_historyAccounts.isEmpty) {
      _removeDropdown();
    }
    await _removeHistoryAccount(account);
    if (!mounted) {
      return;
    }
    if (_accountController.text == account) {
      setState(() {
        _passwordController.clear();
        _rememberPassword = false;
      });
    }
  }

  Future<void> _handleRememberChanged(bool value) async {
    setState(() {
      _rememberPassword = value;
      if (!value) {
        _autoLogin = false;
        for (final Map<String, String> item in _historyAccounts) {
          item['password'] = '';
        }
      }
    });
    await _persistLoginPreferences();
    if (!value) {
      await _clearRememberedPasswords();
    }
  }

  Future<void> _handleAutoLoginChanged(bool value) async {
    setState(() {
      _autoLogin = value;
      if (value) {
        _rememberPassword = true;
      }
    });
    await _persistLoginPreferences();
  }

  @override
  void dispose() {
    _guestCountdownTimer?.cancel();
    _removeDropdown();
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _removeDropdown,
      child: GlassContainer(
        width: widget.width,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 26),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 420,
                  minHeight: 650,
                ),
                child: Column(
                  children: [
                    _buildTitleImage(
                      filePath: _titleImagePath,
                      assetPath: 'assets/brand/denlulogo.png',
                      width: 220,
                      height: 90,
                    ),
                    const SizedBox(height: 6),
                    _buildTitleImage(
                      filePath: _subtitleImagePath,
                      assetPath: _subtitleAssetPath,
                      width: 160,
                      height: 50,
                    ),
                    const SizedBox(height: 2),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: _errorMessage != null
                            ? _ErrorBanner(
                                key: ValueKey(_errorVersion),
                                message: _errorMessage!,
                              )
                            : _guestStatusMessage != null
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _guestStatusMessage!,
                                  style: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TacticalInput(
                      key: _accountInputKey,
                      label: '账号',
                      placeholder: '请输入邮箱',
                      controller: _accountController,
                      onSuffixPressed: _toggleHistory,
                      suffixIcon: const Text(
                        '▼',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TacticalInput(
                      label: '密码',
                      placeholder: '请输入密码',
                      isPassword: true,
                      controller: _passwordController,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _OptionsRow(
                        rememberPassword: _rememberPassword,
                        autoLogin: _autoLogin,
                        onRememberChanged: _handleRememberChanged,
                        onAutoLoginChanged: _handleAutoLoginChanged,
                        onForgotPassword: () =>
                            _openExternalUrl(_accountSecurityUrl),
                      ),
                    ),
                    const SizedBox(height: 22),
                    GiantButton(
                      text: _isLoading ? _loadingLoginText : _loginButtonText,
                      onPressed: _handleLogin,
                      isLoading: _isLoading,
                    ),
                    const SizedBox(height: 16),
                    if (_showGuestButton)
                      GiantButton(
                        text: _guestButtonText ?? '免费体验',
                        onPressed: _handleGuest,
                        style: GiantButtonStyle.guest,
                        isDisabled: _guestButtonText == _loadingGuestText,
                      ),
                    const SizedBox(height: 22),
                    _Footer(
                      onDisclaimer: _openManualDisclaimer,
                      onRegister: () => _openExternalUrl(_registerUrl),
                      onPurchase: () => _openExternalUrl(_purchaseUrl),
                      subscribeBlinking: _subscribeShouldBlink,
                    ),
                  ],
                ),
              ),
            ),
            if (_showDisclaimer)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closeDisclaimer,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.85),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Center(
                        child: _DisclaimerModal(
                          onClose: _closeDisclaimer,
                          onAgree: _agreeDisclaimer,
                          showNoPromptOption: _pendingAction == 'login',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatefulWidget {
  final String message;

  const _ErrorBanner({super.key, required this.message});

  @override
  State<_ErrorBanner> createState() => _ErrorBannerState();
}

class _ErrorBannerState extends State<_ErrorBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _offsetAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -5), weight: 25),
      TweenSequenceItem(tween: Tween(begin: -5, end: 5), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 5, end: 0), weight: 25),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offsetAnimation,
      builder: (context, child) => Transform.translate(
        offset: Offset(_offsetAnimation.value, 0),
        child: child,
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF3A0B14).withValues(alpha: 0.92),
          border: const Border(
            left: BorderSide(color: Color(0xFFE11D48), width: 3),
          ),
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(4),
          ),
        ),
        child: Row(
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 16, height: 1.0)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFFE4E8),
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionsRow extends StatelessWidget {
  final bool rememberPassword;
  final bool autoLogin;
  final ValueChanged<bool> onRememberChanged;
  final ValueChanged<bool> onAutoLoginChanged;
  final VoidCallback onForgotPassword;

  const _OptionsRow({
    required this.rememberPassword,
    required this.autoLogin,
    required this.onRememberChanged,
    required this.onAutoLoginChanged,
    required this.onForgotPassword,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            _TacticalCheckbox(
              label: '记住密码',
              value: rememberPassword,
              onChanged: onRememberChanged,
            ),
            const SizedBox(width: 16),
            _TacticalCheckbox(
              label: '自动登录',
              value: autoLogin,
              onChanged: onAutoLoginChanged,
            ),
          ],
        ),
        _FooterLink(label: '忘记密码？', onTap: onForgotPassword),
      ],
    );
  }
}

class _Footer extends StatefulWidget {
  final VoidCallback onDisclaimer;
  final VoidCallback onRegister;
  final VoidCallback onPurchase;
  final bool subscribeBlinking;

  const _Footer({
    required this.onDisclaimer,
    required this.onRegister,
    required this.onPurchase,
    required this.subscribeBlinking,
  });

  @override
  State<_Footer> createState() => _FooterState();
}

class _FooterState extends State<_Footer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    if (widget.subscribeBlinking) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _Footer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.subscribeBlinking == oldWidget.subscribeBlinking) return;
    if (widget.subscribeBlinking) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _FooterLink(label: '去注册', onTap: widget.onRegister),
        const SizedBox(width: 12),
        _sep(),
        const SizedBox(width: 12),
        _BlinkingFooterLink(
          controller: _controller,
          enabled: widget.subscribeBlinking,
          onTap: widget.onPurchase,
        ),
        const SizedBox(width: 12),
        _sep(),
        const SizedBox(width: 12),
        _FooterLink(label: '免责协议', onTap: widget.onDisclaimer),
      ],
    );
  }

  Widget _sep() {
    return Text(
      '|',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.1),
        fontSize: 12,
      ),
    );
  }
}

class _FooterLink extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;

  const _FooterLink({required this.label, this.onTap});

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color color = _isHovered
        ? const Color(0xFFD1D5DB)
        : const Color(0xFF6B7280);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Text(widget.label, style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }
}

class _BlinkingFooterLink extends StatefulWidget {
  final AnimationController controller;
  final bool enabled;
  final VoidCallback onTap;

  const _BlinkingFooterLink({
    required this.controller,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_BlinkingFooterLink> createState() => _BlinkingFooterLinkState();
}

class _BlinkingFooterLinkState extends State<_BlinkingFooterLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, child) {
            final double pulse = widget.enabled
                ? (math.sin(widget.controller.value * math.pi * 2) + 1) / 2
                : 0;
            final Color baseColor = _isHovered
                ? const Color(0xFFD1D5DB)
                : const Color(0xFF6B7280);
            final Color color = widget.enabled
                ? Color.lerp(baseColor, const Color(0xFFE11D48), pulse)!
                : baseColor;
            final double glow = widget.enabled ? 12 * pulse : 0;
            return Text(
              '去开通',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: widget.enabled
                    ? FontWeight.bold
                    : FontWeight.normal,
                shadows: glow == 0
                    ? null
                    : [
                        Shadow(
                          color: const Color(
                            0xFFE11D48,
                          ).withValues(alpha: 0.8 * pulse),
                          blurRadius: glow,
                        ),
                      ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TacticalCheckbox extends StatefulWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TacticalCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_TacticalCheckbox> createState() => _TacticalCheckboxState();
}

class _TacticalCheckboxState extends State<_TacticalCheckbox> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.value),
        child: Row(
          children: [
            _HardwareCheckbox(value: widget.value, isHovered: _isHovered),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: TextStyle(
                color: _isHovered
                    ? const Color(0xFFD1D5DB)
                    : const Color(0xFF9CA3AF),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HardwareCheckbox extends StatelessWidget {
  final bool value;
  final bool isHovered;

  const _HardwareCheckbox({required this.value, required this.isHovered});

  @override
  Widget build(BuildContext context) {
    return HardwareCheckboxIndicator(
      value: value,
      size: 16,
      radius: 3,
      isHovered: isHovered,
      uncheckedFillColor: Colors.transparent,
      checkSize: 12,
    );
  }
}

class _DisclaimerModal extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool> onAgree;
  final bool showNoPromptOption;

  const _DisclaimerModal({
    required this.onClose,
    required this.onAgree,
    this.showNoPromptOption = true,
  });

  @override
  State<_DisclaimerModal> createState() => _DisclaimerModalState();
}

class _DisclaimerModalState extends State<_DisclaimerModal> {
  bool _noPrompt = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: HardwareDialog(
        width: kHardwareDialogStandardWidth,
        maxHeight: 720,
        scrollable: true,
        title: '用户免责协议',
        titleIcon: const Icon(Icons.gavel_rounded),
        onClose: widget.onClose,
        hudTitle: 'User Disclaimer / 使用提示',
        hudText: const Text(
          '继续使用软件，表示你已知悉文件备份、合法处理权限、试运行验证等基本注意事项。',
          style: TextStyle(height: 1.6),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '本软件为音频处理工具，涉及转码、标签修改、封面写入等操作。使用前请自行备份重要文件，请确保你对这些文件拥有合法处理权。\n\n后面这些我就不跟你端着了，咱直接说人话。\n\n重要的东西先备份一下，别嫌麻烦。真出事的时候，谁都帮不了你。\n\n操作的时候稍微稳一点，别一上来就全量跑。先拿几首试试水，这种事你肯定懂。\n\n还有一点，先说好啊，这些歌得是你的。不是你的还乱动，那就挺刺激了。\n\n继续用，就当你都明白这些事了。我也提醒到这了，剩下就看你自己了。',
              style: TextStyle(
                color: Color(0xFFF3F4F6),
                fontSize: 15,
                height: 1.75,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.showNoPromptOption) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => setState(() => _noPrompt = !_noPrompt),
                child: Row(
                  children: [
                    _HardwareCheckbox(value: _noPrompt, isHovered: false),
                    const SizedBox(width: 8),
                    const Text(
                      '下次不再弹出',
                      style: TextStyle(
                        color: Color(0xFFD1D5DB),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        footer: HardwareDialogFooter(
          actions: <Widget>[
            HardwareDialogAction(
              label: '我已阅读并同意',
              variant: HardwareDialogActionVariant.confirm,
              onPressed: () => widget.onAgree(_noPrompt),
              expand: false,
            ),
          ],
        ),
      ),
    );
  }
}
