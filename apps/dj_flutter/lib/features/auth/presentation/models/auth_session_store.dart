import 'package:flutter/foundation.dart';

import 'auth_session_snapshot.dart';
import '../controllers/auth_controller.dart';

class AuthSessionStore extends ChangeNotifier {
  AuthSessionSnapshot _snapshot = AuthSessionSnapshot.anonymous;
  bool _bootstrapped = false;

  AuthSessionSnapshot get snapshot => _snapshot;

  bool get bootstrapped => _bootstrapped;

  Future<void> bootstrap(AuthController controller) async {
    if (_bootstrapped) {
      return;
    }

    final AuthSessionSnapshot restoredSession = await controller
        .restoreSession();

    _snapshot = restoredSession;
    _bootstrapped = true;
    notifyListeners();
  }

  void update(AuthSessionSnapshot snapshot) {
    _snapshot = snapshot;
    notifyListeners();
  }

  void clear() {
    _snapshot = AuthSessionSnapshot.anonymous;
    notifyListeners();
  }
}
