import 'dart:math';
import '../api/supplier_v21_api.dart';
import '../catalog/supplier_catalog_models.dart';
import 'supplier_inventory_models.dart';

/// Stock mutations use the existing V2.1 transaction and version contracts.
/// Never infer available stock from a local quantity or make unsafe retries.
class SupplierInventoryRepository {
  const SupplierInventoryRepository(this.client);
  final SupplierV21Api client;

  String _scope(String supplierId) =>
      '/api/v2/suppliers/${catalogId(supplierId)}/inventory';

  Future<List<SupplierWarehouse>> warehouses(String supplierId) async {
    final data = (await client.get('${_scope(supplierId)}/warehouses')).data;
    return inventoryRecords(data,
        (row) => SupplierWarehouse.parse(row, supplierId),
        (SupplierWarehouse row) => row.id, limit: 100);
  }

  Future<List<SupplierStockBalance>> balances(String supplierId,
      {String? listingId}) async {
    final data = (await client.get('${_scope(supplierId)}/balances',
        query: listingId == null ? null :
            {'listingId': catalogId(listingId)})).data;
    return inventoryRecords(data, SupplierStockBalance.parse,
        (SupplierStockBalance row) => row.id);
  }

  Future<List<SupplierStockMovement>> movements(
      String supplierId, String warehouseId, {String? listingId}) async {
    final data = (await client.get(
      '${_scope(supplierId)}/warehouses/${catalogId(warehouseId)}/movements',
      query: listingId == null ? null :
          {'listingId': catalogId(listingId)},
    )).data;
    return inventoryRecords(data, SupplierStockMovement.parse,
        (SupplierStockMovement row) => row.id, limit: 100);
  }

  Future<SupplierWarehouse> createWarehouse(String supplierId,
      {required String code, required String name}) async {
    final normalized = code.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9][A-Z0-9._-]{0,79}$').hasMatch(normalized) ||
        name.trim().isEmpty || name.trim().length > 150) {
      throw const FormatException('Enter a valid warehouse code and name');
    }
    final data = (await client.request('POST',
        '${_scope(supplierId)}/warehouses',
        body: {'code': normalized, 'name': name.trim()})).data;
    return SupplierWarehouse.parse(data, supplierId);
  }

  Future<SupplierWarehouse> updateWarehouse(
      String supplierId, SupplierWarehouse warehouse,
      {String? name, bool? active}) async {
    if (warehouse.supplierId != supplierId ||
        (name == null && active == null)) {
      throw StateError('Invalid warehouse update');
    }
    final normalized = name?.trim();
    if (normalized != null &&
        (normalized.isEmpty || normalized.length > 150)) {
      throw const FormatException('Invalid warehouse name');
    }
    final data = (await client.request('PATCH',
        '${_scope(supplierId)}/warehouses/${catalogId(warehouse.id)}',
        body: {if (normalized != null) 'name': normalized,
          if (active != null) 'active': active})).data;
    return SupplierWarehouse.parse(data, supplierId);
  }

  Future<SupplierStockBalance> adjust({
    required String supplierId,
    required String listingId,
    required String warehouseId,
    required String kind,
    required String delta,
    required int expectedVersion,
    required String reason,
    required String intent,
  }) async {
    exactStockDelta(delta, kind);
    stockVersion(expectedVersion);
    if (reason.trim().isEmpty || reason.trim().length > 300) {
      throw const FormatException('A stock reason is required');
    }
    final response = await client.request('POST',
        '${_scope(supplierId)}/adjustments',
        idempotencyKey: intent,
        body: {
          'listingId': catalogId(listingId),
          'warehouseId': catalogId(warehouseId),
          'kind': kind,
          'delta': delta,
          'reason': reason.trim(),
          'expectedVersion': expectedVersion,
        });
    final payload = catalogObject(response.data);
    return SupplierStockBalance.parse(payload['currentBalance']);
  }

  Future<void> transfer({
    required String supplierId,
    required String listingId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required String quantity,
    required int expectedFromVersion,
    required int expectedToVersion,
    required String reason,
    required String intent,
  }) async {
    exactStockQuantity(quantity, allowZero: false);
    stockVersion(expectedFromVersion);
    stockVersion(expectedToVersion);
    if (fromWarehouseId == toWarehouseId ||
        reason.trim().isEmpty || reason.trim().length > 300) {
      throw const FormatException('Select two warehouses and a reason');
    }
    final response = await client.request('POST',
        '${_scope(supplierId)}/transfers', idempotencyKey: intent,
        body: {
          'listingId': catalogId(listingId),
          'fromWarehouseId': catalogId(fromWarehouseId),
          'toWarehouseId': catalogId(toWarehouseId),
          'quantity': quantity,
          'expectedFromVersion': expectedFromVersion,
          'expectedToVersion': expectedToVersion,
          'reason': reason.trim(),
        });
    final result = catalogObject(response.data);
    if (catalogId(result['listingId']) != listingId ||
        catalogId(result['fromWarehouseId']) != fromWarehouseId ||
        catalogId(result['toWarehouseId']) != toWarehouseId ||
        exactStockQuantity(result['quantity']) != quantity) {
      throw const FormatException('Unexpected stock transfer confirmation');
    }
  }
}

/// A fresh UUID is generated once per user intent, not on a network retry.
String supplierInventoryIntent() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
