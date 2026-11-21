import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_session_snapshot.dart';
import '../models/auth_models.dart';
import 'python_auth_task_bridge.dart';
import 'unified_account_service.dart';
import 'python_guest_task_bridge.dart';

class AuthController {
  AuthController({required this.authBridge, required this.guestBridge});

  final AuthTaskBridge authBridge;
  final GuestTaskBridge guestBridge;
  bool _loggedOutStateActive = false;

  void enterLoggedOutState() {
    _loggedOutStateActive = true;
  }

  DateTime? _fromUnixSeconds(int? seconds) {
    if (seconds == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  String _formatRemainingDuration(double hours) {
    final Duration duration = Duration(minutes: (hours * 60).floor());
    final int totalHours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    final String hh = totalHours.toString().padLeft(2, '0');
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  String? _formatRemainingFromExpiresAt(DateTime? expiresAt) {
    if (expiresAt == null) {
      return null;
    }
    final Duration remaining = expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return null;
    }
    final int totalHours = remaining.inHours;
    final int minutes = remaining.inMinutes.remainder(60);
    final int seconds = remaining.inSeconds.remainder(60);
    final String hh = totalHours.toString().padLeft(2, '0');
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = seconds.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  GuestTrialSnapshot _buildGuestTrial({
    required GuestTrialState state,
    int? issuedAt,
    int? expiresAt,
    double? remainingHours,
    String? machineHash,
    bool needNetworkValidation = false,
    String? reason,
    String? errorMessage,
    int? serverTime,
    String? serverSignature,
  }) {
    final DateTime? issuedAtTime = _fromUnixSeconds(issuedAt);
    final DateTime? expiresAtTime = _fromUnixSeconds(expiresAt);
    GuestTrialState resolvedState = state;
    if (resolvedState == GuestTrialState.active &&
        expiresAtTime != null &&
        !expiresAtTime.isAfter(DateTime.now())) {
      resolvedState = GuestTrialState.expired;
    }
    final String? remainingTime = expiresAtTime != null
        ? _formatRemainingFromExpiresAt(expiresAtTime)
        : (remainingHours != null && remainingHours > 0
              ? _formatRemainingDuration(remainingHours)
              : null);
    return GuestTrialSnapshot(
      state: resolvedState,
      issuedAt: issuedAtTime,
      expiresAt: expiresAtTime,
      machineHash: machineHash,
      remainingTime: remainingTime,
      needNetworkValidation: needNetworkValidation,
      reason: reason,
      errorMessage: errorMessage,
      serverTime: _fromUnixSeconds(serverTime),
      serverSignature: serverSignature,
    );
  }

  GuestTrialSnapshot _guestTrialFromSavedSession(SavedGuestSession? session) {
    if (session == null) {
      return GuestTrialSnapshot.neverStarted;
    }
    GuestTrialState state = session.trialState;
    if (state == GuestTrialState.neverStarted) {
      if (session.needNetworkValidation) {
        state = GuestTrialState.unknown;
      } else if (session.hasValidToken) {
        state = GuestTrialState.active;
      } else if (session.expiresAt != null || session.reason == 'expired') {
        state = GuestTrialState.expired;
      }
    }
    return _buildGuestTrial(
      state: state,
      issuedAt: session.issuedAt,
      expiresAt: session.expiresAt,
      remainingHours: session.remainingHours,
      machineHash: session.machineHash,
      needNetworkValidation: session.needNetworkValidation,
      reason: session.reason,
      errorMessage: session.errorMessage ?? session.reason,
      serverTime: session.serverTime,
      serverSignature: session.serverSignature,
    );
  }

  GuestTrialSnapshot _guestTrialFromStatusResult(GuestStatusResult result) {
    return _buildGuestTrial(
      state: result.trialState,
      issuedAt: result.issuedAt,
      expiresAt: result.expiresAt,
      remainingHours: result.remainingHours,
      machineHash: result.machineHash,
      needNetworkValidation: result.needNetworkValidation,
      reason: result.reason,
      errorMessage: result.errorMessage,
      serverTime: result.serverTime,
      serverSignature: result.serverSignature,
    );
  }

  GuestTrialSnapshot _guestTrialFromRegisterResult(GuestRegisterResult result) {
    return _buildGuestTrial(
      state: result.trialState,
      issuedAt: result.issuedAt,
      expiresAt: result.expiresAt,
      remainingHours: result.remainingHours,
      machineHash: result.machineHash,
      needNetworkValidation: result.needNetworkValidation,
      reason: result.reason,
      errorMessage: result.errorMessage,
      serverTime: result.serverTime,
      serverSignature: result.serverSignature,
    );
  }

  AuthSessionSnapshot _anonymousSnapshotFromGuestTrial(
    GuestTrialSnapshot trial,
  ) {
    return AuthSessionSnapshot(
      guestTrial: trial,
      needNetworkValidation: trial.needNetworkValidation,
      guestTrialExpired: trial.isExpired,
      remainingTime: trial.remainingTime,
      guestExpiresAt: trial.expiresAt,
      errorMessage: trial.errorMessage,
    );
  }

  AuthSessionSnapshot _guestSnapshotFromTrial(GuestTrialSnapshot trial) {
    return AuthSessionSnapshot(
      kind: AuthSessionKind.guest,
      guestToken: trial.machineHash,
      guestTrial: trial,
      remainingTime: trial.remainingTime,
      guestExpiresAt: trial.expiresAt,
      isVip: false,
      needNetworkValidation: trial.needNetworkValidation,
    );
  }

  Future<AuthSessionSnapshot> restoreSession() async {
    if (_loggedOutStateActive) {
      return AuthSessionSnapshot.anonymous;
    }
    final SavedSession? savedSession = await authBridge.restoreSession();
    if (savedSession != null && savedSession.hasValidToken) {
      GuestTrialSnapshot guestTrial = GuestTrialSnapshot.neverStarted;
      try {
        final GuestStatusResult guestStatus = await guestBridge
            .checkGuestStatus();
        guestTrial = _guestTrialFromStatusResult(guestStatus);
      } catch (_) {
        guestTrial = const GuestTrialSnapshot(
          state: GuestTrialState.unknown,
          needNetworkValidation: true,
          errorMessage: '免费体验状态校验失败，请联网后重试。',
        );
      }
      return AuthSessionSnapshot(
        kind: AuthSessionKind.user,
        authMode: savedSession.authMode ?? 'legacy',
        token: savedSession.token,
        userId: savedSession.userId,
        loginName: savedSession.loginName,
        stageName: savedSession.stageName,
        avatarType: savedSession.avatarType,
        avatarUrl: savedSession.avatarUrl,
        isVip: savedSession.isVip,
        tokenExpiresAt: savedSession.expiresAt,
        refreshToken: savedSession.refreshToken,
        refreshExpiresAt: savedSession.refreshExpiresAt,
        vipExpiresAt: savedSession.vipExpiresAt,
        entitlements: savedSession.entitlements,
        guestTrial: guestTrial,
        needNetworkValidation:
            savedSession.needNetworkValidation ||
            guestTrial.needNetworkValidation,
        guestTrialExpired: guestTrial.isExpired,
        remainingTime: guestTrial.remainingTime,
        guestExpiresAt: guestTrial.expiresAt,
      );
    }

    final SavedGuestSession? savedGuestSession = await guestBridge
        .restoreGuestSession();
    final GuestTrialSnapshot guestTrial = _guestTrialFromSavedSession(
      savedGuestSession,
    );
    if (guestTrial.isActive && guestTrial.machineHash != null) {
      return _guestSnapshotFromTrial(guestTrial);
    }
    return _anonymousSnapshotFromGuestTrial(guestTrial);
  }

  Future<AuthSessionSnapshot> login({
    required String loginName,
    required String password,
  }) async {
    _loggedOutStateActive = false;
    final AuthLoginResult result = await authBridge.login(
      loginName: loginName,
      password: password,
    );

    if (!result.success) {
      return AuthSessionSnapshot(
        kind: AuthSessionKind.anonymous,
        errorMessage: result.errorMessage ?? '登录失败',
      );
    }

    final EntitlementResult entitlement = await authBridge.checkEntitlement(
      token: result.token!,
    );
    final ProfileResult profile = await authBridge.getProfile(
      token: result.token!,
    );

    return AuthSessionSnapshot(
      kind: AuthSessionKind.user,
      authMode: 'legacy',
      token: result.token,
      userId: result.userId,
      loginName: result.loginName,
      stageName: profile.stageName,
      avatarType: profile.avatarType,
      avatarUrl: profile.avatarUrl,
      isVip: entitlement.isVip,
      tokenExpiresAt: result.expiresAt,
      vipExpiresAt: entitlement.vipExpiresAt,
      entitlements: entitlement.entitlements,
    );
  }

  Future<void> importUnifiedSession(
    AuthSessionSnapshot snapshot, {
    String? refreshToken,
    DateTime? refreshExpiresAt,
  }) async {
    final String? token = snapshot.token;
    if (token == null || token.isEmpty) {
      throw const AuthBridgeException('AUTH_ERROR', '缺少统一账号登录凭证');
    }
    await authBridge.importUnifiedSession(
      token: token,
      refreshToken: refreshToken,
      refreshExpiresAt: refreshExpiresAt,
      userId: snapshot.userId,
      loginName: snapshot.loginName,
      expiresAt: snapshot.tokenExpiresAt,
      isVip: snapshot.isVip,
      vipExpiresAt: snapshot.vipExpiresAt,
      entitlements: snapshot.entitlements,
      stageName: snapshot.stageName,
      avatarType: snapshot.avatarType,
      avatarUrl: snapshot.avatarUrl,
    );
  }

  Future<AuthSessionSnapshot> registerGuest() async {
    _loggedOutStateActive = false;
    final GuestRegisterResult result = await guestBridge.registerGuest();
    final GuestTrialSnapshot guestTrial = _guestTrialFromRegisterResult(result);
    if (!result.success ||
        !guestTrial.isActive ||
        guestTrial.machineHash == null) {
      return _anonymousSnapshotFromGuestTrial(
        guestTrial.copyWith(
          errorMessage: guestTrial.errorMessage ?? '免费体验暂时不可用，请稍后重试。',
        ),
      );
    }
    return _guestSnapshotFromTrial(guestTrial);
  }

  Future<AuthSessionSnapshot> verifyGuestSession(String guestToken) async {
    _loggedOutStateActive = false;
    final GuestStatusResult result = await guestBridge.checkGuestStatus();
    final GuestTrialSnapshot guestTrial = _guestTrialFromStatusResult(result);
    if (!result.success) {
      return _anonymousSnapshotFromGuestTrial(
        guestTrial.copyWith(
          state: GuestTrialState.unknown,
          needNetworkValidation: true,
          errorMessage: guestTrial.errorMessage ?? '游客状态校验失败',
        ),
      );
    }
    if (!guestTrial.isActive) {
      return _anonymousSnapshotFromGuestTrial(guestTrial);
    }
    return _guestSnapshotFromTrial(
      guestTrial.copyWith(machineHash: guestTrial.machineHash ?? guestToken),
    );
  }

  Future<AuthSessionSnapshot> refreshEntitlement() async {
    final AuthSessionSnapshot current = await restoreSession();
    if (!current.isUser || current.token == null) {
      return current;
    }

    final EntitlementResult entitlement = await authBridge.checkEntitlement(
      token: current.token!,
    );
    return current.copyWith(
      isVip: entitlement.isVip,
      vipExpiresAt: entitlement.vipExpiresAt,
      entitlements: entitlement.entitlements,
    );
  }

  Future<AuthSessionSnapshot> refreshProfile() async {
    final AuthSessionSnapshot current = await restoreSession();
    if (!current.isUser || current.token == null) {
      return current;
    }

    final ProfileResult profile = await authBridge.getProfile(
      token: current.token!,
    );
    return current.copyWith(
      stageName: profile.stageName,
      avatarType: profile.avatarType,
      avatarUrl: profile.avatarUrl,
    );
  }

  static const Set<String> _vipEntitlementTypes = <String>{
    'vip',
    'dj_tool',
    'web_vip',
    'web_mvp',
    'web_ceo',
  };

  bool _hasVipEntitlement(List<EntitlementInfo> entitlements) {
    return entitlements.any(
      (EntitlementInfo item) =>
          item.isActive && _vipEntitlementTypes.contains(item.entitlementType),
    );
  }

  DateTime? _vipExpiry(List<EntitlementInfo> entitlements) {
    for (final EntitlementInfo item in entitlements) {
      if (item.isActive &&
          _vipEntitlementTypes.contains(item.entitlementType)) {
        return item.expireAt;
      }
    }
    return null;
  }

  Future<AuthSessionSnapshot> refreshAccountSnapshot() async {
    final AuthSessionSnapshot current = await restoreSession();
    final String? token = current.token;
    if (!current.isUser || token == null || token.isEmpty) {
      return current;
    }

    if (current.authMode == 'unified') {
      final UnifiedAccountService service = UnifiedAccountService();
      try {
        final UnifiedProfile profile = await service.profile(token);
        final List<EntitlementInfo> entitlements = await service.entitlements(
          token,
        );
        final AuthSessionSnapshot updated = current.copyWith(
          loginName: profile.boundEmail ?? current.loginName,
          stageName: profile.stageName ?? current.stageName,
          avatarType: profile.avatarType ?? current.avatarType,
          avatarUrl: profile.avatarUrl ?? current.avatarUrl,
          isVip: _hasVipEntitlement(entitlements),
          vipExpiresAt: _vipExpiry(entitlements),
          entitlements: entitlements,
          authMode: 'unified',
        );
        await authBridge.syncUnifiedSession(
          token: token,
          isVip: updated.isVip,
          vipExpiresAt: updated.vipExpiresAt,
          entitlements: updated.entitlements,
          stageName: updated.stageName,
          avatarType: updated.avatarType,
          avatarUrl: updated.avatarUrl,
        );
        return updated;
      } on UnifiedApiException catch (error) {
        if (error.statusCode == 401) {
          throw const AuthBridgeException('AUTH_EXPIRED', '登录状态已失效，请重新登录。');
        }
        rethrow;
      } finally {
        service.close();
      }
    }

    final EntitlementResult entitlement = await authBridge.checkEntitlement(
      token: token,
    );
    final ProfileResult profile = await authBridge.getProfile(token: token);
    return current.copyWith(
      authMode: 'legacy',
      stageName: profile.stageName,
      avatarType: profile.avatarType,
      avatarUrl: profile.avatarUrl,
      isVip: entitlement.isVip,
      vipExpiresAt: entitlement.vipExpiresAt,
      entitlements: entitlement.entitlements,
    );
  }

  Future<void> clearLocalSession(AuthSessionSnapshot snapshot) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoLogin', false);
    if (snapshot.isUser) {
      await authBridge.clearLocalSession();
    }
    if (snapshot.isGuest) {
      await guestBridge.clearGuestSession();
    }
  }

  Future<void> logout(AuthSessionSnapshot snapshot) async {
    await authBridge.close();
    await guestBridge.close();
    if (snapshot.isUser && snapshot.token != null) {
      await authBridge.logout(token: snapshot.token!);
    }
  }
}
