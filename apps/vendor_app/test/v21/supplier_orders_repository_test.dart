import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/dashboard/supplier_dashboard_models.dart';
import 'package:vendor_app/v21/orders/supplier_orders_repository.dart';

const supplier = '123e4567-e89b-42d3-a456-426614174000';
const order = '123e4567-e89b-42d3-a456-426614174001';
const parent = '123e4567-e89b-42d3-a456-426614174002';
const line = '123e4567-e89b-42d3-a456-426614174003';

Map<String, Object?> orderDto({String status = 'PENDING_ACCEPTANCE'}) => {
  'id': order, 'purchaseOrderId': parent, 'status': status,
  'totalPaise': '150000', 'createdAt': '2026-11-05T10:00:00.000Z',
  'items': [{'id': line, 'sku':'CEMENT-43', 'quantity':'25.000',
    'unitCode':'BAG'}],
};

SupplierOrdersRepository repository(http.Client httpClient) =>
    SupplierOrdersRepository(SupplierV21Api(
      origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
      token: () async => 'verified-clerk-token', httpClient: httpClient,
    ));

http.Response ok(Object? data) => http.Response(jsonEncode({'data': data}),200);

void main() {
  test('supplier-scoped queue uses authenticated V2.1 route', () async {
    final repo = repository(MockClient((request) async {
      expect(request.url.path, '/api/v2/suppliers/$supplier/orders');
      expect(request.headers['Authorization'], 'Bearer verified-clerk-token');
      return ok([orderDto()]);
    }));
    final rows = await repo.orders(supplier);
    expect(rows.single.status, DashboardOrderStatus.pendingAcceptance);
    expect(rows.single.items.single.quantity, '25.000');
  });

  test('accept sends no financial assertions and checks server response',
      () async {
    final repo = repository(MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path.endsWith('/$order/accept'), isTrue);
      expect(jsonDecode(request.body), <String, dynamic>{});
      return ok({'id': order, 'status': 'CONFIRMED', 'replayed': false});
    }));
    final result = await repo.accept(supplier,order);
    expect(result.status, DashboardOrderStatus.confirmed);
  });

  test('only server can authorize refusal of unpaid orders', () async {
    final repo = repository(MockClient((request) async {
      expect(request.method, 'POST');
      expect(jsonDecode(request.body)['reason'], 'Buyer cancelled offline');
      return http.Response('{"error":{"code":"FINANCIAL_ADJUSTMENT_REQUIRED"}}',409);
    }));
    await expectLater(repo.rejectUnpaid(
      supplierId:supplier,supplierOrderId:order,
      reason:'Buyer cancelled offline',
    ), throwsA(isA<SupplierV21Exception>().having(
      (e)=>e.problem, 'status',SupplierV21Problem.conflict)));
  });

  test('invalid order payloads never appear in UI', () {
    expect(() => SupplierOrder.parse({...orderDto(), 'status':'MYSTERY'}),
      throwsFormatException);
    expect(() => SupplierOrder.parse({...orderDto(), 'totalPaise':150000}),
      throwsFormatException);
    expect(() => SupplierOrder.parse({...orderDto(), 'items':[]}),
      throwsFormatException);
    expect(() => SupplierOrderDecision.parse({
      'id':parent, 'status':'CONFIRMED', 'replayed':false,
    },order),throwsFormatException);
  });
}
