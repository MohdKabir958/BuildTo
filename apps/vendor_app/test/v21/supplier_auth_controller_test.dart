import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kraveo_ui/kraveo_ui.dart' show ClerkIdentity;
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/auth/supplier_auth_controller.dart';
import 'package:vendor_app/v21/auth/supplier_clerk_port.dart';

const idA = '123e4567-e89b-12d3-a456-426614174000';
const idB = '123e4567-e89b-12d3-a456-426614174001';

class FakeClerk implements SupplierClerkPort {
  final state = ValueNotifier<ClerkIdentity>(
    const ClerkIdentity(ready: true, signedIn: false),
  );
  String? sessionToken = 'clerk-session-fixture';
  bool remoteRevoked = true;
  int tokenCalls = 0;
  int signOutCalls = 0;
  bool authenticates = true;

  @override
  ValueListenable<ClerkIdentity> get identity => state;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> authenticate({String mode = 'signInOrUp'}) async {
    if (!authenticates) return false;
    login('user_SupplierOne', 'sess_SupplierOne');
    return true;
  }

  void login(String user, String session) {
    state.value = ClerkIdentity(
      ready: true,
      signedIn: true,
      userId: user,
      sessionId: session,
      email: 'supplier@example.invalid',
    );
  }

  @override
  Future<String?> token({bool forceRefresh = false}) async {
    tokenCalls++;
    return sessionToken;
  }

  @override
  Future<bool> signOut() async {
    signOutCalls++;
    state.value = const ClerkIdentity(ready: true, signedIn: false);
    return remoteRevoked;
  }
}

SupplierAuthController makeController(FakeClerk clerk, http.Client client) {
  final api = SupplierV21Api(
    origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
    token: () => clerk.token(),
    httpClient: client,
  );
  return SupplierAuthController(clerk: clerk, api: api);
}

http.Response me(List<Map<String, Object?>> suppliers) => http.Response(
    jsonEncode({
      'data': {
        'id': 'local-account',
        'displayName': 'Verified BuildTo Supplier',
        'adminRole': null,
        'suppliers': suppliers
      },
      'requestId': 'request-me',
    }),
    200);

Map<String, Object?> member(String id, String role) =>
    {'supplierId': id, 'role': role};

http.Response access(String id, String role) => http.Response(
    jsonEncode({
      'data': {'supplierId': id, 'role': role},
      'requestId': 'request-access',
    }),
    200);

Future<void> until(SupplierAuthController c, SupplierAccessStage stage) async {
  for (var i = 0; i < 120; i++) {
    if (c.stage == stage) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Did not reach desired access state; actual: ${c.stage}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('signed-out session cannot request protected supplier data', () async {
    final clerk = FakeClerk();
    var calls = 0;
    final controller = makeController(clerk, MockClient((_) async {
      calls++;
      return me([]);
    }));
    await controller.start();
    expect(controller.stage, SupplierAccessStage.signedOut);
    expect(controller.activeSupplier, isNull);
    expect(calls, 0);
    controller.dispose();
    clerk.state.dispose();
  });

  test('Clerk sign-in checks /me and exact /access before unlock', () async {
    final clerk = FakeClerk();
    final routes = <String>[];
    final controller = makeController(clerk, MockClient((request) async {
      routes.add(request.url.path);
      expect(request.headers['Authorization'], '***');
      if (request.url.path == '/api/v2/me') {
        return me([member(idA, 'INVENTORY')]);
      }
      if (request.url.path == '/api/v2/suppliers/$idA/access') {
        return access(idA, 'INVENTORY');
      }
      return http.Response('{}', 404);
    }));
    await controller.start();
    await controller.authenticate();
    await until(controller, SupplierAccessStage.authorized);
    expect(controller.activeSupplier!.supplierId, idA);
    expect(controller.activeSupplier!.role.name, 'inventory');
    expect(routes, ['/api/v2/me', '/api/v2/suppliers/$idA/access']);
    expect(clerk.tokenCalls, 2);
    controller.dispose();
    clerk.state.dispose();
  });

  test('no approved supplier membership is never authorized', () async {
    final clerk = FakeClerk();
    final controller = makeController(clerk, MockClient((_) async => me([])));
    await controller.start();
    clerk.login('user_SupplierOne', 'sess_SupplierOne');
    await until(controller, SupplierAccessStage.noSupplier);
    expect(controller.activeSupplier, isNull);
    controller.dispose();
    clerk.state.dispose();
  });

  test('multi-supplier switch clears old scope before async access response',
      () async {
    final clerk = FakeClerk();
    final delayedB = Completer<http.Response>();
    final controller = makeController(clerk, MockClient((request) async {
      if (request.url.path == '/api/v2/me') {
        return me([member(idA, 'OWNER'), member(idB, 'VIEWER')]);
      }
      if (request.url.path.endsWith('$idA/access')) return access(idA, 'OWNER');
      return delayedB.future;
    }));
    await controller.start();
    clerk.login('user_SupplierOne', 'sess_SupplierOne');
    await until(controller, SupplierAccessStage.chooseSupplier);
    await controller.selectSupplier(idA);
    expect(controller.stage, SupplierAccessStage.authorized);
    controller.showSupplierChooser();
    expect(controller.activeSupplier, isNull);
    final future = controller.selectSupplier(idB);
    expect(controller.activeSupplier, isNull);
    expect(controller.stage, SupplierAccessStage.checking);
    delayedB.complete(access(idB, 'VIEWER'));
    await future;
    expect(controller.activeSupplier!.supplierId, idB);
    expect(controller.activeSupplier!.role.name, 'viewer');
    controller.dispose();
    clerk.state.dispose();
  });

  test('foreign supplier scope response is rejected', () async {
    final clerk = FakeClerk();
    final controller = makeController(clerk, MockClient((request) async {
      if (request.url.path == '/api/v2/me') return me([member(idA, 'OWNER')]);
      return access(idB, 'OWNER');
    }));
    await controller.start();
    clerk.login('user_SupplierOne', 'sess_SupplierOne');
    await until(controller, SupplierAccessStage.accessDenied);
    expect(controller.activeSupplier, isNull);
    controller.dispose();
    clerk.state.dispose();
  });

  test('late response from previous Clerk identity cannot restore access',
      () async {
    final clerk = FakeClerk();
    final delayed = Completer<http.Response>();
    var reads = 0;
    final controller = makeController(clerk, MockClient((request) async {
      if (request.url.path == '/api/v2/me') {
        reads++;
        if (reads == 1) {
          return await delayed.future;
        }
        return me([]);
      }
      return access(idA, 'OWNER');
    }));
    await controller.start();
    clerk.login('user_SupplierOne', 'sess_SupplierOne');
    for (var i = 0; i < 60 && reads == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(reads, 1);
    clerk.login('user_SupplierTwo', 'sess_SupplierTwo');
    await until(controller, SupplierAccessStage.noSupplier);
    delayed.complete(me([member(idA, 'OWNER')]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.stage, SupplierAccessStage.noSupplier);
    expect(controller.activeSupplier, isNull);
    controller.dispose();
    clerk.state.dispose();
  });

  test('resume/recheck immediately hides revoked supplier membership',
      () async {
    final clerk = FakeClerk();
    var revoked = false;
    final pending = Completer<http.Response>();
    final controller = makeController(clerk, MockClient((request) async {
      if (request.url.path == '/api/v2/me') {
        if (revoked) {
          return await pending.future;
        }
        return me([member(idA, 'OWNER')]);
      }
      return access(idA, 'OWNER');
    }));
    await controller.start();
    clerk.login('user_SupplierOne', 'sess_SupplierOne');
    await until(controller, SupplierAccessStage.authorized);
    revoked = true;
    final check = controller.refresh();
    expect(controller.activeSupplier, isNull);
    expect(controller.stage, SupplierAccessStage.checking);
    pending.complete(me([]));
    await check;
    expect(controller.stage, SupplierAccessStage.noSupplier);
    controller.dispose();
    clerk.state.dispose();
  });

  test('invalid Clerk session does not unlock supplier', () async {
    final clerk = FakeClerk();
    final controller = makeController(
        clerk,
        MockClient((_) async =>
            http.Response('{"error":{"code":"INVALID_SESSION"}}', 401)));
    await controller.start();
    clerk.login('user_SupplierOne', 'sess_SupplierOne');
    await until(controller, SupplierAccessStage.sessionExpired);
    expect(controller.activeSupplier, isNull);
    controller.dispose();
    clerk.state.dispose();
  });

  test('local logout clears access even if remote revocation is uncertain',
      () async {
    final clerk = FakeClerk()..remoteRevoked = false;
    final controller = makeController(clerk, MockClient((request) async {
      if (request.url.path == '/api/v2/me') return me([member(idA, 'OWNER')]);
      return access(idA, 'OWNER');
    }));
    await controller.start();
    clerk.login('user_SupplierOne', 'sess_SupplierOne');
    await until(controller, SupplierAccessStage.authorized);
    await controller.signOut();
    expect(controller.stage, SupplierAccessStage.signedOut);
    expect(controller.activeSupplier, isNull);
    expect(controller.notice, contains('not confirmed'));
    expect(clerk.signOutCalls, 1);
    controller.dispose();
    clerk.state.dispose();
  });
}
