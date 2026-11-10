/// Strict V2.1 identity projections. No JWT metadata or local role
/// inference: only the backend's approved, active memberships are accepted.
enum SupplierV21Role {
  owner,
  manager,
  catalog,
  inventory,
  fulfillment,
  finance,
  viewer
}

class SupplierV21Membership {
  const SupplierV21Membership({required this.supplierId, required this.role});
  final String supplierId;
  final SupplierV21Role role;

  static SupplierV21Membership fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected supplier membership object');
    }
    final id = value['supplierId'];
    final role = value['role'];
    if (id is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
            .hasMatch(id)) {
      throw const FormatException('Invalid supplier membership identity');
    }
    final known = switch (role) {
      'OWNER' => SupplierV21Role.owner,
      'MANAGER' => SupplierV21Role.manager,
      'CATALOG' => SupplierV21Role.catalog,
      'INVENTORY' => SupplierV21Role.inventory,
      'FULFILLMENT' => SupplierV21Role.fulfillment,
      'FINANCE' => SupplierV21Role.finance,
      'VIEWER' => SupplierV21Role.viewer,
      _ => null,
    };
    if (known == null) {
      throw const FormatException('Unknown supplier permission');
    }
    return SupplierV21Membership(supplierId: id, role: known);
  }
}

class SupplierV21Identity {
  const SupplierV21Identity({
    required this.id,
    required this.displayName,
    required this.suppliers,
  });
  final String id;
  final String displayName;
  final List<SupplierV21Membership> suppliers;

  factory SupplierV21Identity.fromJson(Map<String, Object?> value) {
    final id = value['id'];
    final name = value['displayName'];
    final suppliers = value['suppliers'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        suppliers is! List<dynamic> ||
        suppliers.length > 100) {
      throw const FormatException('Malformed supplier account projection');
    }
    final memberships =
        suppliers.map(SupplierV21Membership.fromJson).toList(growable: false);
    if (memberships.map((item) => item.supplierId).toSet().length !=
        memberships.length) {
      throw const FormatException('Duplicate supplier memberships');
    }
    return SupplierV21Identity(
        id: id, displayName: name, suppliers: List.unmodifiable(memberships));
  }
}
