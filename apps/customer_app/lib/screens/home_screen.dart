import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../config/buildto_theme.dart';
import '../models/food_category.dart';
import '../models/menu_item.dart';
import '../models/sample_construction_data.dart';
import '../providers/cart_provider.dart';
import '../providers/dhaba_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/session_provider.dart';
import '../providers/wishlist_provider.dart';
import '../widgets/ui/k_image.dart';
import '../widgets/ui/snack.dart';
import 'addresses_screen.dart';
import 'browse_category_screen.dart';
import 'notifications_screen.dart';
import 'product_detail_screen.dart';
import 'profile_settings_screen.dart';
import 'support_help_screen.dart';
import 'view_cart_screen.dart';

/// Screen 01 — Home Screen
/// Construction marketplace home feed with 4-tab bottom navigation, supplier cards, and wholesale catalog.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _goToTab(int index) {
    setState(() => _currentTab = index);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return PopScope(
      canPop: _currentTab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentTab != 0) {
          _goToTab(0);
        }
      },
      child: Scaffold(
        backgroundColor: BuildtoColors.surfaceLight,
        body: IndexedStack(
          index: _currentTab,
          children: [
            _buildHomeFeed(context),
            const BrowseCategoryScreen(showBackButton: false),
            const ViewCartScreen(showBackButton: false),
            const ProfileSettingsScreen(showBackButton: false),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: BuildtoColors.bgWhite,
            border: const Border(top: BorderSide(color: BuildtoColors.cardBorder)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: SizedBox(
              height: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(0, LucideIcons.house, 'Home'),
                  _buildNavItem(1, LucideIcons.layoutGrid, 'Categories'),
                  _buildCartNavItem(2, cart.itemCount),
                  _buildNavItem(3, LucideIcons.user, 'Profile'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isActive = _currentTab == index;
    return InkWell(
      onTap: () => _goToTab(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 22,
            color: isActive ? BuildtoColors.primaryNavy : BuildtoColors.textLight,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: isActive ? BuildtoColors.primaryNavy : BuildtoColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartNavItem(int index, int itemCount) {
    final isActive = _currentTab == index;
    return InkWell(
      onTap: () => _goToTab(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                LucideIcons.shoppingBag,
                size: 22,
                color: isActive ? BuildtoColors.primaryNavy : BuildtoColors.textLight,
              ),
              if (itemCount > 0)
                Positioned(
                  top: -4,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: BuildtoColors.accentAmber,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Center(
                      child: Text(
                        '$itemCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Cart',
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: isActive ? BuildtoColors.primaryNavy : BuildtoColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeFeed(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final notifs = context.watch<NotificationsProvider>();
    final addressText = session.addressText.isNotEmpty ? session.addressText : 'Lal Bihara, New Delhi';
    final categories = sampleConstructionCategories();
    final suppliers = sampleConstructionStores();
    final allProducts = getAllSampleProducts();
    final featuredProducts = allProducts.take(6).toList();

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top App Bar
            Container(
              color: BuildtoColors.bgWhite,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Buildto Brand Logo & Tagline
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: BuildtoColors.primaryNavy,
                              borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                            ),
                            child: const Icon(LucideIcons.hardHat, color: BuildtoColors.accentAmber, size: 20),
                          ),
                          const SizedBox(width: 8),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BUILDTO',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: BuildtoColors.primaryNavy,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'Building Made Easy.',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: BuildtoColors.accentAmber,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),

                      // Delivery Location Dropdown
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AddressesScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: BuildtoColors.surfaceLight,
                            borderRadius: BorderRadius.circular(BuildtoRadius.pill),
                            border: Border.all(color: BuildtoColors.cardBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.mapPin, size: 14, color: BuildtoColors.primaryNavy),
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 100),
                                child: Text(
                                  addressText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: BuildtoColors.textDark,
                                  ),
                                ),
                              ),
                              const Icon(LucideIcons.chevronDown, size: 12, color: BuildtoColors.textMuted),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Notification Bell
                      Stack(
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            icon: const Icon(LucideIcons.bell, size: 22, color: BuildtoColors.primaryNavy),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                              );
                            },
                          ),
                          if (notifs.unreadCount > 0)
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: BuildtoColors.accentAmber,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Search Bar matching reference: "Search for cement, steel, paint..."
                  GestureDetector(
                    onTap: () {
                      _goToTab(1); // switch to categories
                    },
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: BuildtoColors.surfaceLight,
                        borderRadius: BorderRadius.circular(BuildtoRadius.md),
                        border: Border.all(color: BuildtoColors.cardBorder),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: const Row(
                        children: [
                          Icon(LucideIcons.search, size: 18, color: BuildtoColors.textMuted),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Search for cement, steel, paint...',
                              style: TextStyle(
                                color: BuildtoColors.textLight,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Icon(LucideIcons.slidersHorizontal, size: 16, color: BuildtoColors.primaryNavy),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Hero Promotional Banner matching reference
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(BuildtoRadius.lg),
                  border: Border.all(color: BuildtoColors.cardBorder),
                  boxShadow: BuildtoShadows.card,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(BuildtoRadius.lg),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: KImage('assets/images/construction_hero_banner.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                BuildtoColors.primaryNavy.withValues(alpha: 0.92),
                                BuildtoColors.primaryNavy.withValues(alpha: 0.45),
                                Colors.transparent,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: BuildtoColors.accentAmber,
                                borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                              ),
                              child: const Text(
                                'WHOLESALE RATES',
                                style: TextStyle(
                                  color: BuildtoColors.primaryNavy,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Build Your Project With\nCertified Grade Materials',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: () => _goToTab(1),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: BuildtoColors.accentAmber,
                                foregroundColor: BuildtoColors.primaryNavy,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                minimumSize: const Size(90, 30),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Explore Deals',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Section: Nearby Suppliers matching reference
            _buildSectionHeader(
              title: 'Nearby Suppliers',
              onSeeAll: () => _goToTab(1),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 145,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: suppliers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final supplier = suppliers[index];
                  return _buildSupplierCard(context, supplier);
                },
              ),
            ),
            const SizedBox(height: 22),

            // Section: Popular Categories matching reference
            _buildSectionHeader(
              title: 'Popular Categories',
              onSeeAll: () => _goToTab(1),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 0.82,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: categories.take(8).length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                return _buildCategoryItem(context, cat);
              },
            ),
            const SizedBox(height: 22),

            // Engineer Consultation Promo Banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BuildtoColors.bgWhite,
                  borderRadius: BorderRadius.circular(BuildtoRadius.md),
                  border: Border.all(color: BuildtoColors.cardBorder),
                  boxShadow: BuildtoShadows.card,
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(BuildtoRadius.md),
                      child: SizedBox(
                        width: 70,
                        height: 70,
                        child: KImage('assets/images/construction_engineer.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Need Estimation Advice?',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: BuildtoColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Free material quantity calculation by our qualified civil engineers.',
                            style: TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const SupportHelpScreen()),
                              );
                            },
                            child: const Row(
                              children: [
                                Text(
                                  'Talk to Site Engineer',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: BuildtoColors.primaryNavy,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(LucideIcons.arrowRight, size: 12, color: BuildtoColors.primaryNavy),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),

            // Section: Best Selling Construction Materials
            _buildSectionHeader(
              title: 'Best Selling Materials',
              onSeeAll: () => _goToTab(1),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.66,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: featuredProducts.length,
              itemBuilder: (context, index) {
                final product = featuredProducts[index];
                return _buildHomeProductCard(context, product);
              },
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required VoidCallback onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: BuildtoColors.accentAmber,
                  borderRadius: BorderRadius.circular(BuildtoRadius.pill),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: BuildtoColors.primaryNavy,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          InkWell(
            onTap: onSeeAll,
            child: const Text(
              'See All',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: BuildtoColors.primaryNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierCard(BuildContext context, dynamic supplier) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const BrowseCategoryScreen(categoryName: 'Cement & Concrete'),
          ),
        );
      },
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BuildtoColors.bgWhite,
          borderRadius: BorderRadius.circular(BuildtoRadius.md),
          border: Border.all(color: BuildtoColors.cardBorder),
          boxShadow: BuildtoShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                  child: Container(
                    width: 42,
                    height: 42,
                    color: BuildtoColors.surfaceLight,
                    child: KImage(supplier.bannerUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supplier.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: BuildtoColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(LucideIcons.star, size: 11, color: BuildtoColors.accentAmber),
                          const SizedBox(width: 3),
                          Text(
                            '${supplier.rating}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${supplier.distanceKm} km',
                            style: const TextStyle(fontSize: 10, color: BuildtoColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              supplier.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: BuildtoColors.textMuted),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: BuildtoColors.successBg,
                    borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                  ),
                  child: const Text(
                    'Open • Verified',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: BuildtoColors.successGreen),
                  ),
                ),
                const Icon(LucideIcons.arrowRight, size: 14, color: BuildtoColors.primaryNavy),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryItem(BuildContext context, FoodCategory category) {
    IconData icon = LucideIcons.layers;
    final nameLower = category.name.toLowerCase();
    if (nameLower.contains('cement')) {
      icon = LucideIcons.box;
    } else if (nameLower.contains('steel')) {
      icon = LucideIcons.shield;
    } else if (nameLower.contains('brick')) {
      icon = LucideIcons.layoutGrid;
    } else if (nameLower.contains('sand')) {
      icon = LucideIcons.mountain;
    } else if (nameLower.contains('plumb')) {
      icon = LucideIcons.droplets;
    } else if (nameLower.contains('paint')) {
      icon = LucideIcons.paintbrush;
    } else if (nameLower.contains('elect')) {
      icon = LucideIcons.zap;
    } else if (nameLower.contains('hard')) {
      icon = LucideIcons.wrench;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrowseCategoryScreen(categoryName: category.name),
          ),
        );
      },
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: BuildtoColors.bgWhite,
              borderRadius: BorderRadius.circular(BuildtoRadius.md),
              border: Border.all(color: BuildtoColors.cardBorder),
              boxShadow: BuildtoShadows.card,
            ),
            child: Center(
              child: Icon(icon, size: 24, color: BuildtoColors.primaryNavy),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            category.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: BuildtoColors.textDark,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeProductCard(BuildContext context, MenuItemModel product) {
    final cart = context.watch<CartProvider>();
    final wishlist = context.watch<WishlistProvider>();
    final isWishlisted = wishlist.isWishlisted(product.id);
    final inCartQty = cart.quantityFor(product.id);

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
            // Image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(BuildtoRadius.md)),
                  child: Container(
                    height: 110,
                    width: double.infinity,
                    color: BuildtoColors.surfaceLight,
                    child: KImage(product.imageUrl,
                      fit: BoxFit.cover,
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
                        wishlist.isWishlisted(product.id) ? 'Saved to Wishlist' : 'Removed from Wishlist',
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.heart,
                        size: 14,
                        color: isWishlisted ? BuildtoColors.errorRed : BuildtoColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: BuildtoColors.textDark,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${product.price.toStringAsFixed(0)} / ${product.unit}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: BuildtoColors.primaryNavy,
                      ),
                    ),
                    const Spacer(),
                    if (inCartQty == 0)
                      SizedBox(
                        width: double.infinity,
                        height: 28,
                        child: ElevatedButton(
                          onPressed: () {
                            final qty = product.minOrder > 0 ? product.minOrder : 1;
                            cart.addItem(item: product,
                              dhabaName: 'Shree Shyam Enterprises',
                              quantity: qty,
                            );
                            showKSnack(context, 'Added ${product.name} to Cart');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BuildtoColors.primaryNavy,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                            ),
                            elevation: 0,
                          ),
                          child: const Text('Add to Cart', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      )
                    else
                      Container(
                        height: 28,
                        decoration: BoxDecoration(
                          color: BuildtoColors.surfaceLight,
                          borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                          border: Border.all(color: BuildtoColors.primaryNavy),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            InkWell(
                              onTap: () => cart.decrementItem(product.id),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
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
                              onTap: () => cart.addItem(item: product, dhabaName: 'Shree Shyam Enterprises', quantity: 1),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(LucideIcons.plus, size: 12, color: BuildtoColors.primaryNavy),
                              ),
                            ),
                          ],
                        ),
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
