String? _stringFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = value.toString().trim();
  if (text.isEmpty) {
    return null;
  }
  return text;
}

enum GuestTrialState { neverStarted, active, expired, unknown }

GuestTrialState guestTrialStateFromJson(Object? value) {
  switch (_stringFromJson(value)) {
    case 'active':
      return GuestTrialState.active;
    case 'expired':
      return GuestTrialState.expired;
    case 'unknown':
      return GuestTrialState.unknown;
    case 'never_started':
    default:
      return GuestTrialState.neverStarted;
  }
}

String guestTrialStateToJson(GuestTrialState state) {
  switch (state) {
    case GuestTrialState.active:
      return 'active';
    case GuestTrialState.expired:
      return 'expired';
    case GuestTrialState.unknown:
      return 'unknown';
    case GuestTrialState.neverStarted:
      return 'never_started';
  }
}

List<String>? _stringListFromJson(Object? value) {
  if (value is List<Object?>) {
    final List<String> values = value
        .map(_stringFromJson)
        .whereType<String>()
        .toList();
    if (values.isEmpty) {
      return null;
    }
    return values;
  }
  final String? singleValue = _stringFromJson(value);
  if (singleValue == null) {
    return null;
  }
  return <String>[singleValue];
}

class AuthLoginResult {
  final bool success;
  final String? token;
  final String? userId;
  final String? loginName;
  final DateTime? expiresAt;
  final String? errorMessage;

  const AuthLoginResult({
    required this.success,
    this.token,
    this.userId,
    this.loginName,
    this.expiresAt,
    this.errorMessage,
  });

  factory AuthLoginResult.fromJson(Map<String, Object?> json) {
    return AuthLoginResult(
      success: json['success'] as bool? ?? false,
      token: json['token'] as String?,
      userId: json['user_id'] as String?,
      loginName: json['login_name'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      errorMessage: json['error_message'] as String?,
    );
  }
}

class EntitlementInfo {
  final String? entitlementType;
  final String? status;
  final DateTime? expireAt;
  final int? daysLeft;
  final bool isPermanent;

  const EntitlementInfo({
    this.entitlementType,
    this.status,
    this.expireAt,
    this.daysLeft,
    this.isPermanent = false,
  });

  bool get isActive => status == 'active';

  factory EntitlementInfo.fromJson(Map<String, Object?> json) {
    return EntitlementInfo(
      entitlementType: _stringFromJson(json['entitlement_type']),
      status: _stringFromJson(json['status']),
      expireAt: _stringFromJson(json['expire_at']) != null
          ? DateTime.tryParse(_stringFromJson(json['expire_at'])!)
          : null,
      daysLeft: json['days_left'] as int?,
      isPermanent: json['is_permanent'] as bool? ?? false,
    );
  }
}

class EntitlementResult {
  final bool success;
  final bool isVip;
  final DateTime? vipExpiresAt;
  final List<EntitlementInfo>? entitlements;
  final String? errorMessage;

  const EntitlementResult({
    required this.success,
    this.isVip = false,
    this.vipExpiresAt,
    this.entitlements,
    this.errorMessage,
  });

  factory EntitlementResult.fromJson(Map<String, Object?> json) {
    final rawEntitlements = json['entitlements'] as List<Object?>?;
    return EntitlementResult(
      success: json['success'] as bool? ?? false,
      isVip: json['is_vip'] as bool? ?? false,
      vipExpiresAt: _stringFromJson(json['vip_expires_at']) != null
          ? DateTime.tryParse(_stringFromJson(json['vip_expires_at'])!)
          : null,
      entitlements: rawEntitlements
          ?.whereType<Map<String, Object?>>()
          .map(EntitlementInfo.fromJson)
          .toList(),
      errorMessage: _stringFromJson(json['error_message']),
    );
  }
}

class PurchaseOrderResult {
  final bool success;
  final String? orderId;
  final String? planCode;
  final String? planTitle;
  final double? amount;
  final int? days;
  final String? paymentUrl;
  final String? errorMessage;

  const PurchaseOrderResult({
    required this.success,
    this.orderId,
    this.planCode,
    this.planTitle,
    this.amount,
    this.days,
    this.paymentUrl,
    this.errorMessage,
  });

  factory PurchaseOrderResult.fromJson(Map<String, Object?> json) {
    return PurchaseOrderResult(
      success: json['success'] as bool? ?? false,
      orderId: _stringFromJson(json['order_id']),
      planCode: _stringFromJson(json['plan_code']),
      planTitle: _stringFromJson(json['plan_title']),
      amount: (json['amount'] as num?)?.toDouble(),
      days: json['days'] as int?,
      paymentUrl: _stringFromJson(json['payment_url']),
      errorMessage: _stringFromJson(json['error_message']),
    );
  }
}

class ProfileResult {
  final bool success;
  final String? stageName;
  final String? avatarType;
  final String? avatarUrl;
  final String? gender;
  final String? age;
  final String? city;
  final String? musicStyle;
  final String? djType;
  final String? height;
  final String? weight;
  final String? experience;
  final String? fans;
  final String? price;
  final String? workStatus;
  final List<String>? specialties;
  final String? contact;
  final String? masterpiece;
  final String? socialMedia;
  final String? bio;
  final String? videoUrl;
  final String? pdfUrl;
  final String? errorMessage;

  const ProfileResult({
    required this.success,
    this.stageName,
    this.avatarType,
    this.avatarUrl,
    this.gender,
    this.age,
    this.city,
    this.musicStyle,
    this.djType,
    this.height,
    this.weight,
    this.experience,
    this.fans,
    this.price,
    this.workStatus,
    this.specialties,
    this.contact,
    this.masterpiece,
    this.socialMedia,
    this.bio,
    this.videoUrl,
    this.pdfUrl,
    this.errorMessage,
  });

  factory ProfileResult.fromJson(Map<String, Object?> json) {
    return ProfileResult(
      success: json['success'] as bool? ?? false,
      stageName: _stringFromJson(json['stage_name']),
      avatarType: _stringFromJson(json['avatar_type']),
      avatarUrl: _stringFromJson(json['avatar_url']),
      gender: _stringFromJson(json['gender']),
      age: _stringFromJson(json['age']),
      city: _stringFromJson(json['city']),
      musicStyle: _stringFromJson(json['music_style']),
      djType: _stringFromJson(json['dj_type']),
      height: _stringFromJson(json['height']),
      weight: _stringFromJson(json['weight']),
      experience: _stringFromJson(json['experience']),
      fans: _stringFromJson(json['fans']),
      price: _stringFromJson(json['price']),
      workStatus: _stringFromJson(json['work_status']),
      specialties: _stringListFromJson(json['specialties']),
      contact: _stringFromJson(json['contact']),
      masterpiece: _stringFromJson(json['masterpiece']),
      socialMedia: _stringFromJson(json['social_media']),
      bio: _stringFromJson(json['bio']),
      videoUrl: _stringFromJson(json['video_url']),
      pdfUrl: _stringFromJson(json['pdf_url']),
      errorMessage: _stringFromJson(json['error_message']),
    );
  }
}

class GuestRegisterResult {
  final bool success;
  final GuestTrialState trialState;
  final int? issuedAt;
  final int? expiresAt;
  final double? remainingHours;
  final String? machineHash;
  final bool needNetworkValidation;
  final String? reason;
  final String? errorMessage;
  final int? serverTime;
  final String? serverSignature;

  const GuestRegisterResult({
    required this.success,
    this.trialState = GuestTrialState.neverStarted,
    this.issuedAt,
    this.expiresAt,
    this.remainingHours,
    this.machineHash,
    this.needNetworkValidation = false,
    this.reason,
    this.errorMessage,
    this.serverTime,
    this.serverSignature,
  });

  factory GuestRegisterResult.fromJson(Map<String, Object?> json) {
    return GuestRegisterResult(
      success: json['success'] as bool? ?? false,
      trialState: guestTrialStateFromJson(json['trial_state']),
      issuedAt: json['issued_at'] as int?,
      expiresAt: json['expires_at'] as int?,
      remainingHours: (json['remaining_hours'] as num?)?.toDouble(),
      machineHash: _stringFromJson(json['machine_hash']),
      needNetworkValidation: json['need_network_validation'] as bool? ?? false,
      reason: _stringFromJson(json['reason']),
      errorMessage: _stringFromJson(json['error_message']),
      serverTime: json['server_time'] as int?,
      serverSignature: _stringFromJson(json['sig']),
    );
  }
}

class GuestStatusResult {
  final bool success;
  final GuestTrialState trialState;
  final bool valid;
  final int? issuedAt;
  final int? expiresAt;
  final double? remainingHours;
  final String? machineHash;
  final bool needNetworkValidation;
  final String? reason;
  final String? errorMessage;
  final int? serverTime;
  final String? serverSignature;

  const GuestStatusResult({
    required this.success,
    this.trialState = GuestTrialState.neverStarted,
    this.valid = false,
    this.issuedAt,
    this.expiresAt,
    this.remainingHours,
    this.machineHash,
    this.needNetworkValidation = false,
    this.reason,
    this.errorMessage,
    this.serverTime,
    this.serverSignature,
  });

  factory GuestStatusResult.fromJson(Map<String, Object?> json) {
    return GuestStatusResult(
      success: json['success'] as bool? ?? false,
      trialState: guestTrialStateFromJson(json['trial_state']),
      valid: json['valid'] as bool? ?? false,
      issuedAt: json['issued_at'] as int?,
      expiresAt: json['expires_at'] as int?,
      remainingHours: (json['remaining_hours'] as num?)?.toDouble(),
      machineHash: _stringFromJson(json['machine_hash']),
      needNetworkValidation: json['need_network_validation'] as bool? ?? false,
      reason: _stringFromJson(json['reason']),
      errorMessage: _stringFromJson(json['error_message']),
      serverTime: json['server_time'] as int?,
      serverSignature: _stringFromJson(json['sig']),
    );
  }
}

class AuthBridgeException implements Exception {
  final String code;
  final String message;

  const AuthBridgeException(this.code, this.message);

  @override
  String toString() => message;
}
