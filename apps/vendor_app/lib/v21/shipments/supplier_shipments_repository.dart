import '../api/supplier_v21_api.dart';
import '../catalog/supplier_catalog_models.dart';
import '../inventory/supplier_inventory_models.dart';
import '../orders/supplier_orders_repository.dart';

enum SupplierShipmentStatus {
  planned,
  packed,
  dispatched,
  outForDelivery,
  partiallyDelivered,
  delivered,
  failed,
  returned,
  cancelled;

  static SupplierShipmentStatus parse(Object? value) => switch (value) {
        'PLANNED' => planned,
        'PACKED' => packed,
        'DISPATCHED' => dispatched,
        'OUT_FOR_DELIVERY' => outForDelivery,
        'PARTIALLY_DELIVERED' => partiallyDelivered,
        'DELIVERED' => delivered,
        'FAILED' => failed,
        'RETURNED' => returned,
        'CANCELLED' => cancelled,
        _ => throw const FormatException('Unknown shipment status'),
      };

  String get label => switch (this) {
        planned => 'Planned',
        packed => 'Packed',
        dispatched => 'Dispatched',
        outForDelivery => 'Out for delivery',
        partiallyDelivered => 'Partially delivered',
        delivered => 'Delivered',
        failed => 'Delivery failed',
        returned => 'Returned',
        cancelled => 'Cancelled',
      };
  String? get nextStep => switch (this) {
        planned => 'pack',
        packed => 'dispatch',
        dispatched => 'out-for-delivery',
        _ => null,
      };
}

class SupplierShipmentLine {
  const SupplierShipmentLine({
    required this.id,
    required this.orderItemId,
    required this.quantity,
    required this.deliveredQty,
    required this.rejectedQty,
  });
  final String id, orderItemId, quantity, deliveredQty, rejectedQty;

  factory SupplierShipmentLine.parse(Object? value) {
    final row = catalogObject(value);
    final qty = catalogQty(row['quantity']);
    final delivered = exactStockQuantity(row['deliveredQty']);
    final rejected = exactStockQuantity(row['rejectedQty']);
    if (catalogScaled(delivered, whole: 15, scale: 3, positive: false) +
            catalogScaled(rejected, whole: 15, scale: 3, positive: false) >
        catalogScaled(qty, whole: 15, scale: 3)) {
      throw const FormatException('Shipment line exceeds ordered quantity');
    }
    return SupplierShipmentLine(
      id: catalogId(row['id']),
      orderItemId: catalogId(row['orderItemId']),
      quantity: qty,
      deliveredQty: delivered,
      rejectedQty: rejected,
    );
  }
}

class SupplierShipmentEvent {
  const SupplierShipmentEvent({
    required this.from,
    required this.to,
    required this.at,
  });
  final SupplierShipmentStatus? from;
  final SupplierShipmentStatus to;
  final DateTime at;

  factory SupplierShipmentEvent.parse(Object? value) {
    final row = catalogObject(value);
    return SupplierShipmentEvent(
      from: row['fromStatus'] == null
          ? null
          : SupplierShipmentStatus.parse(row['fromStatus']),
      to: SupplierShipmentStatus.parse(row['toStatus']),
      at: shipmentUtc(row['at']),
    );
  }
}

DateTime shipmentUtc(Object? value) {
  final raw = catalogString(value, max: 40);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw const FormatException('Invalid UTC shipment time');
  }
  return parsed;
}

class SupplierShipment {
  const SupplierShipment({
    required this.id,
    required this.shipmentNumber,
    required this.supplierOrderId,
    required this.supplierId,
    required this.warehouseId,
    required this.status,
    required this.createdAt,
    required this.handoverVerified,
    required this.items,
    required this.events,
    this.carrierName,
    this.trackingReference,
    this.deliveredAt,
  });
  final String id, shipmentNumber, supplierOrderId, supplierId, warehouseId;
  final SupplierShipmentStatus status;
  final DateTime createdAt;
  final bool handoverVerified;
  final String? carrierName, trackingReference;
  final DateTime? deliveredAt;
  final List<SupplierShipmentLine> items;
  final List<SupplierShipmentEvent> events;

  factory SupplierShipment.parse(Object? value,
      {required String supplierId, required String orderId}) {
    final row = catalogObject(value);
    if (catalogId(row['supplierId']) != supplierId ||
        catalogId(row['supplierOrderId']) != orderId ||
        row['handoverVerified'] is! bool) {
      throw const FormatException('Foreign or invalid shipment');
    }
    final items = shipmentRows(row['items'], SupplierShipmentLine.parse,
        (SupplierShipmentLine item) => item.id,
        max: 40);
    final events = shipmentRows(
        row['events'],
        SupplierShipmentEvent.parse,
        (SupplierShipmentEvent event) =>
            '${event.at.toIso8601String()}-${event.to.name}',
        max: 100);
    if (items.isEmpty) {
      throw const FormatException('Shipment has no material lines');
    }
    return SupplierShipment(
      id: catalogId(row['id']),
      shipmentNumber: catalogString(row['shipmentNumber'], max: 50),
      supplierId: supplierId,
      supplierOrderId: orderId,
      warehouseId: catalogId(row['warehouseId']),
      status: SupplierShipmentStatus.parse(row['status']),
      handoverVerified: row['handoverVerified'] as bool,
      createdAt: shipmentUtc(row['createdAt']),
      deliveredAt:
          row['deliveredAt'] == null ? null : shipmentUtc(row['deliveredAt']),
      carrierName: row['carrierName'] == null
          ? null
          : catalogString(row['carrierName'], max: 160),
      trackingReference: row['trackingReference'] == null
          ? null
          : catalogString(row['trackingReference'], max: 100),
      items: items,
      events: events,
    );
  }
}

List<T> shipmentRows<T>(
    Object? raw, T Function(Object?) parse, String Function(T) identity,
    {int max = 100}) {
  if (raw is! List<dynamic> || raw.length > max) {
    throw const FormatException('Invalid bounded shipment data');
  }
  final items = raw.map(parse).toList(growable: false);
  if (items.map(identity).toSet().length != items.length) {
    throw const FormatException('Duplicate shipment identity');
  }
  return List.unmodifiable(items);
}

class SupplierShipmentDecision {
  const SupplierShipmentDecision(
      {required this.id, required this.status, required this.replayed});
  final String id;
  final SupplierShipmentStatus status;
  final bool replayed;
  factory SupplierShipmentDecision.parse(Object? raw,
      {required String shipmentId, required SupplierShipmentStatus expected}) {
    final row = catalogObject(raw);
    final status = SupplierShipmentStatus.parse(row['status']);
    if (catalogId(row['id']) != shipmentId ||
        status != expected ||
        row['replayed'] is! bool) {
      throw const FormatException('Unconfirmed shipment state transition');
    }
    return SupplierShipmentDecision(
        id: shipmentId, status: status, replayed: row['replayed'] as bool);
  }
}

class SupplierShipmentPlanLine {
  const SupplierShipmentPlanLine(this.orderItemId, this.quantity);
  final String orderItemId, quantity;
  Map<String, String> toJson() {
    catalogId(orderItemId);
    catalogQty(quantity);
    return {'orderItemId': orderItemId, 'quantity': quantity};
  }
}

class SupplierShipmentsRepository {
  const SupplierShipmentsRepository(this.client);
  final SupplierV21Api client;
  String _base(String supplierId) =>
      '/api/v2/suppliers/${catalogId(supplierId)}';

  Future<List<SupplierShipment>> list(
      String supplierId, String supplierOrderId) async {
    final id = catalogId(supplierOrderId);
    final data =
        (await client.get('${_base(supplierId)}/orders/$id/shipments')).data;
    return shipmentRows(
        data,
        (row) =>
            SupplierShipment.parse(row, supplierId: supplierId, orderId: id),
        (SupplierShipment shipment) => shipment.id);
  }

  Future<SupplierShipment> plan({
    required String supplierId,
    required SupplierOrder order,
    required String warehouseId,
    required List<SupplierShipmentPlanLine> lines,
    required String intent,
    String? carrierName,
    String? trackingReference,
  }) async {
    if (lines.isEmpty ||
        lines.length > 40 ||
        lines.map((line) => line.orderItemId).toSet().length != lines.length) {
      throw const FormatException('Select 1–40 unique order lines');
    }
    final owned = {for (final line in order.items) line.id: line};
    for (final line in lines) {
      line.toJson();
      final original = owned[line.orderItemId];
      if (original == null ||
          catalogScaled(line.quantity, whole: 15, scale: 3) >
              catalogScaled(original.quantity, whole: 15, scale: 3)) {
        throw const FormatException('Shipment exceeds an order line');
      }
    }
    String? optional(String? text, int max) {
      if (text == null || text.trim().isEmpty) return null;
      return catalogString(text.trim(), max: max);
    }

    final payload = {
      'warehouseId': catalogId(warehouseId),
      'lines': lines.map((e) => e.toJson()).toList(),
      'carrierName': optional(carrierName, 160),
      'trackingReference': optional(trackingReference, 100),
    };
    final data = (await client.request('POST',
            '${_base(supplierId)}/orders/${catalogId(order.id)}/shipments',
            idempotencyKey: intent, body: payload))
        .data;
    return SupplierShipment.parse(data,
        supplierId: supplierId, orderId: order.id);
  }

  Future<SupplierShipmentDecision> progress({
    required String supplierId,
    required SupplierShipment shipment,
    required String stage,
  }) async {
    if (shipment.supplierId != supplierId ||
        shipment.status.nextStep != stage) {
      throw StateError('Shipment transition no longer available');
    }
    final expected = switch (stage) {
      'pack' => SupplierShipmentStatus.packed,
      'dispatch' => SupplierShipmentStatus.dispatched,
      'out-for-delivery' => SupplierShipmentStatus.outForDelivery,
      _ => throw StateError('Unsupported shipment stage'),
    };
    final data = (await client.request('POST',
            '${_base(supplierId)}/shipments/${catalogId(shipment.id)}/$stage',
            body: {}))
        .data;
    return SupplierShipmentDecision.parse(data,
        shipmentId: shipment.id, expected: expected);
  }

  /// Customer obtains OTP in THEIR app. Supplier may only submit the code
  /// personally given at the physical handover; never issue/read customer OTP.
  Future<SupplierShipmentDecision> verifyCustomerOtp({
    required String supplierId,
    required SupplierShipment shipment,
    required String otp,
    String? receivedBy,
  }) async {
    if (shipment.supplierId != supplierId ||
        shipment.status != SupplierShipmentStatus.outForDelivery ||
        !RegExp(r'^[0-9]{6}$').hasMatch(otp)) {
      throw const FormatException('Enter customer-issued six digit OTP');
    }
    final recipient = receivedBy?.trim();
    if (recipient != null &&
        recipient.isNotEmpty &&
        (recipient.length < 2 ||
            recipient.length > 160 ||
            recipient.runes.any((code) => code < 32 || code == 127))) {
      throw const FormatException('Invalid recipient name');
    }
    final data = (await client.request('POST',
            '${_base(supplierId)}/shipments/${catalogId(shipment.id)}/handover',
            body: {
          'method': 'OTP',
          'otp': otp,
          if (recipient != null && recipient.isNotEmpty) 'receivedBy': recipient
        }))
        .data;
    return SupplierShipmentDecision.parse(data,
        shipmentId: shipment.id, expected: SupplierShipmentStatus.delivered);
  }

  Future<SupplierShipmentDecision> cancel({
    required String supplierId,
    required SupplierShipment shipment,
    required String reason,
  }) async {
    if (shipment.supplierId != supplierId ||
        (shipment.status != SupplierShipmentStatus.planned &&
            shipment.status != SupplierShipmentStatus.packed)) {
      throw StateError('Only planned or packed shipments can be cancelled');
    }
    final trimmed = reason.trim();
    if (trimmed.length < 8 || trimmed.length > 500) {
      throw const FormatException('Reason must be between 8 and 500 characters');
    }
    final data = (await client.request(
      'POST',
      '${_base(supplierId)}/shipments/${catalogId(shipment.id)}/cancel',
      body: {'reason': trimmed},
    )).data;
    final row = catalogObject(data);
    final status = SupplierShipmentStatus.parse(row['status']);
    return SupplierShipmentDecision(
      id: shipment.id,
      status: status,
      replayed: row['replayed'] as bool? ?? false,
    );
  }
}
