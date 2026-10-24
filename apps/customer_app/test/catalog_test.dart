import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/providers/dhaba_provider.dart';
import 'package:customer_app/models/sample_construction_data.dart';
import 'support/sample_catalog.dart';

void main() {
  group('Buildto Catalog Tests', () {
    late DhabaProvider provider;

    setUp(() {
      provider = sampleCatalogProvider();
    });

    test('offline demo catalog provides 54 products across 6 stores', () {
      expect(provider.allProducts.length, equals(54));
      expect(provider.allDhabas.length, equals(6));
      expect(provider.homeCategories.length, equals(9));
      expect(provider.isUsingFallbackData, isTrue);
      expect(provider.dataSourceLabel, contains('Offline'));
    });

    test('category filtering returns correct construction materials', () {
      final cementProducts = provider.productsForCategory('cat-cement');
      expect(cementProducts, isNotEmpty);
      for (final p in cementProducts) {
        expect(p.category.toLowerCase(), contains('cement'));
      }

      final steelProducts = provider.productsForCategory('cat-steel');
      expect(steelProducts, isNotEmpty);
      for (final p in steelProducts) {
        expect(p.category.toLowerCase(), contains('steel'));
      }
    });

    test('supplier resolution dynamically resolves depot name', () {
      final sampleProd = provider.allProducts.first;
      final supplierName = provider.supplierNameForProduct(sampleProd);
      expect(supplierName, isNotEmpty);
      // Ensure it does not return empty or fallback improperly
      expect(supplierName.length, greaterThan(2));
    });

    test('product lookup by id returns exact material', () {
      final p1 = provider.productById('prod-cem-ultratech');
      expect(p1, isNotNull);
      expect(p1!.name, contains('Ultratech'));

      final nonExistent = provider.productById('non-existent-id-999');
      expect(nonExistent, isNull);
    });

    test('all sample products have valid construction metadata', () {
      for (final p in provider.allProducts) {
        expect(p.id, isNotEmpty);
        expect(p.name, isNotEmpty);
        expect(p.price, greaterThan(0));
        expect(p.unit, isNotEmpty);
      }
    });
  });
}
