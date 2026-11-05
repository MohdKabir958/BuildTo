import '../catalog/supplier_catalog_models.dart';
import '../delivery/supplier_delivery_models.dart';

DateTime rfqTimestamp(Object? input) {
  final value = catalogString(input, max: 50);
  if (!value.endsWith('Z')) {
    throw const FormatException('Expected a UTC RFQ timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException('Invalid RFQ timestamp');
  }
  return parsed;
}

String rfqMoney(String amount) =>
    '₹${catalogRupeesFromPaise(deliveryPaise(amount))}';

List<T> rfqRecords<T>(
    Object? raw, T Function(Object?) parse, String Function(T) identity,
    {int max = 100}) {
  if (raw is! List<dynamic> || raw.length > max) {
    throw const FormatException('Invalid bounded RFQ data');
  }
  final rows = raw.map(parse).toList(growable: false);
  if (rows.map(identity).toSet().length != rows.length) {
    throw const FormatException('Duplicate RFQ identity');
  }
  return List.unmodifiable(rows);
}

class SupplierRfqItem {
  const SupplierRfqItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unitCode,
    this.productId,
    required this.specification,
  });
  final String id, description, quantity, unitCode;
  final String? productId;
  final Map<String, Object> specification;

  factory SupplierRfqItem.parse(Object? raw) {
    final data = catalogObject(raw);
    final unit = catalogString(data['unitCode'], max: 20);
    final specification = <String, Object>{};
    if (data['specification'] != null) {
      final rawSpec = catalogObject(data['specification']);
      if (rawSpec.length > 24) {
        throw const FormatException('Too many material specification fields');
      }
      for (final entry in rawSpec.entries) {
        final value = entry.value;
        if (!RegExp(r'^[a-z][A-Za-z0-9_]{0,39}
    if (!RegExp(r'^[A-Z0-9][A-Z0-9._-]*$').hasMatch(unit)) {
      throw const FormatException('Unknown RFQ unit code');
    }
    return SupplierRfqItem(
      id: catalogId(data['id']),
      productId:
          data['productId'] == null ? null : catalogId(data['productId']),
      description: catalogString(data['description'], max: 500),
      quantity: catalogQty(data['quantity']),
      unitCode: unit,
      specification: Map.unmodifiable(specification),
    );
  }
}

class SupplierRfq {
  const SupplierRfq({
    required this.id,
    required this.publicNumber,
    required this.items,
    required this.invitedAt,
    required this.createdAt,
    required this.siteCity,
    required this.sitePostalCode,
    this.siteNotes,
    this.notes,
    this.responseDueAt,
  });
  final String id, publicNumber, siteCity, sitePostalCode;
  final List<SupplierRfqItem> items;
  final String? notes, siteNotes;
  final DateTime invitedAt, createdAt;
  final DateTime? responseDueAt;

  bool get isWithinDeadline =>
      responseDueAt == null || responseDueAt!.isAfter(DateTime.now().toUtc());

  factory SupplierRfq.parse(Object? raw) {
    final data = catalogObject(raw);
    final site = catalogObject(data['siteSnapshot']);
    final postal = catalogString(site['postalCode'], max: 6);
    if (!RegExp(r'^[1-9][0-9]{5}
      throw const FormatException('RFQ invitation is not open');
    }
    final items = rfqRecords(
        data['items'], SupplierRfqItem.parse, (SupplierRfqItem item) => item.id,
        max: 30);
    if (items.isEmpty) {
      throw const FormatException('RFQ has no material lines');
    }
    return SupplierRfq(
      id: catalogId(data['id']),
      publicNumber: catalogString(data['publicNumber'], max: 40),
      items: items,
      siteCity: catalogString(site['city'], max: 120),
      sitePostalCode: postal,
      siteNotes: site['siteNotes'] == null
          ? null
          : catalogString(site['siteNotes'], max: 300),
      notes: data['notes'] == null
          ? null
          : catalogString(data['notes'], max: 1000),
      invitedAt: rfqTimestamp(data['invitedAt']),
      createdAt: rfqTimestamp(data['createdAt']),
      responseDueAt: data['responseDueAt'] == null
          ? null
          : rfqTimestamp(data['responseDueAt']),
    );
  }
}

enum SupplierQuoteStatus {
  draft,
  submitted,
  revised,
  accepted,
  rejected,
  withdrawn,
  expired;

  static SupplierQuoteStatus parse(Object? raw) => switch (raw) {
        'DRAFT' => draft,
        'SUBMITTED' => submitted,
        'REVISED' => revised,
        'ACCEPTED' => accepted,
        'REJECTED' => rejected,
        'WITHDRAWN' => withdrawn,
        'EXPIRED' => expired,
        _ => throw const FormatException('Unknown supplier quote status'),
      };
  String get label => switch (this) {
        draft => 'Draft',
        submitted => 'Submitted',
        revised => 'Revised',
        accepted => 'Awarded by customer',
        rejected => 'Not selected',
        withdrawn => 'Withdrawn',
        expired => 'Expired',
      };
}

class SupplierQuoteLine {
  const SupplierQuoteLine({
    required this.rfqItemId,
    required this.quantity,
    required this.unitCode,
    required this.unitPrice,
    required this.taxRateBps,
    required this.lineTotalPaise,
    this.listingId,
  });
  final String rfqItemId, quantity, unitCode, unitPrice, lineTotalPaise;
  final String? listingId;
  final int taxRateBps;

  factory SupplierQuoteLine.parse(Object? raw) {
    final data = catalogObject(raw);
    return SupplierQuoteLine(
      rfqItemId: catalogId(data['rfqItemId']),
      listingId:
          data['listingId'] == null ? null : catalogId(data['listingId']),
      quantity: catalogQty(data['quantity']),
      unitCode: catalogString(data['unitCode'], max: 20),
      unitPrice: catalogPrice(data['unitPrice']),
      taxRateBps: catalogInt(data['taxRateBps'], max: 10000),
      lineTotalPaise: deliveryPaise(data['lineTotalPaise']),
    );
  }
}

class SupplierQuote {
  const SupplierQuote({
    required this.id,
    required this.rfqId,
    required this.supplierId,
    required this.quoteNumber,
    required this.version,
    required this.status,
    required this.subtotalPaise,
    required this.taxPaise,
    required this.deliveryPaiseValue,
    required this.totalPaise,
    required this.lines,
    required this.createdAt,
    this.validUntil,
    this.deliveryTerms,
  });
  final String id, rfqId, supplierId, quoteNumber;
  final int version;
  final SupplierQuoteStatus status;
  final String subtotalPaise, taxPaise, deliveryPaiseValue, totalPaise;
  final String? deliveryTerms;
  final DateTime createdAt;
  final DateTime? validUntil;
  final List<SupplierQuoteLine> lines;

  factory SupplierQuote.parse(Object? raw, String supplierId, String rfqId) {
    final data = catalogObject(raw);
    if (catalogId(data['supplierId']) != supplierId ||
        catalogId(data['rfqId']) != rfqId) {
      throw const FormatException('Foreign supplier quotation');
    }
    final subtotal = deliveryPaise(data['subtotalPaise']);
    final tax = deliveryPaise(data['taxPaise']);
    final delivery = deliveryPaise(data['deliveryPaise']);
    final total = deliveryPaise(data['totalPaise']);
    if (BigInt.parse(subtotal) + BigInt.parse(tax) + BigInt.parse(delivery) !=
        BigInt.parse(total)) {
      throw const FormatException('RFQ amount breakdown does not balance');
    }
    final version = catalogInt(data['version'], max: 50);
    if (version == 0) throw const FormatException('Invalid quotation version');
    final lines = rfqRecords(data['lines'], SupplierQuoteLine.parse,
        (SupplierQuoteLine line) => line.rfqItemId,
        max: 30);
    if (lines.isEmpty) throw const FormatException('Empty supplier quote');
    return SupplierQuote(
      id: catalogId(data['id']),
      rfqId: rfqId,
      supplierId: supplierId,
      quoteNumber: catalogString(data['quoteNumber'], max: 40),
      version: version,
      status: SupplierQuoteStatus.parse(data['status']),
      subtotalPaise: subtotal,
      taxPaise: tax,
      deliveryPaiseValue: delivery,
      totalPaise: total,
      lines: lines,
      createdAt: rfqTimestamp(data['createdAt']),
      validUntil:
          data['validUntil'] == null ? null : rfqTimestamp(data['validUntil']),
      deliveryTerms: data['deliveryTerms'] == null
          ? null
          : catalogString(data['deliveryTerms'], max: 500),
    );
  }
}

class SupplierQuoteLineInput {
  const SupplierQuoteLineInput({
    required this.rfqItemId,
    required this.quantity,
    required this.unitCode,
    required this.unitPrice,
    required this.taxRateBps,
    this.listingId,
  });
  final String rfqItemId, quantity, unitCode, unitPrice;
  final String? listingId;
  final int taxRateBps;

  Map<String, Object?> toJson() {
    catalogId(rfqItemId);
    catalogQty(quantity);
    catalogPrice(unitPrice);
    if (taxRateBps < 0 ||
        taxRateBps > 10000 ||
        listingId != null && listingId!.isEmpty) {
      throw const FormatException('Invalid quote tax or listing');
    }
    return {
      'rfqItemId': rfqItemId,
      'listingId': listingId == null ? null : catalogId(listingId),
      'quantity': quantity,
      'unitCode': unitCode,
      'unitPrice': unitPrice,
      'taxRateBps': taxRateBps,
    };
  }
}

void verifyQuotedLines(SupplierRfq rfq, List<SupplierQuoteLineInput> lines) {
  if (lines.length != rfq.items.length) {
    throw const FormatException('Every RFQ material needs a quote');
  }
  final items = {for (final item in rfq.items) item.id: item};
  if (lines.map((line) => line.rfqItemId).toSet().length != lines.length) {
    throw const FormatException('Duplicate RFQ material quote');
  }
  for (final line in lines) {
    final expected = items[line.rfqItemId];
    if (expected == null ||
        expected.unitCode != line.unitCode ||
        catalogScaled(expected.quantity, whole: 15, scale: 3) !=
            catalogScaled(line.quantity, whole: 15, scale: 3)) {
      throw const FormatException('RFQ item and unit must match request');
    }
    line.toJson();
  }
}
).hasMatch(entry.key) ||
            !(value is bool || value is String)) {
          throw const FormatException('Invalid material specification');
        }
        if (value is String &&
            (value.length > 240 ||
             value.runes.any((code) => code < 32 || code == 127))) {
          throw const FormatException('Invalid material specification text');
        }
        specification[entry.key] = value;
      }
    }
    if (!RegExp(r'^[A-Z0-9][A-Z0-9._-]*$').hasMatch(unit)) {
      throw const FormatException('Unknown RFQ unit code');
    }
    return SupplierRfqItem(
      id: catalogId(data['id']),
      productId:
          data['productId'] == null ? null : catalogId(data['productId']),
      description: catalogString(data['description'], max: 500),
      quantity: catalogQty(data['quantity']),
      unitCode: unit,
    );
  }
}

class SupplierRfq {
  const SupplierRfq({
    required this.id,
    required this.publicNumber,
    required this.items,
    required this.invitedAt,
    required this.createdAt,
    this.notes,
    this.responseDueAt,
  });
  final String id, publicNumber;
  final List<SupplierRfqItem> items;
  final String? notes;
  final DateTime invitedAt, createdAt;
  final DateTime? responseDueAt;

  bool get isWithinDeadline =>
      responseDueAt == null || responseDueAt!.isAfter(DateTime.now().toUtc());

  factory SupplierRfq.parse(Object? raw) {
    final data = catalogObject(raw);
    if (data['status'] != 'OPEN') {
      throw const FormatException('RFQ invitation is not open');
    }
    final items = rfqRecords(
        data['items'], SupplierRfqItem.parse, (SupplierRfqItem item) => item.id,
        max: 30);
    if (items.isEmpty) {
      throw const FormatException('RFQ has no material lines');
    }
    return SupplierRfq(
      id: catalogId(data['id']),
      publicNumber: catalogString(data['publicNumber'], max: 40),
      items: items,
      notes: data['notes'] == null
          ? null
          : catalogString(data['notes'], max: 1000),
      invitedAt: rfqTimestamp(data['invitedAt']),
      createdAt: rfqTimestamp(data['createdAt']),
      responseDueAt: data['responseDueAt'] == null
          ? null
          : rfqTimestamp(data['responseDueAt']),
    );
  }
}

enum SupplierQuoteStatus {
  draft,
  submitted,
  revised,
  accepted,
  rejected,
  withdrawn,
  expired;

  static SupplierQuoteStatus parse(Object? raw) => switch (raw) {
        'DRAFT' => draft,
        'SUBMITTED' => submitted,
        'REVISED' => revised,
        'ACCEPTED' => accepted,
        'REJECTED' => rejected,
        'WITHDRAWN' => withdrawn,
        'EXPIRED' => expired,
        _ => throw const FormatException('Unknown supplier quote status'),
      };
  String get label => switch (this) {
        draft => 'Draft',
        submitted => 'Submitted',
        revised => 'Revised',
        accepted => 'Awarded by customer',
        rejected => 'Not selected',
        withdrawn => 'Withdrawn',
        expired => 'Expired',
      };
}

class SupplierQuoteLine {
  const SupplierQuoteLine({
    required this.rfqItemId,
    required this.quantity,
    required this.unitCode,
    required this.unitPrice,
    required this.taxRateBps,
    required this.lineTotalPaise,
    this.listingId,
  });
  final String rfqItemId, quantity, unitCode, unitPrice, lineTotalPaise;
  final String? listingId;
  final int taxRateBps;

  factory SupplierQuoteLine.parse(Object? raw) {
    final data = catalogObject(raw);
    return SupplierQuoteLine(
      rfqItemId: catalogId(data['rfqItemId']),
      listingId:
          data['listingId'] == null ? null : catalogId(data['listingId']),
      quantity: catalogQty(data['quantity']),
      unitCode: catalogString(data['unitCode'], max: 20),
      unitPrice: catalogPrice(data['unitPrice']),
      taxRateBps: catalogInt(data['taxRateBps'], max: 10000),
      lineTotalPaise: deliveryPaise(data['lineTotalPaise']),
    );
  }
}

class SupplierQuote {
  const SupplierQuote({
    required this.id,
    required this.rfqId,
    required this.supplierId,
    required this.quoteNumber,
    required this.version,
    required this.status,
    required this.subtotalPaise,
    required this.taxPaise,
    required this.deliveryPaiseValue,
    required this.totalPaise,
    required this.lines,
    required this.createdAt,
    this.validUntil,
    this.deliveryTerms,
  });
  final String id, rfqId, supplierId, quoteNumber;
  final int version;
  final SupplierQuoteStatus status;
  final String subtotalPaise, taxPaise, deliveryPaiseValue, totalPaise;
  final String? deliveryTerms;
  final DateTime createdAt;
  final DateTime? validUntil;
  final List<SupplierQuoteLine> lines;

  factory SupplierQuote.parse(Object? raw, String supplierId, String rfqId) {
    final data = catalogObject(raw);
    if (catalogId(data['supplierId']) != supplierId ||
        catalogId(data['rfqId']) != rfqId) {
      throw const FormatException('Foreign supplier quotation');
    }
    final subtotal = deliveryPaise(data['subtotalPaise']);
    final tax = deliveryPaise(data['taxPaise']);
    final delivery = deliveryPaise(data['deliveryPaise']);
    final total = deliveryPaise(data['totalPaise']);
    if (BigInt.parse(subtotal) + BigInt.parse(tax) + BigInt.parse(delivery) !=
        BigInt.parse(total)) {
      throw const FormatException('RFQ amount breakdown does not balance');
    }
    final version = catalogInt(data['version'], max: 50);
    if (version == 0) throw const FormatException('Invalid quotation version');
    final lines = rfqRecords(data['lines'], SupplierQuoteLine.parse,
        (SupplierQuoteLine line) => line.rfqItemId,
        max: 30);
    if (lines.isEmpty) throw const FormatException('Empty supplier quote');
    return SupplierQuote(
      id: catalogId(data['id']),
      rfqId: rfqId,
      supplierId: supplierId,
      quoteNumber: catalogString(data['quoteNumber'], max: 40),
      version: version,
      status: SupplierQuoteStatus.parse(data['status']),
      subtotalPaise: subtotal,
      taxPaise: tax,
      deliveryPaiseValue: delivery,
      totalPaise: total,
      lines: lines,
      createdAt: rfqTimestamp(data['createdAt']),
      validUntil:
          data['validUntil'] == null ? null : rfqTimestamp(data['validUntil']),
      deliveryTerms: data['deliveryTerms'] == null
          ? null
          : catalogString(data['deliveryTerms'], max: 500),
    );
  }
}

class SupplierQuoteLineInput {
  const SupplierQuoteLineInput({
    required this.rfqItemId,
    required this.quantity,
    required this.unitCode,
    required this.unitPrice,
    required this.taxRateBps,
    this.listingId,
  });
  final String rfqItemId, quantity, unitCode, unitPrice;
  final String? listingId;
  final int taxRateBps;

  Map<String, Object?> toJson() {
    catalogId(rfqItemId);
    catalogQty(quantity);
    catalogPrice(unitPrice);
    if (taxRateBps < 0 ||
        taxRateBps > 10000 ||
        listingId != null && listingId!.isEmpty) {
      throw const FormatException('Invalid quote tax or listing');
    }
    return {
      'rfqItemId': rfqItemId,
      'listingId': listingId == null ? null : catalogId(listingId),
      'quantity': quantity,
      'unitCode': unitCode,
      'unitPrice': unitPrice,
      'taxRateBps': taxRateBps,
    };
  }
}

void verifyQuotedLines(SupplierRfq rfq, List<SupplierQuoteLineInput> lines) {
  if (lines.length != rfq.items.length) {
    throw const FormatException('Every RFQ material needs a quote');
  }
  final items = {for (final item in rfq.items) item.id: item};
  if (lines.map((line) => line.rfqItemId).toSet().length != lines.length) {
    throw const FormatException('Duplicate RFQ material quote');
  }
  for (final line in lines) {
    final expected = items[line.rfqItemId];
    if (expected == null ||
        expected.unitCode != line.unitCode ||
        catalogScaled(expected.quantity, whole: 15, scale: 3) !=
            catalogScaled(line.quantity, whole: 15, scale: 3)) {
      throw const FormatException('RFQ item and unit must match request');
    }
    line.toJson();
  }
}
).hasMatch(postal)) {
      throw const FormatException('Invalid RFQ delivery PIN');
    }
    if (data['status'] != 'OPEN') {
      throw const FormatException('RFQ invitation is not open');
    }
    final items = rfqRecords(
        data['items'], SupplierRfqItem.parse, (SupplierRfqItem item) => item.id,
        max: 30);
    if (items.isEmpty) {
      throw const FormatException('RFQ has no material lines');
    }
    return SupplierRfq(
      id: catalogId(data['id']),
      publicNumber: catalogString(data['publicNumber'], max: 40),
      items: items,
      notes: data['notes'] == null
          ? null
          : catalogString(data['notes'], max: 1000),
      invitedAt: rfqTimestamp(data['invitedAt']),
      createdAt: rfqTimestamp(data['createdAt']),
      responseDueAt: data['responseDueAt'] == null
          ? null
          : rfqTimestamp(data['responseDueAt']),
    );
  }
}

enum SupplierQuoteStatus {
  draft,
  submitted,
  revised,
  accepted,
  rejected,
  withdrawn,
  expired;

  static SupplierQuoteStatus parse(Object? raw) => switch (raw) {
        'DRAFT' => draft,
        'SUBMITTED' => submitted,
        'REVISED' => revised,
        'ACCEPTED' => accepted,
        'REJECTED' => rejected,
        'WITHDRAWN' => withdrawn,
        'EXPIRED' => expired,
        _ => throw const FormatException('Unknown supplier quote status'),
      };
  String get label => switch (this) {
        draft => 'Draft',
        submitted => 'Submitted',
        revised => 'Revised',
        accepted => 'Awarded by customer',
        rejected => 'Not selected',
        withdrawn => 'Withdrawn',
        expired => 'Expired',
      };
}

class SupplierQuoteLine {
  const SupplierQuoteLine({
    required this.rfqItemId,
    required this.quantity,
    required this.unitCode,
    required this.unitPrice,
    required this.taxRateBps,
    required this.lineTotalPaise,
    this.listingId,
  });
  final String rfqItemId, quantity, unitCode, unitPrice, lineTotalPaise;
  final String? listingId;
  final int taxRateBps;

  factory SupplierQuoteLine.parse(Object? raw) {
    final data = catalogObject(raw);
    return SupplierQuoteLine(
      rfqItemId: catalogId(data['rfqItemId']),
      listingId:
          data['listingId'] == null ? null : catalogId(data['listingId']),
      quantity: catalogQty(data['quantity']),
      unitCode: catalogString(data['unitCode'], max: 20),
      unitPrice: catalogPrice(data['unitPrice']),
      taxRateBps: catalogInt(data['taxRateBps'], max: 10000),
      lineTotalPaise: deliveryPaise(data['lineTotalPaise']),
    );
  }
}

class SupplierQuote {
  const SupplierQuote({
    required this.id,
    required this.rfqId,
    required this.supplierId,
    required this.quoteNumber,
    required this.version,
    required this.status,
    required this.subtotalPaise,
    required this.taxPaise,
    required this.deliveryPaiseValue,
    required this.totalPaise,
    required this.lines,
    required this.createdAt,
    this.validUntil,
    this.deliveryTerms,
  });
  final String id, rfqId, supplierId, quoteNumber;
  final int version;
  final SupplierQuoteStatus status;
  final String subtotalPaise, taxPaise, deliveryPaiseValue, totalPaise;
  final String? deliveryTerms;
  final DateTime createdAt;
  final DateTime? validUntil;
  final List<SupplierQuoteLine> lines;

  factory SupplierQuote.parse(Object? raw, String supplierId, String rfqId) {
    final data = catalogObject(raw);
    if (catalogId(data['supplierId']) != supplierId ||
        catalogId(data['rfqId']) != rfqId) {
      throw const FormatException('Foreign supplier quotation');
    }
    final subtotal = deliveryPaise(data['subtotalPaise']);
    final tax = deliveryPaise(data['taxPaise']);
    final delivery = deliveryPaise(data['deliveryPaise']);
    final total = deliveryPaise(data['totalPaise']);
    if (BigInt.parse(subtotal) + BigInt.parse(tax) + BigInt.parse(delivery) !=
        BigInt.parse(total)) {
      throw const FormatException('RFQ amount breakdown does not balance');
    }
    final version = catalogInt(data['version'], max: 50);
    if (version == 0) throw const FormatException('Invalid quotation version');
    final lines = rfqRecords(data['lines'], SupplierQuoteLine.parse,
        (SupplierQuoteLine line) => line.rfqItemId,
        max: 30);
    if (lines.isEmpty) throw const FormatException('Empty supplier quote');
    return SupplierQuote(
      id: catalogId(data['id']),
      rfqId: rfqId,
      supplierId: supplierId,
      quoteNumber: catalogString(data['quoteNumber'], max: 40),
      version: version,
      status: SupplierQuoteStatus.parse(data['status']),
      subtotalPaise: subtotal,
      taxPaise: tax,
      deliveryPaiseValue: delivery,
      totalPaise: total,
      lines: lines,
      createdAt: rfqTimestamp(data['createdAt']),
      validUntil:
          data['validUntil'] == null ? null : rfqTimestamp(data['validUntil']),
      deliveryTerms: data['deliveryTerms'] == null
          ? null
          : catalogString(data['deliveryTerms'], max: 500),
    );
  }
}

class SupplierQuoteLineInput {
  const SupplierQuoteLineInput({
    required this.rfqItemId,
    required this.quantity,
    required this.unitCode,
    required this.unitPrice,
    required this.taxRateBps,
    this.listingId,
  });
  final String rfqItemId, quantity, unitCode, unitPrice;
  final String? listingId;
  final int taxRateBps;

  Map<String, Object?> toJson() {
    catalogId(rfqItemId);
    catalogQty(quantity);
    catalogPrice(unitPrice);
    if (taxRateBps < 0 ||
        taxRateBps > 10000 ||
        listingId != null && listingId!.isEmpty) {
      throw const FormatException('Invalid quote tax or listing');
    }
    return {
      'rfqItemId': rfqItemId,
      'listingId': listingId == null ? null : catalogId(listingId),
      'quantity': quantity,
      'unitCode': unitCode,
      'unitPrice': unitPrice,
      'taxRateBps': taxRateBps,
    };
  }
}

void verifyQuotedLines(SupplierRfq rfq, List<SupplierQuoteLineInput> lines) {
  if (lines.length != rfq.items.length) {
    throw const FormatException('Every RFQ material needs a quote');
  }
  final items = {for (final item in rfq.items) item.id: item};
  if (lines.map((line) => line.rfqItemId).toSet().length != lines.length) {
    throw const FormatException('Duplicate RFQ material quote');
  }
  for (final line in lines) {
    final expected = items[line.rfqItemId];
    if (expected == null ||
        expected.unitCode != line.unitCode ||
        catalogScaled(expected.quantity, whole: 15, scale: 3) !=
            catalogScaled(line.quantity, whole: 15, scale: 3)) {
      throw const FormatException('RFQ item and unit must match request');
    }
    line.toJson();
  }
}
).hasMatch(entry.key) ||
            !(value is bool || value is String)) {
          throw const FormatException('Invalid material specification');
        }
        if (value is String &&
            (value.length > 240 ||
             value.runes.any((code) => code < 32 || code == 127))) {
          throw const FormatException('Invalid material specification text');
        }
        specification[entry.key] = value;
      }
    }
    if (!RegExp(r'^[A-Z0-9][A-Z0-9._-]*$').hasMatch(unit)) {
      throw const FormatException('Unknown RFQ unit code');
    }
    return SupplierRfqItem(
      id: catalogId(data['id']),
      productId:
          data['productId'] == null ? null : catalogId(data['productId']),
      description: catalogString(data['description'], max: 500),
      quantity: catalogQty(data['quantity']),
      unitCode: unit,
    );
  }
}

class SupplierRfq {
  const SupplierRfq({
    required this.id,
    required this.publicNumber,
    required this.items,
    required this.invitedAt,
    required this.createdAt,
    this.notes,
    this.responseDueAt,
  });
  final String id, publicNumber;
  final List<SupplierRfqItem> items;
  final String? notes;
  final DateTime invitedAt, createdAt;
  final DateTime? responseDueAt;

  bool get isWithinDeadline =>
      responseDueAt == null || responseDueAt!.isAfter(DateTime.now().toUtc());

  factory SupplierRfq.parse(Object? raw) {
    final data = catalogObject(raw);
    if (data['status'] != 'OPEN') {
      throw const FormatException('RFQ invitation is not open');
    }
    final items = rfqRecords(
        data['items'], SupplierRfqItem.parse, (SupplierRfqItem item) => item.id,
        max: 30);
    if (items.isEmpty) {
      throw const FormatException('RFQ has no material lines');
    }
    return SupplierRfq(
      id: catalogId(data['id']),
      publicNumber: catalogString(data['publicNumber'], max: 40),
      items: items,
      notes: data['notes'] == null
          ? null
          : catalogString(data['notes'], max: 1000),
      invitedAt: rfqTimestamp(data['invitedAt']),
      createdAt: rfqTimestamp(data['createdAt']),
      responseDueAt: data['responseDueAt'] == null
          ? null
          : rfqTimestamp(data['responseDueAt']),
    );
  }
}

enum SupplierQuoteStatus {
  draft,
  submitted,
  revised,
  accepted,
  rejected,
  withdrawn,
  expired;

  static SupplierQuoteStatus parse(Object? raw) => switch (raw) {
        'DRAFT' => draft,
        'SUBMITTED' => submitted,
        'REVISED' => revised,
        'ACCEPTED' => accepted,
        'REJECTED' => rejected,
        'WITHDRAWN' => withdrawn,
        'EXPIRED' => expired,
        _ => throw const FormatException('Unknown supplier quote status'),
      };
  String get label => switch (this) {
        draft => 'Draft',
        submitted => 'Submitted',
        revised => 'Revised',
        accepted => 'Awarded by customer',
        rejected => 'Not selected',
        withdrawn => 'Withdrawn',
        expired => 'Expired',
      };
}

class SupplierQuoteLine {
  const SupplierQuoteLine({
    required this.rfqItemId,
    required this.quantity,
    required this.unitCode,
    required this.unitPrice,
    required this.taxRateBps,
    required this.lineTotalPaise,
    this.listingId,
  });
  final String rfqItemId, quantity, unitCode, unitPrice, lineTotalPaise;
  final String? listingId;
  final int taxRateBps;

  factory SupplierQuoteLine.parse(Object? raw) {
    final data = catalogObject(raw);
    return SupplierQuoteLine(
      rfqItemId: catalogId(data['rfqItemId']),
      listingId:
          data['listingId'] == null ? null : catalogId(data['listingId']),
      quantity: catalogQty(data['quantity']),
      unitCode: catalogString(data['unitCode'], max: 20),
      unitPrice: catalogPrice(data['unitPrice']),
      taxRateBps: catalogInt(data['taxRateBps'], max: 10000),
      lineTotalPaise: deliveryPaise(data['lineTotalPaise']),
    );
  }
}

class SupplierQuote {
  const SupplierQuote({
    required this.id,
    required this.rfqId,
    required this.supplierId,
    required this.quoteNumber,
    required this.version,
    required this.status,
    required this.subtotalPaise,
    required this.taxPaise,
    required this.deliveryPaiseValue,
    required this.totalPaise,
    required this.lines,
    required this.createdAt,
    this.validUntil,
    this.deliveryTerms,
  });
  final String id, rfqId, supplierId, quoteNumber;
  final int version;
  final SupplierQuoteStatus status;
  final String subtotalPaise, taxPaise, deliveryPaiseValue, totalPaise;
  final String? deliveryTerms;
  final DateTime createdAt;
  final DateTime? validUntil;
  final List<SupplierQuoteLine> lines;

  factory SupplierQuote.parse(Object? raw, String supplierId, String rfqId) {
    final data = catalogObject(raw);
    if (catalogId(data['supplierId']) != supplierId ||
        catalogId(data['rfqId']) != rfqId) {
      throw const FormatException('Foreign supplier quotation');
    }
    final subtotal = deliveryPaise(data['subtotalPaise']);
    final tax = deliveryPaise(data['taxPaise']);
    final delivery = deliveryPaise(data['deliveryPaise']);
    final total = deliveryPaise(data['totalPaise']);
    if (BigInt.parse(subtotal) + BigInt.parse(tax) + BigInt.parse(delivery) !=
        BigInt.parse(total)) {
      throw const FormatException('RFQ amount breakdown does not balance');
    }
    final version = catalogInt(data['version'], max: 50);
    if (version == 0) throw const FormatException('Invalid quotation version');
    final lines = rfqRecords(data['lines'], SupplierQuoteLine.parse,
        (SupplierQuoteLine line) => line.rfqItemId,
        max: 30);
    if (lines.isEmpty) throw const FormatException('Empty supplier quote');
    return SupplierQuote(
      id: catalogId(data['id']),
      rfqId: rfqId,
      supplierId: supplierId,
      quoteNumber: catalogString(data['quoteNumber'], max: 40),
      version: version,
      status: SupplierQuoteStatus.parse(data['status']),
      subtotalPaise: subtotal,
      taxPaise: tax,
      deliveryPaiseValue: delivery,
      totalPaise: total,
      lines: lines,
      createdAt: rfqTimestamp(data['createdAt']),
      validUntil:
          data['validUntil'] == null ? null : rfqTimestamp(data['validUntil']),
      deliveryTerms: data['deliveryTerms'] == null
          ? null
          : catalogString(data['deliveryTerms'], max: 500),
    );
  }
}

class SupplierQuoteLineInput {
  const SupplierQuoteLineInput({
    required this.rfqItemId,
    required this.quantity,
    required this.unitCode,
    required this.unitPrice,
    required this.taxRateBps,
    this.listingId,
  });
  final String rfqItemId, quantity, unitCode, unitPrice;
  final String? listingId;
  final int taxRateBps;

  Map<String, Object?> toJson() {
    catalogId(rfqItemId);
    catalogQty(quantity);
    catalogPrice(unitPrice);
    if (taxRateBps < 0 ||
        taxRateBps > 10000 ||
        listingId != null && listingId!.isEmpty) {
      throw const FormatException('Invalid quote tax or listing');
    }
    return {
      'rfqItemId': rfqItemId,
      'listingId': listingId == null ? null : catalogId(listingId),
      'quantity': quantity,
      'unitCode': unitCode,
      'unitPrice': unitPrice,
      'taxRateBps': taxRateBps,
    };
  }
}

void verifyQuotedLines(SupplierRfq rfq, List<SupplierQuoteLineInput> lines) {
  if (lines.length != rfq.items.length) {
    throw const FormatException('Every RFQ material needs a quote');
  }
  final items = {for (final item in rfq.items) item.id: item};
  if (lines.map((line) => line.rfqItemId).toSet().length != lines.length) {
    throw const FormatException('Duplicate RFQ material quote');
  }
  for (final line in lines) {
    final expected = items[line.rfqItemId];
    if (expected == null ||
        expected.unitCode != line.unitCode ||
        catalogScaled(expected.quantity, whole: 15, scale: 3) !=
            catalogScaled(line.quantity, whole: 15, scale: 3)) {
      throw const FormatException('RFQ item and unit must match request');
    }
    line.toJson();
  }
}
