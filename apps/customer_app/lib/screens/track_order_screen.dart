import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../config/buildto_theme.dart';
import '../providers/demo_orders_provider.dart';
import '../widgets/ui/k_image.dart';
import '../widgets/ui/snack.dart';
import 'cancel_order_screen.dart';

/// Screen 07 — Track Order
/// Horizontal timeline progress, supplier dispatch partner info, order items, and site location.
class TrackOrderScreen extends StatefulWidget {
  final String orderId;

  const TrackOrderScreen({
    super.key,
    this.orderId = '#BT012456',
  });

  @override
  State<TrackOrderScreen> createState() => _TrackOrderScreenState();
}

class _TrackOrderScreenState extends State<TrackOrderScreen> {
  final List<String> _stages = [
    'Confirmed',
    'Packed',
    'Out for Delivery',
    'Delivered',
  ];

  @override
  Widget build(BuildContext context) {
    final demoOrders = context.watch<DemoOrdersProvider>();
    final order = demoOrders.getOrderById(widget.orderId) ?? demoOrders.orders.first;
    final currentStage = order.stage >= 0 ? order.stage : 0;
    final isCancelled = order.statusCode == 'cancelled';

    return Scaffold(
      backgroundColor: BuildtoColors.surfaceLight,
      appBar: AppBar(
        backgroundColor: BuildtoColors.bgWhite,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: BuildtoColors.primaryNavy),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Track Order',
              style: TextStyle(
                color: BuildtoColors.primaryNavy,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              order.id,
              style: const TextStyle(
                color: BuildtoColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Horizontal Timeline Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: BuildtoColors.bgWhite,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Order Status Timeline',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: BuildtoColors.textDark,
                        ),
                      ),
                      if (isCancelled)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: BuildtoColors.errorBg,
                            borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                          ),
                          child: const Text(
                            'Cancelled',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: BuildtoColors.errorRed),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Horizontal Stepper
                  Row(
                    children: List.generate(_stages.length, (index) {
                      final isCompleted = !isCancelled && index < currentStage;
                      final isActive = !isCancelled && index == currentStage;

                      return Expanded(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                if (index > 0)
                                  Expanded(
                                    child: Container(
                                      height: 3,
                                      color: isCancelled
                                          ? BuildtoColors.cardBorder
                                          : (index <= currentStage ? BuildtoColors.successGreen : BuildtoColors.cardBorder),
                                    ),
                                  )
                                else
                                  const Spacer(),

                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: isCancelled
                                        ? BuildtoColors.surfaceLight
                                        : (isCompleted
                                            ? BuildtoColors.successGreen
                                            : isActive
                                                ? BuildtoColors.accentAmber
                                                : BuildtoColors.surfaceLight),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isCancelled
                                          ? BuildtoColors.cardBorder
                                          : (isCompleted
                                              ? BuildtoColors.successGreen
                                              : isActive
                                                  ? BuildtoColors.accentAmber
                                                  : BuildtoColors.cardBorder),
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: isCompleted
                                        ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                                        : isActive
                                            ? const Icon(LucideIcons.truck, size: 13, color: Colors.white)
                                            : Text(
                                                '${index + 1}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: BuildtoColors.textLight,
                                                ),
                                              ),
                                  ),
                                ),

                                if (index < _stages.length - 1)
                                  Expanded(
                                    child: Container(
                                      height: 3,
                                      color: isCancelled
                                          ? BuildtoColors.cardBorder
                                          : (index < currentStage ? BuildtoColors.successGreen : BuildtoColors.cardBorder),
                                    ),
                                  )
                                else
                                  const Spacer(),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _stages[index],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isActive || isCompleted ? FontWeight.bold : FontWeight.normal,
                                color: isCancelled
                                    ? BuildtoColors.textLight
                                    : (isActive
                                        ? BuildtoColors.primaryNavy
                                        : isCompleted
                                            ? BuildtoColors.textDark
                                            : BuildtoColors.textLight),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Current Status Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BuildtoColors.bgWhite,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isCancelled
                          ? BuildtoColors.errorBg
                          : BuildtoColors.accentAmber.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCancelled ? LucideIcons.x : LucideIcons.truck,
                      color: isCancelled ? BuildtoColors.errorRed : BuildtoColors.accentAmber,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCancelled ? 'Order Cancelled' : order.status,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isCancelled ? BuildtoColors.errorRed : BuildtoColors.primaryNavy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isCancelled
                              ? (order.cancelReason != null ? 'Reason: ${order.cancelReason}' : 'This order was cancelled prior to dispatch.')
                              : 'Materials dispatched from ${order.supplier}. Loaded on flatbed vehicle.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: BuildtoColors.textMuted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Dispatch Fulfilment Partner Card
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
                    'Supplier Dispatch Logistics',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: BuildtoColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: BuildtoColors.surfaceLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.user, color: BuildtoColors.primaryNavy, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.driverName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: BuildtoColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              order.driverVehicle,
                              style: const TextStyle(fontSize: 12, color: BuildtoColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          showKSnack(context, 'Calling site delivery driver (${order.driverPhone})...');
                        },
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: BuildtoColors.successBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(LucideIcons.phone, size: 18, color: BuildtoColors.successGreen),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Delivery Site Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BuildtoColors.bgWhite,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.cardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.mapPin, size: 20, color: BuildtoColors.primaryNavy),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Delivery Construction Site',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: BuildtoColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${order.deliveryAddress}\nNote: ${order.siteNotes}',
                          style: const TextStyle(fontSize: 12, color: BuildtoColors.textMuted, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Items in this order (DYNAMICALLY RENDERED)
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
                  Text(
                    'Items in this Order (${order.items.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: BuildtoColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...order.items.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final it = entry.value;
                    return Column(
                      children: [
                        if (idx > 0) const Divider(height: 16, color: BuildtoColors.cardBorder),
                        _buildOrderItem(
                          name: it.name,
                          qty: it.qty,
                          price: it.price,
                          imageUrl: it.imageUrl,
                        ),
                      ],
                    );
                  }),
                  const Divider(height: 20, color: BuildtoColors.cardBorder),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Paid (${order.paymentMethod})',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: BuildtoColors.textDark),
                      ),
                      Text(
                        '₹${order.total.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: BuildtoColors.primaryNavy,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Cancel Order Action (if order is active)
            if (!isCancelled && order.statusCode == 'processing')
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CancelOrderScreen(
                          orderId: order.id,
                          orderTotal: order.total,
                          items: order.items.map((i) => {
                            'name': i.name,
                            'qty': i.qty,
                            'price': i.price,
                          }).toList(),
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BuildtoColors.errorRed,
                    side: const BorderSide(color: BuildtoColors.errorRed),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(BuildtoRadius.md),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.ban, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Cancel Order',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItem({
    required String name,
    required int qty,
    required double price,
    required String imageUrl,
  }) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(BuildtoRadius.sm),
          child: SizedBox(
            width: 44,
            height: 44,
            child: KImage(imageUrl, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: BuildtoColors.textDark),
              ),
              const SizedBox(height: 2),
              Text(
                'Qty: $qty',
                style: const TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
              ),
            ],
          ),
        ),
        Text(
          '₹${price.toStringAsFixed(0)}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: BuildtoColors.primaryNavy,
          ),
        ),
      ],
    );
  }
}
