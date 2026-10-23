import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../config/buildto_theme.dart';
import '../widgets/ui/k_image.dart';
import 'home_screen.dart';
import 'track_order_screen.dart';

/// Screen 06 — Order Placed
/// Order confirmation with unique order ID, delivery truck illustration, and tracking CTAs.
class OrderPlacedScreen extends StatelessWidget {
  final String orderId;
  final double amount;
  final String estimatedDelivery;

  const OrderPlacedScreen({
    super.key,
    this.orderId = '#BT012456',
    this.amount = 1650.0,
    this.estimatedDelivery = 'Tomorrow by 2:00 PM',
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

                // Green Success Badge
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: BuildtoColors.successBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      LucideIcons.check,
                      color: BuildtoColors.successGreen,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                const Text(
                  'Order Placed Successfully!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: BuildtoColors.primaryNavy,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),

                // Order ID Tag
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

                // Description
                const Text(
                  'Thank you for ordering with Buildto!\nYour construction materials are being prepared for dispatch.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: BuildtoColors.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),

                // Delivery Truck Illustration Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: BuildtoColors.surfaceLight,
                    borderRadius: BorderRadius.circular(BuildtoRadius.lg),
                    border: Border.all(color: BuildtoColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(BuildtoRadius.md),
                        child: SizedBox(
                          height: 130,
                          width: double.infinity,
                          child: KImage(
                            url: 'assets/images/delivery_truck_illustration.jpg',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.calendarClock, size: 16, color: BuildtoColors.primaryNavy),
                          const SizedBox(width: 8),
                          Text(
                            'Estimated Dispatch: $estimatedDelivery',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: BuildtoColors.primaryNavy,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TrackOrderScreen(orderId: orderId),
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
                        Icon(LucideIcons.mapPin, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Track Order',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
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
                      'Continue Shopping',
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
