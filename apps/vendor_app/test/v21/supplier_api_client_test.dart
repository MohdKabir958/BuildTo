import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/network/supplier_api_client.dart';
import 'package:vendor_app/v21/network/supplier_models.dart';

const origin = 'https://buildto-v21-staging.onrender.com';
const supplierId = '12345678-1234-1234-1234-1234567890ab';

String envelope(Object data) => jsonEncode({
  'data': data,
  'requestId': 'req-test',
});

SupplierApiClient client(
  http.Client httpClient, {SupplierTokenProvider? tokenProvider}) {
  return SupplierApiClient(
    config: SupplierApiConfig.fromOrigin(origin),
    client: httpClient,
    tokenProvider: tokenProvider,
  );
}

void main() {
  test('origin must be explicit, clean, HTTPS and without credentials', () {
    expect(() => SupplierApiConfig.fromOrigin(''), throwsFormatException);
    expect(() => SupplierApiConfig.fromOrigin('https://x.invalid/api'),
        throwsFormatException);
    expect(() => SupplierApiConfig.fromOrigin('https://u:p@x.invalid'),
        throwsFormatException);
    expect(() => SupplierApiConfig.fromOrigin('http://x.invalid'),
        throwsFormatException);
    expect(SupplierApiConfig.fromOrigin(origin).origin.host,
        'buildto-v21-staging.onrender.com');
  });

  test('reads real public-category shape and never adds auth unnecessarily',
      () async {
    final api = client(MockClient((request) async {
      expect(request.url.path, '/api/v2/catalog/categories');
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response(envelope([{
        'id': supplierId, 'name': 'Cement', 'slug': 'cement',
        'displayOrder': 1, 'parentId': null,
      }]), 200);
    }));
    final result = await api.categories();
    expect(result.requestId, 'req-test');
    expect(result.data.single.name, 'Cement');
  });

  test('requires a valid token before protected network calls', () async {
    var requests = 0;
    final api = client(MockClient((request) async {
      requests++;
      return http.Response('{}', 200);
    }));
    await expectLater(api.identity(), throwsA(isA<SupplierSessionMissing>()));
    expect(requests, 0);
  });

  test('reads verified identity and exact selected-supplier access',
      () async {
    var calls = 0;
    final api = client(
      MockClient((request) async {
        calls++;
        expect(request.headers['Authorization'], 'Bearer sdk-session-token');
        if (request.url.path == '/api/v2/me') {
          return http.Response(envelope({
            'id': 'user-uuid', 'displayName': 'BuildTo Supplier',
            'adminRole': null,
            'suppliers': [{'supplierId': supplierId, 'role': 'MANAGER'}],
          }), 200);
        }
        expect(request.url.path,
            '/api/v2/suppliers/' + supplierId + '/access');
        return http.Response(envelope({
          'supplierId': supplierId, 'role': 'MANAGER',
        }), 200);
      }),
      tokenProvider: () async => 'sdk-session-token',
    );
    final me = (await api.identity()).data;
    expect(me.suppliers.single.role, SupplierMemberRole.manager);
    final access = (await api.access(supplierId)).data;
    expect(access.role, SupplierMemberRole.manager);
    expect(calls, 2);
  });

  test('unknown role fails closed and never means approved or owner', () async {
    expect(() => SupplierMemberRole.fromWire('SUPERUSER'), throwsFormatException);
    final api = client(
      MockClient((_) async => http.Response(envelope({
        'id': 'user-uuid', 'displayName': 'Unknown',
        'suppliers': [{'supplierId': supplierId, 'role': 'UNKNOWN'}],
      }), 200)),
      tokenProvider: () async => 'fixture',
    );
    await expectLater(api.identity(), throwsA(isA<SupplierProtocolFailure>()));
  });

  test('supplier IDs must be valid before network access', () async {
    final api = client(MockClient((_) async {
      fail('Invalid supplier ID must never cause a request');
    }), tokenProvider: () async => 'fixture');
    expect(() => api.access('../other-supplier'), throwsFormatException);
  });

  test('propagates explicit backend 401 with request ID', () async {
    final api = client(MockClient((_) async => http.Response(
      jsonEncode({
        'error': {'code': 'INVALID_SESSION', 'message': 'Sign in required.'},
        'requestId': 'req-401',
      }), 401,
    )), tokenProvider: () async => 'fixture');
    try {
      await api.identity();
      fail('Expected backend failure');
    } on SupplierServerFailure catch (error) {
      expect(error.status, 401);
      expect(error.code, 'INVALID_SESSION');
      expect(error.requestId, 'req-401');
    }
  });

  test('malformed error and malformed successful envelopes fail closed',
      () async {
    final invalidResponse = client(
      MockClient((_) async => http.Response('not-json', 500)));
    await expectLater(invalidResponse.system(),
      throwsA(isA<SupplierProtocolFailure>()));
    final invalidSuccess = client(
      MockClient((_) async => http.Response('{"data":[]}', 200)));
    await expectLater(invalidSuccess.categories(),
      throwsA(isA<SupplierProtocolFailure>()));
  });

  test('system information reports staging state, not production claims',
      () async {
    final api = client(MockClient((_) async => http.Response(envelope({
      'apiVersion': 'v2',
      'releaseStage': 'unreleased-staging-candidate',
      'productionReady': false,
      'capabilities': ['catalog.discovery'],
    }), 200)));
    final status = (await api.system()).data;
    expect(status.productionReady, isFalse);
    expect(status.releaseStage, 'unreleased-staging-candidate');
  });

  test('paise conversion is exact for huge and negative values', () {
    expect(ExactPaise.parse('123456789').formatInr(), '₹12,34,567.89');
    expect(ExactPaise.parse('-125').formatInr(), '-₹1.25');
    expect(ExactPaise.parse('100').formatInr(showZeroPaise: true), '₹1.00');
    expect(ExactPaise.parse('9999999999999999999999').formatInr(),
        '₹9,99,99,99,99,99,99,99,99,999.99');
    expect(() => ExactPaise.parse('1.2'), throwsFormatException);
    expect(() => ExactPaise.parse('NaN'), throwsFormatException);
  });

  test('material quantities preserve decimal strings without floats', () {
    expect(ExactMaterialQuantity.parse('12.0001').value, '12.0001');
    expect(() => ExactMaterialQuantity.parse('12,50'), throwsFormatException);
    expect(() => ExactMaterialQuantity.parse('-1'), throwsFormatException);
  });
}
