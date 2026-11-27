import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/v21/customer_catalog.dart';
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

  testWidgets(
      'supplier heart saves and restores the same supplier on this device', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fixture = CustomerFixture();
    addTearDown(fixture.dispose);
    await pumpCustomer(tester, fixture, const SplyzoReferenceHome());
    final save = find.byTooltip('Save Shree Shyam Enterprises');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final remove =
        find.byTooltip('Remove Shree Shyam Enterprises from saved suppliers');
    expect(remove, findsOneWidget);
    expect(find.text('Nearby Suppliers'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpCustomer(tester, fixture, const SplyzoReferenceHome());
    expect(remove, findsOneWidget);
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(save, findsOneWidget);
  });

  testWidgets(
      'nearby directory uses the supplier photo and applies the 1 km radius', (
    tester,
  ) async {
    final fixture = CustomerFixture();
    addTearDown(fixture.dispose);
    fixture.session.chooseAddress({
      ...fixture.address,
      'latitude': '17.403',
      'longitude': '78.4',
    });
    await pumpCustomer(tester, fixture, const SplyzoReferenceHome());
    final directory = find
        .ancestor(
          of: find.text('Nearby Suppliers'),
          matching: find.byType(Row),
        )
        .first;
    final seeAll =
        find.descendant(of: directory, matching: find.text('See All'));
    await tester.ensureVisible(seeAll);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();

    expect(find.text('Within 1 km of your selected delivery address'),
        findsOneWidget);
    expect(find.text('Shree Shyam Enterprises'), findsOneWidget);
    expect(find.text('ABC Building Materials'), findsNothing);
    expect(find.text('334 m away'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) {
      final image = widget is Image ? widget.image : null;
      return image is NetworkImage &&
          image.url.endsWith('/api/v2/catalog/images/${id(72)}');
    }), findsOneWidget);
    final request = fixture.requests.lastWhere(
      (r) => r.url.path.endsWith('/catalog/suppliers'),
    );
    expect(request.url.queryParameters['latitude'], '17.4030000');
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

  testWidgets('categories open matching products and preserve browse state', (
    tester,
  ) async {
    final fixture = CustomerFixture();
    addTearDown(fixture.dispose);
    await pumpCustomer(
      tester,
      fixture,
      const CustomerHome(categoriesOnly: true),
      size: const Size(320, 680),
    );

    expect(find.text('Categories'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsNothing);
    expect(
      fixture.requests.any((r) => r.url.path == '/api/v2/catalog/products'),
      isFalse,
    );

    await tester.tap(find.text('Cement & concrete'));
    await tester.pumpAndSettle();
    expect(fixture.requests.last.url.queryParameters['categoryId'], id(3));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  cement  ');
    await tester.pump();
    await tester.tap(find.byTooltip('Search catalog'));
    await tester.pumpAndSettle();
    expect(find.text('Results for “cement”'), findsOneWidget);
    expect(fixture.requests.last.url.queryParameters['search'], 'cement');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Clear search'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile OTP waits for submission and verifies through identity', (
    tester,
  ) async {
    final fixture = CustomerFixture();
    addTearDown(fixture.dispose);
    fixture.session.user = null;
    await fixture.auth.signOut();
    fixture.auth.formHandler = (action, fields) async {
      if (action == 'sendOtp') {
        expect(fields['phone'], '+919876543210');
        return (step: 'verifyPhone', attempt: 'attempt_fixture');
      }
      expect(action, 'verifyOtp');
      expect(fields, {'attempt': 'attempt_fixture', 'code': '123456'});
      return (step: 'complete', attempt: null);
    };
    await pumpCustomer(tester, fixture, const SplyzoReferenceAuthScreen());

    final password = find.byKey(const Key('auth-field-Password'));
    await tester.ensureVisible(password);
    await tester.enterText(password, 'example-password');
    await tester.pumpAndSettle();
    expect(fixture.auth.authActions, isEmpty);

    final otp = find.text('Login with mobile OTP');
    await tester.ensureVisible(otp);
    await tester.tap(otp);
    await tester.pumpAndSettle();
    expect(password, findsNothing);

    await tester.enterText(
      find.byKey(const Key('auth-field-Mobile Number')),
      '98765 43210',
    );
    final submit = find.byKey(const Key('reference-login'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(fixture.auth.authActions, ['sendOtp']);
    expect(fixture.session.signedIn, isFalse);

    await tester.enterText(
      find.byKey(const Key('auth-field-Verification code')),
      '123456',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(fixture.auth.authActions, ['sendOtp', 'verifyOtp']);
    expect(fixture.session.signedIn, isTrue);
  });

  testWidgets('stalled Google sign-in can be cancelled and retried', (
    tester,
  ) async {
    final fixture = CustomerFixture();
    addTearDown(fixture.dispose);
    fixture.session.user = null;
    await fixture.auth.signOut();
    final pending = Completer<({String step, String? attempt})>();
    fixture.auth.formHandler = (action, _) {
      expect(action, 'google');
      return pending.future;
    };
    fixture.auth.onCancelSocialAuth = () async {
      pending.completeError(PlatformException(code: 'AUTH_CANCELLED'));
    };
    await pumpCustomer(tester, fixture, const SplyzoReferenceAuthScreen());

    final google = find.text('Google');
    await tester.ensureVisible(google);
    await tester.tap(google);
    await tester.pumpAndSettle();
    expect(find.text('Connecting to Google…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final cancel = find.text('Cancel sign-in');
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('Connecting to Google…'), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Google'),
            )
            .onPressed,
        isNotNull);
  });

  testWidgets('auth entry switches to signup and requires accepted terms', (
    tester,
  ) async {
    final fixture = CustomerFixture();
    fixture.session.user = null;
    await fixture.auth.signOut();
    fixture.auth.formHandler = (action, fields) async {
      expect(action, 'signUp');
      expect(fields, {
        'name': 'Example Customer',
        'email': 'customer@example.com',
        'password': 'example-password',
      });
      return (step: 'sendEmail', attempt: 'signup_fixture');
    };
    addTearDown(fixture.dispose);
    await pumpCustomer(tester, fixture, const SplyzoReferenceAuthScreen());
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('auth-switch-mode')));
    await tester.tap(find.byKey(const Key('auth-switch-mode')));
    await tester.pumpAndSettle();
    expect(find.text('Create Account'), findsOneWidget);
    final fullName = find.byKey(const Key('auth-field-Full Name'));
    await tester.ensureVisible(fullName);
    await tester.enterText(fullName, 'Example Customer');
    await tester.pumpAndSettle();
    expect(fixture.auth.authActions, isEmpty);
    await tester.ensureVisible(find.byKey(const Key('auth-terms-checkbox')));
    await tester.tap(find.byKey(const Key('auth-terms-checkbox')));
    await tester.pumpAndSettle();
    final checkbox = tester.widget<Checkbox>(
      find.byKey(const Key('auth-terms-checkbox')),
    );
    expect(checkbox.value, isTrue);

    for (final (label, value) in [
      ('Email', 'customer@example.com'),
      ('Password', 'example-password'),
      ('Confirm Password', 'example-password'),
    ]) {
      final field = find.byKey(Key('auth-field-$label'));
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }
    final submit = find.byKey(const Key('reference-signup'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(fixture.auth.authActions, ['signUp']);
    expect(find.text('Send a verification code to customer@example.com.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
