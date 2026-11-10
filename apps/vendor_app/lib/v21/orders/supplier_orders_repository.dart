import '../api/supplier_v21_api.dart';
import '../catalog/supplier_catalog_models.dart';
import '../dashboard/supplier_dashboard_models.dart';
import '../delivery/supplier_delivery_models.dart';

class SupplierOrderLine {
  const SupplierOrderLine({
    required this.id,
    required this.sku,
    required this.quantity,
    required this.unitCode,
  });
  final String id, sku, quantity, unitCode;

  factory SupplierOrderLine.parse(Object? value) {
    final json = catalogObject(value);
    final sku = catalogString(json['sku'], max: 120);
    final unitCode = catalogString(json['unitCode'], max: 20);
    if (!RegExp(r'^[A-Z0-9][A-Z0-9._-]*$').hasMatch(unitCode)) {
      throw const FormatException('Invalid order unit');
    }
    return SupplierOrderLine(
      id: catalogId(json['id']),
      sku: sku,
      quantity: catalogQty(json['quantity']),
      unitCode: unitCode,
    );
  }
}

class SupplierOrder {
  const SupplierOrder({
    required this.id,
    required this.purchaseOrderId,
    required this.status,
    required this.totalPaise,
    required this.createdAt,
    required this.items,
  });
  final String id, purchaseOrderId, totalPaise;
  final DashboardOrderStatus status;
  final DateTime createdAt;
  final List<SupplierOrderLine> items;

  bool get pending => status == DashboardOrderStatus.pendingAcceptance;

  factory SupplierOrder.parse(Object? value) {
    final json = catalogObject(value);
    final timestamp = catalogString(json['createdAt'], max: 40);
    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) {
      throw const FormatException('Invalid supplier order date');
    }
    final items = deliveryRows(
      json['items'],
      SupplierOrderLine.parse,
      (SupplierOrderLine line) => line.id,
      max: 100,
    );
    if (items.isEmpty) {
      throw const FormatException('Order has no lines');
    }
    return SupplierOrder(
      id: catalogId(json['id']),
      purchaseOrderId: catalogId(json['purchaseOrderId']),
      status: DashboardOrderStatus.parse(json['status']),
      totalPaise: deliveryPaise(json['totalPaise']),
      createdAt: parsed,
      items: items,
    );
  }
}

class SupplierOrderDecision {
  const SupplierOrderDecision({
    required this.id,
    required this.status,
    required this.replayed,
  });
  final String id;
  final DashboardOrderStatus status;
  final bool replayed;

  factory SupplierOrderDecision.parse(Object? value, String expectedId) {
    final json = catalogObject(value);
    if (catalogId(json['id']) != expectedId || json['replayed'] is! bool) {
      throw const FormatException('Unexpected order decision response');
    }
    return SupplierOrderDecision(
      id: expectedId,
      status: DashboardOrderStatus.parse(json['status']),
      replayed: json['replayed'] as bool,
    );
  }
}

/// All mutations are guarded by payment, supplier scope and committed stock on
/// the V2.1 server. A list entry does not prove payment eligibility.
class SupplierOrdersRepository {
  const SupplierOrdersRepository(this.client);
  final SupplierV21Api client;

  String _scope(String supplierId) =>
      '/api/v2/suppliers/${catalogId(supplierId)}/orders';

  Future<List<SupplierOrder>> orders(String supplierId) async {
    final data = (await client.get(_scope(supplierId))).data;
    return deliveryRows(
        data, SupplierOrder.parse, (SupplierOrder order) => order.id);
  }

  Future<SupplierOrderDecision> accept(
      String supplierId, String supplierOrderId) async {
    final id = catalogId(supplierOrderId);
    final data = (await client
            .request('POST', '${_scope(supplierId)}/$id/accept', body: {}))
        .data;
    final result = SupplierOrderDecision.parse(data, id);
    if (result.status != DashboardOrderStatus.confirmed) {
      throw const FormatException('Order was not confirmed by the server');
    }
    return result;
  }

  Future<SupplierOrderDecision> rejectUnpaid({
    required String supplierId,
    required String supplierOrderId,
    required String reason,
  }) async {
    final cleaned = reason.trim();
    if (cleaned.length < 12 ||
        cleaned.length > 200 ||
        cleaned.runes.any((code) => code < 32 || code == 127)) {
      throw const FormatException(
          'Provide an audit reason (12–200 characters)');
    }
    final id = catalogId(supplierOrderId);
    final data = (await client.request(
            'POST', '${_scope(supplierId)}/$id/reject',
            body: {'reason': cleaned}))
        .data;
    final result = SupplierOrderDecision.parse(data, id);
    if (result.status != DashboardOrderStatus.rejected) {
      throw const FormatException('Order refusal was not confirmed');
    }
    return result;
  }
}
