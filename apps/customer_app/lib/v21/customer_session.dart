import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kraveo_ui/kraveo_ui.dart'
    show ClerkIdentity, ClerkSessions, GrozoAuthConfig;
import 'customer_api.dart';

abstract class CustomerIdentity {
  ValueListenable<ClerkIdentity> get identity;
  Future<void> initialize();
  Future<bool> authenticate();
  Future<String?> token();
  Future<bool> signOut();
}

class NativeCustomerIdentity implements CustomerIdentity {
  final sessions = ClerkSessions.instance;
  @override
  ValueListenable<ClerkIdentity> get identity => sessions.identity;
  @override
  Future<void> initialize() => sessions.initialize();
  @override
  Future<bool> authenticate() => sessions.authenticate();
  @override
  Future<String?> token() => sessions.token();
  @override
  Future<bool> signOut() => sessions.signOut();
}

class CustomerSession extends ChangeNotifier {
  CustomerSession({required this.api, required this.auth}) {
    api.onUnauthorized = _lostAccess;
    auth.identity.addListener(_identityChanged);
  }
  final CustomerApi api;
  final CustomerIdentity auth;
  Data? user;
  Data? address;
  int epoch = 0;
  bool busy = false;
  String? authNotice;
  String? _identityKey;
  bool _disposed = false;
  bool get signedIn => user != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _lostAccess() {
    api.invalidate();
    epoch++;
    user = null;
    address = null;
    _notify();
  }

  void _identityChanged() {
    final i = auth.identity.value;
    final key = '${i.userId}:${i.sessionId}:${i.signedIn}';
    if (key == _identityKey) return;
    _identityKey = key;
    _lostAccess();
    if (i.signedIn) unawaited(restore());
  }

  Future<void> start() async {
    try {
      if (!GrozoAuthConfig.usesClerk && auth is NativeCustomerIdentity) {
        authNotice = 'Secure sign-in is not configured for this build.';
        return;
      }
      await auth.initialize();
      if (auth.identity.value.signedIn) await restore();
    } catch (_) {
      authNotice = 'Sign-in could not connect. You can still browse materials.';
    } finally {
      _notify();
    }
  }

  Future<void> restore() async {
    final e = epoch;
    try {
      final me = await api.me();
      if (e != epoch) return;
      user = me;
      authNotice = null;
      _notify();
    } catch (e) {
      if (e is CustomerProblem && [401, 403].contains(e.status)) {
        _lostAccess();
      }
      authNotice =
          e is CustomerProblem ? e.message : 'Sign-in could not connect.';
      _notify();
    }
  }

  Future<void> signIn() async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      if (!GrozoAuthConfig.usesClerk && auth is NativeCustomerIdentity) {
        throw const CustomerProblem(
          'Secure sign-in is not configured for this build.',
        );
      }
      await auth.initialize();
      if (!auth.identity.value.signedIn && !await auth.authenticate()) return;
      await restore();
      if (user == null) {
        throw CustomerProblem(
          authNotice ?? 'Your account is not ready. Please retry.',
        );
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> signOut() async {
    if (!await auth.signOut()) {
      throw const CustomerProblem('Sign-out could not complete. Please retry.');
    }
    _lostAccess();
  }

  void chooseAddress(Data? value) {
    address = value;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    auth.identity.removeListener(_identityChanged);
    api.onUnauthorized = null;
    api.close();
    super.dispose();
  }
}
