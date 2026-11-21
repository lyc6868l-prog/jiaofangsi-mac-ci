import 'dart:async';

import 'package:dj_flutter/shared/platform_utils.dart';
import 'package:flutter/material.dart' hide BoxDecoration, BoxShadow;
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart';
import '../dj_app_scope.dart';
import '../../features/auth/presentation/models/auth_models.dart';
import '../../features/auth/presentation/models/auth_session_snapshot.dart';
import '../../features/auth/presentation/controllers/unified_account_service.dart';
import '../../features/auth/presentation/controllers/sso_service.dart';
import 'shell_tokens.dart';
import 'tip_author_dialog.dart';

class UserCenterPanel extends StatefulWidget {
  const UserCenterPanel({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  State<UserCenterPanel> createState() => _UserCenterPanelState();
}

class _UserCenterPanelState extends State<UserCenterPanel> {
  AuthSessionSnapshot _snapshot = AuthSessionSnapshot.anonymous;
  bool _loaded = false;
  bool _refreshing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    _loaded = true;
    _snapshot = DjAppScope.of(context).sessionStore.snapshot;
    unawaited(_refreshAccount());
  }

  Future<void> _refreshAccount() async {
    if (_refreshing || !_snapshot.isUser) {
      return;
    }
    _refreshing = true;
    try {
      final DjAppScope scope = DjAppScope.of(context);
      final AuthSessionSnapshot updated = await scope.authController
          .refreshAccountSnapshot();
      if (!mounted) {
        return;
      }
      scope.sessionStore.update(updated);
      setState(() => _snapshot = updated);
    } catch (_) {
      // Keep the last known snapshot; login expiry is handled by the shell.
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _bindWechat() async {
    final String? token = _snapshot.token;
    if (token == null || token.isEmpty) {
      return;
    }
    final AuthSessionSnapshot? bound = await showDialog<AuthSessionSnapshot>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _WechatBindDialog(legacyToken: token),
    );
    if (!mounted || bound == null) {
      return;
    }
    final DjAppScope scope = DjAppScope.of(context);
    scope.sessionStore.update(bound);
    setState(() => _snapshot = bound);
  }

  @override
  Widget build(BuildContext context) {
    final AuthSessionSnapshot snapshot = _snapshot;

    return Container(
      key: const ValueKey<String>('user_center_panel'),
      width: 320,
      constraints: BoxConstraints(
        maxHeight: (MediaQuery.sizeOf(context).height - 82).clamp(380.0, 760.0),
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [shellPanelTop, shellPanelBottom],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.9),
            offset: const Offset(0, 15),
            blurRadius: 35,
          ),
          BoxShadow(
            color: shellAccentBlue.withValues(alpha: 0.1),
            blurRadius: 20,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.05),
            offset: const Offset(0, 1),
            blurRadius: 1,
            inset: true,
          ),
        ],
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Container(height: 2, color: shellAccentBlue),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _UserHeader(snapshot: snapshot),
                  if (snapshot.isUser && snapshot.authMode != 'unified') ...[
                    const SizedBox(height: 8),
                    _BindWechatButton(onTap: _bindWechat),
                  ],
                  const SizedBox(height: 8),
                  const _UserMenuList(),
                  const SizedBox(height: 8),
                  const _UserActionGroup(),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text(
                      '会员权益',
                      style: TextStyle(
                        fontSize: 12,
                        color: shellTextMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (snapshot.isGuest)
                    _GuestStatusCard(
                      remainingTime:
                          snapshot.guestTrial.remainingTime ??
                          snapshot.remainingTime,
                    )
                  else
                    _PrivilegeSection(snapshot: snapshot),
                  const SizedBox(height: 16),
                  _LogoutButton(snapshot: snapshot, onLogout: widget.onLogout),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BindWechatButton extends StatelessWidget {
  const _BindWechatButton({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: shellAccentBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: shellAccentBlue.withValues(alpha: 0.22)),
        ),
        child: const Row(
          children: [
            Text('微信', style: TextStyle(fontSize: 13)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '绑定微信，扫码和邮箱共用同一账号',
                style: TextStyle(fontSize: 11, color: shellTextMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.qr_code_2, size: 16, color: shellTextMuted),
          ],
        ),
      ),
    );
  }
}

class _WechatBindDialog extends StatefulWidget {
  const _WechatBindDialog({required this.legacyToken});

  final String legacyToken;

  @override
  State<_WechatBindDialog> createState() => _WechatBindDialogState();
}

class _WechatBindDialogState extends State<_WechatBindDialog> {
  final UnifiedAccountService _service = UnifiedAccountService();
  UnifiedChallenge? _challenge;
  Timer? _timer;
  bool _busy = false;
  bool _finished = false;
  String _status = '正在获取绑定二维码…';
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final UnifiedChallenge challenge = await _service.createChallenge();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _status = '请使用微信扫码，确认绑定到当前账号';
      });
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_poll()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _poll() async {
    final UnifiedChallenge? challenge = _challenge;
    if (_busy || _finished || challenge == null) return;
    _busy = true;
    try {
      final String status = await _service.poll(challenge);
      if (!mounted || _finished) return;
      if (status == 'authorized' || status == 'awaiting_bind') {
        _timer?.cancel();
        await _finish(challenge);
      } else if (status == 'expired' ||
          status == 'cancelled' ||
          status == 'consumed') {
        _timer?.cancel();
        setState(() => _error = '二维码已失效，请关闭后重试。');
      } else {
        setState(() => _status = '等待扫码确认…');
      }
    } catch (error) {
      if (mounted) setState(() => _status = '网络波动，正在重试…');
    } finally {
      _busy = false;
    }
  }

  Future<void> _finish(UnifiedChallenge challenge) async {
    try {
      setState(() => _status = '微信已确认，正在绑定当前账号…');
      final UnifiedSession session = await _service.bindWechat(
        challenge: challenge,
        legacyToken: widget.legacyToken,
      );
      final UnifiedProfile profile = await _service.profile(
        session.accessToken,
      );
      final List<EntitlementInfo> entitlements = await _service.entitlements(
        session.accessToken,
      );
      final bool isVip = entitlements.any(
        (EntitlementInfo item) =>
            item.isActive &&
            const <String>{
              'vip',
              'dj_tool',
              'web_vip',
              'web_mvp',
              'web_ceo',
            }.contains(item.entitlementType),
      );
      DateTime? vipExpiresAt;
      for (final EntitlementInfo item in entitlements) {
        if (item.isActive &&
            const <String>{
              'vip',
              'dj_tool',
              'web_vip',
              'web_mvp',
              'web_ceo',
            }.contains(item.entitlementType)) {
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
        vipExpiresAt: vipExpiresAt,
        entitlements: entitlements,
      );
      final DjAppScope scope = DjAppScope.of(context);
      await scope.authController.importUnifiedSession(
        snapshot,
        refreshToken: session.refreshToken,
        refreshExpiresAt: session.refreshExpiresAt,
      );
      _finished = true;
      if (!mounted) return;
      Navigator.of(context).pop(snapshot);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '绑定失败：$error';
        _finished = false;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UnifiedChallenge? challenge = _challenge;
    return AlertDialog(
      backgroundColor: const Color(0xFF0B0B0D),
      title: const Text('绑定微信'),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (challenge != null)
              Container(
                width: 220,
                height: 220,
                padding: const EdgeInsets.all(10),
                color: Colors.white,
                child: Image.network(
                  challenge.qrImageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text(
                      '二维码加载失败',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            const SizedBox(height: 14),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFFF43F5E)),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _UserHeader extends StatelessWidget {
  const _UserHeader({required this.snapshot});

  final AuthSessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final String accountName = snapshot.loginName ?? '未登录账号';
    final String? syncedStageName = snapshot.stageName;
    final bool hasSameStageAndAccount =
        syncedStageName != null && syncedStageName == snapshot.loginName;
    final String displayName = hasSameStageAndAccount
        ? '这个神秘人还没有名字'
        : (syncedStageName ?? snapshot.loginName ?? '游客');

    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _UserAvatar(
            avatarUrl: snapshot.avatarUrl,
            avatarType: snapshot.avatarType,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text(
                      '艺名：',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: shellTextMuted,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: shellTextPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: <Widget>[
                    const Text(
                      '账号：',
                      style: TextStyle(fontSize: 12, color: shellTextMuted),
                    ),
                    Flexible(
                      child: Text(
                        accountName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: shellTextMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserMenuList extends StatelessWidget {
  const _UserMenuList();

  Future<void> _openStudy() async {
    await openUrl('https://zhajing.vip/');
  }

  Future<void> _openTipAuthor(BuildContext context) async {
    final AuthSessionSnapshot? snapshot = DjAppScope.maybeOf(
      context,
    )?.sessionStore.snapshot;
    final String donorName = snapshot?.stageName?.trim().isNotEmpty == true
        ? snapshot!.stageName!
        : (snapshot?.loginName ?? '乐工');
    final String? token = snapshot?.token;
    if (token == null || token.isEmpty) {
      return;
    }
    await showTipAuthorDialog(
      context,
      donorName: donorName,
      token: token,
      authMode: snapshot?.authMode ?? 'legacy',
    );
  }

  Future<void> _openPersonalCenter(BuildContext context) async {
    final DjAppScope? scope = DjAppScope.maybeOf(context);
    final AuthSessionSnapshot? snapshot = scope?.sessionStore.snapshot;
    String? code;
    if (snapshot != null &&
        snapshot.isUser &&
        snapshot.token != null &&
        snapshot.token!.isNotEmpty) {
      final SsoService service = SsoService();
      try {
        code = await service.issueCode(
          accessToken: snapshot.token!,
          refreshToken: snapshot.refreshToken,
          userId: snapshot.userId,
          loginName: snapshot.loginName,
        );
      } catch (_) {
        code = null;
      } finally {
        service.close();
      }
    }
    final String url = code == null
        ? 'https://www.jiaofangsi.top/personal-center'
        : 'https://www.jiaofangsi.top/personal-center#sso_code=${Uri.encodeComponent(code)}';
    await openUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _UserMenuItem(
          icon: Icons.person_outline,
          label: '个人中心',
          onTap: () => _openPersonalCenter(context),
        ),
        _UserMenuItem(
          icon: Icons.school_outlined,
          label: '学习进修',
          onTap: () => _openStudy(),
        ),
        _UserMenuItem(
          icon: Icons.auto_awesome,
          label: '打赏作者',
          onTap: () => _openTipAuthor(context),
        ),
      ],
    );
  }
}

class _UserMenuItem extends StatefulWidget {
  const _UserMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  State<_UserMenuItem> createState() => _UserMenuItemState();
}

class _UserMenuItemState extends State<_UserMenuItem> {
  bool _isHovered = false;

  Future<void> _handleTap() async {
    try {
      await widget.onTap();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: _isHovered ? Colors.white : shellTextSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  color: _isHovered ? Colors.white : shellTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserActionGroup extends StatelessWidget {
  const _UserActionGroup();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}

class _UserActionButton extends StatefulWidget {
  const _UserActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String icon;
  final String label;
  final Color color;
  final Future<void> Function() onTap;

  @override
  State<_UserActionButton> createState() => _UserActionButtonState();
}

class _UserActionButtonState extends State<_UserActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
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
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Transform.translate(
            offset: Offset(0, _isPressed ? 2 : 0),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0x99141419),
                    shellPanelRedDark.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.color.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.02),
                    offset: const Offset(0, 1),
                    inset: true,
                  ),
                  if (_isPressed)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      offset: const Offset(0, 2),
                      blurRadius: 5,
                      inset: true,
                    )
                  else
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      offset: const Offset(0, 2),
                      blurRadius: 5,
                    ),
                  if (_isHovered)
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.15),
                      blurRadius: 10,
                    ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.icon, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
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
}

class _PrivilegeSection extends StatelessWidget {
  const _PrivilegeSection({required this.snapshot});

  final AuthSessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PrivilegeCard(
          token: snapshot.token,
          title: 'VIP会员',
          entitlementType: 'web_vip',
          icon: Icons.workspace_premium,
          iconColor: shellAccentGold,
          statusText: snapshot.entitlementStatusText('web_vip'),
          actionText: snapshot.hasActiveEntitlement('web_vip') ? '续费' : '开通',
          actionColor: shellAccentGold,
        ),
        const SizedBox(height: 10),
        _MvpPartnerCard(snapshot: snapshot),
      ],
    );
  }
}

class _MvpPartnerCard extends StatelessWidget {
  const _MvpPartnerCard({required this.snapshot});

  final AuthSessionSnapshot snapshot;

  Future<void> _openMvpPage() async {
    await openUrl('https://www.jiaofangsi.top/#member');
  }

  @override
  Widget build(BuildContext context) {
    final bool joined = snapshot.hasActiveEntitlement('web_mvp');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: shellPanelSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            offset: const Offset(0, 2),
            blurRadius: 8,
            inset: true,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.handshake_outlined,
            size: 15,
            color: shellAccentPurple,
          ),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              'MVP 合伙人',
              style: TextStyle(
                color: shellTextSoft,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            joined ? '已加入' : '未加入',
            style: TextStyle(
              color: joined ? shellAccentGreen : shellTextMuted,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _openMvpPage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: shellAccentPurple.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: shellAccentPurple.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                joined ? '查看' : '开通',
                style: const TextStyle(
                  color: shellAccentPurple,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({this.avatarUrl, this.avatarType});

  final String? avatarUrl;
  final String? avatarType;

  @override
  Widget build(BuildContext context) {
    final String url = avatarUrl?.trim() ?? '';
    return Container(
      width: 68,
      height: 68,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: shellPanelSurface,
        border: Border.all(color: shellAccentBlue.withValues(alpha: 0.7)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    final String type = (avatarType ?? '').toLowerCase();
    final String emoji = switch (type) {
      'female' => '👧',
      'animal' => '🦊',
      _ => '👦',
    };
    return ColoredBox(
      color: shellPanelSurface,
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 27))),
    );
  }
}

class _PrivilegeCard extends StatelessWidget {
  const _PrivilegeCard({
    required this.token,
    required this.entitlementType,
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.statusText,
    required this.actionText,
    required this.actionColor,
  });

  final String? token;
  final String entitlementType;
  final IconData icon;
  final String title;
  final Color iconColor;
  final String statusText;
  final String actionText;
  final Color actionColor;

  Future<void> _openExternalUrl(String url) async {
    await openUrl(url);
  }

  Future<void> _refreshEntitlements(BuildContext context) async {
    final DjAppScope scope = DjAppScope.of(context);
    final AuthSessionSnapshot refreshed = await scope.authController
        .refreshEntitlement();
    scope.sessionStore.update(refreshed);
  }

  Future<void> _handleAction(BuildContext context) async {
    if (token == null || token!.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('当前未获取到登录凭证')));
      return;
    }

    final DjAppScope scope = DjAppScope.of(context);
    final PurchaseOrderResult order = entitlementType == 'web_vip'
        ? await scope.authBridge.createVipOrder(token: token!)
        : await scope.authBridge.createDjToolOrder(token: token!);
    final String? paymentUrl = order.paymentUrl;
    if (!context.mounted) {
      return;
    }
    if (!order.success || paymentUrl == null || paymentUrl.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(order.errorMessage ?? '创建订单失败')));
      return;
    }

    await _openExternalUrl(paymentUrl);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已打开支付页面，返回软件后将自动刷新权益')));
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!context.mounted) {
      return;
    }
    await _refreshEntitlements(context);
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor = statusText == '未激活'
        ? shellTextMuted
        : shellAccentGreen;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: shellPanelSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            offset: const Offset(0, 2),
            blurRadius: 8,
            inset: true,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              style: const TextStyle(
                color: shellTextSoft,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          _PrivilegeRenewButton(
            text: actionText,
            color: actionColor,
            onTap: () => _handleAction(context),
          ),
        ],
      ),
    );
  }
}

class _PrivilegeRenewButton extends StatefulWidget {
  const _PrivilegeRenewButton({
    required this.text,
    required this.color,
    required this.onTap,
  });

  final String text;
  final Color color;
  final Future<void> Function() onTap;

  @override
  State<_PrivilegeRenewButton> createState() => _PrivilegeRenewButtonState();
}

class _PrivilegeRenewButtonState extends State<_PrivilegeRenewButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
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
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Transform.translate(
            offset: Offset(0, _isPressed ? 2 : 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    widget.color.withValues(alpha: 0.1),
                    widget.color.withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: widget.color.withValues(alpha: 0.3)),
                boxShadow: [
                  if (_isPressed)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      offset: const Offset(0, 2),
                      blurRadius: 4,
                      inset: true,
                    )
                  else
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      offset: const Offset(0, 2),
                      blurRadius: 4,
                    ),
                  if (_isHovered)
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                ],
              ),
              child: Text(
                widget.text,
                style: TextStyle(
                  color: _isHovered ? Colors.white : widget.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuestStatusCard extends StatelessWidget {
  const _GuestStatusCard({required this.remainingTime});

  final String? remainingTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: shellPanelSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            offset: const Offset(0, 2),
            blurRadius: 8,
            inset: true,
          ),
        ],
      ),
      child: Row(
        children: [
          const Text('🌐', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '游客试用',
              style: TextStyle(
                color: shellTextSoft,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            remainingTime ?? '24:00:00',
            style: const TextStyle(
              color: shellAccentGreen,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatefulWidget {
  const _LogoutButton({required this.snapshot, required this.onLogout});

  final AuthSessionSnapshot snapshot;
  final Future<void> Function() onLogout;

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  Future<void> _handleLogout() async {
    await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) {
          setState(() => _isPressed = false);
          _handleLogout();
        },
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: Transform.translate(
          offset: Offset(0, _isPressed ? 2 : 0),
          child: Container(
            key: const ValueKey<String>('user_center_logout_button'),
            height: 42,

            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  shellAccentPinkDeep.withValues(alpha: 0.8),
                  const Color(0xE6140508),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black.withValues(alpha: 0.9)),
              boxShadow: [
                if (_isPressed)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.9),
                    offset: const Offset(0, 4),
                    blurRadius: 10,
                    inset: true,
                  )
                else
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    offset: const Offset(0, 4),
                    blurRadius: 8,
                  ),
                if (_isHovered)
                  BoxShadow(
                    color: shellAccentPinkDeep.withValues(alpha: 0.2),
                    blurRadius: 15,
                  ),
              ],
            ),
            child: Center(
              child: Text(
                '退出登录',
                style: TextStyle(
                  color: _isHovered ? shellAccentRedSoft : shellAccentRed,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
