import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/care/supplier_care_repository.dart';

const supplier = '123e4567-e89b-42d3-a456-426614174000';
const order = '123e4567-e89b-42d3-a456-426614174001';
const other = '123e4567-e89b-42d3-a456-426614174002';
const returnId = '123e4567-e89b-42d3-a456-426614174003';
const item = '123e4567-e89b-42d3-a456-426614174004';
const reviewId = '123e4567-e89b-42d3-a456-426614174005';
const customer = '123e4567-e89b-42d3-a456-426614174006';

Map<String, Object?> returnDto({String status = 'APPROVED'}) => {
      'id': returnId,
      'supplierOrderId': order,
      'customerId': customer,
      'reason': 'Damaged cement bags',
      'status': status,
      'resolutionNote': null,
      'createdAt': '2026-11-06T05:00:00.000Z',
      'updatedAt': '2026-11-06T06:00:00.000Z',
      'items': [
        {'orderItemId': item, 'quantity': '2.500'}
      ],
      'evidenceMediaIds': <String>[],
      'financialStatus': 'NOT_REFUNDED',
    };
Map<String, Object?> reviewDto() => {
      'id': reviewId,
      'customerId': customer,
      'supplierOrderId': order,
      'supplierId': supplier,
      'rating': 4,
      'comment': 'Material delivered as described',
      'status': 'PENDING',
      'createdAt': '2026-11-06T06:00:00.000Z',
    };
http.Response ok(Object? data) =>
    http.Response(jsonEncode({'data': data}), 200);
SupplierCareRepository repo(http.Client client) =>
    SupplierCareRepository(SupplierV21Api(
      origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
      token: () async => 'verified-clerk-token',
      httpClient: client,
    ));

void main() {
  test('fetch own supplier order returns and private evidence count', () async {
    final service = repo(MockClient((req) async {
      expect(req.url.path, '/api/v2/suppliers/$supplier/orders/$order/returns');
      expect(req.headers['Authorization'], 'Bearer verified-clerk-token');
      return ok([returnDto()]);
    }));
    final items = await service.returns(supplier, order);
    expect(items.single.status, SupplierReturnStatus.approved);
    expect(items.single.items.single.quantity, '2.500');
    expect(items.single.evidenceCount, 0);
  });

  test('physically receive approved claim but never process refund', () async {
    final service = repo(MockClient((req) async {
      expect(req.url.path,
          '/api/v2/suppliers/$supplier/returns/$returnId/receive');
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), <String, dynamic>{});
      return ok({
        'id': returnId,
        'status': 'RECEIVED',
        'replayed': false,
        'financialStatus': 'NOT_REFUNDED'
      });
    }));
    await service.receive(
        supplierId: supplier, item: SupplierReturn.parse(returnDto(), order));
  });

  test('receipt cannot bypass independent review', () async {
    final service = repo(MockClient((req) async =>
        http.Response('{"error":{"code":"RETURN_NOT_APPROVED"}}', 409)));
    await expectLater(
        service.receive(
            supplierId: supplier,
            item: SupplierReturn.parse(returnDto(status: 'REQUESTED'), order)),
        throwsStateError);
    await expectLater(
        service.receive(
            supplierId: supplier,
            item: SupplierReturn.parse(returnDto(), order)),
        throwsA(isA<SupplierV21Exception>()
            .having((e) => e.problem, 'problem', SupplierV21Problem.conflict)));
  });

  test('return finances, ownership and unknown reviews fail closed', () {
    expect(
        () => SupplierReturn.parse({
              ...returnDto(),
              'financialStatus': 'REFUNDED',
            }, order),
        throwsFormatException);
    expect(
        () => SupplierReturn.parse({
              ...returnDto(),
              'supplierOrderId': other,
            }, order),
        throwsFormatException);
    expect(
        () => SupplierCustomerReview.parse({
              ...reviewDto(),
              'status': 'UNKNOWN',
            }, supplier),
        throwsFormatException);
    expect(
        () => SupplierCustomerReview.parse({
              ...reviewDto(),
              'supplierId': other,
            }, supplier),
        throwsFormatException);
  });

  test('supplier reviews are read-only and moderation-aware', () async {
    final service = repo(MockClient((req) async {
      expect(req.url.path, '/api/v2/suppliers/$supplier/reviews/manage');
      return ok([reviewDto()]);
    }));
    final reviews = await service.reviews(supplier);
    expect(reviews.single.status, SupplierReviewStatus.pending);
    expect(reviews.single.rating, 4);
  });
}
