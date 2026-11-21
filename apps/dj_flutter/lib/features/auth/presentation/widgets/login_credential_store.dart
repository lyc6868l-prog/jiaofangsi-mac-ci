import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class LoginCredentialStore {
  Future<String?> readPassword(String account);

  Future<void> savePassword(String account, String password);

  Future<void> deletePassword(String account);
}

class SharedPreferencesLoginCredentialStore implements LoginCredentialStore {
  const SharedPreferencesLoginCredentialStore();

  static const String _keyPrefix = 'dj_login_pwd_';

  @override
  Future<String?> readPassword(String account) async {
    if (account.isEmpty) {
      return null;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString('$_keyPrefix$account');
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> savePassword(String account, String password) async {
    if (account.isEmpty) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String encoded = base64Encode(utf8.encode(password));
    await prefs.setString('$_keyPrefix$account', encoded);
  }

  @override
  Future<void> deletePassword(String account) async {
    if (account.isEmpty) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$account');
  }
}
