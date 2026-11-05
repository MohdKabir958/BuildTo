/// Strict, fail-closed data models for V2.1 supplier identity and read-only
/// reference catalogs. Unknown role values are never treated as OWNER.
enum SupplierMemberRole {
  owner, manager, catalog, inventory, fulfillment, finance, viewer;

  static SupplierMemberRole fromWire(Object? value) {
    if (value is! String) throw const FormatException('Supplier role missing');
    for (final role in values) {
      if (role.name.toUpperCase() == value) return role;
    }
    throw const FormatException('Unknown supplier role');
  }
}

String _str(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Invalid or missing ' + field);
}

Map<String, dynamic> _obj(Object? value, String name) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Expected ' + name + ' object');
}

class SupplierMembership {
  const SupplierMembership({required this.supplierId, required this.role});
  final String supplierId;
  final SupplierMemberRole role;

  factory SupplierMembership.fromJson(Object? raw) {
    final json = _obj(raw, 'supplier membership');
    return SupplierMembership(
      supplierId: _str(json['supplierId'], 'supplierId'),
      role: SupplierMemberRole.fromWire(json['role']),
    );
  }
}

class SupplierIdentity {
  const SupplierIdentity({
    required this.id,
    required this.displayName,
    required this.suppliers,
  });
  final String id;
  final String displayName;
  final List<SupplierMembership> suppliers;

  factory SupplierIdentity.fromJson(Object? raw) {
    final json = _obj(raw, 'identity');
    final memberships = json['suppliers'];
    if (memberships is! List) {
      throw const FormatException('Missing server memberships');
    }
    return SupplierIdentity(
      id: _str(json['id'], 'id'),
      displayName: _str(json['displayName'], 'displayName'),
      suppliers: List.unmodifiable(
        memberships.map(SupplierMembership.fromJson)),
    );
  }
}

class SupplierAccess {
  const SupplierAccess({required this.supplierId, required this.role});
  final String supplierId;
  final SupplierMemberRole role;

  factory SupplierAccess.fromJson(Object? raw) {
    final json = _obj(raw, 'supplier access');
    return SupplierAccess(
      supplierId: _str(json['supplierId'], 'supplierId'),
      role: SupplierMemberRole.fromWire(json['role']),
    );
  }
}

class MaterialCategory {
  const MaterialCategory({
    required this.id,
    required this.slug,
    required this.name,
  });
  final String id;
  final String slug;
  final String name;

  factory MaterialCategory.fromJson(Object? raw) {
    final json = _obj(raw, 'category');
    return MaterialCategory(
      id: _str(json['id'], 'id'),
      slug: _str(json['slug'], 'slug'),
      name: _str(json['name'], 'name'),
    );
  }
}

class SupplierSystemInfo {
  const SupplierSystemInfo({
    required this.apiVersion,
    required this.releaseStage,
    required this.productionReady,
    required this.capabilities,
  });
  final String apiVersion;
  final String releaseStage;
  final bool productionReady;
  final List<String> capabilities;

  factory SupplierSystemInfo.fromJson(Object? raw) {
    final json = _obj(raw, 'system info');
    final version = _str(json['apiVersion'], 'apiVersion');
    if (version != 'v2') throw const FormatException('Unsupported API version');
    if (json['productionReady'] is! bool || json['capabilities'] is! List) {
      throw const FormatException('Malformed V2.1 capability declaration');
    }
    final capabilities = json['capabilities'] as List;
    if (capabilities.any((x) => x is! String)) {
      throw const FormatException('Invalid capabilities');
    }
    return SupplierSystemInfo(
      apiVersion: version,
      releaseStage: _str(json['releaseStage'], 'releaseStage'),
      productionReady: json['productionReady'] as bool,
      capabilities: List.unmodifiable(capabilities.cast<String>()),
    );
  }
}

/// Money values arrive from the server in **integer paise strings**.
/// Never convert supplier prices, settlements or GST into a double.
class ExactPaise {
  ExactPaise._(this.value);
  final BigInt value;

  factory ExactPaise.parse(String text) {
    if (!RegExp(r'^-?[0-9]+$').hasMatch(text)) {
      throw const FormatException('Expected exact integer paise string');
    }
    return ExactPaise._(BigInt.parse(text));
  }

  String formatInr({bool showZeroPaise = false}) {
    final absValue = value.abs();
    final rupees = (absValue ~/ BigInt.from(100)).toString();
    final digits = StringBuffer();
    if (rupees.length <= 3) {
      digits.write(rupees);
    } else {
      final head = rupees.substring(0, rupees.length - 3);
      for (var i = 0; i < head.length; i++) {
        if (i > 0 && (head.length - i) % 2 == 0) digits.write(',');
        digits.write(head[i]);
      }
      digits.write(',');
      digits.write(rupees.substring(rupees.length - 3));
    }
    final paise = (absValue % BigInt.from(100)).toInt();
    final fractional = paise == 0 && !showZeroPaise
        ? '' : '.' + paise.toString().padLeft(2, '0');
    return (value.isNegative ? '-' : '') + '₹' + digits.toString() + fractional;
  }
}

/// Quantity string carrier. Validation prevents accidentally using locale
/// float values or JavaScript-style numeric rounding in mutation forms.
class ExactMaterialQuantity {
  const ExactMaterialQuantity._(this.value);
  final String value;

  factory ExactMaterialQuantity.parse(String raw) {
    if (!RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(raw)) {
      throw const FormatException('Expected canonical decimal quantity string');
    }
    return ExactMaterialQuantity._(raw);
  }
}
