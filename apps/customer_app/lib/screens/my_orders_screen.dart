import '../providers/demo_orders_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../config/buildto_theme.dart';
import '../widgets/ui/k_image.dart';
import 'cancel_order_screen.dart';
import 'repeat_order_screen.dart';
import 'track_order_screen.dart';

/// Screen 08 — My Orders
/// Orders history with status filtering tabs, material thumbnails, and live tracking CTAs.
class MyOrdersScreen extends StatefulWidget {
  final bool showBackButton;

  const MyOrdersScreen({
    super.key,
    this.showBackButton = true,
  });

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Map<String, dynamic>> _demoOrders = [
    {
      'id': '#BT012456',
      'date': '24 Oct 2026, 10:30 AM',
      'status': 'Out for Delivery',
      'statusCode': 'processing',
      'items': [
        {'name': 'Ultratech Cement 50kg Bag', 'qty': 3, 'price': 1170.0, 'image': 'assets/products/ultratech_cement.jpg'},
        {'name': 'Tata Tiscon 550D TMT Rebar 12mm', 'qty': 2, 'price': 2250.0, 'image': 'assets/products/tmt_steel_bars.jpg'},
      ],
      'total': 3420.0,
      'supplier': 'Shree Shyam Enterprises',
    },
    {
      'id': '#BT011982',
      'date': '20 Oct 2026, 03:15 PM',
      'status': 'Delivered',
      'statusCode': 'delivered',
      'items': [
        {'name': 'Kiln Burned Red Clay Bricks (1,000 Pcs)', 'qty': 1, 'price': 7500.0, 'image': 'assets/products/red_bricks.jpg'},
        {'name': 'Coarse River Sand (100 CFT)', 'qty': 1, 'price': 5200.0, 'image': 'assets/products/sand_aggregates.jpg'},
      ],
      'total': 12700.0,
      'supplier': 'ABC Traders',
    },
    {
      'id': '#BT010411',
      'date': '14 Oct 2026, 11:00 AM',
      'status': 'Delivered',
      'statusCode': 'delivered',
      'items': [
        {'name': 'ACC Gold Water Shield Cement 50kg', 'qty': 5, 'price': 2100.0, 'image': 'assets/products/acc_cement.jpg'},
      ],
      'total': 2100.0,
      'supplier': 'R.K. Building Materials',
    },
    {
      'id': '#BT009832',
      'date': '08 Oct 2026, 09:45 AM',
      'status': 'Cancelled',
      'statusCode': 'cancelled',
      'items': [
        {'name': 'Ambuja Kawach Cement 50kg', 'qty': 4, 'price': 1680.0, 'image': 'assets/products/ambuja_cement.jpg'},
      ],
      'total': 1680.0,
      'supplier': 'Shree Shyam Enterprises',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filteredOrders(String filter, List<Map<String, dynamic>> orders) {
    if (filter == 'all') return orders;
    if (filter == 'pending') return orders.where((o) => o['statusCode'] == 'pending').toList();
    if (filter == 'processing') return orders.where((o) => o['statusCode'] == 'processing').toList();
    if (filter == 'delivered') return orders.where((o) => o['statusCode'] == 'delivered').toList();
    if (filter == 'cancelled') return orders.where((o) => o['statusCode'] == 'cancelled').toList();
    return orders;
  }

  @override
  Widget build(BuildContext context) {
    final demoOrders = context.watch<DemoOrdersProvider>();
    final allOrders = demoOrders.orders.map((o) => o.toMap()).toList();

    return Scaffold(
      backgroundColor: BuildtoColors.surfaceLight,
      appBar: AppBar(
        backgroundColor: BuildtoColors.bgWhite,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(LucideIcons.arrowLeft, color: BuildtoColors.primaryNavy),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          'My Orders',
          style: TextStyle(
            color: BuildtoColors.primaryNavy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: BuildtoColors.primaryNavy,
          unselectedLabelColor: BuildtoColors.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          indicatorColor: BuildtoColors.primaryNavy,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'Processing'),
            Tab(text: 'Delivered'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrdersList(_filteredOrders('all', allOrders)),
          _buildOrdersList(_filteredOrders('pending', allOrders)),
          _buildOrdersList(_filteredOrders('processing', allOrders)),
          _buildOrdersList(_filteredOrders('delivered', allOrders)),
          _buildOrdersList(_filteredOrders('cancelled', allOrders)),
        ],
      ),
    );
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> orders) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.packageOpen, size: 48, color: BuildtoColors.textLight),
            const SizedBox(height: 12),
            const Text(
              'No orders found',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: BuildtoColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Orders matching this status will appear here.',
              style: TextStyle(fontSize: 12, color: BuildtoColors.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final order = orders[index];
        final items = order['items'] as List<dynamic>;
        final status = order['status'] as String;
        final statusCode = order['statusCode'] as String;

        Color badgeBg = BuildtoColors.infoBg;
        Color badgeFg = BuildtoColors.infoBlue;
        if (statusCode == 'delivered') {
          badgeBg = BuildtoColors.successBg;
          badgeFg = BuildtoColors.successGreen;
        } else if (statusCode == 'processing') {
          badgeBg = BuildtoColors.warningBg;
          badgeFg = BuildtoColors.warningAmber;
        } else if (statusCode == 'cancelled') {
          badgeBg = BuildtoColors.errorBg;
          badgeFg = BuildtoColors.errorRed;
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: BuildtoColors.bgWhite,
            borderRadius: BorderRadius.circular(BuildtoRadius.md),
            border: Border.all(color: BuildtoColors.cardBorder),
            boxShadow: BuildtoShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Order ID & Status Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order['id'],
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: BuildtoColors.primaryNavy,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: badgeFg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Placed on ${order['date']}',
                style: const TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: BuildtoColors.cardBorder),
              const SizedBox(height: 12),

              // Items Thumbnails Row
              Row(
                children: [
                  Row(
                    children: items.take(2).map((it) {
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                          border: Border.all(color: BuildtoColors.cardBorder),
                          color: BuildtoColors.surfaceLight,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                          child: KImage(
                            url: it['image'] as String,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${items.length} ${items.length == 1 ? "Item" : "Items"} • ${order['supplier']}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: BuildtoColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items.map((i) => i['name']).join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: BuildtoColors.cardBorder),
              const SizedBox(height: 12),

              // Total & Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Amount',
                        style: TextStyle(fontSize: 11, color: BuildtoColors.textMuted),
                      ),
                      Text(
                        '₹${(order['total'] as double).toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: BuildtoColors.primaryNavy,
                        ),
                      ),
                    ],
                  ),

                  // Actions
                  Row(
                    children: [
                      if (statusCode == 'processing') ...[
                        OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CancelOrderScreen(
                                  orderId: order['id'],
                                  orderTotal: order['total'],
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: BuildtoColors.errorRed,
                            side: const BorderSide(color: BuildtoColors.errorRed),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: const Size(60, 32),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                            ),
                          ),
                          child: const Text('Cancel', style: TextStyle(fontSize: 11)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TrackOrderScreen(orderId: order['id']),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BuildtoColors.primaryNavy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: const Size(70, 32),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                            ),
                            elevation: 0,
                          ),
                          child: const Text('Track', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ] else ...[
                        OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RepeatOrderScreen()),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: BuildtoColors.primaryNavy,
                            side: const BorderSide(color: BuildtoColors.primaryNavy),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: const Size(70, 32),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(BuildtoRadius.sm),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.repeat, size: 12),
                              SizedBox(width: 4),
                              Text('Reorder', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
