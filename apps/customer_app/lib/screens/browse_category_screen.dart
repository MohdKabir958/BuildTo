import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../config/buildto_theme.dart';
import '../models/menu_item.dart';
import '../models/sample_construction_data.dart';
import '../providers/cart_provider.dart';
import '../providers/wishlist_provider.dart';
import '../widgets/ui/k_image.dart';
import '../widgets/ui/snack.dart';
import 'product_detail_screen.dart';
import 'view_cart_screen.dart';

/// Screen 02 — Browse Category
/// Two-column construction product grid with sub-category filters, search, and instant cart steppers.
class BrowseCategoryScreen extends StatefulWidget {
  final String categoryName;
  final bool showBackButton;

  const BrowseCategoryScreen({
    super.key,
    this.categoryName = 'Cement & Concrete',
    this.showBackButton = true,
  });

  @override
  State<BrowseCategoryScreen> createState() => _BrowseCategoryScreenState();
}

class _BrowseCategoryScreenState extends State<BrowseCategoryScreen> {
  late String _selectedCategory;
  String _selectedSubCategory = 'All';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final Map<String, List<String>> _categoryFilters = {
    'Cement & Concrete': ['All', 'Cement Bags', 'Concrete Mix', 'RMC', 'Additives'],
    'Steel & TMT Bars': ['All', 'Fe 500D', 'Fe 550D', 'Binding Wire', 'Stirrups'],
    'Bricks & Blocks': ['All', 'Red Clay Bricks', 'AAC Blocks', 'Concrete Blocks', 'Fly Ash'],
    'Sand & Aggregates': ['All', 'River Sand', 'M-Sand', '10mm Blue Stone', '20mm Aggregate'],
    'Paints & Finishes': ['All', 'Exterior Emulsion', 'Interior Emulsion', 'Primers', 'Putty'],
    'Plumbing & Pipes': ['All', 'CPVC Pipes', 'UPVC Fittings', 'Water Tanks', 'Valves'],
    'Electrical & Wiring': ['All', 'FR Cables', 'Conduit Pipes', 'MCB Switches', 'Junction Boxes'],
    'Hardware & Tools': ['All', 'Trowels', 'Measuring Tapes', 'Nails & Screws', 'Shovels'],
    'Waterproofing': ['All', 'Liquid Waterproofing', 'Chemical Slurry', 'Polymer Additive'],
  };

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.categoryName;
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MenuItemModel> _getFilteredProducts() {
    final list = getSampleProductsByCategory(_selectedCategory);
    return list.where((p) {
      final matchesSearch = _searchQuery.isEmpty ||
          p.name.toLowerCase().contains(_searchQuery) ||
          p.brand.toLowerCase().contains(_searchQuery) ||
          p.description.toLowerCase().contains(_searchQuery);

      if (!matchesSearch) return false;

      if (_selectedSubCategory == 'All') return true;

      final sub = _selectedSubCategory.toLowerCase();
      final name = p.name.toLowerCase();
      final desc = p.description.toLowerCase();
      final type = p.materialType.toLowerCase();

      return name.contains(sub) || desc.contains(sub) || type.contains(sub);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final wishlist = context.watch<WishlistProvider>();
    final products = _getFilteredProducts();
    final filters = _categoryFilters[_selectedCategory] ?? ['All'];

    return Scaffold(
      backgroundColor: BuildtoColors.bgWhite,
      appBar: AppBar(
        backgroundColor: BuildtoColors.bgWhite,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(LucideIcons.arrowLeft, color: BuildtoColors.primaryNavy),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          _selectedCategory,
          style: const TextStyle(
            color: BuildtoColors.primaryNavy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
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
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: BuildtoColors.surfaceLight,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.cardBorder),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search in $_selectedCategory...',
                  hintStyle: const TextStyle(color: BuildtoColors.textLight, fontSize: 13),
                  prefixIcon: const Icon(LucideIcons.search, size: 18, color: BuildtoColors.textMuted),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x, size: 16, color: BuildtoColors.textMuted),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),

          // Sub-category Filter Chips
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = filters[index];
                final isSelected = filter == _selectedSubCategory;
                return ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedSubCategory = filter);
                    }
                  },
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? Colors.white : BuildtoColors.textDark,
                  ),
                  backgroundColor: BuildtoColors.surfaceLight,
                  selectedColor: BuildtoColors.primaryNavy,
                  side: BorderSide(
                    color: isSelected ? BuildtoColors.primaryNavy : BuildtoColors.cardBorder,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(BuildtoRadius.pill),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  showCheckmark: false,
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Product Grid
          Expanded(
            child: products.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.packageOpen, size: 48, color: BuildtoColors.textLight),
                        const SizedBox(height: 12),
                        Text(
                          'No materials found',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: BuildtoColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Try searching with different keywords',
                          style: TextStyle(fontSize: 12, color: BuildtoColors.textMuted),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.64,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final isWishlisted = wishlist.isWishlisted(product.id);
                      final inCartQty = cart.quantityFor(product.id);

                      return _buildProductCard(
                        context: context,
                        product: product,
                        isWishlisted: isWishlisted,
                        inCartQty: inCartQty,
                        cart: cart,
                        wishlist: wishlist,
                      );
                    },
                  ),
          ),
        ],
      ),

      // Floating Cart Summary Bar
      bottomSheet: cart.itemCount > 0
          ? Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: BuildtoColors.primaryNavy,
                borderRadius: BorderRadius.circular(BuildtoRadius.lg),
                boxShadow: BuildtoShadows.soft,
              ),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${cart.itemCount} ${cart.itemCount == 1 ? "Item" : "Items"} in Cart',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '₹${cart.subtotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: BuildtoColors.accentAmber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ViewCartScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BuildtoColors.accentAmber,
                      foregroundColor: BuildtoColors.primaryNavy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(BuildtoRadius.md),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View Cart',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        SizedBox(width: 4),
                        Icon(LucideIcons.arrowRight, size: 14),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildProductCard({
    required BuildContext context,
    required MenuItemModel product,
    required bool isWishlisted,
    required int inCartQty,
    required CartProvider cart,
    required WishlistProvider wishlist,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(product: product),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: BuildtoColors.bgWhite,
          borderRadius: BorderRadius.circular(BuildtoRadius.md),
          border: Border.all(color: BuildtoColors.cardBorder),
          boxShadow: BuildtoShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with Wishlist Button
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(BuildtoRadius.md)),
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    color: BuildtoColors.surfaceLight,
                    child: Hero(
                      tag: 'prod_${product.id}',
                      child: KImage(
                        url: product.imageUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    onTap: () {
                      wishlist.toggleWishlist(product);
                      showKSnack(
                        context,
                        wishlist.isWishlisted(product.id)
                            ? 'Added ${product.name} to Wishlist'
                            : 'Removed from Wishlist',
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        isWishlisted ? LucideIcons.heart : LucideIcons.heart,
                        size: 15,
                        color: isWishlisted ? BuildtoColors.errorRed : BuildtoColors.textMuted,
                      ),
                    ),
                  ),
                ),
                // Brand pill
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: BuildtoColors.primaryNavy.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                    ),
                    child: Text(
                      product.brand.isNotEmpty ? product.brand : 'Verified',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Rating
                    Row(
                      children: [
                        const Icon(LucideIcons.star, size: 12, color: BuildtoColors.accentAmber),
                        const SizedBox(width: 3),
                        Text(
                          '${product.rating}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: BuildtoColors.textDark,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '(${product.ratingCount})',
                          style: const TextStyle(
                            fontSize: 10,
                            color: BuildtoColors.textLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Title
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: BuildtoColors.textDark,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),

                    // Unit / Min Order
                    Text(
                      product.minOrder > 1 ? 'Min Order: ${product.minOrder} ${product.unit}s' : 'Per ${product.unit}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: BuildtoColors.textMuted,
                      ),
                    ),
                    const Spacer(),

                    // Price & CTA Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '₹${product.price.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: BuildtoColors.primaryNavy,
                                ),
                              ),
                              Text(
                                '/ ${product.unit}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: BuildtoColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Add / Stepper
                        if (inCartQty == 0)
                          SizedBox(
                            height: 30,
                            child: ElevatedButton(
                              onPressed: () {
                                final qty = product.minOrder > 0 ? product.minOrder : 1;
                                cart.addItem(
                                  product,
                                  dhabaName: 'Shree Shyam Enterprises',
                                  quantity: qty,
                                );
                                showKSnack(context, 'Added ${product.name} to Cart');
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: BuildtoColors.primaryNavy,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Add',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 30,
                            decoration: BoxDecoration(
                              color: BuildtoColors.surfaceLight,
                              borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                              border: Border.all(color: BuildtoColors.primaryNavy),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () {
                                    cart.decrementItem(product.id);
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    child: Icon(LucideIcons.minus, size: 12, color: BuildtoColors.primaryNavy),
                                  ),
                                ),
                                Text(
                                  '$inCartQty',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: BuildtoColors.primaryNavy,
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    cart.addItem(item: product, dhabaName: 'Shree Shyam Enterprises', quantity: 1);
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    child: Icon(LucideIcons.plus, size: 12, color: BuildtoColors.primaryNavy),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
