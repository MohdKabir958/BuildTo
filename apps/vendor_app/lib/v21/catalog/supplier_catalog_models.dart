/// Strict V2.1 supplier catalog DTOs and exact decimal validators.
final _uuid = RegExp(r'^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$');
final _sku = RegExp(r'^[A-Z0-9][A-Z0-9._-]*$');

String catalogId(Object? value) {
  if (value is! String || !_uuid.hasMatch(value)) {
    throw const FormatException('Invalid catalog identifier');
  }
  return value;
}

Map<String, dynamic> catalogObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid catalog object');
  }
  return value;
}

String catalogString(Object? value, {int max = 250}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > max ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException('Invalid catalog text');
  }
  return value;
}

int catalogInt(Object? value, {int max = 2147483647}) {
  if (value is! int || value < 0 || value > max) {
    throw const FormatException('Invalid catalog integer');
  }
  return value;
}

/// Decimal validation converts to scaled BigInt; never to double.
BigInt catalogScaled(String value,
    {required int whole, required int scale, bool positive = true}) {
  final valid = switch ((whole, scale)) {
    (15, 3) => RegExp(r'^(?:0|[1-9][0-9]{0,14})(?:\.[0-9]{1,3})?$'),
    (14, 4) => RegExp(r'^(?:0|[1-9][0-9]{0,13})(?:\.[0-9]{1,4})?$'),
    _ => throw const FormatException('Unsupported decimal precision'),
  };
  if (!valid.hasMatch(value)) {
    throw const FormatException('Invalid exact decimal string');
  }
  final split = value.split('.');
  final scaled = BigInt.parse(
      split.first + (split.length == 2 ? split.last : '').padRight(scale, '0'));
  if (positive && scaled <= BigInt.zero) {
    throw const FormatException('Amount must be greater than zero');
  }
  return scaled;
}

String catalogQty(Object? value) {
  if (value is! String) throw const FormatException('Quantity not a string');
  catalogScaled(value, whole: 15, scale: 3);
  return value;
}

String catalogPrice(Object? value) {
  if (value is! String) throw const FormatException('Price not a string');
  catalogScaled(value, whole: 14, scale: 4);
  return value;
}

String catalogSku(String value) {
  final normalized = value.trim().toUpperCase();
  if (normalized.length > 100 || !_sku.hasMatch(normalized)) {
    throw const FormatException(
        'Use uppercase SKU letters, digits, dot, dash or underscore');
  }
  return normalized;
}

String catalogInr(String price) {
  catalogPrice(price);
  final parts = price.split('.');
  final fractional = parts.length == 2 ? parts[1] : '';
  final useful = fractional.padRight(2, '0');
  final digits = useful.length > 2 && int.parse(useful.substring(2)) != 0
      ? useful.replaceFirst(RegExp(r'0+$'), '')
      : useful.substring(0, 2);
  return '₹${parts[0]}.$digits';
}

/// Supplier-visible rupees to exact backend integer paise (never double).
String catalogPaiseFromRupees(String amount) {
  final normalized = amount.trim();
  if (!RegExp(r'^(?:0|[1-9][0-9]{0,16})(?:\.[0-9]{1,2})?$')
      .hasMatch(normalized)) {
    throw const FormatException('MRP must be in rupees, up to two decimals');
  }
  final parts = normalized.split('.');
  final paise = BigInt.parse(
      parts.first + (parts.length > 1 ? parts.last : '').padRight(2, '0'));
  if (paise > BigInt.parse('9223372036854775807')) {
    throw const FormatException('MRP exceeds permitted value');
  }
  return paise.toString();
}

/// Converts backend paise to display rupees without precision loss.
String catalogRupeesFromPaise(String paise) {
  if (!RegExp(r'^(?:0|[1-9][0-9]{0,18})$').hasMatch(paise) ||
      BigInt.parse(paise) > BigInt.parse('9223372036854775807')) {
    throw const FormatException('Invalid backend paise');
  }
  final pennies = BigInt.parse(paise);
  return (pennies ~/ BigInt.from(100)).toString() + '.' +
      (pennies % BigInt.from(100)).toString().padLeft(2, '0');
}

/// Human-friendly GST percent, exact conversion to backend basis points.
int catalogTaxBasisPoints(String percent) {
  final text = percent.trim();
  if (!RegExp(r'^(?:100(?:\.0{1,2})?|(?:0|[1-9][0-9]?)(?:\.[0-9]{1,2})?)$')
      .hasMatch(text)) {
    throw const FormatException('GST must be 0–100% with up to two decimals');
  }
  final parts = text.split('.');
  final basis = int.parse(parts.first) * 100 +
      int.parse((parts.length == 2 ? parts.last : '').padRight(2, '0'));
  if (basis > 10000) throw const FormatException('GST rate above 100%');
  return basis;
}

String catalogPercentFromBps(int rate) {
  if (rate < 0 || rate > 10000) {
    throw const FormatException('Invalid backend GST basis points');
  }
  final fraction = (rate % 100).toString().padLeft(2, '0');
  return rate % 100 == 0
      ? (rate ~/ 100).toString()
      : (rate ~/ 100).toString() + '.' +
        fraction.replaceFirst(RegExp(r'0+$'), '');
}

enum CatalogListingStatus {
  draft,
  pending,
  approved,
  rejected,
  suspended,
  archived;

  static CatalogListingStatus fromJson(Object? value) => switch (value) {
        'DRAFT' => draft,
        'PENDING' => pending,
        'APPROVED' => approved,
        'REJECTED' => rejected,
        'SUSPENDED' => suspended,
        'ARCHIVED' => archived,
        _ => throw const FormatException('Unknown listing review state'),
      };
  String get label => switch (this) {
        draft => 'Draft',
        pending => 'Under review',
        approved => 'Approved',
        rejected => 'Changes requested',
        suspended => 'Suspended',
        archived => 'Archived',
      };
  bool get canEdit => this == draft || this == rejected || this == approved;
  bool get canSubmit => this == draft || this == rejected;
  bool get canPrice => this != archived && this != suspended;
}

class CatalogCategory {
  const CatalogCategory(this.id, this.name);
  final String id, name;
  factory CatalogCategory.fromJson(Object? input) {
    final data = catalogObject(input);
    return CatalogCategory(catalogId(data['id']), catalogString(data['name']));
  }
}

class CatalogUnit {
  const CatalogUnit(this.code, this.name);
  final String code, name;
  factory CatalogUnit.fromJson(Object? input) {
    final data = catalogObject(input);
    final code = catalogString(data['code'], max: 20);
    if (!_sku.hasMatch(code)) throw const FormatException('Invalid unit code');
    return CatalogUnit(code, catalogString(data['name']));
  }
}

class CatalogProduct {
  const CatalogProduct(
      {required this.id,
      required this.code,
      required this.name,
      required this.categoryId,
      required this.categoryName,
      this.brandName,
      this.description});
  final String id, code, name, categoryId, categoryName;
  final String? brandName, description;
  factory CatalogProduct.fromJson(Object? input) {
    final data = catalogObject(input);
    final cat = catalogObject(data['category']);
    final brand = data['brand'];
    return CatalogProduct(
      id: catalogId(data['id']),
      code: catalogString(data['code']),
      name: catalogString(data['name']),
      categoryId: catalogId(cat['id']),
      categoryName: catalogString(cat['name']),
      brandName:
          brand == null ? null : catalogString(catalogObject(brand)['name']),
      description: data['description'] == null
          ? null
          : catalogString(data['description'], max: 3000),
    );
  }
}

class CatalogProductPage {
  const CatalogProductPage(this.items, this.nextCursor);
  final List<CatalogProduct> items;
  final String? nextCursor;
  factory CatalogProductPage.fromJson(Object? input) {
    final data = catalogObject(input);
    final next = data['nextCursor'];
    return CatalogProductPage(
        catalogList(
            data['items'], CatalogProduct.fromJson, (CatalogProduct x) => x.id,
            max: 25),
        next == null ? null : catalogId(next));
  }
}

class CatalogTier {
  const CatalogTier(this.minQty, this.pricePerUnit);
  final String minQty, pricePerUnit;
  factory CatalogTier.fromJson(Object? input) {
    final data = catalogObject(input);
    return CatalogTier(
        catalogQty(data['minQty']), catalogPrice(data['pricePerUnit']));
  }
  Map<String, Object?> toJson() => {
        'minQty': minQty,
        'pricePerUnit': pricePerUnit,
      };
}

void validateCatalogTiers(List<CatalogTier> tiers,
    {required String minOrderQty, required String unitPrice}) {
  if (tiers.length > 12) throw const FormatException('Maximum 12 price tiers');
  final floor = catalogScaled(minOrderQty, whole: 15, scale: 3);
  var priorMin = BigInt.zero;
  var priorPrice = catalogScaled(unitPrice, whole: 14, scale: 4);
  for (final tier in tiers) {
    final min = catalogScaled(tier.minQty, whole: 15, scale: 3);
    final price = catalogScaled(tier.pricePerUnit, whole: 14, scale: 4);
    if (min < floor || min <= priorMin || price > priorPrice) {
      throw const FormatException(
          'Tiers must increase in quantity and never increase in price');
    }
    priorMin = min;
    priorPrice = price;
  }
}

class CatalogListing {
  const CatalogListing({
    required this.id,
    required this.supplierId,
    required this.productId,
    required this.sku,
    required this.unitCode,
    required this.status,
    required this.active,
    required this.version,
    required this.packSize,
    required this.minOrderQty,
    required this.stepQty,
    required this.maxOrderQty,
    required this.unitPrice,
    required this.mrpPaise,
    required this.taxRateBps,
    required this.taxInclusive,
    required this.tiers,
  });
  final String id, supplierId, productId, sku, unitCode;
  final CatalogListingStatus status;
  final bool active, taxInclusive;
  final int version, taxRateBps;
  final String packSize, minOrderQty, stepQty, unitPrice;
  final String? maxOrderQty, mrpPaise;
  final List<CatalogTier> tiers;

  factory CatalogListing.fromJson(Object? input, String supplierId) {
    final data = catalogObject(input);
    if (catalogId(data['supplierId']) != supplierId) {
      throw const FormatException('Foreign supplier listing');
    }
    final state = CatalogListingStatus.fromJson(data['status']);
    if (data['active'] is! bool || data['taxInclusive'] is! bool) {
      throw const FormatException('Invalid listing flags');
    }
    final mrp = data['mrpPaise'];
    if (mrp != null &&
        (mrp is! String ||
            !RegExp(r'^(?:0|[1-9][0-9]{0,18})$').hasMatch(mrp) ||
            BigInt.parse(mrp) > BigInt.parse('9223372036854775807'))) {
      throw const FormatException('Invalid price MRP');
    }
    final min = catalogQty(data['minOrderQty']);
    final max =
        data['maxOrderQty'] == null ? null : catalogQty(data['maxOrderQty']);
    if (max != null &&
        catalogScaled(max, whole: 15, scale: 3) <
            catalogScaled(min, whole: 15, scale: 3)) {
      throw const FormatException('Maximum order below minimum');
    }
    final price = catalogPrice(data['unitPrice']);
    final tiers = catalogList(
        data['priceTiers'], CatalogTier.fromJson, (CatalogTier x) => x.minQty,
        max: 12);
    validateCatalogTiers(tiers, minOrderQty: min, unitPrice: price);
    return CatalogListing(
      id: catalogId(data['id']),
      supplierId: supplierId,
      productId: catalogId(data['productId']),
      sku: catalogSku(catalogString(data['sku'], max: 100)),
      unitCode: catalogString(data['unitCode'], max: 20),
      status: state,
      active: data['active'] as bool,
      version: catalogInt(data['version']),
      packSize: catalogQty(data['packSize']),
      minOrderQty: min,
      stepQty: catalogQty(data['stepQty']),
      maxOrderQty: max,
      unitPrice: price,
      mrpPaise: mrp as String?,
      taxRateBps: catalogInt(data['taxRateBps'], max: 10000),
      taxInclusive: data['taxInclusive'] as bool,
      tiers: tiers,
    );
  }
}

List<T> catalogList<T>(
    Object? value, T Function(Object?) parse, String Function(T) id,
    {int max = 100}) {
  if (value is! List<dynamic> || value.length > max) {
    throw const FormatException('Invalid bounded catalog data');
  }
  final items = value.map(parse).toList(growable: false);
  if (items.map(id).toSet().length != items.length) {
    throw const FormatException('Duplicate catalog identity');
  }
  return List.unmodifiable(items);
}
