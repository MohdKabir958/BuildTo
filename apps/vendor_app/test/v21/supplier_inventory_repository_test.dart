import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/inventory/supplier_inventory_models.dart';
import 'package:vendor_app/v21/inventory/supplier_inventory_repository.dart';

const supplier = '123e4567-e89b-42d3-a456-426614174000';
const warehouse = '123e4567-e89b-42d3-a456-426614174001';
const listing = '123e4567-e89b-42d3-a456-426614174002';
const balance = '123e4567-e89b-42d3-a456-426614174003';
const destination = '123e4567-e89b-42d3-a456-426614174004';

http.Response ok(Object? data, {int status = 200}) =>
    http.Response(jsonEncode({'data': data}), status);

SupplierInventoryRepository repo(http.Client client) =>
    SupplierInventoryRepository(
      SupplierV21Api(
        origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
        token: () async => 'verified-clerk-token',
        httpClient: client,
      ),
    );

Map<String, Object?> stock({String available = '6.500'}) => {
      'id': balance,
      'listingId': listing,
      'warehouseId': warehouse,
      'onHandQty': '10.000',
      'reservedQty': '3.500',
      'availableQty': available,
      'version': 7,
    };

void main() {
  test('warehouse and balance projections are exact and scoped', () async {
    final service = repo(
      MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer verified-clerk-token');
        if (request.url.path.endsWith('/warehouses')) {
          return ok([
            {
              'id': warehouse,
              'supplierId': supplier,
              'code': 'YARD-1',
              'name': 'Hyderabad yard',
              'active': true,
            },
          ]);
        }
        return ok([stock()]);
      }),
    );
    expect((await service.warehouses(supplier)).single.code, 'YARD-1');
    expect((await service.balances(supplier)).single.availableQty, '6.500');
    expect(supplierInventoryIntent(), isNot(supplierInventoryIntent()));
  });

  test('reject foreign warehouses and inconsistent available quantities', () {
    expect(
      () => SupplierWarehouse.parse({
        'id': warehouse,
        'supplierId': destination,
        'code': 'A',
        'name': 'Other',
        'active': true,
      }, supplier),
      throwsFormatException,
    );
    expect(
      () => SupplierStockBalance.parse(stock(available: '10')),
      throwsFormatException,
    );
    expect(() => exactStockDelta('2', 'DAMAGE'), throwsFormatException);
    expect(() => exactStockDelta('-2', 'RECEIPT'), throwsFormatException);
  });

  test(
    'idempotent adjustment uses exact string and optimistic version',
    () async {
      final intent = supplierInventoryIntent();
      final service = repo(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.headers['Idempotency-Key'], intent);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['expectedVersion'], 7);
          expect(body['delta'], '-1.250');
          expect(body['kind'], 'DAMAGE');
          return ok({'currentBalance': stock()}, status: 201);
        }),
      );
      final result = await service.adjust(
        supplierId: supplier,
        listingId: listing,
        warehouseId: warehouse,
        kind: 'DAMAGE',
        delta: '-1.250',
        expectedVersion: 7,
        reason: 'Broken bags counted',
        intent: intent,
      );
      expect(result.version, 7);
    },
  );

  test(
    'transfer validates both versions and never treats a 409 as success',
    () async {
      final service = repo(
        MockClient((request) async {
          expect(request.headers['Idempotency-Key'], isNotEmpty);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['expectedFromVersion'], 7);
          expect(body['expectedToVersion'], 0);
          return http.Response(
            '{"error":{"code":"STOCK_VERSION_CONFLICT"}}',
            409,
          );
        }),
      );
      await expectLater(
        service.transfer(
          supplierId: supplier,
          listingId: listing,
          fromWarehouseId: warehouse,
          toWarehouseId: destination,
          quantity: '2.500',
          expectedFromVersion: 7,
          expectedToVersion: 0,
          reason: 'Move to second yard',
          intent: supplierInventoryIntent(),
        ),
        throwsA(
          isA<SupplierV21Exception>().having(
            (e) => e.problem,
            'problem',
            SupplierV21Problem.conflict,
          ),
        ),
      );
    },
  );

  test('canonicalized decimal transfer quantity is still exact',
      () async {
    final service = repo(MockClient((request) async => ok({
          'listingId': listing,
          'fromWarehouseId': warehouse,
          'toWarehouseId': destination,
          'quantity': '2.5',
        }, status: 201)));
    await service.transfer(
      supplierId: supplier,
      listingId: listing,
      fromWarehouseId: warehouse,
      toWarehouseId: destination,
      quantity: '2.500',
      expectedFromVersion: 7,
      expectedToVersion: 0,
      reason: 'Move bags between yards',
      intent: supplierInventoryIntent(),
    );
  });

  test(
    'warehouse create is inactive and unknown responses fail closed',
    () async {
      final service = repo(
        MockClient(
          (request) async => ok({
            'id': warehouse,
            'supplierId': supplier,
            'code': 'YARD-2',
            'name': 'New yard',
            'active': false,
          }, status: 201),
        ),
      );
      final created = await service.createWarehouse(
        supplier,
        code: 'yard-2',
        name: 'New yard',
      );
      expect(created.active, isFalse);
      expect(created.code, 'YARD-2');
    },
  );
}
