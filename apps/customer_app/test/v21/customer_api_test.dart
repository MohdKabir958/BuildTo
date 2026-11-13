import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:customer_app/v21/customer_api.dart';
import 'customer_fixture.dart';

void main() {
  test('exact money, unit quantities and empty envelopes', () {
    expect(money('123456789012345'), '₹12,34,56,78,90,123.45');
    expect(price('390.50'), '₹390.50');
    expect(price('1.2345'), '₹1.2345');
    expect(estimatedLinePaise({'unitPrice': '1.2345', 'quantity': '10.125'}),
        BigInt.from(1250));
    expect(decimal(scaled('10.125', 3), 3), '10.125');
    expect(quantityStep('10', '10', '0.125', null, 1), '10.125');
    expect(quantityStep('10', '10', '5', null, -1), '10');
    expect(quantityStep('10', '10', '5', '12', 1), '10');
    expect(rows(null), isEmpty);
    expect(rows({'items': []}), isEmpty);
    expect(() => scaled('1e3', 3), throwsFormatException);
  });
  test('origin and image boundaries reject credential leakage', () {
    for (final s in [
      'http://example.com',
      'https://user:pass@example.com',
      'https://example.com/api',
      'https://example.com?x=1',
      'https://example.com#x'
    ]) {
      expect(() => CustomerApi.parseOrigin(s), throwsA(isA<CustomerProblem>()));
    }
    final f = CustomerFixture();
    addTearDown(f.dispose);
    expect(f.api.imageUri('https://evil.test/api/v2/catalog/images/a'), isNull);
    expect(f.api.imageUri('//evil.test/a'), isNull);
    expect(f.api.imageUri('/api/v2/media/a'), isNull);
    expect(f.api.imageUri('/api/v2/catalog/images/a')!.host, 'api.splyzo.test');
  });
  test(
      'public requests omit credentials and cart mutations preserve exact contract',
      () async {
    final f = CustomerFixture();
    addTearDown(f.dispose);
    await f.api.categories();
    expect(f.requests.last.headers['authorization'], isNull);
    await f.api.setLine(id(12), '10.125', 3);
    expect(f.requests.last.headers['authorization'], 'Bearer fixture-token');
    expect(jsonDecode(f.requests.last.body),
        {'quantity': '10.125', 'expectedVersion': 3});
    expect(f.version, 4);
    await expectLater(
        f.api.setLine(id(12), '10', 3),
        throwsA(isA<CustomerProblem>()
            .having((e) => e.code, 'code', 'CART_VERSION_CONFLICT')));
  });
  test('checkout and placement retain supplied idempotency keys', () async {
    final f = CustomerFixture();
    addTearDown(f.dispose);
    await f.api.preview(id(7), 3, 'preview-key');
    expect(f.requests.last.headers['idempotency-key'], 'preview-key');
    expect(jsonDecode(f.requests.last.body),
        {'addressId': id(7), 'expectedCartVersion': 3});
    await f.api.place(id(15), 'placement-key');
    expect(f.requests.last.headers['idempotency-key'], 'placement-key');
    expect(
        jsonDecode(f.requests.last.body), {'clientRequestId': 'placement-key'});
  });
  test('401 invalidates private scope and never returns raw error details',
      () async {
    var reset = 0;
    final api = CustomerApi(
        origin: Uri.parse('https://api.splyzo.test'),
        token: () async => 'token',
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'error': {'code': 'INVALID_SESSION', 'message': 'secret details'}
            }),
            401)))
      ..onUnauthorized = () => reset++;
    addTearDown(api.close);
    await expectLater(
        api.cart(),
        throwsA(isA<CustomerProblem>()
            .having((e) => e.message, 'message', isNot(contains('secret')))));
    expect(reset, 1);
  });
  test('late responses from an old account are discarded', () async {
    final response = Completer<http.Response>();
    final api = CustomerApi(
        origin: Uri.parse('https://api.splyzo.test'),
        token: () async => 'token',
        client: MockClient((_) => response.future));
    addTearDown(api.close);
    final future = api.cart();
    await Future<void>.delayed(Duration.zero);
    api.invalidate();
    response.complete(http.Response('{"data":{"items":[],"version":99}}', 200));
    await expectLater(future, throwsA(isA<CustomerProblem>()));
  });
}
