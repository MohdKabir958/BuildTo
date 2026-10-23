import 'customization.dart';

class MenuItemModel {
  final String id;
  final String vendorId;
  final String name;
  final double price;
  final String category;
  final String description;
  final String imageUrl;
  final bool isAvailable;
  final bool isVeg;
  final String? sku, productKey;
  final String unit, packSize;
  final int? stockQty, mrpPaise;
  final List<String> imageUrls;
  final List<CustomizationGroup> customizationGroups;

  // Construction specification fields for Screen 03 / catalog
  final String brand;
  final String materialType;
  final String weight;
  final int minOrder;
  final double rating;
  final int ratingCount;
  final String deliveryEstimate;

  const MenuItemModel({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.price,
    required this.category,
    required this.description,
    required this.imageUrl,
    required this.isAvailable,
    this.sku,
    this.productKey,
    this.unit = 'pcs',
    this.packSize = '1',
    this.stockQty,
    this.mrpPaise,
    this.imageUrls = const [],
    this.isVeg = true,
    this.customizationGroups = const [],
    this.brand = 'Buildto Verified',
    this.materialType = 'Standard Grade',
    this.weight = '',
    this.minOrder = 1,
    this.rating = 4.5,
    this.ratingCount = 50,
    this.deliveryEstimate = 'Delivery in 1-2 days',
  });

  String get displayName => sku == null ? name : '$name \u2022 $packSize $unit';
  String get primaryImage => imageUrls.isNotEmpty ? imageUrls.first : imageUrl;
  double get savings => mrpPaise != null && mrpPaise! > (price * 100).round()
      ? mrpPaise! / 100 - price
      : 0;
  bool get hasCustomizations => customizationGroups.isNotEmpty;

  MenuItemModel copyWith({
    String? id,
    String? vendorId,
    String? name,
    double? price,
    String? category,
    String? description,
    String? imageUrl,
    bool? isAvailable,
    String? sku,
    String? productKey,
    String? unit,
    String? packSize,
    int? stockQty,
    int? mrpPaise,
    List<String>? imageUrls,
    bool? isVeg,
    List<CustomizationGroup>? customizationGroups,
    String? brand,
    String? materialType,
    String? weight,
    int? minOrder,
    double? rating,
    int? ratingCount,
    String? deliveryEstimate,
  }) {
    return MenuItemModel(
      id: id ?? this.id,
      vendorId: vendorId ?? this.vendorId,
      name: name ?? this.name,
      price: price ?? this.price,
      category: category ?? this.category,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      isAvailable: isAvailable ?? this.isAvailable,
      sku: sku ?? this.sku,
      productKey: productKey ?? this.productKey,
      unit: unit ?? this.unit,
      packSize: packSize ?? this.packSize,
      stockQty: stockQty ?? this.stockQty,
      mrpPaise: mrpPaise ?? this.mrpPaise,
      imageUrls: imageUrls ?? this.imageUrls,
      isVeg: isVeg ?? this.isVeg,
      customizationGroups: customizationGroups ?? this.customizationGroups,
      brand: brand ?? this.brand,
      materialType: materialType ?? this.materialType,
      weight: weight ?? this.weight,
      minOrder: minOrder ?? this.minOrder,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      deliveryEstimate: deliveryEstimate ?? this.deliveryEstimate,
    );
  }

  factory MenuItemModel.fromJson(Map<String, dynamic> json) {
    return MenuItemModel(
      sku: json['sku'],
      productKey: json['productKey'],
      unit: json['unit'] ?? 'pcs',
      packSize: json['packSize'] ?? '1',
      stockQty: json['stockQty'],
      mrpPaise: json['mrpPaise'],
      imageUrls:
          (json['imageUrls'] as List?)?.whereType<String>().toList() ?? [],
      id: json['id'] ?? '',
      vendorId: json['vendorId'] ?? '',
      name: json['name'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      category: json['category'] ?? '',
      description: json['description'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      isAvailable: json['isAvailable'] ?? true,
      isVeg: json['isVeg'] ?? true,
      customizationGroups: (json['customizationGroups'] as List<dynamic>?)
              ?.map((cg) =>
                  CustomizationGroup.fromJson(cg as Map<String, dynamic>))
              .toList() ??
          [],
      brand: json['brand'] ?? 'Buildto Verified',
      materialType: json['type'] ?? json['materialType'] ?? 'Standard Grade',
      weight: json['weight'] ?? '',
      minOrder: json['minOrder'] is num ? (json['minOrder'] as num).toInt() : 1,
      rating: json['rating'] is num ? (json['rating'] as num).toDouble() : 4.5,
      ratingCount: json['ratingCount'] is num
          ? (json['ratingCount'] as num).toInt()
          : 50,
      deliveryEstimate: json['deliveryEstimate'] ?? 'Delivery in 1-2 days',
    );
  }
}
