import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/v21/catalog/catalog_search_sheet.dart';
import 'package:vendor_app/v21/catalog/supplier_catalog_editor.dart';
import 'package:vendor_app/v21/catalog/supplier_catalog_models.dart';
import 'package:vendor_app/v21/catalog/supplier_catalog_repository.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';

const supplierId = '123e4567-e89b-12d3-a456-426614174000';
const cementCategoryId = '123e4567-e89b-12d3-a456-426614174030';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search picker filters and returns the selected backend value',
      (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            result = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const CatalogSearchSheet(
                title: 'Select product category',
                options: [
                  CatalogSearchOption('cement', 'Cement'),
                  CatalogSearchOption('steel', 'Steel'),
                  CatalogSearchOption('sand', 'Sand'),
                ],
              ),
            );
          },
          child: const Text('Open category picker'),
        )),
      ),
    ));
    await tester.tap(find.text('Open category picker'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('catalog-option-search')), 'ste');
    await tester.pumpAndSettle();
    expect(find.text('Steel'), findsOneWidget);
    expect(find.text('Cement'), findsNothing);
    await tester.tap(find.text('Steel'));
    await tester.pumpAndSettle();
    expect(result, 'steel');
    expect(tester.takeException(), isNull);
  });

  testWidgets('add product puts photo first and uses searchable selectors',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final api = SupplierV21Api(
      origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
      token: () async => 'test-only',
    );
    addTearDown(api.close);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SupplierListingEditor(
          supplierId: supplierId,
          repository: SupplierCatalogRepository(api),
          masters: const CatalogMasters(
            [CatalogCategory(cementCategoryId, 'Cement')],
            [CatalogUnit('BAG', 'Bag'), CatalogUnit('KG', 'Kilogram')],
          ),
        ),
      ),
    ));
    expect(find.text('PRODUCT PHOTO'), findsOneWidget);
    expect(find.text('Select category'), findsOneWidget);
    expect(find.textContaining('Select unit'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Select category'));
    await tester.pumpAndSettle();
    expect(find.text('Cement'), findsOneWidget);
    await tester.tap(find.text('Cement'));
    await tester.pumpAndSettle();
    expect(find.text('Cement'), findsOneWidget);

    await tester.ensureVisible(find.textContaining('Select unit'));
    await tester.tap(find.textContaining('Select unit'));
    await tester.pumpAndSettle();
    expect(find.text('Kilogram'), findsOneWidget);
    await tester.tap(find.text('Kilogram'));
    await tester.pumpAndSettle();
    expect(find.text('Kilogram'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
