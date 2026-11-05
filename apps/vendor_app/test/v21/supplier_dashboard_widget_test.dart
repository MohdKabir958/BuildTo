import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/api/supplier_v21_models.dart';
import 'package:vendor_app/v21/dashboard/supplier_dashboard_repository.dart';
import 'package:vendor_app/v21/dashboard/supplier_dashboard_view.dart';
import 'package:vendor_app/v21/design/buildto_theme.dart';
import 'package:vendor_app/v21/screens/supplier_shell.dart';

const supplier = '123e4567-e89b-12d3-a456-426614174000';
const orderId = '123e4567-e89b-12d3-a456-426614174013';

http.Response data(Object value, {int status = 200}) =>
    http.Response(jsonEncode({'data': value}), status);

class TestDashboard {
  TestDashboard({this.denied = false});
  bool denied;
  int requests = 0;

  late final api = SupplierV21Api(
    origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
    token: () async => 'mock-clerk-session',
    httpClient: MockClient((request) async {
      requests++;
      if (denied) {
        return http.Response('{"error":{"code":"ACCESS_DENIED"}}', 403);
      }
      if (request.url.path.endsWith('/orders')) {
        return data([
          {
            'id': orderId,
            'status': 'PENDING_ACCEPTANCE',
            'createdAt': '2026-11-05T08:00:00.000Z',
            'items': [
              {'id': orderId}
            ],
          }
        ]);
      }
      if (request.url.path.endsWith('/listings')) {
        return data([
          {
            'id': orderId,
            'supplierId': supplier,
            'status': 'APPROVED',
            'active': true,
          }
        ]);
      }
      if (request.url.path.endsWith('/warehouses')) {
        return data([
          {
            'id': orderId,
            'supplierId': supplier,
            'active': true,
          }
        ]);
      }
      if (request.url.path.endsWith('/rfqs')) return data([]);
      return http.Response('{"error":{"code":"NOT_FOUND"}}', 404);
    }),
  );
  SupplierDashboardRepository get repository =>
      SupplierDashboardRepository(api);
}

Future<void> phone(WidgetTester tester, Widget child, Size size,
    {double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
    child: MaterialApp(
      theme: BuildToTheme.light(),
      home: Scaffold(
        body: SafeArea(child: child),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'responsive verified dashboard uses only genuine recorded metrics',
      (tester) async {
    for (final size in [
      const Size(320, 800),
      const Size(360, 800),
      const Size(393, 852),
      const Size(412, 915),
    ]) {
      final backend = TestDashboard();
      await phone(
          tester,
          SupplierDashboardView(
            key: ValueKey('dashboard-${size.width}'),
            supplierId: supplier,
            role: SupplierV21Role.viewer,
            repository: backend.repository,
            onNavigate: (_) {},
          ),
          size);
      expect(find.text('Your supplier overview'), findsOneWidget);
      expect(find.text('Business at a glance'), findsOneWidget);
      expect(find.text('Awaiting acceptance'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('Open RFQ invites'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
      expect(find.text('Revenue'), findsNothing);
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('navigation cards lead to the requested workspace',
      (tester) async {
    final backend = TestDashboard();
    final tabs = <DashboardDestination>[];
    await phone(
        tester,
        SupplierDashboardView(
          supplierId: supplier,
          role: SupplierV21Role.owner,
          repository: backend.repository,
          onNavigate: tabs.add,
        ),
        const Size(393, 852));
    await tester.scrollUntilVisible(
      find.text('Orders & fulfillment'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orders & fulfillment'));
    expect(tabs, [DashboardDestination.orders]);
    await tester.scrollUntilVisible(
      find.text('Product catalog'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Product catalog'));
    expect(tabs.last, DashboardDestination.catalog);
  });

  testWidgets('403 refresh removes all previously shown metrics and orders',
      (tester) async {
    final backend = TestDashboard();
    await phone(
        tester,
        SupplierDashboardView(
          supplierId: supplier,
          role: SupplierV21Role.viewer,
          repository: backend.repository,
          onNavigate: (_) {},
        ),
        const Size(393, 852));
    expect(find.text('Awaiting acceptance'), findsOneWidget);
    backend.denied = true;
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard unavailable'), findsOneWidget);
    expect(find.text('Awaiting acceptance'), findsNothing);
    expect(
        find.textContaining('Recheck your active membership'), findsOneWidget);
    expect(find.byKey(const Key('supplier-dashboard-loaded')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verified shell switches to Orders tab via dashboard hero CTA',
      (tester) async {
    final backend = TestDashboard();
    const membership = SupplierV21Membership(
      supplierId: supplier,
      role: SupplierV21Role.viewer,
    );
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: BuildToTheme.light(),
      home: BuildToSupplierShell(
        verifiedSupplier: membership,
        dashboardRepository: backend.repository,
        displayName: 'Approved supplier',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Your supplier overview'), findsOneWidget);
    await tester.tap(find.text('Review orders'));
    await tester.pumpAndSettle();
    expect(find.text('Supplier orders'), findsOneWidget);
    expect(find.text('Supplier access verified'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide text scaling does not overflow the compact metrics',
      (tester) async {
    final backend = TestDashboard();
    await phone(
        tester,
        SupplierDashboardView(
          supplierId: supplier,
          role: SupplierV21Role.viewer,
          repository: backend.repository,
          onNavigate: (_) {},
        ),
        const Size(320, 800),
        scale: 1.5);
    await tester.scrollUntilVisible(
      find.text('Business at a glance'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Business at a glance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
