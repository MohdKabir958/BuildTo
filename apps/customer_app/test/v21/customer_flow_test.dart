import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/v21/customer_app.dart';
import 'package:customer_app/v21/customer_catalog.dart';
import 'package:customer_app/v21/customer_checkout.dart';
import 'package:customer_app/v21/customer_orders.dart';
import 'package:customer_app/v21/customer_workspace.dart';
import 'package:customer_app/v21/customer_design.dart';
import 'customer_fixture.dart';

Future<void> fonts() async {
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  for (final entry in {
    'packages/kraveo_ui/Jakarta': 'PlusJakartaSans.ttf',
    'packages/kraveo_ui/Bricolage': 'BricolageGrotesque.ttf',
  }.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(
        rootBundle.load('packages/kraveo_ui/assets/fonts/${entry.value}'),
      );
    await loader.load();
  }
}

Future<void> page(
  WidgetTester t,
  CustomerFixture f,
  Widget child, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    CustomerScope(
      session: f.session,
      child: MaterialApp(
        theme: customerTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: child,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  final dir = Platform.environment['SPLYZO_CUSTOMER_CAPTURE_DIR'];
  if (dir == null) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await Directory(dir).create(recursive: true);
  await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
}

void main() {
  setUpAll(fonts);
  testWidgets(
    'home uses catalog and supplier directory, and offers add an exact minimum quantity to cart',
    (t) async {
      final f = CustomerFixture();
      addTearDown(f.dispose);
      await page(t, f, const Scaffold(body: SafeArea(child: CustomerHome())));
      expect(find.text('Good materials.\nGreat beginnings.'), findsOneWidget);
      expect(
        f.requests.any((r) => r.url.path == '/api/v2/catalog/suppliers'),
        isTrue,
      );
      await t.scrollUntilVisible(
        find.text('UltraTech Cement 50 kg'),
        400,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await t.ensureVisible(find.text('UltraTech Cement 50 kg'));
      await t.pumpAndSettle();
      await t.tap(find.text('UltraTech Cement 50 kg'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Add to cart'),
        400,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.text('10'), findsOneWidget);
      await t.ensureVisible(find.text('Add to cart'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add to cart'));
      await t.pumpAndSettle();
      expect(f.cartItems.single['quantity'], '10');
      expect(f.version, 4);
      expect(find.text('Review checkout'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'material details keep purchase controls reachable with large text',
    (t) async {
      final f = CustomerFixture();
      addTearDown(f.dispose);
      await page(
        t,
        f,
        ProductPage({
          'id': id(11),
          'name': 'UltraTech Portland Pozzolana Cement (50 kg bag)',
          'category': const {'name': 'Cement & Concrete'},
        }),
        size: const Size(320, 700),
        scale: 2,
      );
      expect(find.text('Add to cart').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Decrease quantity'), findsOneWidget);
      await t.tap(find.byTooltip('Increase quantity'));
      await t.pumpAndSettle();
      expect(find.text('15'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'cart steppers persist quantity and use the returned cart version',
    (t) async {
      final f = CustomerFixture();
      addTearDown(f.dispose);
      await f.api.setLine(id(12), '10', 3);
      await page(
        t,
        f,
        const CartPage(),
        size: const Size(320, 740),
        scale: 1.4,
      );
      await t.ensureVisible(find.byTooltip('Increase quantity'));
      await t.tap(find.byTooltip('Increase quantity'));
      await t.pumpAndSettle();
      expect(f.cartItems.single['quantity'], '15');
      expect(find.text('15 bag'), findsOneWidget);
      await t.ensureVisible(find.text('15 bag'));
      await t.tap(find.text('15 bag'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), '17');
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Save quantity'));
      await t.tap(find.text('Save quantity'));
      await t.pumpAndSettle();
      expect(f.version, 5);
      expect(find.text('Start at 10 and add 5 bag at a time.'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), '25');
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Save quantity'));
      await t.tap(find.text('Save quantity'));
      await t.pumpAndSettle();
      expect(f.cartItems.single['quantity'], '25');
      expect(f.version, 6);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'staging preview clears the checked-out cart without placing an order',
    (t) async {
      final f = CustomerFixture(
        origin: 'https://buildto-v21-staging.onrender.com',
        commissionBlocked: true,
      );
      addTearDown(f.dispose);
      await f.api.setLine(id(12), '10', 3);
      await page(t, f, const CartPage());
      await t.tap(find.text('Review checkout'));
      await t.pumpAndSettle();
      await t.tap(find.text('New home site'));
      await t.pumpAndSettle();
      final check = find.text('Check delivery & final price');
      await t.ensureVisible(check);
      await t.tap(check);
      await t.pumpAndSettle();
      expect(f.cartItems, hasLength(1));
      final place = find.text('Place demo order');
      await t.ensureVisible(place);
      await t.tap(place);
      await t.pumpAndSettle();
      expect(find.text('STAGING PREVIEW'), findsOneWidget);
      expect(find.text('Order placed'), findsOneWidget);
      expect(
        f.requests.where((request) => request.url.path.endsWith('/place')),
        isEmpty,
      );
      await t.tap(find.widgetWithText(FilledButton, 'Back'));
      await t.pumpAndSettle();
      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(f.cartItems, isEmpty);
      expect(f.version, 5);
    },
  );

  testWidgets('address form submits an Indian number without coordinates', (
    t,
  ) async {
    final f = CustomerFixture();
    addTearDown(f.dispose);
    await page(t, f, const AddressEditor());
    expect(find.textContaining('Latitude'), findsNothing);
    await t.tap(find.text('Delivery city *'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hyderabad').last);
    await t.pumpAndSettle();
    final labels = {
      'Address label': 'Home site',
      'Recipient name': 'Customer Test',
      'Mobile number': '98765 43210',
      'Building, plot or street': '12 Market Street',
      'Area or locality': 'Kondapur',
      'PIN code': '500084',
    };
    for (final entry in labels.entries) {
      final input = find.ancestor(
        of: find.widgetWithText(RequiredLabel, '${entry.key} *'),
        matching: find.byType(TextFormField),
      );
      if (input.evaluate().isEmpty) {
        await t.scrollUntilVisible(
          input,
          110,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await t.ensureVisible(input);
      await t.enterText(input, entry.value);
      await t.pump();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    final save = find.text('Save address');
    await t.ensureVisible(save);
    await t.tap(save);
    await t.pumpAndSettle();
    final request = f.requests.lastWhere((request) => request.method == 'POST');
    final body = jsonDecode(request.body) as Map;
    expect(body['phoneE164'], '+919876543210');
    expect(body.containsKey('latitude'), isFalse);
    expect(body.containsKey('longitude'), isFalse);
  });

  testWidgets(
    'cart checkout previews server total and places once with an idempotency key',
    (t) async {
      final f = CustomerFixture();
      addTearDown(f.dispose);
      await f.api.setLine(id(12), '10', 3);
      await page(t, f, const CartPage());
      await t.tap(find.text('Review checkout'));
      await t.pumpAndSettle();
      await t.tap(find.text('New home site'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Check delivery & final price'),
        300,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await t.tap(find.text('Check delivery & final price'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Place order · ₹3,950'),
        300,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await t.tap(find.text('Place order · ₹3,950'));
      await t.pumpAndSettle();
      final placement =
          f.requests.where((r) => r.url.path.endsWith('/place')).toList();
      expect(placement.length, 1);
      expect(placement.single.headers['idempotency-key'], isNotEmpty);
      expect(find.text('SP-2026-1042'), findsOneWidget);
      expect(find.text('Pending'), findsWidgets);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(
        f.requests.where((r) => r.url.path == '/api/v2/cart/clear'),
        isEmpty,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('support sends the actual backend message field', (t) async {
    final f = CustomerFixture();
    addTearDown(f.dispose);
    await page(t, f, ConversationPage(id(16)));
    await t.enterText(
      find.byType(TextField),
      'Please confirm the delivery date.',
    );
    await t.ensureVisible(find.text('Send reply'));
    await t.tap(find.text('Send reply'));
    await t.pumpAndSettle();
    expect(
      f.requests.lastWhere((r) => r.url.path.endsWith('/messages')).body,
      contains('"message":"Please confirm the delivery date."'),
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'sign-out disposes private detail routes and clears saved address',
    (t) async {
      final f = CustomerFixture();
      addTearDown(f.dispose);
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(SplyzoCustomerApp(session: f.session));
      await t.pumpAndSettle();
      await t.tap(find.text('Orders'));
      await t.pumpAndSettle();
      await t.tap(find.text('SP-2026-1042'));
      await t.pumpAndSettle();
      expect(find.text('Order details'), findsOneWidget);
      f.session.chooseAddress(f.address);
      await f.session.signOut();
      await t.pumpAndSettle();
      expect(find.text('Order details'), findsNothing);
      expect(f.session.user, isNull);
      expect(f.session.address, isNull);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'home, cart and order screens render at phone sizes with large text',
    (t) async {
      final f = CustomerFixture();
      addTearDown(f.dispose);
      await f.api.setLine(id(12), '10', 3);
      for (final child in [
        const Scaffold(body: SafeArea(child: CustomerHome())),
        const CartPage(),
        OrderPage(id(9)),
        const Scaffold(body: ProfilePage()),
      ]) {
        await page(t, f, child, size: const Size(320, 740), scale: 1.4);
        expect(t.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'category departments and long product prices fit narrow screens',
    (t) async {
      final fixture = CustomerFixture();
      addTearDown(fixture.dispose);
      final categories = [
        {'id': id(3), 'slug': 'tmt-steel-rebars', 'name': 'TMT Steel & Rebars'},
        {'id': id(5), 'slug': 'steel-tmt-bars', 'name': 'Steel & TMT Bars'},
        {
          'id': id(6),
          'slug': 'ready-mix-concrete',
          'name': 'Structural Ready Mix Concrete',
        },
      ];
      String? selection;
      for (final scale in [1.0, 1.4, 2.0]) {
        await page(
          t,
          fixture,
          Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                CategoryGrid(
                  categories: categories,
                  selected: selection,
                  onChanged: (value) => selection = value,
                ),
                ProductGrid(
                  products: [
                    for (final product in fixture.products)
                      {
                        ...product,
                        'fromPrice': '12345678.9876',
                        'fromUnit': 'CUBIC METRE',
                      },
                  ],
                  empty: '',
                ),
              ],
            ),
          ),
          size: const Size(320, 740),
          scale: scale,
        );
        expect(find.text('Steel & rebar'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.tap(find.text('Steel & rebar'));
        await t.pumpAndSettle();
        await t.tap(find.text('Steel & TMT Bars'));
        await t.pumpAndSettle();
        expect(selection, id(5));
        expect(t.takeException(), isNull);
      }
    },
  );

  testWidgets('bulk request opens and invites a chosen supplier', (t) async {
    final f = CustomerFixture();
    addTearDown(f.dispose);
    await page(t, f, NewRfqPage(product: f.products.first));
    await t.tap(find.text('Add material'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('BAG'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Saved delivery address *'));
    await t.pumpAndSettle();
    await t.tap(find.text('New home site · 500033').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Shree Shyam Enterprises'));
    await t.tap(find.text('Shree Shyam Enterprises'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Send to suppliers'));
    await t.tap(find.text('Send to suppliers'));
    await t.pumpAndSettle();
    final request = f.requests.firstWhere(
      (r) => r.url.path == '/api/v2/rfqs' && r.method == 'POST',
    );
    expect(jsonDecode(request.body)['siteSnapshot']['postalCode'], '500033');
    expect(jsonDecode(request.body)['items'].single['quantity'], '10');
    expect(
      f.requests.any((r) => r.url.path == '/api/v2/rfqs/${id(18)}/open'),
      isTrue,
    );
    expect(
      f.requests.any(
        (r) => r.url.path == '/api/v2/rfqs/${id(18)}/invitations/${id(6)}',
      ),
      isTrue,
    );
    expect(find.text('Waiting for supplier quotations'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('capture home cart and order UI using isolated fixtures', (
    t,
  ) async {
    final f = CustomerFixture();
    addTearDown(f.dispose);
    await f.api.setLine(id(12), '10', 3);
    for (final entry in <String, Widget>{
      'customer-home': const CustomerShell(),
      'customer-material-detail': ProductPage(f.products.first),
      'customer-cart': const CartPage(),
      'customer-order': OrderPage(id(9)),
    }.entries) {
      await page(
        t,
        f,
        RepaintBoundary(key: const ValueKey('capture'), child: entry.value),
      );
      await t.runAsync(() => capture(t, entry.key));
      expect(t.takeException(), isNull);
    }
  });
}
