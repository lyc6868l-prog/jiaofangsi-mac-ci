import 'auth_models.dart';

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = value.toString().trim();
  if (text.isEmpty) {
    return null;
  }
  return text;
}

enum AuthSessionKind { anonymous, user, guest }

class GuestTrialSnapshot {
  final GuestTrialState state;
  final DateTime? issuedAt;
  final DateTime? expiresAt;
  final String? machineHash;
  final String? remainingTime;
  final bool needNetworkValidation;
  final String? reason;
  final String? errorMessage;
  final DateTime? serverTime;
  final String? serverSignature;

  const GuestTrialSnapshot({
    this.state = GuestTrialState.neverStarted,
    this.issuedAt,
    this.expiresAt,
    this.machineHash,
    this.remainingTime,
    this.needNetworkValidation = false,
    this.reason,
    this.errorMessage,
    this.serverTime,
    this.serverSignature,
  });

  bool get isActive => state == GuestTrialState.active;

  bool get isExpired => state == GuestTrialState.expired;

  bool get isUnknown => state == GuestTrialState.unknown;

  bool get isNeverStarted => state == GuestTrialState.neverStarted;

  GuestTrialSnapshot copyWith({
    GuestTrialState? state,
    DateTime? issuedAt,
    DateTime? expiresAt,
    String? machineHash,
    String? remainingTime,
    bool? needNetworkValidation,
    String? reason,
    String? errorMessage,
    DateTime? serverTime,
    String? serverSignature,
  }) {
    return GuestTrialSnapshot(
      state: state ?? this.state,
      issuedAt: issuedAt ?? this.issuedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      machineHash: machineHash ?? this.machineHash,
      remainingTime: remainingTime ?? this.remainingTime,
      needNetworkValidation:
          needNetworkValidation ?? this.needNetworkValidation,
      reason: reason ?? this.reason,
      errorMessage: errorMessage ?? this.errorMessage,
      serverTime: serverTime ?? this.serverTime,
      serverSignature: serverSignature ?? this.serverSignature,
    );
  }

  static const GuestTrialSnapshot neverStarted = GuestTrialSnapshot();
}

class AuthSessionSnapshot {
  final AuthSessionKind kind;
  final String? authMode;
  final String? token;
  final String? guestToken;
  final String? userId;
  final String? loginName;
  final String? stageName;
  final String? avatarType;
  final String? avatarUrl;
  final bool isVip;
  final DateTime? tokenExpiresAt;
  final String? refreshToken;
  final DateTime? refreshExpiresAt;
  final DateTime? vipExpiresAt;
  final List<EntitlementInfo>? entitlements;
  final GuestTrialSnapshot guestTrial;
  final String? errorMessage;
  final bool needNetworkValidation;
  final bool guestTrialExpired;
  final String? remainingTime;
  final DateTime? guestExpiresAt;

  const AuthSessionSnapshot({
    this.kind = AuthSessionKind.anonymous,
    this.authMode,
    this.token,
    this.guestToken,
    this.userId,
    this.loginName,
    this.stageName,
    this.avatarType,
    this.avatarUrl,
    this.isVip = false,
    this.tokenExpiresAt,
    this.refreshToken,
    this.refreshExpiresAt,
    this.vipExpiresAt,
    this.entitlements,
    this.guestTrial = GuestTrialSnapshot.neverStarted,
    this.errorMessage,
    this.needNetworkValidation = false,
    this.guestTrialExpired = false,
    this.remainingTime,
    this.guestExpiresAt,
  });

  bool get canEnterShell =>
      kind == AuthSessionKind.user || kind == AuthSessionKind.guest;

  bool get isGuest => kind == AuthSessionKind.guest;

  bool get isUser => kind == AuthSessionKind.user;

  bool get isAnonymous => kind == AuthSessionKind.anonymous;

  bool get hasWorkbenchAccess => isVip || isGuest;

  EntitlementInfo? entitlementByType(String entitlementType) {
    final List<EntitlementInfo>? values = entitlements;
    if (values == null) {
      return null;
    }
    for (final EntitlementInfo entitlement in values) {
      if (entitlement.entitlementType == entitlementType) {
        return entitlement;
      }
    }
    return null;
  }

  bool hasActiveEntitlement(String entitlementType) {
    final EntitlementInfo? entitlement = entitlementByType(entitlementType);
    return entitlement != null && entitlement.isActive;
  }

  String entitlementStatusText(String entitlementType) {
    final EntitlementInfo? entitlement = entitlementByType(entitlementType);
    if (entitlement == null ||
        !entitlement.isActive ||
        entitlement.daysLeft == null) {
      return '未激活';
    }
    return '${entitlement.daysLeft}天';
  }

  bool get hasValidToken {
    if (kind == AuthSessionKind.user) {
      return token != null &&
          token!.isNotEmpty &&
          tokenExpiresAt != null &&
          tokenExpiresAt!.isAfter(DateTime.now());
    }
    if (kind == AuthSessionKind.guest) {
      return guestToken != null &&
          guestToken!.isNotEmpty &&
          guestTrial.expiresAt != null &&
          guestTrial.expiresAt!.isAfter(DateTime.now());
    }
    return false;
  }

  AuthSessionSnapshot copyWith({
    AuthSessionKind? kind,
    String? authMode,
    String? token,
    String? guestToken,
    String? userId,
    String? loginName,
    String? stageName,
    String? avatarType,
    String? avatarUrl,
    bool? isVip,
    DateTime? tokenExpiresAt,
    String? refreshToken,
    DateTime? refreshExpiresAt,
    DateTime? vipExpiresAt,
    List<EntitlementInfo>? entitlements,
    GuestTrialSnapshot? guestTrial,
    String? errorMessage,
    bool? needNetworkValidation,
    bool? guestTrialExpired,
    String? remainingTime,
    DateTime? guestExpiresAt,
  }) {
    return AuthSessionSnapshot(
      kind: kind ?? this.kind,
      authMode: authMode ?? this.authMode,
      token: token ?? this.token,
      guestToken: guestToken ?? this.guestToken,
      userId: userId ?? this.userId,
      loginName: loginName ?? this.loginName,
      stageName: stageName ?? this.stageName,
      avatarType: avatarType ?? this.avatarType,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVip: isVip ?? this.isVip,
      tokenExpiresAt: tokenExpiresAt ?? this.tokenExpiresAt,
      refreshToken: refreshToken ?? this.refreshToken,
      refreshExpiresAt: refreshExpiresAt ?? this.refreshExpiresAt,
      vipExpiresAt: vipExpiresAt ?? this.vipExpiresAt,
      entitlements: entitlements ?? this.entitlements,
      guestTrial: guestTrial ?? this.guestTrial,
      errorMessage: errorMessage ?? this.errorMessage,
      needNetworkValidation:
          needNetworkValidation ?? this.needNetworkValidation,
      guestTrialExpired: guestTrialExpired ?? this.guestTrialExpired,
      remainingTime: remainingTime ?? this.remainingTime,
      guestExpiresAt: guestExpiresAt ?? this.guestExpiresAt,
    );
  }

  static const AuthSessionSnapshot anonymous = AuthSessionSnapshot();
}

class SavedSession {
  final String? authMode;
  final String? token;
  final String? userId;
  final String? loginName;
  final DateTime? expiresAt;
  final String? refreshToken;
  final DateTime? refreshExpiresAt;
  final bool isVip;
  final DateTime? vipExpiresAt;
  final String? stageName;
  final String? avatarType;
  final String? avatarUrl;
  final List<EntitlementInfo>? entitlements;
  final bool needNetworkValidation;

  const SavedSession({
    this.authMode,
    this.token,
    this.userId,
    this.loginName,
    this.expiresAt,
    this.refreshToken,
    this.refreshExpiresAt,
    this.isVip = false,
    this.vipExpiresAt,
    this.stageName,
    this.avatarType,
    this.avatarUrl,
    this.entitlements,
    this.needNetworkValidation = false,
  });

  factory SavedSession.fromJson(Map<String, Object?> json) {
    final List<Object?>? rawEntitlements =
        json['entitlements'] as List<Object?>?;
    return SavedSession(
      authMode: json['auth_mode'] as String?,
      token: json['token'] as String?,
      userId: json['user_id'] as String?,
      loginName: json['login_name'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      refreshToken: json['refresh_token'] as String?,
      refreshExpiresAt: json['refresh_expires_at'] != null
          ? DateTime.parse(json['refresh_expires_at'] as String)
          : null,
      isVip: json['is_vip'] as bool? ?? false,
      vipExpiresAt: json['vip_expires_at'] != null
          ? DateTime.parse(json['vip_expires_at'] as String)
          : null,
      stageName: json['stage_name'] as String?,
      avatarType: json['avatar_type'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      entitlements: rawEntitlements
          ?.whereType<Map<String, Object?>>()
          .map(EntitlementInfo.fromJson)
          .toList(),
      needNetworkValidation: json['need_network_validation'] as bool? ?? false,
    );
  }

  bool get hasValidToken =>
      token != null &&
      token!.isNotEmpty &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());
}

class SavedGuestSession {
  final GuestTrialState trialState;
  final String? machineHash;
  final int? issuedAt;
  final int? expiresAt;
  final double? remainingHours;
  final bool valid;
  final String? reason;
  final String? errorMessage;
  final bool needNetworkValidation;
  final int? serverTime;
  final String? serverSignature;

  const SavedGuestSession({
    this.trialState = GuestTrialState.neverStarted,
    this.machineHash,
    this.issuedAt,
    this.expiresAt,
    this.remainingHours,
    this.valid = false,
    this.reason,
    this.errorMessage,
    this.needNetworkValidation = false,
    this.serverTime,
    this.serverSignature,
  });

  factory SavedGuestSession.fromJson(Map<String, Object?> json) {
    return SavedGuestSession(
      trialState: guestTrialStateFromJson(json['trial_state']),
      machineHash: _optionalString(json['machine_hash']),
      issuedAt: json['issued_at'] as int?,
      expiresAt: json['expires_at'] as int?,
      remainingHours: (json['remaining_hours'] as num?)?.toDouble(),
      valid: json['valid'] as bool? ?? false,
      reason: _optionalString(json['reason']),
      errorMessage: _optionalString(json['error_message']),
      needNetworkValidation: json['need_network_validation'] as bool? ?? false,
      serverTime: json['server_time'] as int?,
      serverSignature: _optionalString(json['sig']),
    );
  }

  bool get hasValidToken {
    if (machineHash == null || machineHash!.isEmpty) {
      return false;
    }
    if (trialState != GuestTrialState.active || !valid) {
      return false;
    }
    if (expiresAt == null) {
      return false;
    }
    final int nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt! <= nowSeconds) {
      return false;
    }
    if (remainingHours != null && remainingHours! <= 0) {
      return false;
    }
    return true;
  }
}
