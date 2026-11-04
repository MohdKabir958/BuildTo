import '../providers/demo_orders_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../config/buildto_theme.dart';
import 'order_cancelled_screen.dart';

/// Screen 09 — Cancel Order
/// Confirmation dialog and reason selection for cancelling an order prior to dispatch.
class CancelOrderScreen extends StatefulWidget {
  final String orderId;
  final double orderTotal;
  final List<Map<String, dynamic>> items;

  const CancelOrderScreen({
    super.key,
    this.orderId = '#BT012456',
    this.orderTotal = 3420.0,
    this.items = const [
      {'name': 'Ultratech Cement 50kg Bag', 'qty': 3, 'price': 1170.0},
      {'name': 'Tata Tiscon 550D TMT Rebar 12mm', 'qty': 2, 'price': 2250.0},
    ],
  });

  @override
  State<CancelOrderScreen> createState() => _CancelOrderScreenState();
}

class _CancelOrderScreenState extends State<CancelOrderScreen> {
  String _selectedReason = 'Site construction delayed';

  final List<String> _reasons = [
    'Site construction delayed',
    'Ordered by mistake',
    'Found better price elsewhere',
    'Delivery time too long',
    'Incorrect material grade selected',
    'Other reason',
  ];

  @override
  Widget build(BuildContext context) {
    final demoOrders = context.watch<DemoOrdersProvider>();
    final order = demoOrders.getOrderById(widget.orderId);
    final isCancelled = order?.statusCode == 'cancelled';
    final isDispatched = (order?.stage ?? 0) > 1 || order?.statusCode == 'delivered';

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
        title: const Text(
          'Cancel Order',
          style: TextStyle(
            color: BuildtoColors.primaryNavy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: order == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.packageX, size: 56, color: BuildtoColors.textMuted),
                    const SizedBox(height: 16),
                    Text(
                      'Order "${widget.orderId}" Not Found',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BuildtoColors.textDark),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This order cannot be cancelled because it was not found in your session.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: BuildtoColors.textMuted),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BuildtoColors.primaryNavy,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Back to Orders'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Summary Card
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.orderId,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: BuildtoColors.primaryNavy,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: BuildtoColors.warningBg,
                          borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                        ),
                        child: const Text(
                          'Processing at Yard',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: BuildtoColors.warningAmber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: BuildtoColors.cardBorder),
                  const SizedBox(height: 12),
                  ...widget.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${item['name']} x${item['qty']}',
                              style: const TextStyle(fontSize: 12, color: BuildtoColors.textDark),
                            ),
                            Text(
                              '₹${(item['price'] as double).toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: BuildtoColors.textDark,
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: BuildtoColors.cardBorder),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Order Value',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: BuildtoColors.textDark),
                      ),
                      Text(
                        '₹${widget.orderTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: BuildtoColors.primaryNavy,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Cancellation Policy Alert
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: BuildtoColors.infoBg,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.info, size: 18, color: BuildtoColors.infoBlue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Materials have not left the supplier yard yet. You are eligible for a 100% full refund to your original payment method.',
                      style: TextStyle(fontSize: 12, color: BuildtoColors.infoBlue, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Cancellation Reason Heading
            const Text(
              'Reason for Cancellation',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: BuildtoColors.textDark,
              ),
            ),
            const SizedBox(height: 10),

            // Reason Selector Card
            Container(
              decoration: BoxDecoration(
                color: BuildtoColors.bgWhite,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.cardBorder),
              ),
              child: Column(
                children: _reasons.map((reason) {
                  final isSelected = _selectedReason == reason;
                  return InkWell(
                    onTap: () => setState(() => _selectedReason = reason),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: reason != _reasons.last
                            ? const Border(bottom: BorderSide(color: BuildtoColors.cardBorder))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? LucideIcons.circleDot : LucideIcons.circle,
                            size: 18,
                            color: isSelected ? BuildtoColors.errorRed : BuildtoColors.textLight,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              reason,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                color: isSelected ? BuildtoColors.textDark : BuildtoColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 30),

            if (isCancelled)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BuildtoColors.errorBg,
                  borderRadius: BorderRadius.circular(BuildtoRadius.md),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.info, size: 18, color: BuildtoColors.errorRed),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This order has already been cancelled.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BuildtoColors.errorRed),
                      ),
                    ),
                  ],
                ),
              )
            else if (isDispatched)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BuildtoColors.warningBg,
                  borderRadius: BorderRadius.circular(BuildtoRadius.md),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.alertTriangle, size: 18, color: BuildtoColors.warningAmber),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Materials have already been dispatched or delivered from the depot. Automated cancellation is closed. Contact site support desk for unloading adjustments.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BuildtoColors.warningAmber, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),

            // Action Buttons
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: (isCancelled || isDispatched)
                    ? null
                    : () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Confirm Order Cancellation'),
                      content: Text(
                        'Are you sure you want to cancel order ${widget.orderId}? This action cannot be reversed.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Keep Order', style: TextStyle(color: BuildtoColors.textMuted)),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.read<DemoOrdersProvider>().cancelOrder(widget.orderId, _selectedReason);
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderCancelledScreen(
                                  orderId: widget.orderId,
                                  refundAmount: widget.orderTotal,
                                  reason: _selectedReason,
                                ),
                              ),
                            );
                          },
                          child: const Text('Cancel Order', style: TextStyle(color: BuildtoColors.errorRed)),
                        ),
                      ],
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
                child: const Text(
                  'Cancel Order',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BuildtoColors.primaryNavy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(BuildtoRadius.md),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Keep My Order',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
