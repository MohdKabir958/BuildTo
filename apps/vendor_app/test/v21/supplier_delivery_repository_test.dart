import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/delivery/supplier_delivery_models.dart';
import 'package:vendor_app/v21/delivery/supplier_delivery_repository.dart';

const supplier = '123e4567-e89b-42d3-a456-426614174000';
const city = '123e4567-e89b-42d3-a456-426614174001';
const area = '123e4567-e89b-42d3-a456-426614174002';
const rate = '123e4567-e89b-42d3-a456-426614174003';

http.Response ok(Object? data) =>
    http.Response(jsonEncode({'data': data}), 200);

SupplierDeliveryRepository repository(http.Client client) =>
    SupplierDeliveryRepository(SupplierV21Api(
      origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
      token: () async => 'clerk-delivery-token',
      httpClient: client,
    ));

void main() {
  test('city, PIN and supplier coverage read from exact V2.1 paths', () async {
    final service = repository(MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer clerk-delivery-token');
      if (request.url.path.endsWith('/cities')) {
        return ok([{
          'id': city, 'name': 'Hyderabad',
          'stateCode': 'TS', 'countryCode': 'IN',
        }]);
      }
      if (request.url.path.endsWith('/areas')) {
        expect(request.url.queryParameters, {'cityId': city});
        return ok([{
          'id': area, 'cityId': city,
          'name': 'West Hyderabad', 'postalCodes': ['500001', '500002'],
        }]);
      }
      return ok([{
        'areaId': area, 'areaName': 'West Hyderabad', 'cityId': city,
        'active': true, 'minimumPaise': '50000',
        'rates': [{
          'id': rate, 'baseFeePaise': '10000',
          'handlingFeePaise': '2500', 'freeAbovePaise': null,
        }],
      }]);
    }));
    expect((await service.cities()).single.name, 'Hyderabad');
    expect((await service.areas(city)).single.pins.length, 2);
    final configured = (await service.coverage(supplier)).single;
    expect(configured.rates.single.handlingPaise, '2500');
    expect(deliveryMoney(configured.minimumPaise), '₹500.00');
  });

  test('exact rupees convert to paise and reject unsafe money', () {
    expect(deliveryRupeesToPaise('399.12'), '39912');
    expect(() => deliveryRupeesToPaise('20.001'), throwsFormatException);
    expect(() => deliveryPaise('999999999999'), throwsFormatException);
    expect(() => SupplierArea.parse({
      'id': area, 'cityId': supplier, 'name': 'Foreign',
      'postalCodes': ['500001'],
    }, city), throwsFormatException);
  });

  test('coverage toggles send server-owned area and exact minimum', () async {
    final service = repository(MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path,
          '/api/v2/suppliers/$supplier/delivery/areas/$area');
      final body = jsonDecode(request.body);
      expect(body, {'active': true, 'minimumPaise': '10000'});
      return ok({'supplierId': supplier, 'areaId': area,
          'active': true, 'minimumPaise': '10000'});
    }));
    await service.setCoverage(
        supplierId: supplier, areaId: area,
        active: true, minimumPaise: '10000');
  });

  test('flat freight uses exact paise and checks confirmation', () async {
    final service = repository(MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path.endsWith('/flat-rate'), isTrue);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['baseFeePaise'], '12500');
      expect(body['handlingFeePaise'], '300');
      return ok({
        'id': rate, 'supplierId': supplier, 'areaId': area,
        'active': true, 'baseFeePaise': '12500',
        'handlingFeePaise': '300', 'freeAbovePaise': null,
      });
    }));
    final result = await service.configureFlatRate(
      supplierId: supplier, areaId: area,
      baseFeePaise: '12500', handlingFeePaise: '300',
    );
    expect(result.basePaise, '12500');
  });

  test('rejects malformed overlaid rates and unexpected supplier data', () {
    expect(() => SupplierCoverage.parse({
      'areaId': area, 'cityId': city, 'areaName': 'A',
      'active': true, 'minimumPaise': '0',
      'rates': [
        {'id': rate, 'baseFeePaise': '0',
         'handlingFeePaise': '0', 'freeAbovePaise': null},
        {'id': city, 'baseFeePaise': '0',
         'handlingFeePaise': '0', 'freeAbovePaise': null},
      ],
    }), throwsFormatException);
  });
}
