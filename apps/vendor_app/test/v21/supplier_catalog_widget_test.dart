import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/api/supplier_v21_models.dart';
import 'package:vendor_app/v21/catalog/supplier_catalog_repository.dart';
import 'package:vendor_app/v21/design/buildto_theme.dart';
import 'package:vendor_app/v21/screens/supplier_shell.dart';

const supplier = '123e4567-e89b-12d3-a456-426614174000';
const listingId = '123e4567-e89b-12d3-a456-426614174010';
const product = '123e4567-e89b-12d3-a456-426614174020';

http.Response data(Object object) =>
    http.Response(jsonEncode({'data': object}), 200);

class CatalogServer {
  bool forbidden = false;
  int reads = 0;
  late final api = SupplierV21Api(
    origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
    token: () async => 'clerk-widget-session',
    httpClient: MockClient((req) async {
      reads++;
      if (forbidden) {
        return http.Response('{"error":{"code":"MEMBERSHIP_REVOKED"}}', 403);
      }
      if (req.url.path.endsWith('/listings')) {
        return data([
          {
            'id': listingId,
            'productId': product,
            'supplierId': supplier,
            'sku': 'CEMENT-43',
            'unitCode': 'BAG',
            'packSize': '1',
            'minOrderQty': '10',
            'stepQty': '5',
            'maxOrderQty': null,
            'unitPrice': '315.2500',
            'mrpPaise': null,
            'taxRateBps': 1800,
            'taxInclusive': true,
            'status': 'DRAFT',
            'active': false,
            'version': 0,
            'priceTiers': [],
          }
        ]);
      }
      if (req.url.path.endsWith('/categories')) {
        return data([
          {
            'id': '123e4567-e89b-12d3-a456-426614174030',
            'name': 'Cement',
          }
        ]);
      }
      if (req.url.path.endsWith('/units')) {
        return data([
          {'code': 'BAG', 'name': 'Bag'}
        ]);
      }
      return http.Response('{"error":{"code":"NOT_FOUND"}}', 404);
    }),
  );
  SupplierCatalogRepository get repo => SupplierCatalogRepository(api);
}

Future<void> buildShell(
    WidgetTester tester, CatalogServer server, SupplierV21Role role,
    {Size size = const Size(393, 852), double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    theme: BuildToTheme.light(),
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: BuildToSupplierShell(
      verifiedSupplier: SupplierV21Membership(supplierId: supplier, role: role),
      catalogRepository: server.repo,
      displayName: 'BuildTo Material Supplier',
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Catalog').last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> showFirstListing(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('CEMENT-43'),
      180,
      scrollable: find.descendant(
        of: find.byKey(const Key('supplier-catalog-loaded')),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('professional owner catalog shows real rows and create control',
      (tester) async {
    final server = CatalogServer();
    await buildShell(tester, server, SupplierV21Role.owner);
    expect(find.text('Material catalog'), findsOneWidget);
    await showFirstListing(tester);
    expect(find.text('CEMENT-43'), findsOneWidget);
    expect(find.textContaining('₹315.25'), findsWidgets);
    expect(find.text('Draft'), findsWidgets);
    expect(find.text('Add material listing'), findsOneWidget);
    expect(server.reads, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewer catalog has no create, edit or submission privileges',
      (tester) async {
    final server = CatalogServer();
    await buildShell(tester, server, SupplierV21Role.viewer);
    await showFirstListing(tester);
    expect(find.text('CEMENT-43'), findsOneWidget);
    expect(find.text('Add material listing'), findsNothing);
    expect(server.reads, 1);
    await tester.tap(find.text('CEMENT-43'));
    await tester.pumpAndSettle();
    expect(find.text('Listing details'), findsOneWidget);
    expect(find.text('Edit listing'), findsNothing);
    expect(find.text('Submit for admin review'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('403 on refresh hides previously loaded listing immediately',
      (tester) async {
    final server = CatalogServer();
    await buildShell(tester, server, SupplierV21Role.catalog);
    await showFirstListing(tester);
    expect(find.text('CEMENT-43'), findsOneWidget);
    server.forbidden = true;
    await tester.tap(find.byTooltip('Refresh supplier listings'));
    await tester.pumpAndSettle();
    expect(find.text('Catalog unavailable'), findsOneWidget);
    expect(find.text('CEMENT-43'), findsNothing);
    expect(find.byKey(const Key('catalog-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px phone and larger text keep catalog readable',
      (tester) async {
    final server = CatalogServer();
    await buildShell(tester, server, SupplierV21Role.viewer,
        size: const Size(320, 800), scale: 1.5);
    expect(find.text('Material catalog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
