import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/v21/auth/supplier_release_policy.dart';

void main() {
  test('debug staging mode is permitted for isolated test fixtures', () {
    expect(
        () => SupplierReleasePolicy.validate(
              release: false,
              authMode: 'clerk-test',
              apiOrigin: 'https://buildto-v21-staging.onrender.com',
            ),
        returnsNormally);
  });

  test('release blocks test auth even on an explicitly approved origin', () {
    expect(
        () => SupplierReleasePolicy.validate(
              release: true,
              authMode: 'clerk-test',
              apiOrigin: 'https://api.buildto.in',
              productionHost: 'api.buildto.in',
            ),
        throwsStateError);
  });

  test('release blocks implicit trusted host and staging targets', () {
    expect(
        () => SupplierReleasePolicy.validate(
              release: true,
              authMode: 'clerk',
              apiOrigin: 'https://api.buildto.in',
              productionHost: '',
            ),
        throwsStateError);
    expect(
        () => SupplierReleasePolicy.validate(
              release: true,
              authMode: 'clerk',
              apiOrigin: 'https://buildto-v21-staging.onrender.com',
              productionHost: 'buildto-v21-staging.onrender.com',
            ),
        throwsStateError);
  });

  test('release blocks wrong origin, http and nonstandard port', () {
    expect(
        () => SupplierReleasePolicy.validate(
              release: true,
              authMode: 'clerk',
              apiOrigin: 'https://not-buildto.in',
              productionHost: 'api.buildto.in',
            ),
        throwsStateError);
    expect(
        () => SupplierReleasePolicy.validate(
              release: true,
              authMode: 'clerk',
              apiOrigin: 'http://api.buildto.in',
              productionHost: 'api.buildto.in',
            ),
        throwsStateError);
    expect(
        () => SupplierReleasePolicy.validate(
              release: true,
              authMode: 'clerk',
              apiOrigin: 'https://api.buildto.in:8443',
              productionHost: 'api.buildto.in',
            ),
        throwsStateError);
  });

  test('correct production Clerk and matching production host pass policy', () {
    expect(
        () => SupplierReleasePolicy.validate(
              release: true,
              authMode: 'clerk',
              apiOrigin: 'https://api.buildto.in',
              productionHost: 'api.buildto.in',
            ),
        returnsNormally);
  });
}
