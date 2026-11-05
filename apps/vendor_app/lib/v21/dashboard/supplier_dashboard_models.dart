/// Bounded, read-only S04 models. The V2.1 list endpoints return at most
/// 100 records; counts derived here are sample counts, not database totals.
class DashboardCount {
  const DashboardCount(this.value, {required this.bounded});
  final int value;
  final bool bounded;

  /// For a saturated list, even zero matches is only a lower bound.
  String get label => bounded ? '$value+' : '$value';
}

enum DashboardOrderStatus {
  pendingAcceptance,
  confirmed,
  packing,
  ready,
  dispatched,
  partiallyDelivered,
  delivered,
  cancelled,
  rejected;

  static DashboardOrderStatus parse(Object? input) => switch (input) {
    'PENDING_ACCEPTANCE' => pendingAcceptance,
    'CONFIRMED' => confirmed,
    'PACKING' => packing,
    'READY' => ready,
    'DISPATCHED' => dispatched,
    'PARTIALLY_DELIVERED' => partiallyDelivered,
    'DELIVERED' => delivered,
    'CANCELLED' => cancelled,
    'REJECTED' => rejected,
    _ => throw const FormatException('Unknown supplier order status'),
  };

  String get label => switch (this) {
    pendingAcceptance => 'Awaiting acceptance',
    confirmed => 'Confirmed',
    packing => 'Packing',
    ready => 'Ready to dispatch',
    dispatched => 'Dispatched',
    partiallyDelivered => 'Partially delivered',
    delivered => 'Delivered',
    cancelled => 'Cancelled',
    rejected => 'Rejected',
  };

  bool get fulfillmentInProgress => switch (this) {
    confirmed || packing || ready || dispatched || partiallyDelivered => true,
    _ => false,
  };
}

class DashboardOrder {
  const DashboardOrder({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.lineCount,
  });

  final String id;
  final DashboardOrderStatus status;
  final DateTime createdAt;
  final int lineCount;

  String get shortId => id.substring(id.length - 8).toUpperCase();

  factory DashboardOrder.fromJson(Object? value) {
    final record = _object(value, 'Order');
    final id = _uuid(record['id'], 'Order ID');
    final createdAt = _date(record['createdAt'], 'Order date');
    final items = record['items'];
    if (items is! List<dynamic> || items.length > 100) {
      throw const FormatException('Invalid supplier order lines');
    }
    return DashboardOrder(
      id: id,
      status: DashboardOrderStatus.parse(record['status']),
      createdAt: createdAt,
      lineCount: items.length,
    );
  }
}

class DashboardListing {
  const DashboardListing({required this.id, required this.published});
  final String id;
  final bool published;

  factory DashboardListing.fromJson(Object? value, String supplierId) {
    final record = _object(value, 'Listing');
    final id = _uuid(record['id'], 'Listing ID');
    if (_uuid(record['supplierId'], 'Listing supplier') != supplierId) {
      throw const FormatException('Foreign supplier listing in dashboard');
    }
    const statuses = {
      'DRAFT', 'PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED', 'ARCHIVED',
    };
    final status = record['status'];
    final active = record['active'];
    if (!statuses.contains(status) || active is! bool) {
      throw const FormatException('Invalid supplier listing status');
    }
    return DashboardListing(
      id: id,
      published: status == 'APPROVED' && active,
    );
  }
}

class DashboardWarehouse {
  const DashboardWarehouse({required this.id, required this.active});
  final String id;
  final bool active;

  factory DashboardWarehouse.fromJson(Object? value, String supplierId) {
    final record = _object(value, 'Warehouse');
    final id = _uuid(record['id'], 'Warehouse ID');
    if (_uuid(record['supplierId'], 'Warehouse supplier') != supplierId) {
      throw const FormatException('Foreign supplier warehouse in dashboard');
    }
    if (record['active'] is! bool) {
      throw const FormatException('Invalid warehouse status');
    }
    return DashboardWarehouse(id: id, active: record['active'] as bool);
  }
}

class DashboardInvitation {
  const DashboardInvitation(this.id);
  final String id;

  factory DashboardInvitation.fromJson(Object? value) {
    final record = _object(value, 'RFQ');
    final id = _uuid(record['id'], 'RFQ ID');
    if (record['status'] != 'OPEN') {
      throw const FormatException('Non-open RFQ returned in open invitations');
    }
    return DashboardInvitation(id);
  }
}

class SupplierDashboardSnapshot {
  const SupplierDashboardSnapshot({
    required this.supplierId,
    required this.refreshedAt,
    required this.awaitingAcceptance,
    required this.inFulfillment,
    required this.publishedListings,
    required this.activeWarehouses,
    required this.openInvitations,
    required this.recentOrders,
  });

  final String supplierId;
  final DateTime refreshedAt;
  final DashboardCount awaitingAcceptance;
  final DashboardCount inFulfillment;
  final DashboardCount publishedListings;
  final DashboardCount activeWarehouses;
  /// Null means the current backend role cannot query RFQs; never show zero.
  final DashboardCount? openInvitations;
  final List<DashboardOrder> recentOrders;

  bool get sampleLimited => awaitingAcceptance.bounded ||
      publishedListings.bounded || activeWarehouses.bounded ||
      (openInvitations?.bounded ?? false);
}

Map<String, dynamic> _object(Object? value, String label) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$label response must be an object');
  }
  return value;
}

final _uuidPattern =
    RegExp(r'^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$');

String _uuid(Object? value, String label) {
  if (value is! String || !_uuidPattern.hasMatch(value)) {
    throw FormatException('Invalid $label');
  }
  return value;
}

DateTime _date(Object? value, String label) {
  if (value is! String) throw FormatException('Missing $label');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !value.endsWith('Z')) {
    throw FormatException('Invalid $label');
  }
  return parsed;
}

/// Reject truncated/foreign/duplicate record sets; never turn broken data into
/// reassuring zero counts or unqualified business performance metrics.
List<T> dashboardRecords<T>(
  Object? value,
  T Function(Object?) decode,
  String Function(T) idOf,
) {
  if (value is! List<dynamic> || value.length > 100) {
    throw const FormatException('Invalid bounded dashboard response');
  }
  final items = value.map(decode).toList(growable: false);
  if (items.map(idOf).toSet().length != items.length) {
    throw const FormatException('Duplicate dashboard records');
  }
  return List.unmodifiable(items);
}
