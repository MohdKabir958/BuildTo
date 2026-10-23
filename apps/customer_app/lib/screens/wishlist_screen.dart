import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../config/buildto_theme.dart';
import '../providers/cart_provider.dart';
import '../providers/wishlist_provider.dart';
import '../widgets/ui/k_image.dart';
import '../widgets/ui/snack.dart';
import 'product_detail_screen.dart';
import 'view_cart_screen.dart';

/// Screen 11 — Wishlist / Saved Items
/// Dedicated list of saved construction materials with direct Add to Cart and removal actions.
class WishlistScreen extends StatelessWidget {
  final bool showBackButton;

  const WishlistScreen({
    super.key,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final wishlist = context.watch<WishlistProvider>();
    final cart = context.watch<CartProvider>();
    final items = wishlist.items;

    return Scaffold(
      backgroundColor: BuildtoColors.surfaceLight,
      appBar: AppBar(
        backgroundColor: BuildtoColors.bgWhite,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: showBackButton
            ? IconButton(
                icon: const Icon(LucideIcons.arrowLeft, color: BuildtoColors.primaryNavy),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Row(
          children: [
            const Text(
              'My Wishlist',
              style: TextStyle(
                color: BuildtoColors.primaryNavy,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: BuildtoColors.primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(BuildtoRadius.pill),
                ),
                child: Text(
                  '${items.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: BuildtoColors.primaryNavy,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
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
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: const BoxDecoration(
                        color: BuildtoColors.surfaceLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.heart, size: 44, color: BuildtoColors.textLight),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Your Wishlist is Empty',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: BuildtoColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Save materials you frequently use on site for quick reordering.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: BuildtoColors.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BuildtoColors.primaryNavy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(BuildtoRadius.md),
                        ),
                      ),
                      child: const Text('Explore Catalog', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final product = items[index];
                final inCartQty = cart.quantityFor(product.id);

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BuildtoColors.bgWhite,
                    borderRadius: BorderRadius.circular(BuildtoRadius.md),
                    border: Border.all(color: BuildtoColors.cardBorder),
                    boxShadow: BuildtoShadows.card,
                  ),
                  child: Row(
                    children: [
                      // Thumbnail
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProductDetailScreen(product: product),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                          child: Container(
                            width: 70,
                            height: 70,
                            color: BuildtoColors.surfaceLight,
                            child: KImage(product.imageUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: BuildtoColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${product.price.toStringAsFixed(0)} / ${product.unit}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: BuildtoColors.primaryNavy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(LucideIcons.check, size: 12, color: BuildtoColors.successGreen),
                                const SizedBox(width: 4),
                                const Text(
                                  'In Stock',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: BuildtoColors.successGreen,
                                  ),
                                ),
                                if (product.minOrder > 1) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    'Min: ${product.minOrder}',
                                    style: const TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Actions Column
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: const Icon(LucideIcons.trash2, size: 16, color: BuildtoColors.errorRed),
                            onPressed: () {
                              wishlist.removeFromWishlist(product.id);
                              showKSnack(context, 'Removed ${product.name} from Wishlist');
                            },
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () {
                              final qty = product.minOrder > 0 ? product.minOrder : 1;
                              cart.addItem(
                                item: product,
                                dhabaName: 'Shree Shyam Enterprises',
                                quantity: qty,
                              );
                              showKSnack(context, 'Added $qty ${product.unit}s to Cart');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: BuildtoColors.primaryNavy,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: const Size(60, 30),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              inCartQty > 0 ? 'Add ($inCartQty)' : 'Add',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
