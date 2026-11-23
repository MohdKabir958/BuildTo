import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/v21/customer_design.dart';
import 'package:customer_app/v21/customer_reference_auth.dart';
import 'package:customer_app/v21/customer_reference_home.dart';

import 'customer_fixture.dart';

Future<void> pumpCustomer(
  WidgetTester tester,
  CustomerFixture fixture,
  Widget child, {
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    CustomerScope(
      session: fixture.session,
      child: MaterialApp(
        theme: customerTheme(),
        home: Scaffold(body: SafeArea(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reference home displays native navy-orange sections from API', (
    tester,
  ) async {
    final fixture = CustomerFixture();
    addTearDown(fixture.dispose);
    await pumpCustomer(tester, fixture, const SplyzoReferenceHome());
    expect(find.text('Splyzo'), findsOneWidget);
    expect(find.text('Nearby Suppliers'), findsOneWidget);
    expect(find.text('Shop by Category'), findsOneWidget);
    expect(find.text('Best Deals Near You'), findsOneWidget);
    expect(find.text('Shree Shyam Enterprises'), findsOneWidget);
    expect(find.byKey(const Key('reference-category-Cement')), findsOneWidget);
    expect(find.textContaining('₹390'), findsWidgets);
    expect(
      fixture.requests.any((r) => r.url.path == '/api/v2/catalog/suppliers'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference home remains laid out at 320 pixel phone width', (
    tester,
  ) async {
    final fixture = CustomerFixture();
    addTearDown(fixture.dispose);
    await pumpCustomer(
      tester,
      fixture,
      const SplyzoReferenceHome(),
      size: const Size(320, 680),
    );
    expect(find.text('Nearby Suppliers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth entry switches to signup and requires accepted terms', (
    tester,
  ) async {
    final fixture = CustomerFixture();
    fixture.session.user = null;
    addTearDown(fixture.dispose);
    await pumpCustomer(tester, fixture, const SplyzoReferenceAuthScreen());
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('auth-switch-mode')));
    await tester.tap(find.byKey(const Key('auth-switch-mode')));
    await tester.pumpAndSettle();
    expect(find.text('Create Account'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('auth-terms-checkbox')));
    await tester.tap(find.byKey(const Key('auth-terms-checkbox')));
    await tester.pumpAndSettle();
    final checkbox = tester.widget<Checkbox>(
      find.byKey(const Key('auth-terms-checkbox')),
    );
    expect(checkbox.value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
