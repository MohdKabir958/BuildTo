import 'dart:async';
import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../api/supplier_v21_models.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_dashboard_models.dart';
import 'supplier_dashboard_repository.dart';

enum DashboardDestination { orders, catalog, stock, more }

/// Mounted only for an S02 verified supplier. No persisted business cache:
/// previous figures disappear before refresh and on every failure/scope change.
class SupplierDashboardView extends StatefulWidget {
  const SupplierDashboardView({
    super.key,
    required this.supplierId,
    required this.role,
    required this.repository,
    required this.onNavigate,
    this.onRecheckAccess,
  });
  final String supplierId;
  final SupplierV21Role role;
  final SupplierDashboardRepository repository;
  final ValueChanged<DashboardDestination> onNavigate;
  final VoidCallback? onRecheckAccess;

  @override
  State<SupplierDashboardView> createState() => _SupplierDashboardViewState();
}

class _SupplierDashboardViewState extends State<SupplierDashboardView> {
  SupplierDashboardSnapshot? snapshot;
  String? problem;
  bool loading = true;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(SupplierDashboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.supplierId != widget.supplierId ||
        oldWidget.role != widget.role ||
        !identical(oldWidget.repository, widget.repository)) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _version++;
    super.dispose();
  }

  Future<void> refresh() async {
    final version = ++_version;
    setState(() {
      loading = true;
      snapshot = null;
      problem = null;
    });
    try {
      final data = await widget.repository.load(
        supplierId: widget.supplierId,
        role: widget.role,
      );
      if (!mounted ||
          version != _version ||
          data.supplierId != widget.supplierId) {
        return;
      }
      setState(() {
        snapshot = data;
        loading = false;
      });
    } catch (error) {
      if (!mounted || version != _version) return;
      setState(() {
        snapshot = null;
        loading = false;
        problem = _message(error);
      });
    }
  }

  static String _message(Object error) {
    if (error is SupplierV21Exception) {
      return switch (error.problem) {
        SupplierV21Problem.authentication =>
          'Your Clerk session needs verification before loading business data.',
        SupplierV21Problem.forbidden ||
        SupplierV21Problem.notFound =>
          'Your supplier access has changed. Recheck your active membership.',
        SupplierV21Problem.network ||
        SupplierV21Problem.rateLimited =>
          'Could not refresh business data. Check your connection and retry.',
        SupplierV21Problem.server =>
          'The BuildTo dashboard service is temporarily unavailable.',
        _ => 'Unable to verify the supplier dashboard response.',
      };
    }
    return 'Unable to verify the supplier dashboard response. No previous figures are displayed.';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView(
        key: const Key('supplier-dashboard-loading'),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: const [
          BuildToSkeleton(height: 160),
          SizedBox(height: 18),
          BuildToSkeleton(height: 130),
          SizedBox(height: 12),
          BuildToSkeleton(height: 130),
          SizedBox(height: 16),
          BuildToSkeleton(height: 140),
        ],
      );
    }
    if (problem != null || snapshot == null) {
      return ListView(
        key: const Key('supplier-dashboard-error'),
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 36),
        children: [
          const BuildToSectionHeading(
            title: 'Supplier overview',
            subtitle:
                'Protected business figures require current verification.',
          ),
          const SizedBox(height: 20),
          BuildToStatePanel(
            title: 'Dashboard unavailable',
            message: problem ?? 'Could not verify current supplier data.',
            icon: Icons.shield_outlined,
            actionLabel: 'Retry dashboard',
            onAction: () => unawaited(refresh()),
          ),
          if (widget.onRecheckAccess != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.onRecheckAccess,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Recheck supplier permissions'),
            ),
          ],
        ],
      );
    }

    final data = snapshot!;
    final metrics = <_OverviewMetric>[
      _OverviewMetric(
          'Awaiting acceptance',
          'Recent new orders',
          data.awaitingAcceptance,
          Icons.pending_actions_outlined,
          BuildToPalette.orange),
      _OverviewMetric(
          'In fulfillment',
          'Active order queue',
          data.inFulfillment,
          Icons.local_shipping_outlined,
          BuildToPalette.blue),
      _OverviewMetric(
          'Published listings',
          'Visible materials',
          data.publishedListings,
          Icons.inventory_2_outlined,
          BuildToPalette.success),
      _OverviewMetric('Active warehouses', 'Stock locations',
          data.activeWarehouses, Icons.warehouse_outlined, BuildToPalette.navy),
      if (data.openInvitations != null)
        _OverviewMetric(
            'Open RFQ invites',
            'Available requests',
            data.openInvitations!,
            Icons.request_quote_outlined,
            BuildToPalette.blue),
    ];
    return RefreshIndicator(
      color: BuildToPalette.navy,
      onRefresh: refresh,
      child: ListView(
        key: const Key('supplier-dashboard-loaded'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          Text('Your supplier overview',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('Your material business, in one place.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 18),
          _DashboardHero(
            pending: data.awaitingAcceptance,
            onOrders: () => widget.onNavigate(DashboardDestination.orders),
            onRefresh: () => unawaited(refresh()),
          ),
          const SizedBox(height: 24),
          const BuildToSectionHeading(
            title: 'Business at a glance',
            subtitle: 'Supplier-scoped operational snapshots.',
          ),
          const SizedBox(height: 13),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width < 285 ? 1 : 2;
            final tileWidth = columns == 1 ? width : (width - 12) / 2;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final metric in metrics)
                SizedBox(width: tileWidth, child: _MetricTile(metric: metric)),
            ]);
          }),
          const SizedBox(height: 12),
          Text(
            'Up to 100 most-recent records per section. A “+” means at least '
            'that many matches, not a lifetime total. This is not live push '
            'data, verified revenue, or a bank settlement.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 26),
          const BuildToSectionHeading(
            title: 'Quick access',
            subtitle: 'Open your construction-material workspaces.',
          ),
          const SizedBox(height: 12),
          _QuickActions(onNavigate: widget.onNavigate),
          const SizedBox(height: 26),
          const BuildToSectionHeading(
            title: 'Recent supplier orders',
            subtitle: 'Five most recently returned orders.',
          ),
          const SizedBox(height: 12),
          if (data.recentOrders.isEmpty)
            const BuildToStatePanel(
              title: 'No supplier orders yet',
              message:
                  'When an order reaches this supplier, its real status will appear here.',
              icon: Icons.receipt_long_outlined,
            )
          else
            BuildToCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < data.recentOrders.length; i++) ...[
                  _OrderPreview(order: data.recentOrders[i]),
                  if (i < data.recentOrders.length - 1)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              ]),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => widget.onNavigate(DashboardDestination.orders),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Open orders workspace'),
          ),
          const SizedBox(height: 18),
          Row(children: [
            const Icon(Icons.shield_outlined,
                size: 16, color: BuildToPalette.success),
            const SizedBox(width: 7),
            Expanded(
                child: Text('Clerk-secured scope · manual refresh',
                    style: Theme.of(context).textTheme.bodySmall)),
          ]),
        ],
      ),
    );
  }
}

class _OverviewMetric {
  const _OverviewMetric(
      this.label, this.hint, this.count, this.icon, this.accent);
  final String label, hint;
  final DashboardCount count;
  final IconData icon;
  final Color accent;
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.pending,
    required this.onOrders,
    required this.onRefresh,
  });
  final DashboardCount pending;
  final VoidCallback onOrders, onRefresh;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 23, 22, 21),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              BuildToPalette.navyDeep,
              BuildToPalette.navy,
              Color(0xFF07528B),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.auto_graph_rounded,
                size: 19, color: BuildToPalette.orange),
            SizedBox(width: 9),
            Expanded(
                child: Text(
              'BUILDTO • BUSINESS PULSE',
              style: TextStyle(
                  color: Colors.white,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  fontSize: 11),
            )),
          ]),
          const SizedBox(height: 18),
          const Text(
            'Building business,\nmade easier.',
            style: TextStyle(
                fontSize: 25,
                color: Colors.white,
                height: 1.12,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            '${pending.label} awaiting acceptance in your recent supplier orders',
            style: const TextStyle(
                color: Color(0xFFE6F2FF), fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
              onPressed: onOrders,
              style: FilledButton.styleFrom(
                backgroundColor: BuildToPalette.orange,
                foregroundColor: BuildToPalette.navyDeep,
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Review orders'),
            ),
            OutlinedButton.icon(
              onPressed: onRefresh,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF9BBDD9)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ]),
        ]),
      );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});
  final _OverviewMetric metric;

  @override
  Widget build(BuildContext context) => BuildToCard(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 146),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: metric.accent.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(metric.icon, color: metric.accent, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              metric.count.label,
              key: Key('dashboard-metric-${metric.label}'),
              style: const TextStyle(
                  color: BuildToPalette.navyDeep,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.0),
            ),
            const SizedBox(height: 9),
            Text(metric.label,
                maxLines: 2, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(metric.hint,
                maxLines: 2, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onNavigate});
  final ValueChanged<DashboardDestination> onNavigate;

  @override
  Widget build(BuildContext context) => Column(children: [
        _QuickActionTile(
            title: 'Orders & fulfillment',
            subtitle: 'Order workspace',
            icon: Icons.local_shipping_outlined,
            action: () => onNavigate(DashboardDestination.orders)),
        const SizedBox(height: 10),
        _QuickActionTile(
            title: 'Product catalog',
            subtitle: 'Materials & listing status',
            icon: Icons.category_outlined,
            action: () => onNavigate(DashboardDestination.catalog)),
        const SizedBox(height: 10),
        _QuickActionTile(
            title: 'Warehouse stock',
            subtitle: 'Stock locations',
            icon: Icons.warehouse_outlined,
            action: () => onNavigate(DashboardDestination.stock)),
        const SizedBox(height: 10),
        _QuickActionTile(
            title: 'Business & support',
            subtitle: 'Applications & account tools',
            icon: Icons.business_center_outlined,
            action: () => onNavigate(DashboardDestination.more)),
      ]);
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.action,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) => BuildToCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          onTap: action,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: BuildToPalette.sky,
            foregroundColor: BuildToPalette.navy,
            child: Icon(icon),
          ),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle:
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          trailing: const Icon(Icons.arrow_forward_ios_rounded,
              size: 17, color: BuildToPalette.blue),
        ),
      );
}

class _OrderPreview extends StatelessWidget {
  const _OrderPreview({required this.order});
  final DashboardOrder order;

  BuildToStatus get status => switch (order.status) {
        DashboardOrderStatus.pendingAcceptance => BuildToStatus.warning,
        DashboardOrderStatus.confirmed ||
        DashboardOrderStatus.packing ||
        DashboardOrderStatus.ready =>
          BuildToStatus.pending,
        DashboardOrderStatus.dispatched ||
        DashboardOrderStatus.partiallyDelivered =>
          BuildToStatus.warning,
        DashboardOrderStatus.delivered => BuildToStatus.success,
        DashboardOrderStatus.cancelled ||
        DashboardOrderStatus.rejected =>
          BuildToStatus.danger,
      };

  @override
  Widget build(BuildContext context) {
    final localDate = order.createdAt.toLocal();
    final date = '${localDate.day.toString().padLeft(2, '0')}/'
        '${localDate.month.toString().padLeft(2, '0')}/'
        '${localDate.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.receipt_long_outlined,
              color: BuildToPalette.navy, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Order • ${order.shortId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium)),
          const SizedBox(width: 8),
          Text(date, style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BuildToStatusChip(label: order.status.label, status: status),
            Text('${order.lineCount} material line(s)',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ]),
    );
  }
}
