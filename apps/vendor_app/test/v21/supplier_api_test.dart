import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';

void main() {
  final origin = Uri.parse('https://buildto-v21-staging.onrender.com');

  test('release denies HTTP and credentials in API origin', () {
    expect(() => SupplierV21Config.parseOrigin('http://example.com', release: true), throwsStateError);
    expect(() => SupplierV21Config.parseOrigin('https://name:pass@example.com', release: true), throwsStateError);
    expect(() => SupplierV21Config.parseOrigin('https://example.com/api', release: true), throwsStateError);
    expect(() => SupplierV21Config.parseOrigin('https://example.com?key=secret', release: true), throwsStateError);
    expect(SupplierV21Config.parseOrigin('https://example.com', release: true).host, 'example.com');
    expect(SupplierV21Config.parseOrigin('http://10.0.2.2:5000', release: false).host, '10.0.2.2');
  });

  test('authenticated request uses V2.1 path and explicit token source', () async {
    final api = SupplierV21Api(origin: origin, token: () async => 'test-session',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v2/me');
        expect(request.headers['Authorization'], 'Bearer test-session');
        return http.Response('{"data":{"adminRole":null,"suppliers":[]},"requestId":"req-1"}', 200);
      }));
    final result = await api.get('/api/v2/me');
    expect(result.requestId, 'req-1');
    expect(result.requireObject()['suppliers'], isEmpty);
    api.close();
  });

  test('rejects protected calls without a Clerk token before sending', () async {
    var calls = 0;
    final api = SupplierV21Api(origin: origin, token: () async => null,
      httpClient: MockClient((request) async { calls++; return http.Response('{}', 200); }));
    await expectLater(api.get('/api/v2/me'), throwsA(isA<SupplierV21Exception>()
      .having((e) => e.problem, 'problem', SupplierV21Problem.authentication)));
    expect(calls, 0);
    api.close();
  });

  test('disallows legacy endpoints, query strings and off-domain URLs', () async {
    final api = SupplierV21Api(origin: origin, token: () async => 'token',
      httpClient: MockClient((request) async => http.Response('{}', 200)));
    for (final path in ['/api/orders', 'https://attacker.invalid/api/v2/me',
      '/api/v2/me?role=OWNER', '/api/v2/../admin', '/api/v2//me']) {
      await expectLater(api.get(path), throwsArgumentError);
    }
    api.close();
  });

  test('preserves mutation Idempotency-Key and version header', () async {
    final api = SupplierV21Api(origin: origin, token: () async => 'token',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.headers['Idempotency-Key'], 'one-intent-id');
        expect(request.headers['If-Match'], '8');
        expect(request.body, '{"quantity":"1.250"}');
        return http.Response('{"data":{"id":"stock-movement-1"},"requestId":"req-2"}', 201);
      }));
    final result = await api.request('POST', '/api/v2/suppliers/supplier-id/inventory/adjustments',
      body: {'quantity': '1.250'}, idempotencyKey: 'one-intent-id', ifMatch: '8');
    expect(result.requireObject()['id'], 'stock-movement-1');
    api.close();
  });

  test('maps conflict and rate limiting without claiming success', () async {
    final client = MockClient((request) async => request.url.path.endsWith('/me')
      ? http.Response('{"error":{"code":"LISTING_VERSION_CONFLICT"},"requestId":"req-3"}', 409)
      : http.Response('{"error":{"code":"RATE_LIMITED"}}', 429,
          headers: {'retry-after': '7'}));
    final api = SupplierV21Api(origin: origin, token: () async => 'token', httpClient: client);
    await expectLater(api.get('/api/v2/me'), throwsA(isA<SupplierV21Exception>()
      .having((e) => e.problem, 'problem', SupplierV21Problem.conflict)
      .having((e) => e.requestId, 'requestId', 'req-3')));
    await expectLater(api.get('/api/v2/suppliers/id/orders'), throwsA(isA<SupplierV21Exception>()
      .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 7))));
    api.close();
  });

  test('timeout is an unknown outcome and never implicitly retried', () async {
    var calls = 0;
    final api = SupplierV21Api(origin: origin, token: () async => 'token',
      timeout: const Duration(milliseconds: 5),
      httpClient: MockClient((request) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('{"data":{"success":true}}', 200);
      }));
    await expectLater(api.request('POST', '/api/v2/suppliers/id/inventory/adjustments',
      body: {'quantity': '1'}, idempotencyKey: 'stable'),
      throwsA(isA<SupplierV21Exception>()
        .having((e) => e.code, 'code', 'TIMEOUT_UNKNOWN_OUTCOME')));
    expect(calls, 1);
    api.close();
  });

  test('malformed and unwrapped responses fail closed', () async {
    final api = SupplierV21Api(origin: origin, token: () async => 'token',
      httpClient: MockClient((request) async => http.Response('{"ok":true}', 200)));
    await expectLater(api.get('/api/v2/me'), throwsA(isA<SupplierV21Exception>()
      .having((e) => e.problem, 'problem', SupplierV21Problem.invalidResponse)));
    api.close();
  });
}
