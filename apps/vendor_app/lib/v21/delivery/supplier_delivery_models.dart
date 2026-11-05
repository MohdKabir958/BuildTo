import '../catalog/supplier_catalog_models.dart';

final _pin = RegExp(r'^[1-9][0-9]{5}$');
final _paise = RegExp(r'^(?:0|[1-9][0-9]{0,11})$');

String deliveryPaise(Object? value) {
  if (value is! String ||
      !_paise.hasMatch(value) ||
      BigInt.parse(value) > BigInt.from(100000000000)) {
    throw const FormatException('Invalid delivery amount in paise');
  }
  return value;
}

String deliveryRupeesToPaise(String rupees) {
  final paise = catalogPaiseFromRupees(rupees);
  return deliveryPaise(paise);
}

String deliveryMoney(String paise) =>
    '₹${catalogRupeesFromPaise(deliveryPaise(paise))}';

List<T> deliveryRows<T>(
    Object? raw, T Function(Object?) parse, String Function(T) identity,
    {int max = 100}) {
  if (raw is! List<dynamic> || raw.length > max) {
    throw const FormatException('Invalid bounded delivery data');
  }
  final rows = raw.map(parse).toList(growable: false);
  if (rows.map(identity).toSet().length != rows.length) {
    throw const FormatException('Duplicate delivery identity');
  }
  return List.unmodifiable(rows);
}

class SupplierCity {
  const SupplierCity(this.id, this.name, this.stateCode);
  final String id, name, stateCode;

  factory SupplierCity.parse(Object? raw) {
    final data = catalogObject(raw);
    final state = catalogString(data['stateCode'], max: 2);
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(state) || data['countryCode'] != 'IN') {
      throw const FormatException('Invalid Indian delivery city');
    }
    return SupplierCity(
        catalogId(data['id']), catalogString(data['name'], max: 120), state);
  }
}

class SupplierArea {
  const SupplierArea(this.id, this.cityId, this.name, this.pins);
  final String id, cityId, name;
  final List<String> pins;

  factory SupplierArea.parse(Object? raw, String cityId) {
    final data = catalogObject(raw);
    if (catalogId(data['cityId']) != cityId) {
      throw const FormatException('Foreign delivery city area');
    }
    final pins = data['postalCodes'];
    if (pins is! List<dynamic> ||
        pins.isEmpty ||
        pins.length > 100 ||
        pins.any((pin) => pin is! String || !_pin.hasMatch(pin))) {
      throw const FormatException('Invalid delivery PIN coverage');
    }
    final normalized = pins.cast<String>();
    if (normalized.toSet().length != normalized.length) {
      throw const FormatException('Duplicate area PIN codes');
    }
    return SupplierArea(catalogId(data['id']), cityId,
        catalogString(data['name'], max: 150), List.unmodifiable(normalized));
  }
}

class SupplierFlatRate {
  const SupplierFlatRate({
    required this.id,
    required this.basePaise,
    required this.handlingPaise,
    this.freeAbovePaise,
  });
  final String id, basePaise, handlingPaise;
  final String? freeAbovePaise;

  factory SupplierFlatRate.parse(Object? raw) {
    final data = catalogObject(raw);
    return SupplierFlatRate(
      id: catalogId(data['id']),
      basePaise: deliveryPaise(data['baseFeePaise']),
      handlingPaise: deliveryPaise(data['handlingFeePaise']),
      freeAbovePaise: data['freeAbovePaise'] == null
          ? null
          : deliveryPaise(data['freeAbovePaise']),
    );
  }
}

class SupplierCoverage {
  const SupplierCoverage({
    required this.areaId,
    required this.areaName,
    required this.cityId,
    required this.active,
    required this.minimumPaise,
    required this.rates,
  });
  final String areaId, areaName, cityId, minimumPaise;
  final bool active;
  final List<SupplierFlatRate> rates;

  factory SupplierCoverage.parse(Object? raw) {
    final data = catalogObject(raw);
    if (data['active'] is! bool) {
      throw const FormatException('Invalid supplier delivery state');
    }
    final rates = deliveryRows(data['rates'], SupplierFlatRate.parse,
        (SupplierFlatRate rate) => rate.id,
        max: 1);
    return SupplierCoverage(
      areaId: catalogId(data['areaId']),
      areaName: catalogString(data['areaName'], max: 150),
      cityId: catalogId(data['cityId']),
      active: data['active'] as bool,
      minimumPaise: deliveryPaise(data['minimumPaise']),
      rates: rates,
    );
  }
}
