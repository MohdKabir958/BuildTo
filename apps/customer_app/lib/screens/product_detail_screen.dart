import '../providers/dhaba_provider.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../config/buildto_theme.dart';
import '../models/menu_item.dart';
import '../providers/cart_provider.dart';
import '../providers/wishlist_provider.dart';
import '../widgets/ui/k_image.dart';
import '../widgets/ui/snack.dart';
import 'view_cart_screen.dart';

/// Screen 03 — Product Detail
/// Detailed view of construction product with specifications, supplier verification, and bulk quantity stepper.
class ProductDetailScreen extends StatefulWidget {
  final MenuItemModel product;

  const ProductDetailScreen({
    super.key,
    required this.product,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late int _quantity;

  @override
  void initState() {
    super.initState();
    final min = widget.product.minOrder > 0 ? widget.product.minOrder : 1;
    _quantity = min;
  }

  void _increment() {
    if (_quantity < widget.product.availableStock) {
      setState(() {
        _quantity++;
      });
    } else {
      showKSnack(context, 'Maximum available quantity is ${widget.product.availableStock} ${widget.product.unit}s');
    }
  }

  void _decrement() {
    final min = widget.product.minOrder > 0 ? widget.product.minOrder : 1;
    if (_quantity > min) {
      setState(() {
        _quantity--;
      });
    } else {
      showKSnack(context, 'Minimum order quantity is $min ${widget.product.unit}s');
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final wishlist = context.watch<WishlistProvider>();
    final cart = context.watch<CartProvider>();
    final dhaba = context.watch<DhabaProvider>();
    final supplier = dhaba.supplierForProduct(product);
    final supplierName = dhaba.supplierNameForProduct(product);
    final isWishlisted = wishlist.isWishlisted(product.id);
    final minOrder = product.minOrder > 0 ? product.minOrder : 1;
    final totalPrice = product.price * _quantity;

    return Scaffold(
      backgroundColor: BuildtoColors.bgWhite,
      appBar: AppBar(
        backgroundColor: BuildtoColors.bgWhite,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: BuildtoColors.primaryNavy),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isWishlisted ? LucideIcons.heart : LucideIcons.heart,
              color: isWishlisted ? BuildtoColors.errorRed : BuildtoColors.primaryNavy,
            ),
            onPressed: () {
              wishlist.toggleWishlist(product);
              showKSnack(
                context,
                wishlist.isWishlisted(product.id)
                    ? 'Saved to Wishlist'
                    : 'Removed from Wishlist',
              );
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.share2, color: BuildtoColors.primaryNavy),
            onPressed: () {
              showKSnack(context, 'Product link copied to clipboard');
            },
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.shoppingBag, color: BuildtoColors.primaryNavy),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ViewCartScreen()),
                  );
                },
              ),
              if (cart.itemCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: BuildtoColors.accentAmber,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Center(
                      child: Text(
                        '${cart.itemCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Large Centered Product Image Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              height: 280,
              width: double.infinity,
              decoration: BoxDecoration(
                color: BuildtoColors.surfaceLight,
                borderRadius: BorderRadius.circular(BuildtoRadius.lg),
                border: Border.all(color: BuildtoColors.cardBorder),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(BuildtoRadius.lg),
                child: Hero(
                  tag: 'prod_${product.id}',
                  child: KImage(product.imageUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            // Content Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand & Stock status
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: BuildtoColors.primaryNavy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                        ),
                        child: Text(
                          product.brand.isNotEmpty ? product.brand.toUpperCase() : 'BUILDTO VERIFIED',
                          style: const TextStyle(
                            color: BuildtoColors.primaryNavy,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: product.isOutOfStock ? BuildtoColors.errorBg : BuildtoColors.successBg,
                          borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(product.isOutOfStock ? LucideIcons.alertCircle : LucideIcons.check,
                                size: 12,
                                color: product.isOutOfStock ? BuildtoColors.errorRed : BuildtoColors.successGreen),
                            const SizedBox(width: 4),
                            Text(
                              product.isOutOfStock
                                  ? 'Out of Stock'
                                  : (product.hasConfirmedStock
                                      ? 'In Stock (${product.stockQty} ${product.unit}s)'
                                      : 'In Stock (Direct Allocation)'),
                              style: TextStyle(
                                color: product.isOutOfStock ? BuildtoColors.errorRed : BuildtoColors.successGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Title
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: BuildtoColors.textDark,
                      letterSpacing: -0.4,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Rating Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: BuildtoColors.warningBg,
                          borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.star, size: 13, color: BuildtoColors.warningAmber),
                            const SizedBox(width: 3),
                            Text(
                              '${product.rating}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: BuildtoColors.warningAmber,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${product.ratingCount} Customer Reviews)',
                        style: const TextStyle(fontSize: 12, color: BuildtoColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Price Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '₹${product.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: BuildtoColors.primaryNavy,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/ ${product.unit}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: BuildtoColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if ((product.mrpPaise ?? 0) > 0) ...[
                        const SizedBox(width: 10),
                        Text(
                          '₹${((product.mrpPaise ?? 0) / 100).toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: BuildtoColors.textLight,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (minOrder > 1)
                        Text(
                          'Min Order: $minOrder ${product.unit}s',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: BuildtoColors.accentAmber,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Supplier Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: BuildtoColors.surfaceLight,
                      borderRadius: BorderRadius.circular(BuildtoRadius.md),
                      border: Border.all(color: BuildtoColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: BuildtoColors.primaryNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                          ),
                          child: const Icon(LucideIcons.store, color: BuildtoColors.primaryNavy, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                supplierName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: BuildtoColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(LucideIcons.badgeCheck, size: 12, color: BuildtoColors.successGreen),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${supplier?.address ?? 'Verified Material Depot'} • ${supplier?.distanceKm ?? 2.5} km',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Delivery Estimate Banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: BuildtoColors.infoBg,
                      borderRadius: BorderRadius.circular(BuildtoRadius.md),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.truck, size: 18, color: BuildtoColors.infoBlue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            product.deliveryEstimate.isNotEmpty
                                ? '${product.deliveryEstimate} to Lal Bihara'
                                : 'Delivery in 1-2 days to Lal Bihara',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: BuildtoColors.infoBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Description
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: BuildtoColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product.description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: BuildtoColors.textMuted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Specifications Table (Matching Reference Screen 03)
                  const Text(
                    'Product Specifications',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: BuildtoColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: BuildtoColors.surfaceLight,
                      borderRadius: BorderRadius.circular(BuildtoRadius.md),
                      border: Border.all(color: BuildtoColors.cardBorder),
                    ),
                    child: Column(
                      children: [
                        _buildSpecRow('Brand / Manufacturer', product.brand.isNotEmpty ? product.brand : 'Buildto Standard'),
                        const Divider(height: 1, color: BuildtoColors.cardBorder),
                        _buildSpecRow('Material Type / Grade', product.materialType.isNotEmpty ? product.materialType : 'Industrial Grade'),
                        const Divider(height: 1, color: BuildtoColors.cardBorder),
                        _buildSpecRow('Weight / Unit Size', product.weight.isNotEmpty ? product.weight : product.packSize),
                        const Divider(height: 1, color: BuildtoColors.cardBorder),
                        _buildSpecRow('Minimum Order Quantity', '$minOrder ${product.unit}s'),
                        const Divider(height: 1, color: BuildtoColors.cardBorder),
                        _buildSpecRow('Packaging', 'Heavy-Duty Moisture-Proof Sack'),
                        const Divider(height: 1, color: BuildtoColors.cardBorder),
                        _buildSpecRow('Quality Assurance', 'BIS Standard Compliant & Laboratory Tested'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 100), // Spacing for bottom bar
                ],
              ),
            ),
          ],
        ),
      ),

      // Bottom Bar with Stepper & Add to Cart
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: BuildtoColors.bgWhite,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Quantity Stepper
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: BuildtoColors.surfaceLight,
                  borderRadius: BorderRadius.circular(BuildtoRadius.md),
                  border: Border.all(color: BuildtoColors.cardBorder),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.minus, size: 16, color: BuildtoColors.primaryNavy),
                      onPressed: _decrement,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '$_quantity',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: BuildtoColors.primaryNavy,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.plus, size: 16, color: BuildtoColors.primaryNavy),
                      onPressed: _increment,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Add to Cart Button
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: product.isOutOfStock
                        ? null
                        : () {
                            final ok = cart.addItem(
                              item: product,
                              dhabaName: supplierName,
                              quantity: _quantity,
                            );
                            if (ok) {
                              showKSnack(
                                context,
                                'Added $_quantity ${product.unit}s from $supplierName to Cart',
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ViewCartScreen()),
                              );
                            } else {
                              showKSnack(context, 'Cannot add: exceeds available inventory or multi-depot limit');
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: product.isOutOfStock ? BuildtoColors.textLight : BuildtoColors.primaryNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(BuildtoRadius.md),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(product.isOutOfStock ? LucideIcons.alertCircle : LucideIcons.shoppingBag, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          product.isOutOfStock
                              ? 'Out of Stock'
                              : 'Add to Cart • ₹${totalPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: BuildtoColors.textMuted),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: BuildtoColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
