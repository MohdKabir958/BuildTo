import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/catalog/supplier_catalog_models.dart';
import 'package:vendor_app/v21/catalog/supplier_catalog_repository.dart';

const supplier = '123e4567-e89b-12d3-a456-426614174000';
const outsider = '123e4567-e89b-12d3-a456-426614174001';
const product = '123e4567-e89b-12d3-a456-426614174010';
const listingId = '123e4567-e89b-12d3-a456-426614174020';
const category = '123e4567-e89b-12d3-a456-426614174030';
const intent = '123e4567-e89b-42d3-a456-426614174040';

Map<String, Object?> row({
  String status = 'DRAFT', int version = 0,
  String owner = supplier,
}) => {
  'id': listingId, 'supplierId': owner, 'productId': product,
  'sku': 'CEMENT-43', 'unitCode': 'BAG', 'status': status,
  'active': status == 'APPROVED', 'version': version,
  'packSize': '1', 'minOrderQty': '10', 'stepQty': '5',
  'maxOrderQty': '100', 'unitPrice': '315.2500',
  'mrpPaise': '39900', 'taxRateBps': 1800,
  'taxInclusive': true, 'priceTiers': [],
};

const input = CatalogListingInput(
  productId: product, sku: 'CEMENT-43', unitCode: 'BAG',
  packSize: '1', minOrderQty: '10', stepQty: '5',
  maxOrderQty: '100', unitPrice: '315.2500',
  mrpPaise: '39900', taxRateBps: 1800, taxInclusive: true,
);
http.Response ok(Object object, {int code = 200}) =>
    http.Response(jsonEncode({'data': object}), code);
SupplierCatalogRepository repository(http.Client client) =>
    SupplierCatalogRepository(SupplierV21Api(
      origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
      token: () async => 's05-clerk-token', httpClient: client));

void main() {
  test('money and quantity remain exact decimal strings', () {
    expect(catalogScaled('315.2500', whole: 14, scale: 4), BigInt.from(3152500));
    expect(catalogScaled('10.500', whole: 15, scale: 3), BigInt.from(10500));
    expect(catalogInr('315.2500'), '₹315.25');
    expect(catalogInr('315.2575'), '₹315.2575');
    for (final bad in ['0', '-1', '1e9', '12.12345', '01.20', '1,200']) {
      expect(() => catalogPrice(bad), throwsFormatException);
    }
    expect(() => catalogQty('1.0000'), throwsFormatException);
    expect(input.toJson()['unitPrice'], '315.2500');
    expect(input.toJson()['mrpPaise'], '39900');
    expect(input.toJson()['taxRateBps'], 1800);
  });

  test('tier quantities and discounts are ordered without floating-point math', () {
    validateCatalogTiers([
      const CatalogTier('10', '300'),
      const CatalogTier('30', '280.2500'),
    ], minOrderQty: '10', unitPrice: '315.2500');
    for (final tiers in [
      [const CatalogTier('20', '300'), const CatalogTier('15', '290')],
      [const CatalogTier('10', '300'), const CatalogTier('30', '310')],
      [const CatalogTier('5', '300')],
    ]) {
      expect(() => validateCatalogTiers(tiers,
        minOrderQty: '10', unitPrice: '315.2500'), throwsFormatException);
    }
  });

  test('only own GET listing, paginated master catalogs and encoded filters', () async {
    final paths = <String>[];
    final service = repository(MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/listings')) {
        expect(request.headers['Authorization'], 'Bearer s05-clerk-token');
        return ok([row()]);
      }
      if (request.url.path.endsWith('/categories')) {
        return ok([{'id': category, 'name': 'Cement'}]);
      }
      if (request.url.path.endsWith('/units')) {
        return ok([{'code': 'BAG', 'name': 'Bags'}]);
      }
      expect(request.url.queryParameters, {
        'search': 'Portland cement', 'categoryId': category,
      });
      return ok({'items': [
        {'id': product, 'code': 'CEM-43', 'name': 'Portland cement',
        'category': {'id': category, 'name': 'Cement'},
        'brand': null, 'description': null},
      ], 'nextCursor': null});
    }));
    expect((await service.listings(supplier)).single.sku, 'CEMENT-43');
    final masters = await service.masters();
    expect(masters.categories.single.name, 'Cement');
    expect(masters.units.single.code, 'BAG');
    expect((await service.products(search: 'Portland cement',
      categoryId: category)).items.single.name, 'Portland cement');
    expect(paths.length, 4);
  });

  test('idempotent draft, optimistic edit, submit and tier PUT are separate calls',
      () async {
    var calls = 0;
    final service = repository(MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (calls == 1) {
        expect(request.method, 'POST');
        expect(request.headers['Idempotency-Key'], intent);
        expect(body['unitPrice'], '315.2500');
        expect(body.containsKey('expectedVersion'), isFalse);
        return ok(row(), code: 201);
      }
      if (calls == 2) {
        expect(request.method, 'PATCH');
        expect(body['expectedVersion'], 0);
        expect(body.containsKey('sku'), isFalse);
        expect(body.containsKey('productId'), isFalse);
        return ok(row(version: 1));
      }
      if (calls == 3) {
        expect(request.method, 'PUT');
        expect(body['expectedVersion'], 1);
        expect(body['tiers'], [{'minQty': '10', 'pricePerUnit': '300'}]);
        return ok(row(version: 2));
      }
      expect(request.method, 'POST');
      expect(request.url.path.endsWith('/submit'), isTrue);
      expect(body, {'expectedVersion': 2});
      return ok(row(status: 'PENDING', version: 3));
    }));
    final draft = await service.create(
      supplierId: supplier, input: input, idempotencyKey: intent);
    final edited = await service.update(
      supplierId: supplier, original: draft, input: input);
    final priced = await service.replaceTiers(supplierId: supplier,
      listing: edited, tiers: [const CatalogTier('10', '300')]);
    final submitted = await service.submit(
      supplierId: supplier, listing: priced);
    expect(submitted.status, CatalogListingStatus.pending);
    expect(submitted.active, isFalse);
    expect(calls, 4);
  });

  test('foreign supplier data and unknown review states are never trusted', () async {
    expect(() => CatalogListing.fromJson(row(owner: outsider), supplier),
      throwsFormatException);
    expect(() => CatalogListing.fromJson(row(status: 'UNKNOWN'), supplier),
      throwsFormatException);
    final service = repository(MockClient((request) async => ok([row(), row()])));
    await expectLater(service.listings(supplier), throwsFormatException);
  });

  test('authorization, versions, and admin approval remain server enforced',
      () async {
    final approved = CatalogListing.fromJson(row(status: 'APPROVED'), supplier);
    expect(approved.status.canEdit, isTrue);
    expect(approved.status.canSubmit, isFalse);
    expect(CatalogListing.fromJson(row(status: 'REJECTED'), supplier)
      .status.canSubmit, isTrue);
    final service = repository(MockClient((_) async =>
      http.Response('{"error":{"code":"LISTING_VERSION_CONFLICT"}}', 409)));
    await expectLater(service.update(
      supplierId: supplier, original: approved, input: input),
      throwsA(isA<SupplierV21Exception>().having((error) => error.problem,
        'problem', SupplierV21Problem.conflict)));
    await expectLater(service.submit(supplierId: supplier, listing: approved),
      throwsStateError);
  });
}
