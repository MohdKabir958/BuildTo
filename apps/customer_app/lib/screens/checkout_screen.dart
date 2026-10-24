import '../providers/demo_orders_provider.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../config/buildto_theme.dart';
import '../providers/cart_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/ui/snack.dart';
import 'addresses_screen.dart';
import 'order_placed_screen.dart';
import 'payment_success_alt_screen.dart';

/// Screen 05 — Checkout
/// Three-step checkout: Address -> Payment -> Review with demo mode safety indicator.
class CheckoutScreen extends StatefulWidget {
  final String? selectedHostel;
  final double? customAmount;

  const CheckoutScreen({
    super.key,
    this.selectedHostel,
    this.customAmount,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  int _currentStep = 1; // 0: Address, 1: Payment, 2: Review
  String _selectedPaymentMethod = 'UPI'; // UPI, COD, NetBanking
  final TextEditingController _siteNotesController =
      TextEditingController(text: 'Call site supervisor before unloading at Gate #2');
  bool _isPlacingOrder = false;

  @override
  void dispose() {
    _siteNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final session = context.watch<SessionProvider>();
    final addressText = session.addressText.isNotEmpty
        ? session.addressText
        : '4891/1C Lal Bihara, Near Metro Pillar 42, New Delhi - 110001';

    final quote = cart.quote;
    final subtotal = widget.customAmount != null
        ? (cart.items.isNotEmpty ? cart.subtotal : widget.customAmount!)
        : quote.subtotal;
    final deliveryFee = widget.customAmount != null
        ? (cart.items.isNotEmpty ? quote.deliveryFee : 0.0)
        : quote.deliveryFee;
    final discount = cart.items.isNotEmpty ? quote.discount : 0.0;
    final grandTotal = widget.customAmount ?? (cart.items.isNotEmpty ? quote.grandTotal : 0.0);
    final isCartEmpty = cart.items.isEmpty && widget.customAmount == null;

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
          'Checkout',
          style: TextStyle(
            color: BuildtoColors.primaryNavy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Demo Safety Banner
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: BuildtoColors.infoBg,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.infoBlue.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.shieldCheck, size: 18, color: BuildtoColors.infoBlue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Demo Mode: Simulated Checkout • No real payments will be charged to your card or account.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: BuildtoColors.infoBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 3-Step Progress Indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: BuildtoColors.bgWhite,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.cardBorder),
              ),
              child: Row(
                children: [
                  _buildStepItem(1, 'Address', _currentStep >= 0),
                  _buildStepConnector(_currentStep >= 1),
                  _buildStepItem(2, 'Payment', _currentStep >= 1),
                  _buildStepConnector(_currentStep >= 2),
                  _buildStepItem(3, 'Review', _currentStep >= 2),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Step 1: Delivery Address Section
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
                      const Row(
                        children: [
                          Icon(LucideIcons.mapPin, size: 18, color: BuildtoColors.primaryNavy),
                          SizedBox(width: 8),
                          Text(
                            'Delivery Site Address',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: BuildtoColors.textDark,
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AddressesScreen()),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(50, 30),
                        ),
                        child: const Text(
                          'Change',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: BuildtoColors.primaryNavy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    session.customerName.isNotEmpty ? session.customerName : 'Rohit Sharma (Site Contractor)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: BuildtoColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '+91 98765 43210',
                    style: const TextStyle(fontSize: 12, color: BuildtoColors.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    addressText,
                    style: const TextStyle(fontSize: 12, color: BuildtoColors.textDark, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  // Site Notes
                  TextField(
                    controller: _siteNotesController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Site Unloading Instructions',
                      labelStyle: const TextStyle(fontSize: 12, color: BuildtoColors.textMuted),
                      prefixIcon: const Icon(LucideIcons.fileText, size: 16, color: BuildtoColors.textMuted),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                        borderSide: const BorderSide(color: BuildtoColors.cardBorder),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Step 2: Payment Methods
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
                  const Row(
                    children: [
                      Icon(LucideIcons.creditCard, size: 18, color: BuildtoColors.primaryNavy),
                      SizedBox(width: 8),
                      Text(
                        'Select Payment Method',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: BuildtoColors.textDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // UPI
                  _buildPaymentOption(
                    id: 'UPI',
                    title: 'UPI (Google Pay, PhonePe, Paytm, BHIM)',
                    subtitle: 'Instant digital transfer for site supplies',
                    icon: LucideIcons.smartphone,
                  ),
                  const Divider(height: 1, color: BuildtoColors.cardBorder),

                  // COD
                  _buildPaymentOption(
                    id: 'COD',
                    title: 'Pay on Unloading (Cash / Site Cheque)',
                    subtitle: 'Verify materials at site before release of payment',
                    icon: LucideIcons.banknote,
                  ),
                  const Divider(height: 1, color: BuildtoColors.cardBorder),

                  // Net Banking / Card
                  _buildPaymentOption(
                    id: 'NetBanking',
                    title: 'Net Banking / Corporate Card',
                    subtitle: 'HDFC, ICICI, SBI, Axis Bank with GST invoice',
                    icon: LucideIcons.building2,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Demo Mode Notice Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BuildtoColors.warningBg,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.warningAmber.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.shieldAlert, size: 18, color: BuildtoColors.warningAmber),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Demonstration Checkout: Orders are saved directly into your demonstration session with live status tracking. No financial charge occurs.',
                      style: TextStyle(
                        fontSize: 11,
                        color: BuildtoColors.warningAmber,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bill Summary
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
                    'Order Bill Summary',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: BuildtoColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Materials Subtotal', style: TextStyle(fontSize: 12, color: BuildtoColors.textMuted)),
                      Text('₹${subtotal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  if (discount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Bulk / Coupon Discount', style: TextStyle(fontSize: 12, color: BuildtoColors.successGreen)),
                        Text('-₹${discount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BuildtoColors.successGreen)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Site Unloading / Logistics', style: TextStyle(fontSize: 12, color: BuildtoColors.textMuted)),
                      Text(
                        deliveryFee == 0 ? 'FREE (≥ ₹25k)' : '₹${deliveryFee.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: BuildtoColors.cardBorder),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Payable',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: BuildtoColors.textDark),
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
            const SizedBox(height: 24),

            // Confirm Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_isPlacingOrder || isCartEmpty)
                    ? null
                    : () async {
                        setState(() => _isPlacingOrder = true);
                        await Future.delayed(const Duration(milliseconds: 600));
                        if (!mounted) return;

                        final demoOrders = context.read<DemoOrdersProvider>();
                        final createdOrder = demoOrders.createOrder(
                          cartItems: cart.items,
                          total: grandTotal,
                          address: addressText,
                          paymentMethod: _selectedPaymentMethod,
                          siteNotes: _siteNotesController.text,
                        );

                        // Clear cart after placement
                        cart.clear();

                        if (_selectedPaymentMethod == 'UPI') {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PaymentSuccessAltScreen(
                                orderId: createdOrder.id,
                                amount: grandTotal,
                                paymentMethod: 'UPI (Demonstration)',
                              ),
                            ),
                          );
                        } else {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderPlacedScreen(
                                orderId: createdOrder.id,
                                amount: grandTotal,
                              ),
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: BuildtoColors.primaryNavy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(BuildtoRadius.md),
                  ),
                  elevation: 0,
                ),
                child: _isPlacingOrder
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(LucideIcons.shieldCheck, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Confirm Order & Pay ₹${grandTotal.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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

  Widget _buildStepItem(int stepNumber, String title, bool isActive) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: isActive ? BuildtoColors.primaryNavy : BuildtoColors.surfaceLight,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? BuildtoColors.primaryNavy : BuildtoColors.cardBorder,
            ),
          ),
          child: Center(
            child: Text(
              '$stepNumber',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.white : BuildtoColors.textLight,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? BuildtoColors.primaryNavy : BuildtoColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector(bool isActive) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: isActive ? BuildtoColors.primaryNavy : BuildtoColors.cardBorder,
      ),
    );
  }

  Widget _buildPaymentOption({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedPaymentMethod == id;
    return InkWell(
      onTap: () => setState(() => _selectedPaymentMethod = id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          children: [
            Icon(
              isSelected ? LucideIcons.circleDot : LucideIcons.circle,
              size: 18,
              color: isSelected ? BuildtoColors.primaryNavy : BuildtoColors.textLight,
            ),
            const SizedBox(width: 12),
            Icon(icon, size: 20, color: BuildtoColors.primaryNavy),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: BuildtoColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
