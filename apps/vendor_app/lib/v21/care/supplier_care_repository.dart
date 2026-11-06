import '../api/supplier_v21_api.dart';
import '../catalog/supplier_catalog_models.dart';
import '../delivery/supplier_delivery_models.dart';

DateTime _utc(Object? value) {
  final raw = catalogString(value, max: 50);
  final date = DateTime.tryParse(raw);
  if (!raw.endsWith('Z') || date == null || !date.isUtc) {
    throw const FormatException('Invalid date');
  }
  return date;
}

String _careNote(Object? value, {required int max}) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > max ||
      value.runes.any((code) =>
          code < 9 ||
          code == 11 ||
          code == 12 ||
          (code >= 14 && code < 32) ||
          code == 127)) {
    throw const FormatException('Invalid care note');
  }
  return value;
}

enum SupplierReturnStatus {
  requested,
  underReview,
  approved,
  rejected,
  inTransit,
  received,
  resolved,
  cancelled;

  static SupplierReturnStatus parse(Object? raw) => switch (raw) {
        'REQUESTED' => requested,
        'UNDER_REVIEW' => underReview,
        'APPROVED' => approved,
        'REJECTED' => rejected,
        'IN_TRANSIT' => inTransit,
        'RECEIVED' => received,
        'RESOLVED' => resolved,
        'CANCELLED' => cancelled,
        _ => throw const FormatException('Unknown return status'),
      };

  bool get canReceive => this == approved || this == inTransit;
  String get label => switch (this) {
        requested => 'Requested',
        underReview => 'Under independent review',
        approved => 'Approved for return',
        rejected => 'Rejected',
        inTransit => 'In transit',
        received => 'Physically received',
        resolved => 'Resolved',
        cancelled => 'Cancelled',
      };
}

class SupplierReturnLine {
  const SupplierReturnLine(this.orderItemId, this.quantity);
  final String orderItemId, quantity;
  factory SupplierReturnLine.parse(Object? raw) {
    final row = catalogObject(raw);
    return SupplierReturnLine(
        catalogId(row['orderItemId']), catalogQty(row['quantity']));
  }
}

class SupplierReturn {
  const SupplierReturn({
    required this.id,
    required this.supplierOrderId,
    required this.reason,
    required this.status,
    required this.items,
    required this.evidenceCount,
    required this.createdAt,
    this.resolutionNote,
  });
  final String id, supplierOrderId, reason;
  final SupplierReturnStatus status;
  final List<SupplierReturnLine> items;
  final int evidenceCount;
  final DateTime createdAt;
  final String? resolutionNote;

  factory SupplierReturn.parse(Object? raw, String expectedOrderId) {
    final json = catalogObject(raw);
    if (catalogId(json['supplierOrderId']) != expectedOrderId ||
        json['financialStatus'] != 'NOT_REFUNDED') {
      throw const FormatException('Invalid or unauthorized return state');
    }
    catalogId(json['customerId']); // Validate but never display customer PII.
    final lines = deliveryRows(json['items'], SupplierReturnLine.parse,
        (SupplierReturnLine line) => line.orderItemId,
        max: 40);
    if (lines.isEmpty) throw const FormatException('Return has no goods');
    final evidence = json['evidenceMediaIds'];
    if (evidence is! List<dynamic> || evidence.length > 8) {
      throw const FormatException('Invalid private evidence');
    }
    for (final id in evidence) {
      catalogId(id);
    }
    if (evidence.toSet().length != evidence.length) {
      throw const FormatException('Duplicate private evidence');
    }
    return SupplierReturn(
      id: catalogId(json['id']),
      supplierOrderId: expectedOrderId,
      reason: _careNote(json['reason'], max: 300),
      status: SupplierReturnStatus.parse(json['status']),
      items: lines,
      evidenceCount: evidence.length,
      createdAt: _utc(json['createdAt']),
      resolutionNote: json['resolutionNote'] == null
          ? null
          : _careNote(json['resolutionNote'], max: 500),
    );
  }
}

enum SupplierReviewStatus {
  pending,
  published,
  hidden,
  rejected;

  static SupplierReviewStatus parse(Object? raw) => switch (raw) {
        'PENDING' => pending,
        'PUBLISHED' => published,
        'HIDDEN' => hidden,
        'REJECTED' => rejected,
        _ => throw const FormatException('Unknown moderation status'),
      };
  String get label => switch (this) {
        pending => 'Awaiting moderation',
        published => 'Published',
        hidden => 'Hidden',
        rejected => 'Not published',
      };
}

class SupplierCustomerReview {
  const SupplierCustomerReview({
    required this.id,
    required this.supplierOrderId,
    required this.rating,
    required this.status,
    required this.createdAt,
    this.comment,
  });
  final String id, supplierOrderId;
  final int rating;
  final SupplierReviewStatus status;
  final DateTime createdAt;
  final String? comment;

  factory SupplierCustomerReview.parse(Object? raw, String supplierId) {
    final json = catalogObject(raw);
    if (catalogId(json['supplierId']) != supplierId) {
      throw const FormatException('Foreign supplier review');
    }
    catalogId(json['customerId']);
    final rating = catalogInt(json['rating'], max: 5);
    if (rating < 1) throw const FormatException('Invalid rating');
    return SupplierCustomerReview(
      id: catalogId(json['id']),
      supplierOrderId: catalogId(json['supplierOrderId']),
      rating: rating,
      status: SupplierReviewStatus.parse(json['status']),
      createdAt: _utc(json['createdAt']),
      comment: json['comment'] == null
          ? null
          : _careNote(json['comment'], max: 1500),
    );
  }
}

class SupplierCareRepository {
  const SupplierCareRepository(this.client);
  final SupplierV21Api client;
  String _base(String supplierId) =>
      '/api/v2/suppliers/${catalogId(supplierId)}';

  Future<List<SupplierReturn>> returns(
      String supplierId, String supplierOrderId) async {
    final id = catalogId(supplierOrderId);
    final data =
        (await client.get('${_base(supplierId)}/orders/$id/returns')).data;
    return deliveryRows(data, (raw) => SupplierReturn.parse(raw, id),
        (SupplierReturn item) => item.id);
  }

  /// Physical receipt is neither a refund nor inventory restock.
  Future<void> receive({
    required String supplierId,
    required SupplierReturn item,
  }) async {
    if (!item.status.canReceive) {
      throw StateError('Independent return approval required');
    }
    final data = (await client.request('POST',
            '${_base(supplierId)}/returns/${catalogId(item.id)}/receive',
            body: {}))
        .data;
    final json = catalogObject(data);
    if (catalogId(json['id']) != item.id ||
        json['status'] != 'RECEIVED' ||
        json['financialStatus'] != 'NOT_REFUNDED' ||
        json['replayed'] is! bool) {
      throw const FormatException('Physical receipt not confirmed');
    }
  }

  Future<List<SupplierCustomerReview>> reviews(String supplierId) async {
    final data = (await client.get('${_base(supplierId)}/reviews/manage')).data;
    return deliveryRows(
        data,
        (raw) => SupplierCustomerReview.parse(raw, supplierId),
        (SupplierCustomerReview review) => review.id);
  }
}
