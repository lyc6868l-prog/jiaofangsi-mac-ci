import '../../../../shared/python_rpc/python_rpc_client.dart';
import '../models/auth_models.dart';
import '../models/auth_session_snapshot.dart';

abstract class GuestTaskBridge {
  Future<void> ensureStarted();
  Future<GuestRegisterResult> registerGuest();
  Future<GuestStatusResult> checkGuestStatus();
  Future<SavedGuestSession?> restoreGuestSession();
  Future<void> clearGuestSession();
  Future<void> close();
}

class PythonGuestTaskBridge implements GuestTaskBridge {
  PythonGuestTaskBridge({
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
  Future<GuestRegisterResult> registerGuest() async {
    final Map<String, Object?> data = await _request(
      action: 'register_guest',
      payload: <String, Object?>{},
    );
    return GuestRegisterResult.fromJson(data);
  }

  @override
  Future<GuestStatusResult> checkGuestStatus() async {
    final Map<String, Object?> data = await _request(
      action: 'check_guest_status',
      payload: <String, Object?>{},
    );
    return GuestStatusResult.fromJson(data);
  }

  @override
  Future<SavedGuestSession?> restoreGuestSession() async {
    final Map<String, Object?> data = await _request(
      action: 'restore_guest_session',
      payload: <String, Object?>{},
    );
    if (data.isEmpty) {
      return null;
    }
    return SavedGuestSession.fromJson(data);
  }

  @override
  Future<void> clearGuestSession() async {
    await _request(action: 'clear_guest_session', payload: <String, Object?>{});
  }

  Future<Map<String, Object?>> _request({
    required String action,
    required Map<String, Object?> payload,
  }) {
    return _call<Map<String, Object?>>(
      () => _client.request(module: 'guest', action: action, payload: payload),
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
