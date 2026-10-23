import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../config/buildto_theme.dart';
import '../providers/cart_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/ui/k_image.dart';
import '../widgets/ui/snack.dart';
import 'checkout_screen.dart';

/// Screen 04 — View Cart
/// Cart review screen with line item totals, quantities, bill breakdown, and checkout CTA.
class ViewCartScreen extends StatelessWidget {
  final bool showBackButton;

  const ViewCartScreen({
    super.key,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final session = context.watch<SessionProvider>();
    final items = cart.items;
    final addressText = session.addressText.isNotEmpty
        ? session.addressText
        : '4891/1C Lal Bihara, Near Metro Pillar 42, New Delhi - 110001';

    final subtotal = cart.subtotal;
    const deliveryFee = 150.0;
    final grandTotal = subtotal > 0 ? subtotal + deliveryFee : 0.0;

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
          'My Cart',
          style: TextStyle(
            color: BuildtoColors.primaryNavy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear Cart'),
                    content: const Text('Are you sure you want to remove all items from your cart?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel', style: TextStyle(color: BuildtoColors.textMuted)),
                      ),
                      TextButton(
                        onPressed: () {
                          cart.clear();
                          Navigator.pop(ctx);
                          showKSnack(context, 'Cart cleared');
                        },
                        child: const Text('Clear', style: TextStyle(color: BuildtoColors.errorRed)),
                      ),
                    ],
                  ),
                );
              },
              child: const Text(
                'Clear Cart',
                style: TextStyle(
                  color: BuildtoColors.errorRed,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
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
                      child: const Icon(LucideIcons.shoppingBag, size: 44, color: BuildtoColors.textLight),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Your Cart is Empty',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: BuildtoColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Explore our wide catalog of construction materials\nand wholesale prices.',
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
                      child: const Text(
                        'Browse Materials',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Delivery location banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: BuildtoColors.bgWhite,
                      borderRadius: BorderRadius.circular(BuildtoRadius.md),
                      border: Border.all(color: BuildtoColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.mapPin, size: 18, color: BuildtoColors.primaryNavy),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Delivering to Construction Site',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: BuildtoColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                addressText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: BuildtoColors.textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Cart Items
                  const Text(
                    'Order Items',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: BuildtoColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: BuildtoColors.bgWhite,
                          borderRadius: BorderRadius.circular(BuildtoRadius.md),
                          border: Border.all(color: BuildtoColors.cardBorder),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Product Image
                            ClipRRect(
                              borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                              child: Container(
                                width: 64,
                                height: 64,
                                color: BuildtoColors.surfaceLight,
                                child: KImage(item.imageUrl ?? 'assets/products/ultratech_cement.jpg',
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
                                    item.name,
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
                                    '₹${item.price.toStringAsFixed(0)} each',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: BuildtoColors.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Total: ₹${item.totalPrice.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: BuildtoColors.primaryNavy,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Stepper Controls
                            Container(
                              height: 32,
                              decoration: BoxDecoration(
                                color: BuildtoColors.surfaceLight,
                                borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                                border: Border.all(color: BuildtoColors.cardBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    icon: Icon(
                                      item.quantity == 1 ? LucideIcons.trash2 : LucideIcons.minus,
                                      size: 13,
                                      color: item.quantity == 1 ? BuildtoColors.errorRed : BuildtoColors.primaryNavy,
                                    ),
                                    onPressed: () => cart.decrementItem(item.dishId),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      '${item.quantity}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: BuildtoColors.primaryNavy,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    icon: const Icon(LucideIcons.plus, size: 13, color: BuildtoColors.primaryNavy),
                                    onPressed: () => cart.incrementItem(item.dishId),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // Bill Breakdown Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: BuildtoColors.bgWhite,
                      borderRadius: BorderRadius.circular(BuildtoRadius.md),
                      border: Border.all(color: BuildtoColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bill Summary',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: BuildtoColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildBillRow('Item Total', '₹${subtotal.toStringAsFixed(0)}'),
                        const SizedBox(height: 8),
                        _buildBillRow('Site Logistics / Delivery', '₹${deliveryFee.toStringAsFixed(0)}'),
                        const SizedBox(height: 8),
                        _buildBillRow('GST (18% / 28%)', 'Included in item prices'),
                        const Divider(height: 24, color: BuildtoColors.cardBorder),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Grand Total',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: BuildtoColors.textDark,
                              ),
                            ),
                            Text(
                              '₹${grandTotal.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: BuildtoColors.primaryNavy,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

      // Bottom Checkout Bar
      bottomSheet: items.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Payable',
                          style: TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
                        ),
                        Text(
                          '₹${grandTotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: BuildtoColors.primaryNavy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CheckoutScreen(
                                  customAmount: grandTotal,
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BuildtoColors.primaryNavy,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(BuildtoRadius.md),
                            ),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Proceed to Checkout',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(LucideIcons.arrowRight, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBillRow(String label, String value) {
    return Row(
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
    );
  }
}
