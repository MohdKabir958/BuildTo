import 'dart:async';
import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../dashboard/supplier_dashboard_models.dart';
import '../delivery/supplier_delivery_models.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_orders_repository.dart';

class SupplierOrdersView extends StatefulWidget {
  const SupplierOrdersView({
    super.key,
    required this.supplierId,
    required this.repository,
    required this.canFulfill,
    this.onRecheckAccess,
    this.onOpenShipments,
  });
  final String supplierId;
  final SupplierOrdersRepository repository;
  final bool canFulfill;
  final VoidCallback? onRecheckAccess;
  final void Function(SupplierOrder)? onOpenShipments;

  @override
  State<SupplierOrdersView> createState() => _SupplierOrdersViewState();
}

class _SupplierOrdersViewState extends State<SupplierOrdersView> {
  List<SupplierOrder> orders = const [];
  bool loading = true;
  String? error;
  int generation = 0;
  String filter = 'ALL';

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(SupplierOrdersView old) {
    super.didUpdateWidget(old);
    if (old.supplierId != widget.supplierId ||
        old.repository != widget.repository ||
        old.canFulfill != widget.canFulfill) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> refresh() async {
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = null;
      orders = const [];
    });
    try {
      final data = await widget.repository.orders(widget.supplierId);
      if (!mounted || ticket != generation) return;
      setState(() {
        orders = data;
        loading = false;
      });
    } catch (exception) {
      if (!mounted || ticket != generation) return;
      setState(() {
        loading = false;
        error = switch (exception) {
          SupplierV21Exception(problem: SupplierV21Problem.authentication) =>
            'Your Clerk session has expired.',
          SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
          SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
            'Your approved supplier membership could not be verified.',
          _ => 'Order queue unavailable. Previous order details were cleared.',
        };
      });
    }
  }

  String failure(Object e) => switch (e) {
        SupplierV21Exception(problem: SupplierV21Problem.conflict) =>
          'Backend rejected the transition. Payment, COD selection, committed stock or order status may have changed.',
        SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
        SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
          'Supplier permission changed. Recheck access before acting.',
        SupplierV21Exception(problem: SupplierV21Problem.network) =>
          'Outcome unknown. Refresh orders before attempting another action.',
        FormatException() => 'Check the rejection reason and try again.',
        _ => 'Could not confirm the order decision. Refresh the queue.',
      };

  Future<void> accept(SupplierOrder order) async {
    if (!widget.canFulfill || !order.pending) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Accept supplier order?'),
        content: const Text(
            'BuildTo will verify the captured payment or selected COD and all committed warehouse stock. This action confirms supplier fulfillment.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Confirm acceptance')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await widget.repository.accept(widget.supplierId, order.id);
      if (mounted) await refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure(e))));
      await refresh();
    }
  }

  Future<void> reject(SupplierOrder order) async {
    if (!widget.canFulfill || !order.pending) return;
    final reason = TextEditingController();
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Refuse unpaid order only'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Paid or COD-selected orders cannot be refused here. The backend checks this before changing the status.'),
              const SizedBox(height: 12),
              TextField(
                  controller: reason,
                  minLines: 2,
                  maxLines: 3,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Reason (at least 12 characters)',
                  )),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(dialog, reason.text.trim()),
                child: const Text('Request refusal')),
          ],
        ),
      );
    } finally {
      reason.dispose();
    }
    if (result == null || !mounted) return;
    try {
      await widget.repository.rejectUnpaid(
        supplierId: widget.supplierId,
        supplierOrderId: order.id,
        reason: result,
      );
      if (mounted) await refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure(e))),
      );
      await refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView(
          padding: const EdgeInsets.all(20),
          children: const [BuildToSkeleton(height: 140), BuildToSkeleton()]);
    }
    if (error != null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        BuildToStatePanel(
            title: 'Orders unavailable',
            message: error!,
            actionLabel: 'Retry orders',
            onAction: () => unawaited(refresh())),
        if (widget.onRecheckAccess != null)
          OutlinedButton(
              onPressed: widget.onRecheckAccess,
              child: const Text('Recheck supplier access')),
      ]);
    }
    final visible = orders
        .where((o) =>
            filter == 'ALL' ||
            filter == 'PENDING' && o.pending ||
            filter == 'ACTIVE' && o.status.fulfillmentInProgress ||
            filter == 'CLOSED' && !o.pending && !o.status.fulfillmentInProgress)
        .toList();
    final pending = orders.where((o) => o.pending).length;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        key: const Key('supplier-orders-loaded'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          Row(children: [
            Expanded(
                child: Text('Supplier orders',
                    style: Theme.of(context).textTheme.headlineMedium)),
            IconButton(
                onPressed: () => unawaited(refresh()),
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh orders'),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: BuildToPalette.navy,
              borderRadius: BorderRadius.circular(20),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('BUILDTO • ORDER OPERATIONS',
                  style: TextStyle(
                      color: BuildToPalette.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text('${pending == 100 ? '100+' : pending} awaiting acceptance',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text(
                  'Only the backend can confirm funded/COD eligibility and reserved stock.',
                  style: TextStyle(color: Color(0xFFDDECF9))),
            ]),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 7, runSpacing: 5, children: [
            for (final entry in const {
              'ALL': 'All',
              'PENDING': 'New',
              'ACTIVE': 'In progress',
              'CLOSED': 'Closed'
            }.entries)
              ChoiceChip(
                  label: Text(entry.value),
                  selected: filter == entry.key,
                  onSelected: (_) => setState(() => filter = entry.key)),
          ]),
          const SizedBox(height: 14),
          if (visible.isEmpty)
            const BuildToStatePanel(
              title: 'No orders in this view',
              message: 'Pull to refresh the supplier-scoped queue.',
              icon: Icons.receipt_long_outlined,
            ),
          ...visible.map((order) => BuildToCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                'Order ${order.id.substring(order.id.length - 8).toUpperCase()}',
                                style:
                                    Theme.of(context).textTheme.titleMedium)),
                        BuildToStatusChip(
                          label: order.status.label,
                          status: order.pending
                              ? BuildToStatus.pending
                              : order.status == DashboardOrderStatus.delivered
                                  ? BuildToStatus.success
                                  : order.status ==
                                          DashboardOrderStatus.rejected
                                      ? BuildToStatus.danger
                                      : BuildToStatus.neutral,
                        ),
                      ]),
                      const SizedBox(height: 9),
                      Text('Supplier total: ${deliveryMoney(order.totalPaise)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      ...order.items.take(4).map((line) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                                '${line.sku} • ${line.quantity} ${line.unitCode}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          )),
                      if (order.items.length > 4)
                        Text(
                            '+ ${order.items.length - 4} additional material lines'),
                      const Divider(),
                      if (widget.canFulfill && order.pending)
                        Wrap(spacing: 8, runSpacing: 7, children: [
                          FilledButton.icon(
                              onPressed: () => unawaited(accept(order)),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Accept order')),
                          OutlinedButton(
                              onPressed: () => unawaited(reject(order)),
                              child: const Text('Refuse unpaid only')),
                        ]),
                      if (!widget.canFulfill)
                        const Text('Read-only supplier role.',
                            style: TextStyle(color: BuildToPalette.muted)),
                      if (widget.onOpenShipments != null &&
                          (order.status.fulfillmentInProgress ||
                           order.status == DashboardOrderStatus.delivered))
                        OutlinedButton.icon(
                          onPressed: () => widget.onOpenShipments!(order),
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: const Text('Shipments'),
                        ),
                    ]),
              )),
          if (orders.length == 100)
            const Text(
                'Showing at most 100 recent supplier orders. Counts are bounded.'),
        ],
      ),
    );
  }
}
