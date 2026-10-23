import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String timestamp;
  final String time;
  final String category;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String? orderId;
  final bool isRead;

  const NotificationItem({
    required this.id,
    required this.title,
    this.body = '',
    this.timestamp = '',
    this.time = '',
    this.category = 'order',
    this.icon = LucideIcons.bell,
    this.iconColor = const Color(0xFF002B5B),
    this.iconBg = const Color(0xFFE2E8F0),
    this.orderId,
    this.isRead = false,
  });
}

class NotificationsProvider with ChangeNotifier {
  final List<NotificationItem> _notifications = [
    const NotificationItem(
      id: 'notif-1',
      title: 'Order Out for Delivery',
      body: 'Your materials (#BT012456) are on flatbed truck DL 1L AA 9081 and heading to Lal Bihara site.',
      timestamp: '15m ago',
      time: '12 Apr 04:20 PM',
      category: 'order',
      icon: LucideIcons.truck,
      iconColor: Color(0xFF0284C7),
      iconBg: Color(0xFFE0F2FE),
      orderId: 'BT012456',
      isRead: false,
    ),
    const NotificationItem(
      id: 'notif-2',
      title: 'Order Packed at Supplier Yard',
      body: 'Shree Shyam Enterprises has loaded and packed your UltraTech cement bags and TMT bars.',
      timestamp: '2h ago',
      time: '12 Apr 02:15 PM',
      category: 'order',
      icon: LucideIcons.packageCheck,
      iconColor: Color(0xFFD97706),
      iconBg: Color(0xFFFEF3C7),
      orderId: 'BT012456',
      isRead: false,
    ),
    const NotificationItem(
      id: 'notif-3',
      title: 'Bulk Discount Alert',
      body: 'Get 10% off on all Fe 550D TMT Steel rebars when ordering 20+ pieces this weekend.',
      timestamp: '1d ago',
      time: '11 Apr 10:00 AM',
      category: 'promo',
      icon: LucideIcons.badgePercent,
      iconColor: Color(0xFF16A34A),
      iconBg: Color(0xFFDCFCE7),
      isRead: true,
    ),
    const NotificationItem(
      id: 'notif-4',
      title: 'New Material Stocked',
      body: 'Asian Paints Apex Ultima Exterior Emulsion (20L) is now in stock at National Hardware.',
      timestamp: '2d ago',
      time: '10 Apr 06:45 PM',
      category: 'promo',
      icon: LucideIcons.sparkles,
      iconColor: Color(0xFF4F46E5),
      iconBg: Color(0xFFEEF2FF),
      isRead: true,
    ),
  ];

  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void markAsRead(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index >= 0 && !_notifications[index].isRead) {
      final old = _notifications[index];
      _notifications[index] = NotificationItem(
        id: old.id,
        title: old.title,
        body: old.body,
        timestamp: old.timestamp,
        time: old.time,
        category: old.category,
        icon: old.icon,
        iconColor: old.iconColor,
        iconBg: old.iconBg,
        orderId: old.orderId,
        isRead: true,
      );
      notifyListeners();
    }
  }

  void markAllAsRead() {
    for (int i = 0; i < _notifications.length; i++) {
      final old = _notifications[i];
      _notifications[i] = NotificationItem(
        id: old.id,
        title: old.title,
        body: old.body,
        timestamp: old.timestamp,
        time: old.time,
        category: old.category,
        icon: old.icon,
        iconColor: old.iconColor,
        iconBg: old.iconBg,
        orderId: old.orderId,
        isRead: true,
      );
    }
    notifyListeners();
  }
}
