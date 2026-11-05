import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kraveo_ui/kraveo_ui.dart' show ClerkIdentity;
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/auth/supplier_auth_controller.dart';
import 'package:vendor_app/v21/auth/supplier_auth_gate.dart';
import 'package:vendor_app/v21/auth/supplier_clerk_port.dart';

const supplier = '123e4567-e89b-12d3-a456-426614174000';
const second = '123e4567-e89b-12d3-a456-426614174001';

class UiClerk implements SupplierClerkPort {
  final state = ValueNotifier<ClerkIdentity>(
      const ClerkIdentity(ready: true, signedIn: false));
  @override
  ValueListenable<ClerkIdentity> get identity => state;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> authenticate({String mode = 'signInOrUp'}) async {
    state.value = const ClerkIdentity(
        ready: true,
        signedIn: true,
        userId: 'user_SupplierTest',
        sessionId: 'sess_SupplierTest',
        email: 'supplier@example.invalid');
    return true;
  }

  @override
  Future<String?> token({bool forceRefresh = false}) async =>
      'widget-test-only';
  @override
  Future<bool> signOut() async {
    state.value = const ClerkIdentity(ready: true, signedIn: false);
    return true;
  }
}

SupplierAuthController makeController(UiClerk clerk, {bool multi = false}) {
  final api = SupplierV21Api(
    origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
    token: () => clerk.token(),
    httpClient: MockClient((request) async {
      if (request.url.path == '/api/v2/me') {
        return http.Response(
            jsonEncode({
              'data': {
                'id': 'db-account',
                'displayName': 'BuildTo Verified',
                'adminRole': null,
                'suppliers': [
                  {'supplierId': supplier, 'role': 'OWNER'},
                  if (multi) {'supplierId': second, 'role': 'VIEWER'},
                ],
              },
            }),
            200);
      }
      if (request.url.path.endsWith('/access')) {
        final id = request.url.path.split('/')[4];
        return http.Response(
            jsonEncode({
              'data': {
                'supplierId': id,
                'role': id == supplier ? 'OWNER' : 'VIEWER'
              }
            }),
            200);
      }
      return http.Response('{"error":{"code":"NOT_FOUND"}}', 404);
    }),
  );
  return SupplierAuthController(clerk: clerk, api: api);
}

Future<void> pumpPhone(WidgetTester tester, Widget child, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'BuildTo Clerk sign-in leads to backend-authorized supplier shell',
      (tester) async {
    final clerk = UiClerk();
    final controller = makeController(clerk);
    addTearDown(() {
      controller.dispose();
      clerk.state.dispose();
    });
    await pumpPhone(tester, BuildToSupplierV21App(controller: controller),
        const Size(393, 852));
    expect(find.text('Welcome to BuildTo Supplier'), findsOneWidget);
    await tester.tap(find.text('Continue securely with Clerk'));
    await tester.pumpAndSettle();
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('BuildTo Verified'), findsOneWidget);
    expect(find.textContaining('Supplier • '), findsOneWidget);
    expect(find.text('Orders'), findsWidgets);
    expect(find.textContaining('₹'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multi-supplier selection is explicit and shows verified role',
      (tester) async {
    final clerk = UiClerk();
    final controller = makeController(clerk, multi: true);
    addTearDown(() {
      controller.dispose();
      clerk.state.dispose();
    });
    await pumpPhone(tester, BuildToSupplierV21App(controller: controller),
        const Size(393, 852));
    await tester.tap(find.text('Continue securely with Clerk'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your supplier'), findsOneWidget);
    expect(find.text('Role: OWNER'), findsOneWidget);
    expect(find.text('Role: VIEWER'), findsOneWidget);
    await tester.tap(find.text('Role: VIEWER'));
    await tester.pumpAndSettle();
    expect(find.text('Verified'), findsOneWidget);
    expect(find.textContaining('VIEWER'), findsWidgets);
    await tester.tap(find.byTooltip('Supplier account actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch supplier'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your supplier'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clerk status and empty supplier permission state stay readable',
      (tester) async {
    for (final size in [
      const Size(320, 800),
      const Size(360, 800),
      const Size(412, 915)
    ]) {
      final clerk = UiClerk();
      final controller = makeController(clerk);
      await pumpPhone(
          tester, BuildToSupplierV21App(controller: controller), size);
      expect(find.text('Welcome to BuildTo Supplier'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      clerk.state.dispose();
    }
  });
}
