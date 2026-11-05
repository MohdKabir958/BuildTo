import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:kraveo_ui/kraveo_ui.dart' show ClerkIdentity;
import '../api/supplier_v21_api.dart';
import '../api/supplier_v21_models.dart';
import 'supplier_clerk_port.dart';
import '../onboarding/supplier_applications_api.dart';
import '../dashboard/supplier_dashboard_repository.dart';
import '../catalog/supplier_catalog_repository.dart';
import '../inventory/supplier_inventory_repository.dart';
import '../delivery/supplier_delivery_repository.dart';
import '../rfq/supplier_rfq_repository.dart';

enum SupplierAccessStage {
  starting,
  signedOut,
  checking,
  chooseSupplier,
  authorized,
  noSupplier,
  accessDenied,
  sessionExpired,
  unavailable,
  misconfigured,
}

/// Server memberships are the sole source of business access. Every identity
/// change, re-selection and refresh clears the previous business scope *before*
/// waiting for the network. Stale requests from prior sessions are discarded.
class SupplierAuthController extends ChangeNotifier {
  SupplierAuthController({
    required SupplierClerkPort clerk,
    required SupplierV21Api api,
  })  : _clerk = clerk,
        _api = api {
    _clerk.identity.addListener(_onNativeIdentity);
  }

  final SupplierClerkPort _clerk;
  final SupplierV21Api _api;
  SupplierAccessStage _stage = SupplierAccessStage.starting;
  SupplierV21Identity? _account;
  SupplierV21Membership? _activeSupplier;
  String? _fingerprint;
  String? _selectedId;
  String? _notice;
  int _generation = 0;
  bool _started = false;
  bool _disposed = false;
  bool _locallyBlocked = false;
  bool _busy = false;

  SupplierAccessStage get stage => _stage;
  SupplierV21Identity? get account => _account;
  SupplierV21Membership? get activeSupplier => _activeSupplier;
  String? get notice => _notice;
  bool get busy => _busy;
  String? get signedInEmail => _clerk.identity.value.email;

  /// Invalidates open onboarding screens across session and account changes.
  String? get sessionKey => _fingerprint;

  /// Reuses the token-injecting V2.1 client; applicants do not need active
  /// supplier membership to manage their own pending application.
  SupplierApplicationsApi get applications => SupplierApplicationsApi(_api);

  /// One shared request boundary for the approved supplier's S04 overview.
  late final SupplierDashboardRepository dashboardRepository =
      SupplierDashboardRepository(_api);

  /// Native Clerk-backed V2.1 catalog boundary, never legacy vendor API.
  late final SupplierCatalogRepository catalogRepository =
      SupplierCatalogRepository(_api);

  late final SupplierInventoryRepository inventoryRepository =
      SupplierInventoryRepository(_api);

  late final SupplierDeliveryRepository deliveryRepository =
      SupplierDeliveryRepository(_api);

  late final SupplierRfqRepository rfqRepository =
      SupplierRfqRepository(_api);

  bool _current(int generation, String? fingerprint) =>
      !_disposed &&
      !_locallyBlocked &&
      generation == _generation &&
      fingerprint != null &&
      _fingerprint == fingerprint;

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  void _clear(SupplierAccessStage stage) {
    _generation++;
    _account = null;
    _activeSupplier = null;
    _selectedId = null;
    _stage = stage;
    _publish();
  }

  /// Start the verified Clerk bridge; never runs the legacy restaurant gate.
  Future<void> start() async {
    if (_started || _disposed) return;
    try {
      await _clerk.initialize();
      if (_disposed) return;
      _started = true;
      _onNativeIdentity();
    } catch (_) {
      if (_disposed) return;
      _stage = SupplierAccessStage.misconfigured;
      _notice =
          'Native Clerk sign-in is unavailable. Check Android staging setup.';
      _publish();
    }
  }

  void _onNativeIdentity() {
    if (!_started || _disposed || _locallyBlocked) return;
    final state = _clerk.identity.value;
    if (!state.signedIn) {
      if (_fingerprint != null || _stage != SupplierAccessStage.signedOut) {
        _fingerprint = null;
        _notice = null;
        _clear(SupplierAccessStage.signedOut);
      }
      return;
    }
    if (!_validNativeIdentity(state)) {
      _fingerprint = null;
      _notice = 'Clerk returned an incomplete account session.';
      _clear(SupplierAccessStage.sessionExpired);
      return;
    }
    final next = [state.userId, state.sessionId].join('|');
    if (next == _fingerprint) return;
    _fingerprint = next;
    _notice = null;
    _clear(SupplierAccessStage.checking);
    unawaited(refresh());
  }

  static bool _validNativeIdentity(ClerkIdentity identity) =>
      identity.ready &&
      identity.signedIn &&
      RegExp(r'^user_[A-Za-z0-9]{6,150}$').hasMatch(identity.userId ?? '') &&
      RegExp(r'^sess_[A-Za-z0-9]{6,150}$').hasMatch(identity.sessionId ?? '');

  /// Revalidates /me and supplier-specific /access, including after resume.
  /// Previously approved permissions are not used while refresh is pending.
  Future<void> refresh() async {
    if (_disposed || _locallyBlocked || _fingerprint == null) return;
    final fingerprint = _fingerprint;
    final generation = ++_generation;
    final previouslySelected = _selectedId;
    _activeSupplier = null;
    _account = null;
    _stage = SupplierAccessStage.checking;
    _notice = null;
    _publish();
    try {
      final result = await _api.get('/api/v2/me');
      final account = SupplierV21Identity.fromJson(result.requireObject());
      if (!_current(generation, fingerprint)) return;
      _account = account;
      if (account.suppliers.isEmpty) {
        _selectedId = null;
        _stage = SupplierAccessStage.noSupplier;
        _publish();
        return;
      }
      final matching = account.suppliers.where(
        (member) => member.supplierId == previouslySelected,
      );
      final desired = matching.isEmpty ? null : matching.first;
      final single =
          account.suppliers.length == 1 ? account.suppliers.first : null;
      final target = desired ?? single;
      if (target == null) {
        _selectedId = null;
        _stage = SupplierAccessStage.chooseSupplier;
        _publish();
        return;
      }
      await _verifySupplier(target, generation, fingerprint);
    } on SupplierV21Exception catch (error) {
      if (_current(generation, fingerprint)) _fail(error);
    } on FormatException {
      if (_current(generation, fingerprint)) {
        _stage = SupplierAccessStage.accessDenied;
        _notice = 'The backend returned an invalid supplier access record.';
        _publish();
      }
    } catch (_) {
      if (_current(generation, fingerprint)) {
        _stage = SupplierAccessStage.unavailable;
        _notice = 'Could not verify your supplier account. Please retry.';
        _publish();
      }
    }
  }

  /// Explicit switch: clear old access before checking selected membership.
  Future<void> selectSupplier(String supplierId) async {
    if (_disposed ||
        _locallyBlocked ||
        _fingerprint == null ||
        _account == null) {
      return;
    }
    final choices = _account!.suppliers.where(
      (item) => item.supplierId == supplierId,
    );
    if (choices.length != 1) {
      _selectedId = null;
      _activeSupplier = null;
      _stage = SupplierAccessStage.accessDenied;
      _notice = 'This supplier does not belong to your verified account.';
      _publish();
      return;
    }
    final fingerprint = _fingerprint;
    final generation = ++_generation;
    _activeSupplier = null;
    _selectedId = null;
    _stage = SupplierAccessStage.checking;
    _notice = null;
    _publish();
    try {
      await _verifySupplier(choices.single, generation, fingerprint);
    } on SupplierV21Exception catch (error) {
      if (_current(generation, fingerprint)) _fail(error);
    } on FormatException {
      if (_current(generation, fingerprint)) {
        _stage = SupplierAccessStage.accessDenied;
        _notice = 'Supplier permissions changed. Refresh your account.';
        _publish();
      }
    } catch (_) {
      if (_current(generation, fingerprint)) {
        _stage = SupplierAccessStage.unavailable;
        _notice = 'Could not verify this supplier. Please retry.';
        _publish();
      }
    }
  }

  Future<void> _verifySupplier(
    SupplierV21Membership candidate,
    int generation,
    String? fingerprint,
  ) async {
    final route = '/api/v2/suppliers/${candidate.supplierId}/access';
    final result = await _api.get(route);
    final verified = SupplierV21Membership.fromJson(result.requireObject());
    if (!_current(generation, fingerprint)) return;
    if (verified.supplierId != candidate.supplierId ||
        verified.role != candidate.role) {
      throw const FormatException(
        'Supplier membership changed during verification',
      );
    }
    _selectedId = verified.supplierId;
    _activeSupplier = verified;
    _stage = SupplierAccessStage.authorized;
    _notice = null;
    _publish();
  }

  void showSupplierChooser() {
    if (_disposed ||
        _stage != SupplierAccessStage.authorized ||
        _account == null ||
        _account!.suppliers.length < 2) {
      return;
    }
    _generation++;
    _activeSupplier = null;
    _selectedId = null;
    _stage = SupplierAccessStage.chooseSupplier;
    _publish();
  }

  void _fail(SupplierV21Exception error) {
    _activeSupplier = null;
    _stage = switch (error.problem) {
      SupplierV21Problem.authentication => SupplierAccessStage.sessionExpired,
      SupplierV21Problem.forbidden ||
      SupplierV21Problem.notFound =>
        SupplierAccessStage.accessDenied,
      SupplierV21Problem.configuration => SupplierAccessStage.misconfigured,
      _ => SupplierAccessStage.unavailable,
    };
    _notice = switch (_stage) {
      SupplierAccessStage.sessionExpired =>
        'Your Clerk session expired. Sign in again.',
      SupplierAccessStage.accessDenied =>
        'This account does not currently have access to that supplier.',
      SupplierAccessStage.misconfigured => 'BuildTo staging is not configured.',
      _ => 'Secure account verification is unavailable. Please retry.',
    };
    _publish();
  }

  Future<void> authenticate({String mode = 'signInOrUp'}) async {
    if (_busy || _disposed) return;
    _busy = true;
    _locallyBlocked = false;
    _notice = null;
    _publish();
    try {
      final signedIn = await _clerk.authenticate(mode: mode);
      if (_disposed) return;
      if (!signedIn) {
        _notice = 'Sign-in was cancelled.';
      } else {
        final prior = _fingerprint;
        _onNativeIdentity();
        if (prior != null &&
            prior == _fingerprint &&
            _stage != SupplierAccessStage.checking &&
            _stage != SupplierAccessStage.authorized) {
          // Native SDK may reuse the same session after reauthentication.
          // Recheck the backend even if no identity-change event was emitted.
          await refresh();
        }
      }
    } catch (_) {
      if (!_disposed) {
        _notice = 'Secure sign-in is unavailable. Please try again.';
      }
    } finally {
      _busy = false;
      _publish();
    }
  }

  /// Local business access disappears immediately; never claim remote Clerk
  /// session revocation when the SDK did not confirm it.
  Future<void> signOut() async {
    if (_busy || _disposed) return;
    _locallyBlocked = true;
    _fingerprint = null;
    _notice = null;
    _clear(SupplierAccessStage.signedOut);
    _busy = true;
    _publish();
    try {
      final revoked = await _clerk.signOut();
      if (!_disposed && !revoked) {
        _notice = 'Signed out locally; remote revocation was not confirmed.';
      }
    } catch (_) {
      if (!_disposed) {
        _notice =
            'Access is hidden here. Native sign-out could not be confirmed; retry or close the app.';
      }
    } finally {
      _busy = false;
      _publish();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _clerk.identity.removeListener(_onNativeIdentity);
    _api.close();
    super.dispose();
  }
}
