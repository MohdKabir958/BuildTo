import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/v21/api/supplier_v21_models.dart';

void main() {
  const supplierId = '123e4567-e89b-12d3-a456-426614174000';

  test('accepts a backend-scoped supplier membership', () {
    final identity = SupplierV21Identity.fromJson({
      'id': 'user-db-id',
      'displayName': 'Verified Supplier',
      'adminRole': null,
      'suppliers': [
        {'supplierId': supplierId, 'role': 'OWNER'}
      ],
    });
    expect(identity.suppliers.single.supplierId, supplierId);
    expect(identity.suppliers.single.role, SupplierV21Role.owner);
  });

  test('unknown role cannot become an approved supplier', () {
    expect(() => SupplierV21Membership.fromJson({
      'supplierId': supplierId, 'role': 'SUPER_ADMIN'
    }), throwsFormatException);
    expect(() => SupplierV21Membership.fromJson({
      'supplierId': supplierId, 'role': null
    }), throwsFormatException);
  });

  test('missing and invalid membership identity fail closed', () {
    expect(() => SupplierV21Membership.fromJson({
      'supplierId': '', 'role': 'OWNER'
    }), throwsFormatException);
    expect(() => SupplierV21Identity.fromJson({
      'id': 'db-id', 'displayName': 'Example'
    }), throwsFormatException);
  });

  test('membership spoofing or duplicate supplier scope is rejected', () {
    expect(() => SupplierV21Identity.fromJson({
      'id': 'user', 'displayName': 'Example',
      'suppliers': [
        {'supplierId': supplierId, 'role': 'OWNER'},
        {'supplierId': supplierId, 'role': 'VIEWER'},
      ],
    }), throwsFormatException);
  });
}
