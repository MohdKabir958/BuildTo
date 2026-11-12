import 'dart:typed_data';
import '../api/supplier_v21_api.dart';
import 'supplier_catalog_models.dart';

class CatalogMasters {
  const CatalogMasters(this.categories, this.units);
  final List<CatalogCategory> categories;
  final List<CatalogUnit> units;
}

/// Form DTO; creates a new supplier-owned draft or edits mutable fields only.
class CatalogListingInput {
  const CatalogListingInput({
    required this.productId,
    required this.sku,
    this.productName,
    this.categoryId,
    this.imageUrl,
    required this.unitCode,
    required this.packSize,
    required this.minOrderQty,
    required this.stepQty,
    required this.maxOrderQty,
    required this.unitPrice,
    required this.mrpPaise,
    required this.taxRateBps,
    required this.taxInclusive,
  });
  final String productId,
      sku,
      unitCode;
  final String? productName, categoryId, imageUrl;
  final String
      packSize,
      minOrderQty,
      stepQty,
      unitPrice;
  final String? maxOrderQty, mrpPaise;
  final int taxRateBps;
  final bool taxInclusive;

  bool get namesOwnProduct => (productName ?? '').trim().isNotEmpty;

  void validate() {
    if (namesOwnProduct) {
      final ownName = productName!.trim();
      if (ownName.length > 240) {
        throw const FormatException('Enter a shorter product name.');
      }
      if (categoryId != null && categoryId!.isNotEmpty) catalogId(categoryId!);
    } else {
      catalogId(productId);
      catalogSku(sku);
    }
    if (unitCode.length > 20 ||
        !RegExp(r'^[A-Z0-9][A-Z0-9._-]*$').hasMatch(unitCode)) {
      throw const FormatException('Select a valid product unit');
    }
    catalogQty(packSize);
    catalogQty(minOrderQty);
    catalogQty(stepQty);
    if (maxOrderQty != null) {
      catalogQty(maxOrderQty);
      if (catalogScaled(maxOrderQty!, whole: 15, scale: 3) <
          catalogScaled(minOrderQty, whole: 15, scale: 3)) {
        throw const FormatException(
            'Maximum order must be at least the minimum');
      }
    }
    catalogPrice(unitPrice);
    if (taxRateBps < 0 || taxRateBps > 10000) {
      throw const FormatException('GST tax rate outside 0–10000 bps');
    }
    if (mrpPaise != null &&
        (!RegExp(r'^(?:0|[1-9][0-9]{0,18})$').hasMatch(mrpPaise!) ||
            BigInt.parse(mrpPaise!) > BigInt.parse('9223372036854775807'))) {
      throw const FormatException(
          'MRP must be exact nonnegative integer paise');
    }
  }

  Map<String, Object?> toJson({int? expectedVersion}) {
    validate();
    return {
      if (expectedVersion == null) ...{
        if (namesOwnProduct) ...{
          'productName': productName!.trim(),
          if (categoryId != null && categoryId!.isNotEmpty)
            'categoryId': categoryId,
        } else ...{
          'productId': productId,
          'sku': catalogSku(sku),
        },
        'unitCode': unitCode,
      } else
        'expectedVersion': expectedVersion,
      'packSize': packSize,
      'minOrderQty': minOrderQty,
      'stepQty': stepQty,
      'maxOrderQty': maxOrderQty,
      'unitPrice': unitPrice,
      'mrpPaise': mrpPaise,
      'taxRateBps': taxRateBps,
      'taxInclusive': taxInclusive,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }
}

class SupplierCatalogRepository {
  const SupplierCatalogRepository(this.client);
  final SupplierV21Api client;
  String _scope(String supplierId) =>
      '/api/v2/suppliers/${catalogId(supplierId)}/listings';

  Future<List<CatalogListing>> listings(String supplierId) async {
    final result = await client.get(_scope(supplierId));
    return catalogList(
        result.data,
        (value) => CatalogListing.fromJson(value, supplierId),
        (CatalogListing listing) => listing.id);
  }

  Future<CatalogMasters> masters() async {
    final responses = await Future.wait([
      client.get('/api/v2/catalog/categories'),
      client.get('/api/v2/catalog/units'),
    ]);
    return CatalogMasters(
      catalogList(responses[0].data, CatalogCategory.fromJson,
          (CatalogCategory category) => category.id,
          max: 250),
      catalogList(responses[1].data, CatalogUnit.fromJson,
          (CatalogUnit unit) => unit.code),
    );
  }

  Future<CatalogProductPage> products({
    String search = '',
    String? categoryId,
    String? cursor,
  }) async {
    final query = <String, String>{};
    final keyword = search.trim();
    if (keyword.isNotEmpty) {
      if (keyword.length > 80 ||
          !RegExp(r'^[a-zA-Z0-9 ._\-/]+$').hasMatch(keyword)) {
        throw const FormatException(
            'Search accepts letters, digits, space, dot, dash or slash');
      }
      query['search'] = keyword;
    }
    if (categoryId != null) query['categoryId'] = catalogId(categoryId);
    if (cursor != null) query['cursor'] = catalogId(cursor);
    final response = await client.get('/api/v2/catalog/products',
        query: query.isEmpty ? null : query);
    return CatalogProductPage.fromJson(response.data);
  }

  Future<String> uploadProductPhoto({
    required String supplierId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final response = await client.sendBytes(
      '/api/v2/suppliers/${catalogId(supplierId)}/product-photos',
      bytes,
      contentType,
    );
    final url = response.requireObject()['imageUrl'];
    if (url is! String || !url.startsWith('/api/v2/catalog/images/')) {
      throw const FormatException('Photo was not stored.');
    }
    return url;
  }

  Future<CatalogListing> create({
    required String supplierId,
    required CatalogListingInput input,
    required String idempotencyKey,
  }) async {
    final result = await client.request('POST', _scope(supplierId),
        body: input.toJson(), idempotencyKey: idempotencyKey);
    return CatalogListing.fromJson(result.data, supplierId);
  }

  Future<CatalogListing> update({
    required String supplierId,
    required CatalogListing original,
    required CatalogListingInput input,
  }) async {
    if (original.supplierId != supplierId || !original.status.canEdit) {
      throw StateError('Listing cannot be edited in this supplier state');
    }
    final result = await client.request(
        'PATCH', '${_scope(supplierId)}/${catalogId(original.id)}',
        body: input.toJson(expectedVersion: original.version));
    return CatalogListing.fromJson(result.data, supplierId);
  }

  Future<CatalogListing> submit({
    required String supplierId,
    required CatalogListing listing,
  }) async {
    if (listing.supplierId != supplierId || !listing.status.canSubmit) {
      throw StateError(
          'Only own drafts and rejected listings can be submitted');
    }
    final result = await client.request(
        'POST', '${_scope(supplierId)}/${catalogId(listing.id)}/submit',
        body: {'expectedVersion': listing.version});
    return CatalogListing.fromJson(result.data, supplierId);
  }

  Future<CatalogListing> replaceTiers({
    required String supplierId,
    required CatalogListing listing,
    required List<CatalogTier> tiers,
  }) async {
    if (listing.supplierId != supplierId || !listing.status.canPrice) {
      throw StateError('Listing pricing is locked');
    }
    validateCatalogTiers(tiers,
        minOrderQty: listing.minOrderQty, unitPrice: listing.unitPrice);
    final result = await client.request(
        'PUT', '${_scope(supplierId)}/${catalogId(listing.id)}/price-tiers',
        body: {
          'expectedVersion': listing.version,
          'tiers': tiers.map((tier) => tier.toJson()).toList(growable: false)
        });
    return CatalogListing.fromJson(result.data, supplierId);
  }
}
