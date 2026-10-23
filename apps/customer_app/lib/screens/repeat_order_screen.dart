import '../providers/demo_orders_provider.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../config/buildto_theme.dart';
import '../models/sample_construction_data.dart';
import '../providers/cart_provider.dart';
import '../widgets/ui/k_image.dart';
import '../widgets/ui/snack.dart';
import 'my_orders_screen.dart';
import 'view_cart_screen.dart';

/// Screen 16 — Repeat Order
/// Fast 1-tap reordering for frequently consumed construction site materials.
class RepeatOrderScreen extends StatelessWidget {
  final bool showBackButton;

  const RepeatOrderScreen({
    super.key,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final demoOrders = context.watch<DemoOrdersProvider>();
    final orderedList = demoOrders.frequentlyOrderedItems;

    final repeatItems = orderedList.isNotEmpty
        ? orderedList.map((it) {
            return {
              'id': it.name.toLowerCase().contains('cement') ? 'prod-cem-ultratech' : (it.name.toLowerCase().contains('tmt') ? 'prod-stl-tata-12' : 'prod-brk-red-clay'),
              'name': it.name,
              'price': it.price > 0 ? (it.qty > 0 ? it.price / it.qty : it.price) : 390.0,
              'unit': it.unit,
              'orderedTimes': 1,
              'lastOrdered': 'Recent Order',
              'image': it.imageUrl,
            };
          }).toList()
        : [
      {
        'id': 'prod-cem-ultratech',
        'name': 'Ultratech Cement 50kg Bag',
        'price': 390.0,
        'unit': 'bag',
        'orderedTimes': 3,
        'lastOrdered': '24 Oct 2026',
        'image': 'assets/products/ultratech_cement.jpg',
      },
      {
        'id': 'prod-stl-tata-12',
        'name': 'Tata Tiscon 550D TMT Rebar 12mm',
        'price': 450.0,
        'unit': 'piece',
        'orderedTimes': 2,
        'lastOrdered': '24 Oct 2026',
        'image': 'assets/products/tmt_steel_bars.jpg',
      },
      {
        'id': 'prod-brk-red-clay',
        'name': 'Kiln Burned Red Clay Bricks (1,000 Pcs)',
        'price': 7500.0,
        'unit': 'lot',
        'orderedTimes': 1,
        'lastOrdered': '20 Oct 2026',
        'image': 'assets/products/red_bricks.jpg',
      },
      {
        'id': 'prod-snd-river-100',
        'name': 'Coarse River Sand (100 CFT)',
        'price': 5200.0,
        'unit': 'truckload',
        'orderedTimes': 1,
        'lastOrdered': '20 Oct 2026',
        'image': 'assets/products/sand_aggregates.jpg',
      },
      {
        'id': 'prod-cem-acc-gold',
        'name': 'ACC Gold Water Shield Cement 50kg',
        'price': 420.0,
        'unit': 'bag',
        'orderedTimes': 1,
        'lastOrdered': '14 Oct 2026',
        'image': 'assets/products/acc_cement.jpg',
      },
    ];

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
        title: const Text(
          'Order Again',
          style: TextStyle(
            color: BuildtoColors.primaryNavy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Intro Callout
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BuildtoColors.primaryNavy.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.primaryNavy.withValues(alpha: 0.15)),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.repeat, size: 20, color: BuildtoColors.primaryNavy),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Materials previously ordered for your site. One-tap add to re-stock instantly.',
                      style: TextStyle(fontSize: 12, color: BuildtoColors.primaryNavy, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Items List
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: repeatItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = repeatItems[index];
                final inCart = cart.quantityFor(item['id'] as String);

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: BuildtoColors.bgWhite,
                    borderRadius: BorderRadius.circular(BuildtoRadius.md),
                    border: Border.all(color: BuildtoColors.cardBorder),
                    boxShadow: BuildtoShadows.card,
                  ),
                  child: Row(
                    children: [
                      // Image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                        child: Container(
                          width: 64,
                          height: 64,
                          color: BuildtoColors.surfaceLight,
                          child: KImage(item['image'] as String,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['name'] as String,
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
                              '₹${(item['price'] as double).toStringAsFixed(0)} / ${item['unit']}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: BuildtoColors.primaryNavy,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Ordered ${item['orderedTimes']} times • Last on ${item['lastOrdered']}',
                              style: const TextStyle(fontSize: 10, color: BuildtoColors.textMuted),
                            ),
                          ],
                        ),
                      ),

                      // Button
                      ElevatedButton(
                        onPressed: () {
                          final product = getSampleProductById(item['id'] as String);
                          if (product != null) {
                            cart.addItem(item: product, dhabaName: 'Shree Shyam Enterprises', quantity: 1);
                            showKSnack(context, 'Added ${item['name']} to Cart');
                          } else {
                            showKSnack(context, 'Added ${item['name']} to Cart');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BuildtoColors.primaryNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          inCart > 0 ? 'Add ($inCart)' : 'Reorder',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // See Past Orders Link
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
                  );
                },
                icon: const Text(
                  'See All Past Orders',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: BuildtoColors.primaryNavy,
                  ),
                ),
                label: const Icon(LucideIcons.arrowRight, size: 14, color: BuildtoColors.primaryNavy),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
