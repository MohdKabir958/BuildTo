
import '../api/supplier_v21_api.dart';
import '../catalog/supplier_catalog_models.dart';
import '../delivery/supplier_delivery_models.dart';

/// Money crosses the V2.1 wire exclusively as exact decimal integer paise.
/// UI cannot infer successful bank settlement from provider or journal state.
String financePaise(Object? value) {
  if (value is! String ||
      !RegExp(r'^(?:0|[1-9][0-9]{0,18})$').hasMatch(value) ||
      BigInt.parse(value) > BigInt.parse('9223372036854775807')) {
    throw const FormatException('Invalid exact paise amount');
  }
  return value;
}
String financeMoney(String paise) =>
    '₹${catalogRupeesFromPaise(financePaise(paise))}';

DateTime financeUtc(Object? value) {
  final raw = catalogString(value, max: 50);
  final parsed = DateTime.tryParse(raw);
  if (!raw.endsWith('Z') || parsed == null || !parsed.isUtc) {
    throw const FormatException('Expected a UTC timestamp');
  }
  return parsed;
}

String financeStatus(Object? raw, Set<String> choices) {
  if (raw is! String || !choices.contains(raw)) {
    throw const FormatException('Unknown financial state');
  }
  return raw;
}

class SupplierSettlementLine {
  const SupplierSettlementLine(this.supplierOrderId, this.netPaise);
  final String supplierOrderId, netPaise;
  factory SupplierSettlementLine.parse(Object? raw) {
    final j = catalogObject(raw);
    for (final key in ['grossPaise', 'commissionPaise', 'refundPaise', 'adjustmentPaise']) {
      financePaise(j[key]);
    }
    return SupplierSettlementLine(
      catalogId(j['supplierOrderId']), financePaise(j['netPaise']));
  }
}

class SupplierSettlement {
  const SupplierSettlement({
    required this.id, required this.status, required this.payoutState,
    required this.grossPaise, required this.commissionPaise,
    required this.refundPaise, required this.adjustmentPaise,
    required this.payablePaise, required this.lines, required this.createdAt,
  });
  final String id, status, payoutState, grossPaise, commissionPaise,
      refundPaise, adjustmentPaise, payablePaise;
  final List<SupplierSettlementLine> lines;
  final DateTime createdAt;
  factory SupplierSettlement.parse(Object? raw, String supplierId) {
    final j = catalogObject(raw);
    if (catalogId(j['supplierId']) != supplierId) {
      throw const FormatException('Foreign supplier settlement');
    }
    financeUtc(j['periodStart']);
    financeUtc(j['periodEnd']);
    final lines = deliveryRows(j['lines'], SupplierSettlementLine.parse,
        (SupplierSettlementLine x) => x.supplierOrderId);
    final transfers = j['transfers'];
    if (transfers is! List<dynamic> || transfers.length > 5) {
      throw const FormatException('Invalid settlement transfer history');
    }
    for (final record in transfers) {
      final r = catalogObject(record);
      catalogId(r['id']);
      financeStatus(r['status'], {'PENDING','PROCESSING','SUCCEEDED','FAILED'});
      financePaise(r['amountPaise']);
    }
    return SupplierSettlement(
      id: catalogId(j['id']),
      status: financeStatus(j['status'], {
        'OPEN','ON_HOLD','APPROVED','PROCESSING','PAID','FAILED','CANCELLED'
      }),
      payoutState: financeStatus(j['payoutState'], {
        'NOT_DISBURSED','DUPLICATE_PAYOUT_MANUAL_REVIEW',
        'PROVIDER_PROCESSED_BANK_STATEMENT_NOT_API_VERIFIED',
        'PAYOUT_INTENT_NOT_SENT','PROVIDER_PROCESSING',
        'PAYOUT_EXCEPTION_MANUAL_REVIEW'
      }),
      grossPaise: financePaise(j['grossPaise']),
      commissionPaise: financePaise(j['commissionPaise']),
      refundPaise: financePaise(j['refundPaise']),
      adjustmentPaise: financePaise(j['adjustmentPaise']),
      payablePaise: financePaise(j['payablePaise']),
      createdAt: financeUtc(j['createdAt']),
      lines: lines,
    );
  }
}

class SupplierReceivable {
  const SupplierReceivable(this.id, this.status,
      this.commissionPaise, this.offsetPaise);
  final String id, status, commissionPaise, offsetPaise;
  factory SupplierReceivable.parse(Object? raw) {
    final j = catalogObject(raw);
    catalogId(j['supplierOrderId']);
    financeUtc(j['createdAt']);
    final commission = financePaise(j['commissionPaise']);
    final offset = financePaise(j['offsetPaise']);
    if (BigInt.parse(offset) > BigInt.parse(commission)) {
      throw const FormatException('COD commission over-offset');
    }
    return SupplierReceivable(catalogId(j['id']),
        financeStatus(j['status'], {'OPEN','PARTIALLY_OFFSET','SETTLED','WRITTEN_OFF'}),
        commission, offset);
  }
}

class SupplierFinanceStatement {
  const SupplierFinanceStatement(this.settlements, this.receivables);
  final List<SupplierSettlement> settlements;
  final List<SupplierReceivable> receivables;
  factory SupplierFinanceStatement.parse(Object? raw, String supplierId) {
    final j = catalogObject(raw);
    if (j['bankingReconciled'] != false || j['payoutExecutionEnabled'] != false) {
      throw const FormatException('Unsupported bank status semantics');
    }
    return SupplierFinanceStatement(
      deliveryRows(j['settlements'],
        (row) => SupplierSettlement.parse(row, supplierId),
        (SupplierSettlement s) => s.id),
      deliveryRows(j['codCommissionReceivables'],
        SupplierReceivable.parse, (SupplierReceivable r) => r.id),
    );
  }
}

class SupplierInvoice {
  const SupplierInvoice({
    required this.id, required this.number, required this.kind,
    required this.status, required this.totalPaise,
    required this.taxablePaise, required this.taxPaise, required this.issuedAt,
  });
  final String id, number, kind, status, totalPaise, taxablePaise, taxPaise;
  final DateTime issuedAt;

  factory SupplierInvoice.parse(Object? raw, String supplierId, String orderId) {
    final j = catalogObject(raw);
    if (catalogId(j['supplierId']) != supplierId ||
        catalogId(j['supplierOrderId']) != orderId ||
        j['currency'] != 'INR') {
      throw const FormatException('Foreign or invalid invoice');
    }
    for (final key in ['cgstPaise','sgstPaise','utgstPaise','igstPaise','cessPaise']) {
      financePaise(j[key]);
    }
    return SupplierInvoice(
      id: catalogId(j['id']), number: catalogString(j['invoiceNumber'], max: 80),
      kind: financeStatus(j['kind'], {'TAX_INVOICE','BILL_OF_SUPPLY','CREDIT_NOTE','DEBIT_NOTE'}),
      status: financeStatus(j['status'], {'ISSUED','VOIDED','CREDITED'}),
      totalPaise: financePaise(j['totalPaise']),
      taxablePaise: financePaise(j['taxablePaise']),
      taxPaise: financePaise(j['taxPaise']),
      issuedAt: financeUtc(j['issuedAt']),
    );
  }
}

class SupplierCodReceipt {
  const SupplierCodReceipt({
    required this.id, required this.supplierOrderId,
    required this.receiptNumber, required this.collectedPaise,
    required this.status, required this.receivedAt,
  });
  final String id, supplierOrderId, receiptNumber, collectedPaise, status;
  final DateTime receivedAt;
  factory SupplierCodReceipt.parse(Object? raw, String supplierId, String orderId) {
    final j = catalogObject(raw);
    if (catalogId(j['supplierId']) != supplierId ||
        catalogId(j['supplierOrderId']) != orderId ||
        j['currency'] != 'INR') {
      throw const FormatException('Foreign COD receipt');
    }
    if (j['shipmentId'] != null) catalogId(j['shipmentId']);
    if (j['verifiedAt'] != null) financeUtc(j['verifiedAt']);
    return SupplierCodReceipt(
      id: catalogId(j['id']), supplierOrderId: orderId,
      receiptNumber: catalogString(j['receiptNumber'], max: 100),
      collectedPaise: financePaise(j['collectedPaise']),
      status: financeStatus(j['status'], {'RECORDED','VERIFIED','DISPUTED','REVERSED'}),
      receivedAt: financeUtc(j['receivedAt']),
    );
  }
}

class SupplierBeneficiary {
  const SupplierBeneficiary({
    required this.id, required this.maskedBank,
    required this.active, required this.verified,
  });
  final String id;
  final String? maskedBank;
  final bool active, verified;
  factory SupplierBeneficiary.parse(Object? raw, String supplierId) {
    final j = catalogObject(raw);
    if (catalogId(j['supplierId']) != supplierId ||
        j['active'] is! bool || j['bankValidationApproved'] is! bool ||
        j['externalPayoutExecutionOnly'] != true) {
      throw const FormatException('Invalid verified beneficiary');
    }
    final masked = j['maskedBankAccount'];
    if (masked != null &&
        (masked is! String || !RegExp(r'^\*{4}[0-9]{4}$').hasMatch(masked))) {
      throw const FormatException('Unmasked beneficiary account rejected');
    }
    if (j['verifiedAt'] != null) financeUtc(j['verifiedAt']);
    final verified = j['bankValidationApproved'] as bool;
    if (verified && j['active'] != true) {
      throw const FormatException('Invalid bank approval');
    }
    return SupplierBeneficiary(
      id: catalogId(j['id']), maskedBank: masked as String?,
      active: j['active'] as bool, verified: verified);
  }
}

class SupplierPayout {
  const SupplierPayout({
    required this.id, required this.amountPaise,
    required this.status, required this.meaning,
    required this.bankEvidenceType, required this.createdAt,
    this.maskedBank,
  });
  final String id, amountPaise, status, meaning, bankEvidenceType;
  final String? maskedBank;
  final DateTime createdAt;

  factory SupplierPayout.parse(Object? raw, String supplierId) {
    final j = catalogObject(raw);
    if (catalogId(j['supplierId']) != supplierId ||
        j['currency'] != 'INR' ||
        j['payoutExecutionByBuildtoApi'] != false ||
        j['bankEvidenceType'] != 'PROVIDER_ONLY') {
      throw const FormatException('Invalid payout evidence semantics');
    }
    final masked = j['maskedBankAccount'];
    if (masked != null &&
        (masked is! String || !RegExp(r'^\*{4}[0-9]{4}$').hasMatch(masked))) {
      throw const FormatException('Unsafe bank account display');
    }
    if (j['completedAt'] != null) financeUtc(j['completedAt']);
    final status = financeStatus(j['status'],
        {'PENDING','PROCESSING','SUCCEEDED','FAILED'});
    final meaning = financeStatus(j['payoutStatusMeaning'], {
      'RAZORPAYX_PROCESSED','AWAITING_EXTERNAL_ACTION','PROVIDER_REVIEW_REQUIRED'
    });
    if (status == 'SUCCEEDED' && meaning != 'RAZORPAYX_PROCESSED') {
      throw const FormatException('Inconsistent provider payout status');
    }
    catalogId(j['settlementId']);
    return SupplierPayout(
      id: catalogId(j['id']), amountPaise: financePaise(j['amountPaise']),
      status: status, meaning: meaning,
      bankEvidenceType: j['bankEvidenceType'] as String,
      createdAt: financeUtc(j['createdAt']), maskedBank: masked as String?);
  }
}

class SupplierCreditNote {
  const SupplierCreditNote(this.id, this.invoiceNumber, this.totalPaise);
  final String id, invoiceNumber, totalPaise;
  factory SupplierCreditNote.parse(Object? raw) {
    final j = catalogObject(raw);
    if (j['kind'] != 'CREDIT_NOTE' || j['currency'] != 'INR' ||
        j['status'] != 'ISSUED') {
      throw const FormatException('Credit note has not been issued');
    }
    catalogId(j['sourceInvoiceId']);
    catalogId(j['returnRequestId']);
    for (final key in ['taxablePaise','taxPaise','cgstPaise','sgstPaise',
      'utgstPaise','igstPaise','cessPaise']) {
      financePaise(j[key]);
    }
    return SupplierCreditNote(
      catalogId(j['id']),
      catalogString(j['invoiceNumber'], max: 80),
      financePaise(j['totalPaise']));
  }
}

/// S12 uses only existing V2.1 contracts. The server has sole authority for
/// taxes, GST invoice numbering, payment state, refunds and payouts.
class SupplierFinanceRepository {
  const SupplierFinanceRepository(this.client);
  final SupplierV21Api client;
  String _base(String supplierId) =>
      '/api/v2/suppliers/${catalogId(supplierId)}';

  Future<SupplierFinanceStatement> statement(String supplierId) async =>
      SupplierFinanceStatement.parse(
        (await client.get('${_base(supplierId)}/finance/statement')).data, supplierId);

  Future<List<SupplierBeneficiary>> beneficiaries(String supplierId) async =>
      deliveryRows(
        (await client.get('${_base(supplierId)}/finance/beneficiaries')).data,
        (value) => SupplierBeneficiary.parse(value, supplierId),
        (SupplierBeneficiary x) => x.id,
        max: 20);

  Future<List<SupplierPayout>> payouts(String supplierId) async =>
      deliveryRows(
        (await client.get('${_base(supplierId)}/finance/payouts')).data,
        (value) => SupplierPayout.parse(value, supplierId),
        (SupplierPayout x) => x.id);

  String _order(String supplierId, String orderId) =>
      '${_base(supplierId)}/orders/${catalogId(orderId)}';

  Future<List<SupplierInvoice>> invoices(String supplierId, String orderId) async =>
      deliveryRows(
        (await client.get('${_order(supplierId, orderId)}/invoices')).data,
        (value) => SupplierInvoice.parse(value, supplierId, orderId),
        (SupplierInvoice x) => x.id, max: 20);

  Future<SupplierInvoice> issueInvoice(String supplierId, String orderId) async =>
      SupplierInvoice.parse(
        (await client.request('POST', '${_order(supplierId, orderId)}/invoices',
          body: {})).data, supplierId, orderId);

  Future<List<SupplierCodReceipt>> codReceipts(String supplierId, String orderId) async =>
      deliveryRows(
        (await client.get('${_order(supplierId, orderId)}/cod')).data,
        (value) => SupplierCodReceipt.parse(value, supplierId, orderId),
        (SupplierCodReceipt x) => x.id, max: 50);

  Future<SupplierCodReceipt> recordCod({
    required String supplierId, required String orderId,
    required String shipmentId, required String receiptNumber,
    required String intent,
    String? note,
  }) async {
    catalogId(shipmentId);
    final normalized = receiptNumber.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9./_-]{2,99}$').hasMatch(normalized)) {
      throw const FormatException('Invalid COD receipt reference');
    }
    final cleaned = note?.trim();
    if (cleaned != null && cleaned.isNotEmpty &&
        (cleaned.length < 8 || cleaned.length > 300 ||
         cleaned.runes.any((c) => c < 32 || c == 127))) {
      throw const FormatException('Invalid COD receipt note');
    }
    final json = (await client.request('POST', '${_order(supplierId, orderId)}/cod',
      idempotencyKey: intent, body: {
        'shipmentId': shipmentId, 'receiptNumber': normalized,
        if (cleaned != null && cleaned.isNotEmpty) 'note': cleaned,
      })).data;
    return SupplierCodReceipt.parse(json, supplierId, orderId);
  }

  Future<SupplierCreditNote> issueCreditNote({
    required String supplierId, required String returnId,
  }) async {
    final raw = (await client.request('POST',
        '${_base(supplierId)}/returns/${catalogId(returnId)}/credit-note',
        body: {})).data;
    return SupplierCreditNote.parse(raw);
  }
}
