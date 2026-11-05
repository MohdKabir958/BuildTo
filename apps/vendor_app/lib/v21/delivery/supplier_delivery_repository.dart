import '../api/supplier_v21_api.dart';
import '../catalog/supplier_catalog_models.dart';
import 'supplier_delivery_models.dart';

/// A supplier can enable only an admin-approved city/PIN area. The server
/// remains authoritative for serviceability and final checkout freight.
class SupplierDeliveryRepository {
  const SupplierDeliveryRepository(this.client);
  final SupplierV21Api client;

  String _scope(String supplierId) =>
      '/api/v2/suppliers/${catalogId(supplierId)}/delivery';

  Future<List<SupplierCity>> cities() async {
    final result = await client.get('/api/v2/delivery/cities');
    return deliveryRows(
        result.data, SupplierCity.parse, (SupplierCity city) => city.id,
        max: 300);
  }

  Future<List<SupplierArea>> areas(String cityId) async {
    final validCity = catalogId(cityId);
    final result = await client
        .get('/api/v2/delivery/areas', query: {'cityId': validCity});
    return deliveryRows(
        result.data,
        (raw) => SupplierArea.parse(raw, validCity),
        (SupplierArea area) => area.id);
  }

  Future<List<SupplierCoverage>> coverage(String supplierId) async {
    final result = await client.get(_scope(supplierId));
    return deliveryRows(result.data, SupplierCoverage.parse,
        (SupplierCoverage coverage) => coverage.areaId);
  }

  Future<void> setCoverage({
    required String supplierId,
    required String areaId,
    required bool active,
    required String minimumPaise,
  }) async {
    final value = deliveryPaise(minimumPaise);
    final response = await client.request(
        'PUT', '${_scope(supplierId)}/areas/${catalogId(areaId)}',
        body: {'active': active, 'minimumPaise': value});
    final result = catalogObject(response.data);
    if (catalogId(result['supplierId']) != supplierId ||
        catalogId(result['areaId']) != areaId ||
        result['active'] != active ||
        deliveryPaise(result['minimumPaise']) != value) {
      throw const FormatException('Coverage confirmation did not match');
    }
  }

  Future<SupplierFlatRate> configureFlatRate({
    required String supplierId,
    required String areaId,
    required String baseFeePaise,
    required String handlingFeePaise,
    String? freeAbovePaise,
  }) async {
    deliveryPaise(baseFeePaise);
    deliveryPaise(handlingFeePaise);
    if (BigInt.parse(baseFeePaise) + BigInt.parse(handlingFeePaise) >
        BigInt.from(100000000000)) {
      throw const FormatException('Delivery fee exceeds supported limit');
    }
    if (freeAbovePaise != null) deliveryPaise(freeAbovePaise);
    final response = await client.request(
        'PUT', '${_scope(supplierId)}/areas/${catalogId(areaId)}/flat-rate',
        body: {
          'baseFeePaise': baseFeePaise,
          'handlingFeePaise': handlingFeePaise,
          'freeAbovePaise': freeAbovePaise,
        });
    final result = catalogObject(response.data);
    if (catalogId(result['supplierId']) != supplierId ||
        catalogId(result['areaId']) != areaId ||
        result['active'] != true) {
      throw const FormatException('Delivery rate confirmation failed');
    }
    final rate = SupplierFlatRate.parse(result);
    if (rate.basePaise != baseFeePaise ||
        rate.handlingPaise != handlingFeePaise ||
        rate.freeAbovePaise != freeAbovePaise) {
      throw const FormatException('Delivery rate confirmation changed');
    }
    return rate;
  }
}
