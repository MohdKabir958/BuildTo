import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../config/buildto_theme.dart';
import 'home_screen.dart';

/// Screen 10 — Order Cancelled
/// Displays cancellation confirmation, refund information (demo simulation), and back to home CTA.
class OrderCancelledScreen extends StatelessWidget {
  final String orderId;
  final double refundAmount;
  final String reason;

  const OrderCancelledScreen({
    super.key,
    this.orderId = '#BT012456',
    this.refundAmount = 3420.0,
    this.reason = 'Site construction delayed',
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
        }
      },
      child: Scaffold(
        backgroundColor: BuildtoColors.bgWhite,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Red Cancelled Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: BuildtoColors.errorBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      LucideIcons.x,
                      color: BuildtoColors.errorRed,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Order Cancelled',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: BuildtoColors.primaryNavy,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: BuildtoColors.surfaceLight,
                    borderRadius: BorderRadius.circular(BuildtoRadius.pill),
                    border: Border.all(color: BuildtoColors.cardBorder),
                  ),
                  child: Text(
                    'Order ID: $orderId',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: BuildtoColors.primaryNavy,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Your order has been cancelled.\nReason: "$reason"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: BuildtoColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                // Refund Simulation Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: BuildtoColors.surfaceLight,
                    borderRadius: BorderRadius.circular(BuildtoRadius.lg),
                    border: Border.all(color: BuildtoColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Refund Status',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: BuildtoColors.textDark,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: BuildtoColors.infoBg,
                              borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                            ),
                            child: const Text(
                              'Initiated (Demo)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: BuildtoColors.infoBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Refund Amount',
                            style: TextStyle(fontSize: 12, color: BuildtoColors.textMuted),
                          ),
                          Text(
                            '₹${refundAmount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: BuildtoColors.primaryNavy,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20, color: BuildtoColors.cardBorder),
                      const Row(
                        children: [
                          Icon(LucideIcons.info, size: 14, color: BuildtoColors.textMuted),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Simulated Refund: For demo orders, no actual bank transactions were processed.',
                              style: TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Buttons
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
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
                    child: const Text(
                      'Back to Home',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Refund Breakdown'),
                          content: Text(
                            'Order: $orderId\nAmount: ₹${refundAmount.toStringAsFixed(0)}\nMethod: Original Payment Source (Demo)\nCredit Time: Instant (Simulated)',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: BuildtoColors.primaryNavy,
                      side: const BorderSide(color: BuildtoColors.primaryNavy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(BuildtoRadius.md),
                      ),
                    ),
                    child: const Text(
                      'View Refund Details',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
