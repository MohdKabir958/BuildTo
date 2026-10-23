import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../config/buildto_theme.dart';
import 'home_screen.dart';
import 'track_order_screen.dart';

/// Screen 15 — Payment Success Alternative
/// Visual payment receipt with transaction reference, paid amount, and instant order tracking navigation.
class PaymentSuccessAltScreen extends StatelessWidget {
  final String orderId;
  final double amount;
  final String paymentMethod;
  final String txnId;

  const PaymentSuccessAltScreen({
    super.key,
    this.orderId = '#BT012456',
    this.amount = 1650.0,
    this.paymentMethod = 'UPI (Google Pay / PhonePe)',
    this.txnId = 'TXN_BUILDTO_982310',
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
        backgroundColor: BuildtoColors.surfaceLight,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Green Success Circle
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: BuildtoColors.successBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      LucideIcons.checkCheck,
                      color: BuildtoColors.successGreen,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Payment Successful!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: BuildtoColors.primaryNavy,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),

                Text(
                  '₹${amount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: BuildtoColors.primaryNavy,
                  ),
                ),
                const SizedBox(height: 24),

                // Receipt Details Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: BuildtoColors.bgWhite,
                    borderRadius: BorderRadius.circular(BuildtoRadius.lg),
                    border: Border.all(color: BuildtoColors.cardBorder),
                    boxShadow: BuildtoShadows.card,
                  ),
                  child: Column(
                    children: [
                      _buildReceiptRow('Order ID', orderId, isBold: true),
                      const Divider(height: 20, color: BuildtoColors.cardBorder),
                      _buildReceiptRow('Transaction ID', txnId),
                      const Divider(height: 20, color: BuildtoColors.cardBorder),
                      _buildReceiptRow('Payment Method', paymentMethod),
                      const Divider(height: 20, color: BuildtoColors.cardBorder),
                      _buildReceiptRow('Status', 'Completed (Demo)'),
                      const Divider(height: 20, color: BuildtoColors.cardBorder),
                      _buildReceiptRow('Date & Time', '24 Oct 2026, 10:30 AM'),
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
                    child: const Text(
                      'View Order Status',
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

  Widget _buildReceiptRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: BuildtoColors.textMuted),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: BuildtoColors.textDark,
          ),
        ),
      ],
    );
  }
}
