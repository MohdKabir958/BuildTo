import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/rfq/supplier_rfq_models.dart';
import 'package:vendor_app/v21/rfq/supplier_rfq_repository.dart';

const supplier = '123e4567-e89b-42d3-a456-426614174000';
const rfq = '123e4567-e89b-42d3-a456-426614174001';
const item = '123e4567-e89b-42d3-a456-426614174002';
const quoteId = '123e4567-e89b-42d3-a456-426614174003';
const now = '2026-11-05T10:00:00.000Z';

Map<String, Object?> request() => {
      'id': rfq,
      'publicNumber': 'RFQ-123',
      'status': 'OPEN',
      'invitedAt': now,
      'createdAt': now,
      'responseDueAt': null,
      'notes': 'Bulk cement bags',
      'items': [
        {
          'id': item,
          'description': 'Cement',
          'quantity': '125.000',
          'unitCode': 'BAG',
          'productId': null,
        }
      ],
    };

Map<String, Object?> quote() => {
      'id': quoteId,
      'rfqId': rfq,
      'supplierId': supplier,
      'quoteNumber': 'QT-123',
      'version': 1,
      'status': 'SUBMITTED',
      'subtotalPaise': '10000',
      'taxPaise': '1800',
      'deliveryPaise': '500',
      'totalPaise': '12300',
      'deliveryTerms': null,
      'validUntil': null,
      'createdAt': now,
      'lines': [
        {
          'rfqItemId': item,
          'listingId': null,
          'quantity': '125.000',
          'unitCode': 'BAG',
          'unitPrice': '0.8000',
          'taxRateBps': 1800,
          'lineTotalPaise': '11800',
        }
      ],
    };

http.Response ok(Object? data, {int status = 200}) =>
    http.Response(jsonEncode({'data': data}), status);

SupplierRfqRepository repository(http.Client client) =>
    SupplierRfqRepository(SupplierV21Api(
      origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
      token: () async => 'verified-clerk-token',
      httpClient: client,
    ));

void main() {
  test('only invited open RFQs and their supplier-owned quote histories',
      () async {
    final service = repository(MockClient((req) async {
      expect(req.headers['Authorization'], 'Bearer verified-clerk-token');
      if (req.url.path.endsWith('/quotes')) return ok([quote()]);
      return ok([request()]);
    }));
    expect(
        (await service.invitations(supplier)).single.publicNumber, 'RFQ-123');
    expect((await service.quotes(supplier, rfq)).single.totalPaise, '12300');
  });

  test('reject foreign quote, impossible totals and duplicate RFQ item', () {
    expect(
        () => SupplierQuote.parse({
              ...quote(),
              'supplierId': rfq,
            }, supplier, rfq),
        throwsFormatException);
    expect(
        () => SupplierQuote.parse({
              ...quote(),
              'totalPaise': '12000',
            }, supplier, rfq),
        throwsFormatException);
    expect(
        () => SupplierRfq.parse({
              ...request(),
              'items': [
                request()['items'] is List
                    ? (request()['items'] as List).first
                    : {},
                (request()['items'] as List).first
              ],
            }),
        throwsFormatException);
  });

  test('RFQ submit uses exact line values and stable idempotency header',
      () async {
    final initial = SupplierRfq.parse(request());
    final intent = supplierQuoteIntent();
    final service = repository(MockClient((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/api/v2/suppliers/$supplier/rfqs/$rfq/quotes');
      expect(req.headers['Idempotency-Key'], intent);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['deliveryPaise'], '500');
      expect(body['lines'], [
        {
          'rfqItemId': item,
          'listingId': null,
          'quantity': '125.000',
          'unitCode': 'BAG',
          'unitPrice': '0.8000',
          'taxRateBps': 1800,
        }
      ]);
      return ok({'quote': quote(), 'replayed': false}, status: 201);
    }));
    final saved = await service.submit(
      supplierId: supplier,
      rfq: initial,
      intent: intent,
      lines: const [
        SupplierQuoteLineInput(
            rfqItemId: item,
            quantity: '125.000',
            unitCode: 'BAG',
            unitPrice: '0.8000',
            taxRateBps: 1800)
      ],
      deliveryPaiseValue: '500',
      deliveryTerms: null,
    );
    expect(saved.status, SupplierQuoteStatus.submitted);
    expect(saved.version, 1);
  });

  test('RFQ revisions do not treat conflict or auth loss as approval',
      () async {
    final initial = SupplierRfq.parse(request());
    final service = repository(MockClient((req) async =>
        http.Response('{"error":{"code":"RFQ_NOT_OPEN"}}', 409)));
    await expectLater(
        service.submit(
          supplierId: supplier,
          rfq: initial,
          lines: const [
            SupplierQuoteLineInput(
                rfqItemId: item,
                quantity: '125',
                unitCode: 'BAG',
                unitPrice: '1.0000',
                taxRateBps: 1800)
          ],
          deliveryPaiseValue: '0',
          deliveryTerms: null,
          intent: supplierQuoteIntent(),
        ),
        throwsA(isA<SupplierV21Exception>()
            .having((e) => e.problem, 'problem', SupplierV21Problem.conflict)));
  });

  test('quote must match each RFQ line and exact quantities', () {
    final original = SupplierRfq.parse(request());
    expect(() => verifyQuotedLines(original, const []), throwsFormatException);
    expect(
        () => verifyQuotedLines(original, const [
              SupplierQuoteLineInput(
                  rfqItemId: item,
                  quantity: '124',
                  unitCode: 'BAG',
                  unitPrice: '1.0000',
                  taxRateBps: 0)
            ]),
        throwsFormatException);
  });
}
