import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/unified_account_service.dart';
import '../models/auth_session_snapshot.dart';
import '../controllers/password_reset_service.dart';
import 'login_credential_store.dart';

/// New login surface for the DJ tool.
///
/// Layout: dark brand panel (old 教坊司 / DJ便捷工具 logos) + light account panel.
/// The QR tab talks to the existing WeChat auth service; the password tab keeps
/// using the existing Python auth bridge through the callbacks supplied by
/// LoginPage.
class NewLoginScreen extends StatefulWidget {
  const NewLoginScreen({
    super.key,
    this.onLogin,
    this.onUnifiedLogin,
    this.onDisclaimer,
    this.credentialStore,
  });

  final Future<AuthSessionSnapshot> Function(String loginName, String password)?
  onLogin;
  final Future<void> Function(UnifiedSession session)? onUnifiedLogin;
  final VoidCallback? onDisclaimer;
  final LoginCredentialStore? credentialStore;

  @override
  State<NewLoginScreen> createState() => _NewLoginScreenState();
}

enum _LoginMode { qr, password }

class _NewLoginScreenState extends State<NewLoginScreen> {
  static const Color _ink = Color(0xFF0B0D0C);
  static const Color _paper = Color(0xFFF3EEE3);
  static const Color _paperDeep = Color(0xFFE9E0CF);
  static const Color _red = Color(0xFF8E342B);
  static const Color _redBright = Color(0xFFB54A3D);
  static const Color _green = Color(0xFF223C34);
  static const Color _text = Color(0xFF252C29);
  static const Color _muted = Color(0xFF786B5C);

  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final UnifiedAccountService _unified = UnifiedAccountService();

  _LoginMode _mode = _LoginMode.qr;
  bool _passwordLoading = false;
  bool _rememberPassword = true;
  bool _autoLogin = false;
  late final LoginCredentialStore _credentialStore =
      widget.credentialStore ?? const SharedPreferencesLoginCredentialStore();
  bool _qrLoading = false;
  bool _qrPolling = false;
  bool _qrAuthorized = false;
  String? _error;
  String _qrStatus = '正在连接微信…';
  UnifiedChallenge? _challenge;
  Timer? _qrTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadLoginPreferences());
      unawaited(_startQrLogin());
    });
  }

  @override
  void dispose() {
    _qrTimer?.cancel();
    _accountController.dispose();
    _passwordController.dispose();
    _unified.close();
    super.dispose();
  }

  void _setMode(_LoginMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
    });
    if (mode == _LoginMode.qr && _challenge == null && !_qrLoading) {
      unawaited(_startQrLogin());
    }
  }

  Future<void> _loadLoginPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool remember = prefs.getBool('rememberPassword') ?? true;
    final bool autoLogin = prefs.getBool('autoLogin') ?? false;
    final String? lastAccount = prefs.getString('lastLoginAccount');
    String? password;
    if (remember && lastAccount != null && lastAccount.isNotEmpty) {
      password = await _credentialStore.readPassword(lastAccount);
    }
    if (!mounted) return;
    setState(() {
      _rememberPassword = remember;
      _autoLogin = autoLogin;
      if (lastAccount != null && lastAccount.isNotEmpty) {
        _accountController.text = lastAccount;
      }
      if (password != null) {
        _passwordController.text = password;
      }
    });
  }

  Future<void> _saveLoginPreferences(String account, String password) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rememberPassword', _rememberPassword);
    await prefs.setBool('autoLogin', _autoLogin);
    await prefs.setString('lastLoginAccount', account);
    if (_rememberPassword) {
      await _credentialStore.savePassword(account, password);
    } else {
      await _credentialStore.deletePassword(account);
    }
  }

  Future<void> _startQrLogin() async {
    if (_qrLoading) return;
    _qrTimer?.cancel();
    setState(() {
      _qrLoading = true;
      _qrAuthorized = false;
      _challenge = null;
      _error = null;
      _qrStatus = '正在连接微信…';
    });
    try {
      final UnifiedChallenge challenge = await _unified.createChallenge();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _qrLoading = false;
        _qrStatus = '请使用微信扫一扫，在手机上确认登录';
      });
      _qrTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_pollQrLogin()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _qrLoading = false;
        _error = error.toString();
        _qrStatus = '二维码获取失败，请点击刷新';
      });
    }
  }

  Future<void> _pollQrLogin() async {
    final UnifiedChallenge? challenge = _challenge;
    if (challenge == null || _qrPolling || _qrAuthorized) return;
    _qrPolling = true;
    try {
      final String status = await _unified.poll(challenge);
      if (!mounted) return;
      if (status == 'authorized') {
        _qrTimer?.cancel();
        setState(() {
          _qrAuthorized = true;
          _qrStatus = '微信已确认，正在登录…';
        });
        final UnifiedSession session = await _unified.exchange(challenge);
        if (!mounted) return;
        if (widget.onUnifiedLogin == null) {
          throw UnifiedApiException('当前版本未配置扫码登录回调。');
        }
        await widget.onUnifiedLogin!(session);
      } else if (status == 'awaiting_bind') {
        _qrTimer?.cancel();
        setState(() {
          _error = '这个微信还没有绑定账号。请先切换到账号密码登录，登录后在用户中心点击「绑定微信」，绑定完成后再扫码。';
          _qrStatus = '请先用账号密码登录并绑定微信';
        });
      } else if (status == 'expired') {
        _qrTimer?.cancel();
        setState(() {
          _qrStatus = '二维码已过期，正在刷新…';
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) await _startQrLogin();
      } else if (status == 'cancelled' || status == 'consumed') {
        _qrTimer?.cancel();
        setState(() {
          _qrStatus = '二维码已失效，请刷新';
        });
      } else {
        setState(() {
          _qrStatus = '等待扫码确认…';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _qrStatus = '网络波动，正在重试…';
      });
    } finally {
      _qrPolling = false;
    }
  }

  Future<void> _submitPassword() async {
    if (_passwordLoading) return;
    final String account = _accountController.text.trim();
    final String password = _passwordController.text;
    if (account.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写账号和密码。');
      return;
    }
    if (widget.onLogin == null) {
      setState(() => _error = '登录服务未配置。');
      return;
    }
    setState(() {
      _passwordLoading = true;
      _error = null;
    });
    try {
      final AuthSessionSnapshot snapshot = await widget.onLogin!(
        account,
        password,
      );
      if (!mounted) return;
      if (!snapshot.canEnterShell) {
        setState(() {
          _error = snapshot.errorMessage ?? '登录失败，请稍后重试。';
        });
      } else {
        await _saveLoginPreferences(account, password);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('AuthBridgeException: ', '');
      });
    } finally {
      if (mounted) setState(() => _passwordLoading = false);
    }
  }

  Future<void> _openExternal(String url) async {
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else {
      await Process.start('xdg-open', [url]);
    }
  }

  void _showDisclaimer() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: _paper,
        title: const Text(
          '免责声明',
          style: TextStyle(color: _ink),
        ),
        content: const Text(
          '本软件仅用于个人学习、演出准备与合法音乐文件管理。请确保你拥有所处理音频文件的使用权，并遵守当地法律法规及平台规则。',
          style: TextStyle(color: _ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _ink,
      child: Center(
        child: SizedBox(
          width: 960,
          height: 680,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildBrandPanel()),
                Expanded(flex: 6, child: _buildAccountPanel()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandPanel() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101511), Color(0xFF080A09)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -90,
            top: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _red.withValues(alpha: 0.11),
                boxShadow: [
                  BoxShadow(
                    color: _red.withValues(alpha: 0.25),
                    blurRadius: 90,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: -140,
            bottom: -160,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _green.withValues(alpha: 0.35),
                boxShadow: [
                  BoxShadow(
                    color: _green.withValues(alpha: 0.4),
                    blurRadius: 100,
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(46, 54, 42, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 9, height: 9, color: _redBright),
                      const SizedBox(width: 10),
                      Text(
                        'JIAOFANGSI  /  DJ TOOLKIT',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.48),
                          fontSize: 11,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Image.asset(
                    'assets/brand/denlulogo.png',
                    width: 295,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 32),
                  Image.asset(
                    'assets/brand/a3ee22ebdae68c52f43688042d492994.png',
                    width: 335,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 30),
                  Container(width: 70, height: 1, color: _redBright),
                  const SizedBox(height: 18),
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '用科技简化流程，把时间留给音乐。',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: Color(0xFFD8C9B5),
                        fontSize: 14,
                        height: 1.7,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '教坊司 × 听雷   ·   2026',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountPanel() {
    return DecoratedBox(
      decoration: const BoxDecoration(color: _paper),
      child: Stack(
        children: [
          Positioned(
            right: -80,
            top: -100,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _red.withValues(alpha: 0.045),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(46, 62, 46, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '教坊司  /  账号中心',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '登录',
                  style: TextStyle(
                    color: _text,
                    fontSize: 42,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 22),
                _buildModeTabs(),
                const SizedBox(height: 22),
                Expanded(
                  child: SingleChildScrollView(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _mode == _LoginMode.qr
                          ? _buildQrPanel()
                          : _buildPasswordPanel(),
                    ),
                  ),
                ),
                _buildFooterLinks(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabs() {
    return Row(
      children: [
        _modeButton('微信扫码', _LoginMode.qr),
        const SizedBox(width: 10),
        _modeButton('账号密码', _LoginMode.password),
      ],
    );
  }

  Widget _modeButton(String label, _LoginMode mode) {
    final bool active = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setMode(mode),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _red : Colors.transparent,
            border: Border.all(color: active ? _red : const Color(0xFFC9BBA8)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? _paper : _text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQrPanel() {
    final UnifiedChallenge? challenge = _challenge;
    return Column(
      key: const ValueKey<String>('qr'),
      children: [
        const SizedBox(height: 2),
        Container(
          width: 210,
          height: 210,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFBFAE94)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: _qrLoading
              ? const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _red,
                    ),
                  ),
                )
              : challenge == null
              ? Center(
                  child: Text(
                    '二维码加载失败\n请点击下方刷新',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, height: 1.6),
                  ),
                )
              : Image.network(
                  challenge.qrImageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(
                      '二维码加载失败\n请点击下方刷新',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, height: 1.6),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 18),
        Text(
          _qrStatus,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _error == null ? _text : _red,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        if (_qrAuthorized) ...[
          const SizedBox(height: 8),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _red),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _red, fontSize: 12, height: 1.5),
          ),
        ],
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _qrLoading ? null : () => unawaited(_startQrLogin()),
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFBFAE94)),
            ),
            alignment: Alignment.center,
            child: Text(
              '刷新二维码',
              style: TextStyle(
                color: _qrLoading ? _muted : _text,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordPanel() {
    return Column(
      key: const ValueKey<String>('password'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _inputField(
          controller: _accountController,
          hint: '邮箱 / 账号',
          obscure: false,
        ),
        const SizedBox(height: 12),
        _inputField(controller: _passwordController, hint: '密码', obscure: true),
        const SizedBox(height: 10),
        Row(
          children: [
            _checkOption(
              label: '记住密码',
              value: _rememberPassword,
              onChanged: (bool value) {
                setState(() {
                  _rememberPassword = value;
                  if (!value) _autoLogin = false;
                });
              },
            ),
            const SizedBox(width: 22),
            _checkOption(
              label: '自动登录',
              value: _autoLogin,
              onChanged: (bool value) {
                setState(() {
                  _autoLogin = value;
                  if (value) _rememberPassword = true;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton(
            onPressed: _passwordLoading ? null : _submitPassword,
            style: FilledButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: _paper,
              shape: const RoundedRectangleBorder(),
            ),
            child: Text(
              _passwordLoading ? '正在验证…' : '登 录',
              style: const TextStyle(fontSize: 15, letterSpacing: 2),
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _checkOption({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: value,
              onChanged: (bool? next) => onChanged(next ?? false),
              activeColor: _red,
              checkColor: _paper,
              side: const BorderSide(color: Color(0xFFB7A58C)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: _muted, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      onSubmitted: obscure ? (_) => _submitPassword() : null,
      style: const TextStyle(color: _text, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _muted.withValues(alpha: 0.75)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        filled: true,
        fillColor: _paperDeep.withValues(alpha: 0.65),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xFFC9BBA8)),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xFFC9BBA8)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: _red),
        ),
      ),
    );
  }

  Future<void> _showPasswordReset() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) =>
          _PasswordResetDialog(initialAccount: _accountController.text.trim()),
    );
  }

  Widget _buildFooterLinks() {
    return Column(
      children: [
        const Divider(color: Color(0xFFD5C8B6), height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _footerLink('去注册', () {
              unawaited(_openExternal('https://www.jiaofangsi.top/#register'));
            }),
            _footerLink('忘记密码', _showPasswordReset),
            _footerLink('去开通', () {
              unawaited(_openExternal('https://www.jiaofangsi.top/#member'));
            }),
            _footerLink('免责协议', () {
              widget.onDisclaimer?.call();
              _showDisclaimer();
            }),
          ],
        ),
      ],
    );
  }

  Widget _footerLink(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        label,
        style: TextStyle(
          color: _muted,
          fontSize: 12,
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xFFC9BBA8),
        ),
      ),
    );
  }
}

class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog({required this.initialAccount});

  final String initialAccount;

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  final PasswordResetService _service = PasswordResetService();
  late final TextEditingController _account = TextEditingController(
    text: widget.initialAccount,
  );
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _sending = false;
  bool _resetting = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _service.close();
    _account.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String account = _account.text.trim();
    if (account.isEmpty) {
      setState(() => _error = '请填写邮箱账号');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _message = null;
    });
    try {
      await _service.sendCode(account);
      if (mounted) setState(() => _message = '验证码已发送，请检查邮箱');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reset() async {
    final String account = _account.text.trim();
    final String code = _code.text.trim();
    final String password = _password.text;
    if (account.isEmpty || code.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写邮箱、验证码和新密码');
      return;
    }
    setState(() {
      _resetting = true;
      _error = null;
      _message = null;
    });
    try {
      await _service.resetPassword(
        loginName: account,
        code: code,
        newPassword: password,
      );
      if (!mounted) return;
      setState(() => _message = '密码已重置，请返回登录');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFF5EFDF),
      title: const Text('找回密码'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _account,
              decoration: const InputDecoration(labelText: '邮箱账号'),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _code,
                    decoration: const InputDecoration(labelText: '邮箱验证码'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _sending ? null : _send,
                  child: Text(_sending ? '发送中...' : '发送验证码'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!, style: const TextStyle(color: Color(0xFF157F3C))),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFE11D48))),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _resetting ? null : _reset,
          child: Text(_resetting ? '提交中...' : '重置密码'),
        ),
      ],
    );
  }
}
