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
      await t.drag(find.byType(ListView).last, const Offset(0, -700));
      await t.pumpAndSettle();
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
    await t.tap(find.text('Saved delivery address'));
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
