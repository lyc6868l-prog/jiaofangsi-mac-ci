import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/python_auth_task_bridge.dart';
import 'login_credential_store.dart';

/// Stores remembered passwords in the Python runtime's encrypted secure
/// storage instead of leaving them Base64-encoded in SharedPreferences.
class PythonLoginCredentialStore implements LoginCredentialStore {
  PythonLoginCredentialStore(this.bridge);

  final AuthTaskBridge bridge;
  static const SharedPreferencesLoginCredentialStore _legacy =
      SharedPreferencesLoginCredentialStore();

  @override
  Future<String?> readPassword(String account) async {
    if (account.isEmpty) {
      return null;
    }
    try {
      final String? value = await bridge.readLoginCredential(account: account);
      if (value != null && value.isNotEmpty) {
        return value;
      }
    } catch (_) {
      // Fall through to the old local store for migration.
    }
    final String? legacyPassword = await _legacy.readPassword(account);
    if (legacyPassword != null && legacyPassword.isNotEmpty) {
      try {
        await bridge.saveLoginCredential(
          account: account,
          password: legacyPassword,
        );
        await _legacy.deletePassword(account);
      } catch (_) {}
      return legacyPassword;
    }
    return null;
  }

  @override
  Future<void> savePassword(String account, String password) async {
    if (account.isEmpty) {
      return;
    }
    await bridge.saveLoginCredential(account: account, password: password);
    await _legacy.deletePassword(account);
  }

  @override
  Future<void> deletePassword(String account) async {
    if (account.isEmpty) {
      return;
    }
    try {
      await bridge.clearLoginCredential(account: account);
    } catch (_) {}
    await _legacy.deletePassword(account);
  }
}
