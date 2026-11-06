import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/finance/supplier_finance_repository.dart';

const supplier = '123e4567-e89b-42d3-a456-426614174000';
const order = '123e4567-e89b-42d3-a456-426614174001';
const settlement = '123e4567-e89b-42d3-a456-426614174002';
const invoiceId = '123e4567-e89b-42d3-a456-426614174003';
const shipment = '123e4567-e89b-42d3-a456-426614174004';
const receiptId = '123e4567-e89b-42d3-a456-426614174005';

http.Response ok(Object? data) =>
    http.Response(jsonEncode({'data': data}), 200);

SupplierFinanceRepository repo(http.Client transport) =>
    SupplierFinanceRepository(SupplierV21Api(
      origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
      token: () async => 'clerk-session',
      httpClient: transport,
    ));

Map<String, Object?> invoice() => {
  'id': invoiceId, 'supplierId': supplier, 'supplierOrderId': order,
  'invoiceNumber': 'BT/26-27/0001', 'financialYear': '2026-27',
  'kind': 'TAX_INVOICE', 'status': 'ISSUED', 'currency': 'INR',
  'taxablePaise': '100000', 'taxPaise': '18000', 'totalPaise': '118000',
  'cgstPaise': '9000', 'sgstPaise': '9000', 'utgstPaise': '0',
  'igstPaise': '0', 'cessPaise': '0',
  'issuedAt': '2026-11-06T09:00:00.000Z',
};

Map<String, Object?> codReceipt({String status = 'RECORDED'}) => {
  'id': receiptId, 'supplierId': supplier, 'supplierOrderId': order,
  'shipmentId': shipment, 'receiptNumber': 'CASH-123',
  'collectedPaise': '118000', 'currency': 'INR', 'status': status,
  'receivedAt': '2026-11-06T10:00:00.000Z', 'verifiedAt': null,
};

Map<String, Object?> statement() => {
  'settlements': [
    {'id': settlement, 'supplierId': supplier,
      'settlementKey': 'S1', 'periodStart': '2026-11-01T00:00:00.000Z',
      'periodEnd': '2026-11-06T00:00:00.000Z', 'status': 'OPEN',
      'grossPaise': '118000', 'commissionPaise': '11800',
      'refundPaise': '0', 'adjustmentPaise': '0', 'payablePaise': '106200',
      'payoutState': 'NOT_DISBURSED',
      'createdAt': '2026-11-06T09:00:00.000Z',
      'transfers': <Object>[],
      'lines': [{'supplierOrderId': order, 'grossPaise': '118000',
        'commissionPaise': '11800', 'refundPaise': '0',
        'adjustmentPaise': '0', 'netPaise': '106200'}]
    }
  ],
  'codCommissionReceivables': <Object>[],
  'bankingReconciled': false, 'payoutExecutionEnabled': false,
};

void main() {
  test('money is parsed only from exact integer paise', () {
    expect(financeMoney('118000'), '₹1180.00');
    for (final invalid in [118000, '1e5', '-1', '0.5', '9223372036854775808']) {
      expect(() => financePaise(invalid), throwsFormatException);
    }
  });

  test('finance statement is supplier-scoped and never bank-verified', () async {
    final service = repo(MockClient((request) async {
      expect(request.url.path, '/api/v2/suppliers/$supplier/finance/statement');
      expect(request.headers['Authorization'], 'Bearer clerk-session');
      return ok(statement());
    }));
    final result = await service.statement(supplier);
    expect(result.settlements.single.payablePaise, '106200');
    expect(result.settlements.single.payoutState, 'NOT_DISBURSED');
    expect(() => SupplierFinanceStatement.parse({
      ...statement(), 'bankingReconciled': true,
    }, supplier), throwsFormatException);
    final altered = statement();
    final rows = List<Map<String, Object?>>.from(altered['settlements'] as List);
    altered['settlements'] = [{...rows.single, 'supplierId': order}];
    expect(() => SupplierFinanceStatement.parse(altered, supplier),
      throwsFormatException);
  });

  test('GST invoice issue sends empty body; no client tax or pricing', () async {
    final service = repo(MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path,
        '/api/v2/suppliers/$supplier/orders/$order/invoices');
      expect(jsonDecode(request.body), <String, dynamic>{});
      return ok(invoice());
    }));
    final issued = await service.issueInvoice(supplier, order);
    expect(issued.taxPaise, '18000');
  });

  test('COD receipt is an unverified claim with fixed intent', () async {
    final service = repo(MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.headers['Idempotency-Key'], 'unique-cod-intent-11');
      expect(jsonDecode(request.body), {
        'shipmentId': shipment, 'receiptNumber': 'CASH-123',
      });
      return ok(codReceipt());
    }));
    final result = await service.recordCod(
      supplierId: supplier, orderId: order, shipmentId: shipment,
      receiptNumber: 'CASH-123', intent: 'unique-cod-intent-11');
    expect(result.status, 'RECORDED');
  });

  test('unknown finance statuses, raw bank account and crossed scope fail closed', () {
    expect(() => SupplierInvoice.parse({...invoice(), 'kind':'UNOFFICIAL'},
      supplier, order), throwsFormatException);
    expect(() => SupplierCodReceipt.parse({
      ...codReceipt(), 'supplierId': order,
    }, supplier, order), throwsFormatException);
    final beneficiary = {
      'id': invoiceId, 'supplierId': supplier, 'maskedBankAccount': '12345678',
      'active': true, 'bankValidationApproved': true,
      'externalPayoutExecutionOnly': true, 'verifiedAt': '2026-11-06T09:00:00.000Z'
    };
    expect(() => SupplierBeneficiary.parse(beneficiary, supplier),
      throwsFormatException);
  });

  test('verified payout provider is not bank credit', () {
    final payout = {
      'id': invoiceId, 'supplierId': supplier, 'settlementId': settlement,
      'currency': 'INR', 'amountPaise': '106200', 'status': 'SUCCEEDED',
      'payoutStatusMeaning': 'RAZORPAYX_PROCESSED',
      'payoutExecutionByBuildtoApi': false, 'bankEvidenceType': 'PROVIDER_ONLY',
      'maskedBankAccount': '****1234', 'completedAt': null,
      'createdAt': '2026-11-06T09:00:00.000Z',
    };
    final parsed = SupplierPayout.parse(payout, supplier);
    expect(parsed.meaning, 'RAZORPAYX_PROCESSED');
    expect(() => SupplierPayout.parse({
      ...payout, 'bankEvidenceType': 'BANK_VERIFIED',
    }, supplier), throwsFormatException);
  });
}
