import '../../../../shared/python_rpc/python_rpc_client.dart';
import '../models/auth_models.dart';
import '../models/auth_session_snapshot.dart';

abstract class AuthTaskBridge {
  Future<void> ensureStarted();
  Future<AuthLoginResult> login({
    required String loginName,
    required String password,
  });
  Future<void> syncUnifiedSession({
    required String token,
    required bool isVip,
    DateTime? vipExpiresAt,
    List<EntitlementInfo>? entitlements,
    String? stageName,
    String? avatarType,
    String? avatarUrl,
  });
  Future<void> importUnifiedSession({
    required String token,
    String? refreshToken,
    DateTime? refreshExpiresAt,
    String? userId,
    String? loginName,
    DateTime? expiresAt,
    bool isVip = false,
    DateTime? vipExpiresAt,
    List<EntitlementInfo>? entitlements,
    String? stageName,
    String? avatarType,
    String? avatarUrl,
  });
  Future<String?> readLoginCredential({required String account});
  Future<void> saveLoginCredential({
    required String account,
    required String password,
  });
  Future<void> clearLoginCredential({String? account});
  Future<void> logout({required String token});
  Future<void> clearLocalSession();
  Future<EntitlementResult> checkEntitlement({required String token});
  Future<ProfileResult> getProfile({required String token});
  Future<ProfileResult> getFullProfile({required String token});
  Future<PurchaseOrderResult> createVipOrder({required String token});
  Future<PurchaseOrderResult> createDjToolOrder({required String token});
  Future<SavedSession?> restoreSession();
  Future<void> close();
}

class PythonAuthTaskBridge implements AuthTaskBridge {
  PythonAuthTaskBridge({
    required String pythonExecutable,
    required String workingDirectory,
    required String scriptModule,
  }) : _client = PythonRpcClient(
         pythonExecutable: pythonExecutable,
         workingDirectory: workingDirectory,
         scriptModule: scriptModule,
         requestTimeout: const Duration(seconds: 35),
       );

  final PythonRpcClient _client;

  @override
  Future<void> ensureStarted() => _call<void>(() => _client.ensureStarted());

  @override
  Future<AuthLoginResult> login({
    required String loginName,
    required String password,
  }) async {
    final Map<String, Object?> data = await _request(
      action: 'login',
      payload: <String, Object?>{'login_name': loginName, 'password': password},
    );
    return AuthLoginResult.fromJson(data);
  }

  @override
  Future<void> syncUnifiedSession({
    required String token,
    required bool isVip,
    DateTime? vipExpiresAt,
    List<EntitlementInfo>? entitlements,
    String? stageName,
    String? avatarType,
    String? avatarUrl,
  }) async {
    await _request(
      action: 'sync_unified_session',
      payload: <String, Object?>{
        'token': token,
        'is_vip': isVip,
        'vip_expires_at': vipExpiresAt?.toUtc().toIso8601String(),
        'entitlements': entitlements
            ?.map(
              (EntitlementInfo item) => <String, Object?>{
                'entitlement_type': item.entitlementType,
                'status': item.status,
                'expire_at': item.expireAt?.toUtc().toIso8601String(),
                'days_left': item.daysLeft,
                'is_permanent': item.isPermanent,
                'permanent': item.isPermanent,
              },
            )
            .toList(),
        'stage_name': stageName,
        'avatar_type': avatarType,
        'avatar_url': avatarUrl,
      },
    );
  }

  @override
  Future<void> importUnifiedSession({
    required String token,
    String? refreshToken,
    DateTime? refreshExpiresAt,
    String? userId,
    String? loginName,
    DateTime? expiresAt,
    bool isVip = false,
    DateTime? vipExpiresAt,
    List<EntitlementInfo>? entitlements,
    String? stageName,
    String? avatarType,
    String? avatarUrl,
  }) async {
    await _request(
      action: 'import_unified_session',
      payload: <String, Object?>{
        'token': token,
        'refresh_token': refreshToken,
        'refresh_expires_at': refreshExpiresAt?.toUtc().toIso8601String(),
        'user_id': userId,
        'login_name': loginName,
        'expires_at': expiresAt?.toUtc().toIso8601String(),
        'is_vip': isVip,
        'vip_expires_at': vipExpiresAt?.toUtc().toIso8601String(),
        'entitlements': entitlements
            ?.map(
              (EntitlementInfo item) => <String, Object?>{
                'entitlement_type': item.entitlementType,
                'status': item.status,
                'expire_at': item.expireAt?.toUtc().toIso8601String(),
                'days_left': item.daysLeft,
                'is_permanent': item.isPermanent,
                'permanent': item.isPermanent,
              },
            )
            .toList(),
        'stage_name': stageName,
        'avatar_type': avatarType,
        'avatar_url': avatarUrl,
      },
    );
  }

  @override
  Future<String?> readLoginCredential({required String account}) async {
    final Map<String, Object?> data = await _request(
      action: 'load_login_credential',
      payload: <String, Object?>{'account': account},
    );
    final String? value = (data['password'] ?? '').toString();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> saveLoginCredential({
    required String account,
    required String password,
  }) async {
    await _request(
      action: 'save_login_credential',
      payload: <String, Object?>{'account': account, 'password': password},
    );
  }

  @override
  Future<void> clearLoginCredential({String? account}) async {
    await _request(
      action: 'clear_login_credential',
      payload: <String, Object?>{'account': account},
    );
  }

  @override
  Future<void> logout({required String token}) async {
    await _request(
      action: 'logout',
      payload: <String, Object?>{'token': token},
    );
  }

  @override
  Future<void> clearLocalSession() async {
    await _request(action: 'clear_local_session', payload: <String, Object?>{});
  }

  @override
  Future<EntitlementResult> checkEntitlement({required String token}) async {
    final Map<String, Object?> data = await _request(
      action: 'check_entitlement',
      payload: <String, Object?>{'token': token},
    );
    return EntitlementResult.fromJson(data);
  }

  @override
  Future<ProfileResult> getProfile({required String token}) async {
    final Map<String, Object?> data = await _request(
      action: 'get_profile',
      payload: <String, Object?>{'token': token},
    );
    return ProfileResult.fromJson(data);
  }

  @override
  Future<ProfileResult> getFullProfile({required String token}) async {
    final Map<String, Object?> data = await _request(
      action: 'get_full_profile',
      payload: <String, Object?>{'token': token},
    );
    return ProfileResult.fromJson(data);
  }

  @override
  Future<PurchaseOrderResult> createVipOrder({required String token}) async {
    final Map<String, Object?> data = await _request(
      action: 'create_vip_order',
      payload: <String, Object?>{'token': token, 'device_type': 'pc'},
    );
    return PurchaseOrderResult.fromJson(data);
  }

  @override
  Future<PurchaseOrderResult> createDjToolOrder({required String token}) async {
    final Map<String, Object?> data = await _request(
      action: 'create_dj_tool_order',
      payload: <String, Object?>{'token': token, 'device_type': 'pc'},
    );
    return PurchaseOrderResult.fromJson(data);
  }

  @override
  Future<SavedSession?> restoreSession() async {
    final Map<String, Object?> data = await _request(
      action: 'restore_session',
      payload: <String, Object?>{},
    );
    if (data.isEmpty) {
      return null;
    }
    return SavedSession.fromJson(data);
  }

  Future<Map<String, Object?>> _request({
    required String action,
    required Map<String, Object?> payload,
  }) {
    return _call<Map<String, Object?>>(
      () => _client.request(module: 'auth', action: action, payload: payload),
    );
  }

  @override
  Future<void> close() => _call<void>(() => _client.close());

  Future<T> _call<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PythonRpcClientException catch (error) {
      throw AuthBridgeException(error.code, error.message);
    }
  }
}
