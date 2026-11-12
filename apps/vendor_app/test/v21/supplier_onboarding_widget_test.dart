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

const supplierId = '123e4567-e89b-12d3-a456-426614174000';
Map<String, Object?> summary({String approval = 'PENDING'}) => {
      'id': supplierId,
      'slug': 'materials-hub',
      'legalName': 'Materials Hub Pvt Ltd',
      'displayName': 'Materials Hub',
      'approval': approval,
      'gstRegistration': 'REGULAR',
      'gstin': '36ABCDE1234F1Z5',
      'createdAt': '2026-11-05T09:00:00.000Z',
      'verifiedAt': null,
      'suspendedAt': null,
    };

class ClerkFixture implements SupplierClerkPort {
  final identityValue = ValueNotifier<ClerkIdentity>(
      const ClerkIdentity(ready: true, signedIn: false));
  @override
  ValueListenable<ClerkIdentity> get identity => identityValue;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> authenticate({String mode = 'signInOrUp'}) async {
    identityValue.value = const ClerkIdentity(
        ready: true,
        signedIn: true,
        userId: 'user_SupplierTester',
        sessionId: 'sess_SupplierTester',
        email: 'owner@example.test');
    return true;
  }

  @override
  Future<String?> token({bool forceRefresh = false}) async =>
      'staging-test-token';
  @override
  Future<bool> signOut() async {
    identityValue.value = const ClerkIdentity(ready: true, signedIn: false);
    return true;
  }
}

Future<void> pumpAt(WidgetTester tester, Widget app, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Clerk applicant can submit registration then see actual pending status',
      (tester) async {
    final clerk = ClerkFixture();
    var submitted = false, posted = 0;
    final backend = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer staging-test-token');
      final path = request.url.path;
      if (path == '/api/v2/me') {
        return http.Response(
            jsonEncode({
              'data': {
                'id': 'user-db',
                'displayName': 'Supplier Tester',
                'suppliers': [],
              }
            }),
            200);
      }
      if (path == '/api/v2/me/supplier-applications') {
        return http.Response(
            jsonEncode({
              'data': submitted ? [summary()] : []
            }),
            200);
      }
      if (path == '/api/v2/me/supplier-applications/$supplierId') {
        return http.Response(
            jsonEncode({
              'data': {...summary(), 'documents': []}
            }),
            200);
      }
      if (path == '/api/v2/supplier-applications' && request.method == 'POST') {
        posted++;
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        expect(data['contactEmail'], 'owner@example.test');
        expect(data['slug'], 'materials-hub');
        expect(data['gstRegistration'], 'REGULAR');
        expect(data['billingAddress']['pinCode'], '500001');
        submitted = true;
        return http.Response(jsonEncode({'data': summary()}), 201);
      }
      return http.Response('{"error":{"code":"NOT_FOUND"}}', 404);
    });
    final api = SupplierV21Api(
        origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
        token: () => clerk.token(),
        httpClient: backend);
    final controller = SupplierAuthController(clerk: clerk, api: api);
    addTearDown(() {
      controller.dispose();
      clerk.identityValue.dispose();
    });
    await pumpAt(tester, BuildToSupplierV21App(controller: controller),
        const Size(393, 852));
    await tester.tap(find.text('Sign in to my account'));
    await tester.pumpAndSettle();
    expect(find.text('Your account is in review'), findsOneWidget);
    await tester.tap(find.text('Open supplier applications'));
    await tester.pumpAndSettle();
    expect(find.text('Grow with Splyzo'), findsOneWidget);
    expect(find.text('Your business'), findsOneWidget);
    Finder field(String label) =>
        find.byKey(ValueKey('supplier-registration-$label'));
    await tester.enterText(
        field('Registered legal name'), 'Materials Hub Pvt Ltd');
    await tester.enterText(field('Supplier display name'), 'Materials Hub');
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('GST & contact'), findsOneWidget);
    await tester.enterText(field('15-character GSTIN'), '36ABCDE1234F1Z5');
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Billing address'), findsOneWidget);
    await tester.enterText(
        field('Billing address line 1'), 'Industrial Estate Road 12');
    await tester.enterText(field('City'), 'Hyderabad');
    await tester.enterText(field('State'), 'Telangana');
    await tester.enterText(field('6-digit PIN'), '500001');
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Review & submit'), findsOneWidget);
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('Submit application'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit application'));
    await tester.pumpAndSettle();
    expect(posted, 1);
    expect(find.text('Application progress'), findsOneWidget);
    expect(find.text('Pending review'), findsOneWidget);
    expect(find.text('Document checklist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S03 entry is responsive and never displays approval as assumed',
      (tester) async {
    final clerk = ClerkFixture();
    final backend = MockClient((request) async {
      if (request.url.path == '/api/v2/me') {
        return http.Response(
            '{"data":{"id":"applicant","displayName":"Applicant","suppliers":[]}}',
            200);
      }
      return http.Response('{"data":[]}', 200);
    });
    final controller = SupplierAuthController(
        clerk: clerk,
        api: SupplierV21Api(
            origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
            token: () => clerk.token(),
            httpClient: backend));
    addTearDown(() {
      controller.dispose();
      clerk.identityValue.dispose();
    });
    await pumpAt(tester, BuildToSupplierV21App(controller: controller),
        const Size(320, 800));
    await tester.tap(find.text('Sign in to my account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open supplier applications'));
    await tester.pumpAndSettle();
    expect(find.text('Your business'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approved application opens the supplier home', (tester) async {
    final clerk = ClerkFixture();
    var membershipReady = false;
    final backend = MockClient((request) async {
      final path = request.url.path;
      if (path == '/api/v2/me') {
        return http.Response(
            jsonEncode({
              'data': {
                'id': 'user-db',
                'displayName': 'Supplier Tester',
                'suppliers': membershipReady
                    ? [
                        {'supplierId': supplierId, 'role': 'OWNER'}
                      ]
                    : [],
              }
            }),
            200);
      }
      if (path == '/api/v2/me/supplier-applications') {
        membershipReady = true;
        return http.Response(
            jsonEncode({
              'data': [summary(approval: 'APPROVED')]
            }),
            200);
      }
      if (path == '/api/v2/suppliers/$supplierId/access') {
        return http.Response(
            jsonEncode({
              'data': {'supplierId': supplierId, 'role': 'OWNER'}
            }),
            200);
      }
      return http.Response('{"error":{"code":"NOT_FOUND"}}', 404);
    });
    final controller = SupplierAuthController(
        clerk: clerk,
        api: SupplierV21Api(
            origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
            token: () => clerk.token(),
            httpClient: backend));
    addTearDown(() {
      controller.dispose();
      clerk.identityValue.dispose();
    });
    await pumpAt(tester, BuildToSupplierV21App(controller: controller),
        const Size(393, 852));
    await tester.tap(find.text('Sign in to my account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open supplier applications'));
    await tester.pumpAndSettle();
    expect(find.text('Supplier registration'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Catalog'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
