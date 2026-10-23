import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../config/buildto_theme.dart';
import '../providers/notifications_provider.dart';
import 'browse_category_screen.dart';
import 'track_order_screen.dart';

/// Screen 12 — Notifications
/// Order updates, supplier dispatch alerts, bulk offers, and wholesale price drops.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifProvider = context.watch<NotificationsProvider>();
    final notifications = notifProvider.notifications;

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
          'Notifications',
          style: TextStyle(
            color: BuildtoColors.primaryNavy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (notifProvider.unreadCount > 0)
            TextButton(
              onPressed: () => notifProvider.markAllAsRead(),
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: BuildtoColors.primaryNavy,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.bellOff, size: 48, color: BuildtoColors.textLight),
                  const SizedBox(height: 12),
                  const Text(
                    'No notifications yet',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: BuildtoColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'You will receive real-time order and price updates here.',
                    style: TextStyle(fontSize: 12, color: BuildtoColors.textMuted),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final notif = notifications[index];
                final isOrder = notif.category == 'order';

                return InkWell(
                  onTap: () {
                    notifProvider.markAsRead(notif.id);
                    if (isOrder) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TrackOrderScreen()),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BrowseCategoryScreen(categoryName: 'Steel & TMT Bars'),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: notif.isRead ? BuildtoColors.bgWhite : const Color(0xFFF0F7FF),
                      borderRadius: BorderRadius.circular(BuildtoRadius.md),
                      border: Border.all(
                        color: notif.isRead ? BuildtoColors.cardBorder : BuildtoColors.primaryNavy.withValues(alpha: 0.2),
                      ),
                      boxShadow: BuildtoShadows.card,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Category Icon
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isOrder
                                ? BuildtoColors.primaryNavy.withValues(alpha: 0.1)
                                : BuildtoColors.accentAmber.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isOrder ? LucideIcons.truck : LucideIcons.badgePercent,
                            size: 18,
                            color: isOrder ? BuildtoColors.primaryNavy : BuildtoColors.accentAmber,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Message Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      notif.title,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.bold,
                                        color: BuildtoColors.textDark,
                                      ),
                                    ),
                                  ),
                                  if (!notif.isRead)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: BuildtoColors.accentAmber,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                notif.body,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: BuildtoColors.textMuted,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                notif.timestamp,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: BuildtoColors.textLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
