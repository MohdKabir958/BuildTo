import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../config/buildto_theme.dart';
const bool kBuildtoOfflineDemo = bool.fromEnvironment('BUILDTO_OFFLINE_DEMO', defaultValue: true);
import '../providers/cart_provider.dart';
import '../providers/demo_orders_provider.dart';
import '../providers/session_provider.dart';
import '../providers/wishlist_provider.dart';
import '../widgets/ui/snack.dart';
import 'addresses_screen.dart';
import 'auth_screen.dart';
import 'my_orders_screen.dart';
import 'notifications_screen.dart';
import 'repeat_order_screen.dart';
import 'support_help_screen.dart';
import 'wishlist_screen.dart';

/// Screen 13 — Profile / Settings
/// Contractor profile information, account management, saved addresses, and preferences.
class ProfileSettingsScreen extends StatelessWidget {
  final bool showBackButton;

  const ProfileSettingsScreen({
    super.key,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final wishlist = context.watch<WishlistProvider>();
    final name = session.customerName.isNotEmpty ? session.customerName : 'Rohit Sharma';
    const phone = '+91 98765 43210';
    const role = 'Civil Contractor / Site Engineer';

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
          'Profile & Settings',
          style: TextStyle(
            color: BuildtoColors.primaryNavy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
        child: Column(
          children: [
            // User Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: BuildtoColors.bgWhite,
                borderRadius: BorderRadius.circular(BuildtoRadius.lg),
                border: Border.all(color: BuildtoColors.cardBorder),
                boxShadow: BuildtoShadows.card,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: BuildtoColors.primaryNavy,
                          shape: BoxShape.circle,
                          border: Border.all(color: BuildtoColors.accentAmber, width: 2),
                        ),
                        child: const Center(
                          child: Icon(LucideIcons.hardHat, color: Colors.white, size: 28),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: BuildtoColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              phone,
                              style: const TextStyle(fontSize: 12, color: BuildtoColors.textMuted),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: BuildtoColors.primaryNavy.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                              ),
                              child: const Text(
                                role,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: BuildtoColors.primaryNavy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1, color: BuildtoColors.cardBorder),
                  const SizedBox(height: 14),

                  // Quick Stats Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatColumn('4', 'Orders Placed'),
                      Container(height: 24, width: 1, color: BuildtoColors.cardBorder),
                      _buildStatColumn('${wishlist.items.length}', 'Saved Items'),
                      Container(height: 24, width: 1, color: BuildtoColors.cardBorder),
                      _buildStatColumn('2', 'Site Addresses'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Orders & Shopping Section
            _buildSectionHeader('Orders & Site Logistics'),
            Container(
              decoration: BoxDecoration(
                color: BuildtoColors.bgWhite,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.cardBorder),
              ),
              child: Column(
                children: [
                  _buildMenuItem(
                    icon: LucideIcons.package,
                    title: 'My Orders',
                    subtitle: 'Track live dispatches and past orders',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
                      );
                    },
                  ),
                  const Divider(height: 1, color: BuildtoColors.cardBorder),
                  _buildMenuItem(
                    icon: LucideIcons.repeat,
                    title: 'Order Again',
                    subtitle: 'Quickly reorder materials for active sites',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RepeatOrderScreen()),
                      );
                    },
                  ),
                  const Divider(height: 1, color: BuildtoColors.cardBorder),
                  _buildMenuItem(
                    icon: LucideIcons.heart,
                    title: 'Wishlist & Saved Materials',
                    subtitle: '${wishlist.items.length} materials bookmarked',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WishlistScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Account & Preferences
            _buildSectionHeader('Account & Configuration'),
            Container(
              decoration: BoxDecoration(
                color: BuildtoColors.bgWhite,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.cardBorder),
              ),
              child: Column(
                children: [
                  _buildMenuItem(
                    icon: LucideIcons.mapPin,
                    title: 'Delivery Site Addresses',
                    subtitle: 'Manage construction site locations & gate instructions',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AddressesScreen()),
                      );
                    },
                  ),
                  const Divider(height: 1, color: BuildtoColors.cardBorder),
                  _buildMenuItem(
                    icon: LucideIcons.bell,
                    title: 'Notifications & Alerts',
                    subtitle: 'Dispatch status and wholesale price alerts',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                    },
                  ),
                  const Divider(height: 1, color: BuildtoColors.cardBorder),
                  _buildMenuItem(
                    icon: LucideIcons.creditCard,
                    title: 'Payment & Billing Methods',
                    subtitle: 'UPI, NEFT/RTGS, and company GST invoices',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Saved Payment Methods'),
                          content: const Text(
                            'UPI: rohit.sharma@okaxis\nNet Banking: HDFC Current Account (**** 4109)\nGSTIN: 07AAAAA0000A1Z5',
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
                  ),
                  const Divider(height: 1, color: BuildtoColors.cardBorder),
                  _buildMenuItem(
                    icon: LucideIcons.headphones,
                    title: 'Help & Site Support',
                    subtitle: 'Toll-free hotline, live chat & FAQs',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SupportHelpScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // App Version & Logout
            Container(
              decoration: BoxDecoration(
                color: BuildtoColors.bgWhite,
                borderRadius: BorderRadius.circular(BuildtoRadius.md),
                border: Border.all(color: BuildtoColors.cardBorder),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(LucideIcons.info, color: BuildtoColors.textMuted, size: 20),
                    title: const Text(
                      'Buildto Customer App',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: BuildtoColors.textDark),
                    ),
                    subtitle: const Text(
                      'Version 2.4.0 (Build 120) • Construction Marketplace',
                      style: TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
                    ),
                  ),
                  const Divider(height: 1, color: BuildtoColors.cardBorder),
                  if (kBuildtoOfflineDemo)
                    ListTile(
                      leading: const Icon(LucideIcons.refreshCw, color: BuildtoColors.primaryNavy, size: 20),
                      title: const Text(
                        'Reset Demo Session',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: BuildtoColors.primaryNavy),
                      ),
                      subtitle: const Text(
                        'Clear cart and restore default sample orders',
                        style: TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
                      ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Reset Demo Session'),
                            content: const Text(
                              'This will clear your current cart, restore original demo orders, and reset sample delivery data.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel', style: TextStyle(color: BuildtoColors.textMuted)),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  context.read<CartProvider>().clear();
                                  context.read<DemoOrdersProvider>().resetDemoData();
                                  showKSnack(context, 'Demo session reset to initial state');
                                },
                                child: const Text('Reset', style: TextStyle(color: BuildtoColors.primaryNavy)),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  else
                    ListTile(
                      leading: const Icon(LucideIcons.logOut, color: BuildtoColors.errorRed, size: 20),
                      title: const Text(
                        'Log Out',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: BuildtoColors.errorRed),
                      ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Log Out'),
                            content: const Text('Are you sure you want to log out of your Buildto account?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel', style: TextStyle(color: BuildtoColors.textMuted)),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  session.logOut();
                                  showKSnack(context, 'Logged out successfully');
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                                    (route) => false,
                                  );
                                },
                                child: const Text('Log Out', style: TextStyle(color: BuildtoColors.errorRed)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: BuildtoColors.primaryNavy,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: BuildtoColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: BuildtoColors.surfaceLight,
                borderRadius: BorderRadius.circular(BuildtoRadius.sm),
              ),
              child: Icon(icon, size: 18, color: BuildtoColors.primaryNavy),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
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
            const Icon(LucideIcons.chevronRight, size: 16, color: BuildtoColors.textLight),
          ],
        ),
      ),
    );
  }
}
