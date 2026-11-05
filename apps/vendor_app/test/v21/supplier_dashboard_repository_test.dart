import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/api/supplier_v21_models.dart';
import 'package:vendor_app/v21/dashboard/supplier_dashboard_models.dart';
import 'package:vendor_app/v21/dashboard/supplier_dashboard_repository.dart';

const supplierA = '123e4567-e89b-12d3-a456-426614174000';
const supplierB = '123e4567-e89b-12d3-a456-426614174001';
const orderA = '123e4567-e89b-12d3-a456-426614174010';
const orderB = '123e4567-e89b-12d3-a456-426614174011';
const listingA = '123e4567-e89b-12d3-a456-426614174020';
const warehouseA = '123e4567-e89b-12d3-a456-426614174030';
const rfqA = '123e4567-e89b-12d3-a456-426614174040';

Map<String, Object?> order(String id, String status) => {
  'id': id, 'status': status, 'totalPaise': '888800',
  'createdAt': '2026-11-05T09:00:00.000Z',
  'items': [
    {'id': supplierA, 'sku': 'CEMENT-43', 'quantity': '10', 'unitCode': 'BAG'}
  ],
};
Map<String, Object?> listing(String supplierId, bool active,
    {String status = 'APPROVED'}) => {
  'id': listingA, 'supplierId': supplierId, 'status': status, 'active': active,
};
Map<String, Object?> warehouse(String supplierId, bool active) => {
  'id': warehouseA, 'supplierId': supplierId, 'active': active,
};
Map<String, Object?> rfq() => {'id': rfqA, 'status': 'OPEN'};

SupplierDashboardRepository repo(http.Client client) => SupplierDashboardRepository(
  SupplierV21Api(
    origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
    token: () async => 'supplier-dashboard-fixture',
    httpClient: client,
  ),
);

http.Response response(Object data, {int status = 200}) =>
    http.Response(jsonEncode({'data': data, 'requestId': 'dashboard-request'}), status);

void main() {
  test('owner dashboard uses scoped GETs and honest per-section counts', () async {
    final paths = <String>[];
    final dashboard = repo(MockClient((request) async {
      paths.add(request.url.path);
      expect(request.method, 'GET');
      expect(request.headers['Authorization'], 'Bearer supplier-dashboard-fixture');
      switch (request.url.path) {
        case '/api/v2/suppliers/$supplierA/orders':
          return response([
            order(orderA, 'PENDING_ACCEPTANCE'),
            order(orderB, 'CONFIRMED'),
          ]);
        case '/api/v2/suppliers/$supplierA/listings':
          return response([listing(supplierA, true)]);
        case '/api/v2/suppliers/$supplierA/inventory/warehouses':
          return response([warehouse(supplierA, true)]);
        case '/api/v2/suppliers/$supplierA/rfqs':
          return response([rfq()]);
      }
      fail('Unexpected endpoint: ${request.url.path}');
    }));
    final result = await dashboard.load(
      supplierId: supplierA, role: SupplierV21Role.owner);
    expect(paths.toSet(), {
      '/api/v2/suppliers/$supplierA/orders',
      '/api/v2/suppliers/$supplierA/listings',
      '/api/v2/suppliers/$supplierA/inventory/warehouses',
      '/api/v2/suppliers/$supplierA/rfqs',
    });
    expect(result.awaitingAcceptance.label, '1');
    expect(result.inFulfillment.label, '1');
    expect(result.publishedListings.label, '1');
    expect(result.activeWarehouses.label, '1');
    expect(result.openInvitations?.label, '1');
    expect(result.recentOrders.map((x) => x.id), [orderA, orderB]);
    expect(result.sampleLimited, isFalse);
  });

  test('viewer has no RFQ read and does not show an invented zero', () async {
    final paths = <String>[];
    final dashboard = repo(MockClient((request) async {
      paths.add(request.url.path);
      return response([]);
    }));
    final data = await dashboard.load(
      supplierId: supplierA, role: SupplierV21Role.viewer);
    expect(paths.length, 3);
    expect(paths.any((path) => path.endsWith('/rfqs')), isFalse);
    expect(data.openInvitations, isNull);
    expect(data.awaitingAcceptance.label, '0');
    expect(data.recentOrders, isEmpty);
  });

  test('saturated orders only produce lower bounds, never fake lifetime totals', () async {
    final dashboard = repo(MockClient((request) async {
      if (request.url.path.endsWith('/orders')) {
        return response(List.generate(100, (index) => order(
          '123e4567-e89b-12d3-a456-${(100000000000 + index).toString()}',
          index.isEven ? 'PENDING_ACCEPTANCE' : 'DELIVERED',
        )));
      }
      return response([]);
    }));
    final data = await dashboard.load(
      supplierId: supplierA, role: SupplierV21Role.viewer);
    expect(data.awaitingAcceptance.label, '50+');
    expect(data.inFulfillment.label, '0+');
    expect(data.recentOrders.length, 5);
    expect(data.sampleLimited, isTrue);
  });

  test('a foreign supplier response cannot pollute the active dashboard', () async {
    final dashboard = repo(MockClient((request) async {
      if (request.url.path.endsWith('/listings')) {
        return response([listing(supplierB, true)]);
      }
      return response([]);
    }));
    await expectLater(
      dashboard.load(supplierId: supplierA, role: SupplierV21Role.viewer),
      throwsFormatException,
    );
  });

  test('unknown order status, duplicate records and malformed lists fail closed', () async {
    for (final badOrders in [
      [order(orderA, 'UNRECOGNIZED')],
      [order(orderA, 'CONFIRMED'), order(orderA, 'CONFIRMED')],
      {'not': 'a bounded order list'},
    ]) {
      final dashboard = repo(MockClient((request) async {
        if (request.url.path.endsWith('/orders')) return response(badOrders);
        return response([]);
      }));
      await expectLater(
        dashboard.load(supplierId: supplierA, role: SupplierV21Role.viewer),
        throwsFormatException,
      );
    }
  });

  test('401 cannot show data and invalid supplier IDs never trigger requests', () async {
    var calls = 0;
    final dashboard = repo(MockClient((request) async {
      calls++;
      return http.Response('{"error":{"code":"INVALID_SESSION"}}', 401);
    }));
    await expectLater(
      dashboard.load(supplierId: supplierA, role: SupplierV21Role.viewer),
      throwsA(isA<SupplierV21Exception>().having(
        (error) => error.problem, 'problem', SupplierV21Problem.authentication,
      )),
    );
    final previousCalls = calls;
    await expectLater(
      dashboard.load(supplierId: 'another-business', role: SupplierV21Role.viewer),
      throwsFormatException,
    );
    expect(calls, previousCalls);
  });

  test('RFQ permission changes do not trigger forbidden quotes for finance', () async {
    final paths = <String>[];
    final dashboard = repo(MockClient((request) async {
      paths.add(request.url.path);
      return response([]);
    }));
    await dashboard.load(supplierId: supplierA, role: SupplierV21Role.finance);
    expect(paths, hasLength(3));
    expect(paths.any((path) => path.contains('rfqs')), isFalse);
  });

  test('exact listing and warehouse flags do not count drafts or inactive sites', () async {
    final dashboard = repo(MockClient((request) async {
      if (request.url.path.endsWith('/listings')) {
        return response([listing(supplierA, false, status: 'DRAFT')]);
      }
      if (request.url.path.endsWith('/warehouses')) {
        return response([warehouse(supplierA, false)]);
      }
      return response([]);
    }));
    final data = await dashboard.load(
      supplierId: supplierA, role: SupplierV21Role.viewer);
    expect(data.publishedListings.label, '0');
    expect(data.activeWarehouses.label, '0');
  });
}
