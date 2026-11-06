import 'dart:async';
import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import '../orders/supplier_orders_repository.dart';
import 'supplier_care_repository.dart';

/// Supplier care: independent return approval and moderated customer feedback.
/// Receiving goods never refunds the customer or restocks a warehouse.
class SupplierCareView extends StatefulWidget {
  const SupplierCareView({
    super.key,
    required this.supplierId,
    required this.repository,
    required this.ordersRepository,
    required this.canReceive,
    this.onRecheckAccess,
  });
  final String supplierId;
  final SupplierCareRepository repository;
  final SupplierOrdersRepository ordersRepository;
  final bool canReceive;
  final VoidCallback? onRecheckAccess;

  @override
  State<SupplierCareView> createState() => _SupplierCareViewState();
}

class _SupplierCareViewState extends State<SupplierCareView> {
  List<SupplierOrder> orders = const [];
  List<SupplierReturn> returns = const [];
  List<SupplierCustomerReview> reviews = const [];
  String? selectedOrder;
  String? error;
  bool loading = true;
  int generation = 0;
  int section = 0;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(SupplierCareView old) {
    super.didUpdateWidget(old);
    if (old.supplierId != widget.supplierId ||
        old.repository != widget.repository ||
        old.ordersRepository != widget.ordersRepository ||
        old.canReceive != widget.canReceive) {
      selectedOrder = null;
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> refresh({String? orderId}) async {
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = null;
      orders = const [];
      returns = const [];
      reviews = const [];
    });
    try {
      final base = await Future.wait<Object>([
        widget.ordersRepository.orders(widget.supplierId),
        widget.repository.reviews(widget.supplierId),
      ]);
      if (!mounted || ticket != generation) return;
      final recent = base[0] as List<SupplierOrder>;
      final feedback = base[1] as List<SupplierCustomerReview>;
      final preferred = orderId ?? selectedOrder;
      final next = recent.any((o) => o.id == preferred)
          ? preferred
          : (recent.isEmpty ? null : recent.first.id);
      final claims = next == null
          ? <SupplierReturn>[]
          : await widget.repository.returns(widget.supplierId, next);
      if (!mounted || ticket != generation) return;
      setState(() {
        orders = recent;
        reviews = feedback;
        returns = claims;
        selectedOrder = next;
        loading = false;
      });
    } catch (e) {
      if (!mounted || ticket != generation) return;
      setState(() {
        loading = false;
        error = switch (e) {
          SupplierV21Exception(problem: SupplierV21Problem.authentication) =>
            'Your Clerk session expired. Sign in again.',
          SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
          SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
            'Supplier membership or this order is no longer authorized.',
          _ => 'Returns and reviews could not be verified. Old data is hidden.',
        };
      });
    }
  }

  Future<void> receive(SupplierReturn item) async {
    if (!widget.canReceive || !item.status.canReceive) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Confirm physical goods receipt?'),
        content: const Text(
            'Confirm only when the independently approved returned materials are physically in your possession. This does not issue a refund, credit note, or warehouse restock.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Goods physically received')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.repository
          .receive(supplierId: widget.supplierId, item: item);
      if (mounted) await refresh();
    } catch (e) {
      if (!mounted) return;
      final message = switch (e) {
        SupplierV21Exception(problem: SupplierV21Problem.conflict) =>
          'Return is not currently approved for receipt. Refresh to review.',
        SupplierV21Exception(problem: SupplierV21Problem.network) =>
          'Receipt outcome is uncertain. Refresh before attempting again.',
        SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
        SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
          'Supplier permission was changed. Recheck access.',
        _ => 'Physical receipt not confirmed. Refresh before trying again.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      await refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView(
          padding: const EdgeInsets.all(20),
          children: const [BuildToSkeleton(height: 145), BuildToSkeleton()]);
    }
    if (error != null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        BuildToStatePanel(
            title: 'Supplier care unavailable',
            message: error!,
            actionLabel: 'Retry',
            onAction: () => unawaited(refresh())),
        if (widget.onRecheckAccess != null)
          OutlinedButton(
              onPressed: widget.onRecheckAccess,
              child: const Text('Recheck supplier access')),
      ]);
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        key: const Key('supplier-care-loaded'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text('Returns & reviews',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: BuildToPalette.navy,
                borderRadius: BorderRadius.circular(20)),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BUILDTO • SUPPLIER CARE',
                    style: TextStyle(
                        color: BuildToPalette.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 12),
                Text('Receipts ≠ refunds',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 5),
                Text(
                    'Only BuildTo support approves claims. Returning goods never automatically restores stock or credits a customer.',
                    style: TextStyle(color: Color(0xFFDDECF9))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            ChoiceChip(
                label: const Text('Return claims'),
                selected: section == 0,
                onSelected: (_) => setState(() => section = 0)),
            ChoiceChip(
                label: const Text('Customer reviews'),
                selected: section == 1,
                onSelected: (_) => setState(() => section = 1)),
          ]),
          const SizedBox(height: 15),
          if (section == 0) ...[
            const BuildToSectionHeading(
                title: 'Return claims',
                subtitle: 'Select a supplier order to review only its claims.'),
            const SizedBox(height: 10),
            if (orders.isEmpty)
              const BuildToStatePanel(
                  title: 'No supplier orders',
                  message: 'Returns become visible against a customer order.',
                  icon: Icons.assignment_return_outlined)
            else
              DropdownButtonFormField<String>(
                key: ValueKey(selectedOrder),
                initialValue: selectedOrder,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Supplier order'),
                items: orders
                    .map((o) => DropdownMenuItem(
                        value: o.id,
                        child: Text(
                            'Order ${o.id.substring(o.id.length - 8).toUpperCase()} · ${o.status.label}',
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (id) {
                  if (id != null) unawaited(refresh(orderId: id));
                },
              ),
            const SizedBox(height: 14),
            if (orders.isNotEmpty && returns.isEmpty)
              const BuildToStatePanel(
                  title: 'No return claims for this order',
                  message:
                      'This view contains only server-verified, supplier-owned claims.'),
            ...returns.map((claim) => BuildToCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                'Return ${claim.id.substring(claim.id.length - 8).toUpperCase()}',
                                style:
                                    Theme.of(context).textTheme.titleMedium)),
                        BuildToStatusChip(
                            label: claim.status.label,
                            status: claim.status ==
                                    SupplierReturnStatus.received
                                ? BuildToStatus.success
                                : claim.status == SupplierReturnStatus.rejected
                                    ? BuildToStatus.danger
                                    : BuildToStatus.pending),
                      ]),
                      const SizedBox(height: 8),
                      Text(claim.reason),
                      ...claim.items.map((line) => Text(
                          '${line.quantity} material units • order item ${line.orderItemId.substring(line.orderItemId.length - 8)}')),
                      if (claim.resolutionNote != null)
                        Text('Support note: ${claim.resolutionNote}'),
                      if (claim.evidenceCount > 0)
                        Text(
                            '${claim.evidenceCount} private evidence items on file'),
                      const SizedBox(height: 8),
                      const Text('Finance: NOT REFUNDED',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: BuildToPalette.warning)),
                      if (widget.canReceive && claim.status.canReceive) ...[
                        const Divider(),
                        BuildToPrimaryButton(
                            label: 'Confirm physical receipt',
                            icon: Icons.inventory_2_outlined,
                            onPressed: () => unawaited(receive(claim))),
                      ],
                    ],
                  ),
                )),
            if (orders.length == 100 || returns.length == 100)
              const Text('List is bounded to the latest 100 orders/claims.'),
          ] else ...[
            const BuildToSectionHeading(
                title: 'Customer feedback',
                subtitle: 'Moderation belongs to independent BuildTo support.'),
            const SizedBox(height: 12),
            if (reviews.isEmpty)
              const BuildToStatePanel(
                  title: 'No customer reviews yet',
                  message: 'Verified supplier feedback will appear here.'),
            ...reviews.map((review) => BuildToCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text('${review.rating} / 5 stars',
                                style:
                                    Theme.of(context).textTheme.titleMedium)),
                        BuildToStatusChip(
                            label: review.status.label,
                            status:
                                review.status == SupplierReviewStatus.published
                                    ? BuildToStatus.success
                                    : BuildToStatus.pending),
                      ]),
                      const SizedBox(height: 7),
                      if (review.comment != null) Text(review.comment!),
                      const SizedBox(height: 5),
                      Text(
                          'Order ${review.supplierOrderId.substring(review.supplierOrderId.length - 8).toUpperCase()}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                )),
            if (reviews.length == 100)
              const Text('Showing the latest 100 supplier reviews.'),
          ],
        ],
      ),
    );
  }
}
