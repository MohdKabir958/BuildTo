import '../catalog/supplier_catalog_models.dart';

final _quantityPattern = RegExp(r'^(?:0|[1-9][0-9]{0,14})(?:\.[0-9]{1,3})?$');

String exactStockQuantity(Object? value, {bool allowZero = true}) {
  if (value is! String || !_quantityPattern.hasMatch(value)) {
    throw const FormatException('Invalid exact stock quantity');
  }
  if (!allowZero &&
      catalogScaled(value, whole: 15, scale: 3, positive: false) ==
          BigInt.zero) {
    throw const FormatException('Quantity must be greater than zero');
  }
  return value;
}

String exactStockDelta(String value, String kind) {
  final isNegative = value.startsWith('-');
  final unsigned = isNegative ? value.substring(1) : value;
  exactStockQuantity(unsigned, allowZero: false);
  if (kind == 'RECEIPT' && isNegative ||
      kind == 'DAMAGE' && !isNegative ||
      !{'RECEIPT', 'DAMAGE', 'ADJUSTMENT'}.contains(kind)) {
    throw const FormatException('Invalid stock movement direction');
  }
  return value;
}

int stockVersion(Object? value) {
  if (value is! int || value < 0 || value > 2147483646) {
    throw const FormatException('Invalid stock version');
  }
  return value;
}

List<T> inventoryRecords<T>(
  Object? value,
  T Function(Object?) parse,
  String Function(T) identity, {
  int limit = 200,
}) {
  if (value is! List<dynamic> || value.length > limit) {
    throw const FormatException('Invalid bounded inventory response');
  }
  final rows = value.map(parse).toList(growable: false);
  if (rows.map(identity).toSet().length != rows.length) {
    throw const FormatException('Duplicate inventory record');
  }
  return List.unmodifiable(rows);
}

class SupplierWarehouse {
  const SupplierWarehouse({
    required this.id,
    required this.supplierId,
    required this.code,
    required this.name,
    required this.active,
  });
  final String id, supplierId, code, name;
  final bool active;

  factory SupplierWarehouse.parse(Object? raw, String supplierId) {
    final data = catalogObject(raw);
    if (catalogId(data['supplierId']) != supplierId ||
        data['active'] is! bool) {
      throw const FormatException('Foreign or invalid supplier warehouse');
    }
    return SupplierWarehouse(
      id: catalogId(data['id']),
      supplierId: supplierId,
      code: catalogString(data['code'], max: 80),
      name: catalogString(data['name'], max: 150),
      active: data['active'] as bool,
    );
  }
}

class SupplierStockBalance {
  const SupplierStockBalance({
    required this.id,
    required this.listingId,
    required this.warehouseId,
    required this.onHandQty,
    required this.reservedQty,
    required this.availableQty,
    required this.version,
  });
  final String id, listingId, warehouseId;
  final String onHandQty, reservedQty, availableQty;
  final int version;

  factory SupplierStockBalance.parse(Object? raw) {
    final data = catalogObject(raw);
    final onHand = exactStockQuantity(data['onHandQty']);
    final reserved = exactStockQuantity(data['reservedQty']);
    final available = exactStockQuantity(data['availableQty']);
    final sum = catalogScaled(reserved, whole: 15, scale: 3, positive: false) +
        catalogScaled(available, whole: 15, scale: 3, positive: false);
    if (sum != catalogScaled(onHand, whole: 15, scale: 3, positive: false)) {
      throw const FormatException('Stock availability does not reconcile');
    }
    return SupplierStockBalance(
      id: catalogId(data['id']),
      listingId: catalogId(data['listingId']),
      warehouseId: catalogId(data['warehouseId']),
      onHandQty: onHand,
      reservedQty: reserved,
      availableQty: available,
      version: stockVersion(data['version']),
    );
  }
}

class SupplierStockMovement {
  const SupplierStockMovement({
    required this.id,
    required this.listingId,
    required this.warehouseId,
    required this.kind,
    required this.delta,
    required this.reason,
    required this.createdAt,
  });
  final String id, listingId, warehouseId, kind, delta, reason;
  final DateTime createdAt;

  factory SupplierStockMovement.parse(Object? raw) {
    final data = catalogObject(raw);
    final kind = catalogString(data['kind'], max: 40);
    final delta = catalogString(data['delta'], max: 22);
    if (!{
      'RECEIPT',
      'DAMAGE',
      'ADJUSTMENT',
      'TRANSFER_IN',
      'TRANSFER_OUT',
      'SALE',
      'RESERVATION_RELEASE',
      'RETURN',
    }.contains(kind)) {
      throw const FormatException('Unknown stock movement');
    }
    final absolute = delta.startsWith('-') ? delta.substring(1) : delta;
    exactStockQuantity(absolute);
    final date = DateTime.tryParse(catalogString(data['createdAt']));
    if (date == null || !date.isUtc) {
      throw const FormatException('Invalid movement timestamp');
    }
    return SupplierStockMovement(
      id: catalogId(data['id']),
      listingId: catalogId(data['listingId']),
      warehouseId: catalogId(data['warehouseId']),
      kind: kind,
      delta: delta,
      reason: data['reason'] == null
          ? 'System movement'
          : catalogString(data['reason'], max: 300),
      createdAt: date,
    );
  }
}
