import 'dart:math';
import '../api/supplier_v21_api.dart';
import '../catalog/supplier_catalog_models.dart';
import '../delivery/supplier_delivery_models.dart';
import 'supplier_rfq_models.dart';

/// Supplier quote requests only. Customer award, checkout and payment are
/// independent backend transitions and cannot be inferred from SUBMITTED.
class SupplierRfqRepository {
  const SupplierRfqRepository(this.client);
  final SupplierV21Api client;

  String _scope(String supplierId) =>
      '/api/v2/suppliers/${catalogId(supplierId)}/rfqs';

  Future<List<SupplierRfq>> invitations(String supplierId) async {
    final response = await client.get(_scope(supplierId));
    return rfqRecords(response.data, SupplierRfq.parse,
        (SupplierRfq rfq) => rfq.id);
  }

  Future<List<SupplierQuote>> quotes(
      String supplierId, String rfqId) async {
    final id = catalogId(rfqId);
    final response = await client.get('${_scope(supplierId)}/$id/quotes');
    return rfqRecords(response.data,
        (raw) => SupplierQuote.parse(raw, supplierId, id),
        (SupplierQuote quote) => quote.id, max: 50);
  }

  Future<SupplierQuote> submit({
    required String supplierId,
    required SupplierRfq rfq,
    required List<SupplierQuoteLineInput> lines,
    required String deliveryPaiseValue,
    required String? deliveryTerms,
    required String intent,
  }) async {
    if (!rfq.isWithinDeadline) {
      throw const FormatException('RFQ invitation has expired');
    }
    verifyQuotedLines(rfq, lines);
    deliveryPaise(deliveryPaiseValue);
    if (deliveryTerms != null && (deliveryTerms.isEmpty ||
        deliveryTerms.length > 500 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(deliveryTerms))) {
      throw const FormatException('Invalid quote delivery terms');
    }
    final envelope = (await client.request('POST',
        '${_scope(supplierId)}/${catalogId(rfq.id)}/quotes',
        idempotencyKey: intent,
        body: {
          'lines': lines.map((line) => line.toJson()).toList(growable: false),
          'deliveryPaise': deliveryPaiseValue,
          'deliveryTerms': deliveryTerms,
          'validUntil': null,
        })).data;
    final data = catalogObject(envelope);
    return SupplierQuote.parse(data['quote'], supplierId, rfq.id);
  }
}

/// One cryptographically strong key per create/revision intent.
String supplierQuoteIntent() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
