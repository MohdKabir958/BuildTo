import 'package:flutter/foundation.dart';
import 'package:kraveo_ui/kraveo_ui.dart' show ClerkIdentity, ClerkSessions;

/// The existing Android Clerk SDK bridge is the sole owner of tokens,
/// credentials, account recovery and multi-factor authentication.
///
/// Production never imports session tokens from Flutter storage or JWT claims.
/// A fake port is used only in isolated Flutter tests.
abstract class SupplierClerkPort {
  ValueListenable<ClerkIdentity> get identity;
  Future<void> initialize();
  Future<bool> authenticate({String mode = 'signInOrUp'});
  Future<String?> token({bool forceRefresh = false});
  Future<bool> signOut();
}

/// Uses the already-installed native Android Clerk UI and secure session SDK.
class NativeSupplierClerkPort implements SupplierClerkPort {
  NativeSupplierClerkPort({ClerkSessions? sessions})
      : _sessions = sessions ?? ClerkSessions.instance;

  final ClerkSessions _sessions;

  @override
  ValueListenable<ClerkIdentity> get identity => _sessions.identity;

  @override
  Future<void> initialize() => _sessions.initialize();

  @override
  Future<bool> authenticate({String mode = 'signInOrUp'}) =>
      _sessions.authenticate(mode: mode);

  @override
  Future<String?> token({bool forceRefresh = false}) =>
      _sessions.token(forceRefresh: forceRefresh);

  @override
  Future<bool> signOut() => _sessions.signOut();
}
