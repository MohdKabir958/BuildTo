import 'dart:async';
import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../dashboard/supplier_dashboard_models.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import '../inventory/supplier_inventory_models.dart';
import '../inventory/supplier_inventory_repository.dart';
import '../orders/supplier_orders_repository.dart';
import 'supplier_shipments_repository.dart';

/// S10: supplier fulfils its own construction order. This screen never
/// creates an OTP, marks local delivery or bypasses the customer handover.
class SupplierShipmentsView extends StatefulWidget {
  const SupplierShipmentsView({
    super.key,
    required this.supplierId,
    required this.order,
    required this.repository,
    required this.inventory,
    required this.canFulfill,
    this.onRecheckAccess,
  });
  final String supplierId;
  final SupplierOrder order;
  final SupplierShipmentsRepository repository;
  final SupplierInventoryRepository inventory;
  final bool canFulfill;
  final VoidCallback? onRecheckAccess;

  @override
  State<SupplierShipmentsView> createState() => _SupplierShipmentsViewState();
}

class _SupplierShipmentsViewState extends State<SupplierShipmentsView> {
  List<SupplierShipment> shipments = const [];
  List<SupplierWarehouse> warehouses = const [];
  bool loading = true;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(SupplierShipmentsView old) {
    super.didUpdateWidget(old);
    if (old.supplierId != widget.supplierId ||
        old.order.id != widget.order.id ||
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
    final current = ++generation;
    setState(() {
      loading = true;
      error = null;
      shipments = const [];
      warehouses = const [];
    });
    try {
      final results = await Future.wait<Object>([
        widget.repository.list(widget.supplierId, widget.order.id),
        widget.inventory.warehouses(widget.supplierId),
      ]);
      if (!mounted || current != generation) return;
      setState(() {
        shipments = results[0] as List<SupplierShipment>;
        warehouses = results[1] as List<SupplierWarehouse>;
        loading = false;
      });
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(() {
        loading = false;
        error = switch (e) {
          SupplierV21Exception(problem: SupplierV21Problem.authentication) =>
            'Clerk session expired.',
          SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
          SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
            'Supplier access was revoked or this order is unavailable.',
          _ => 'Could not verify live shipments. Stale data is hidden.',
        };
      });
    }
  }

  String actionError(Object e) => switch (e) {
        SupplierV21Exception(problem: SupplierV21Problem.conflict) =>
          'Shipment state or stock allocation changed. Refresh before a new action.',
        SupplierV21Exception(problem: SupplierV21Problem.network) =>
          'Outcome uncertain. Refresh shipments before trying again.',
        SupplierV21Exception(problem: SupplierV21Problem.rateLimited) =>
          'Too many attempts. Customer OTP may be temporarily locked.',
        SupplierV21Exception(problem: SupplierV21Problem.validation) =>
          'The backend rejected this handover or quantity. Check the details.',
        SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
        SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
          'Supplier access changed. Recheck current permissions.',
        FormatException() =>
          'Check the exact quantity, warehouse and form details.',
        _ => 'Shipment action not confirmed. Refresh before trying again.',
      };

  void report(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(actionError(e))),
    );
    unawaited(refresh());
  }

  Future<void> plan() async {
    if (!widget.canFulfill) return;
    final available = warehouses.where((w) => w.active).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active warehouse found. Please activate a warehouse in the Stock tab first.'),
        ),
      );
      return;
    }
    final selected = <String>{};
    final quantity = {
      for (final line in widget.order.items)
        line.id: TextEditingController(text: line.quantity),
    };
    final carrier = TextEditingController();
    final tracking = TextEditingController();
    String chosenWarehouse = available.first.id;
    final intent = supplierInventoryIntent();
    bool busy = false;
    bool uncertain = false;
    String? notice;
    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheet) => StatefulBuilder(
          builder: (sheet, change) => FractionallySizedBox(
            heightFactor: .92,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, MediaQuery.viewInsetsOf(sheet).bottom + 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Plan warehouse shipment',
                      style: Theme.of(sheet).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text(
                      'Choose committed warehouse stock and exact order quantities. Allocation is rechecked by BuildTo.'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: chosenWarehouse,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Active dispatch warehouse'),
                    items: available
                        .map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(w.name),
                            ))
                        .toList(),
                    onChanged: busy || uncertain
                        ? null
                        : (value) => change(
                            () => chosenWarehouse = value ?? chosenWarehouse),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                      child: ListView(children: [
                    for (final line in widget.order.items)
                      BuildToCard(
                          child: Column(children: [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(line.sku),
                          subtitle:
                              Text('Ordered ${line.quantity} ${line.unitCode}'),
                          value: selected.contains(line.id),
                          onChanged: busy || uncertain
                              ? null
                              : (value) => change(() {
                                    if (value == true) {
                                      selected.add(line.id);
                                    } else {
                                      selected.remove(line.id);
                                    }
                                  }),
                        ),
                        if (selected.contains(line.id))
                          TextField(
                            controller: quantity[line.id],
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Quantity to ship (${line.unitCode})',
                              helperText:
                                  'May not exceed unallocated committed warehouse stock',
                            ),
                          ),
                      ])),
                    const SizedBox(height: 9),
                    TextField(
                        controller: carrier,
                        maxLength: 160,
                        decoration: const InputDecoration(
                            labelText: 'Carrier name (optional)')),
                    const SizedBox(height: 9),
                    TextField(
                        controller: tracking,
                        maxLength: 100,
                        decoration: const InputDecoration(
                            labelText: 'Tracking reference (optional)')),
                    if (notice != null)
                      Text(notice!,
                          style: const TextStyle(color: BuildToPalette.danger)),
                  ])),
                  const SizedBox(height: 10),
                  BuildToPrimaryButton(
                    label: uncertain
                        ? 'Refresh to reconcile shipment'
                        : 'Create server-validated shipment',
                    busy: busy,
                    onPressed: busy || uncertain || selected.isEmpty
                        ? null
                        : () async {
                            change(() {
                              busy = true;
                              notice = null;
                            });
                            try {
                              await widget.repository.plan(
                                supplierId: widget.supplierId,
                                order: widget.order,
                                warehouseId: chosenWarehouse,
                                lines: [
                                  for (final id in selected)
                                    SupplierShipmentPlanLine(
                                        id, quantity[id]!.text.trim()),
                                ],
                                carrierName: carrier.text,
                                trackingReference: tracking.text,
                                intent: intent,
                              );
                              if (sheet.mounted) Navigator.pop(sheet, true);
                            } catch (e) {
                              if (sheet.mounted) {
                                change(() {
                                  busy = false;
                                  uncertain = e is SupplierV21Exception &&
                                      e.problem == SupplierV21Problem.network;
                                  notice = uncertain
                                      ? 'Outcome may have committed. Close and refresh to reconcile; do not create a duplicate.'
                                      : 'Shipment was not confirmed. Check selection, available stock and status.';
                                });
                              }
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (saved == true && mounted) await refresh();
    } finally {
      for (final controller in [...quantity.values, carrier, tracking]) {
        controller.dispose();
      }
    }
  }

  Future<void> progress(SupplierShipment shipment, String stage) async {
    if (!widget.canFulfill || shipment.status.nextStep != stage) return;
    final expected = switch (stage) {
      'pack' => 'Pack',
      'dispatch' => 'Dispatch',
      'out-for-delivery' => 'Mark out for delivery',
      _ => 'Change shipment',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('$expected shipment?'),
        content: Text('Only BuildTo can confirm the next shipment status. '
            'Shipment: ${shipment.shipmentNumber}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(expected)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.progress(
          supplierId: widget.supplierId, shipment: shipment, stage: stage);
      if (mounted) await refresh();
    } catch (e) {
      report(e);
    }
  }

  Future<void> handover(SupplierShipment shipment) async {
    if (!widget.canFulfill ||
        shipment.status != SupplierShipmentStatus.outForDelivery) {
      return;
    }
    final code = TextEditingController();
    final recipient = TextEditingController();
    bool busy = false;
    bool uncertain = false;
    String? notice;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, change) => AlertDialog(
            title: const Text('Customer delivery OTP'),
            content: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Ask the customer to issue a fresh OTP from their own order. Never generate it here. OTP expires after five minutes.'),
                const SizedBox(height: 14),
                TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Customer-issued 6-digit code'),
                ),
                TextField(
                    controller: recipient,
                    maxLength: 160,
                    decoration: const InputDecoration(
                        labelText: 'Received by (optional)')),
                if (notice != null)
                  Text(notice!,
                      style: const TextStyle(color: BuildToPalette.danger)),
              ],
            )),
            actions: [
              TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialog, false),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: busy || uncertain
                    ? null
                    : () async {
                        change(() {
                          busy = true;
                          notice = null;
                        });
                        try {
                          await widget.repository.verifyCustomerOtp(
                            supplierId: widget.supplierId,
                            shipment: shipment,
                            otp: code.text.trim(),
                            receivedBy: recipient.text,
                          );
                          if (dialog.mounted) Navigator.pop(dialog, true);
                        } catch (e) {
                          if (dialog.mounted) {
                            change(() {
                              busy = false;
                              uncertain = e is SupplierV21Exception &&
                                  e.problem == SupplierV21Problem.network;
                              notice = uncertain
                                  ? 'Outcome uncertain. Close and refresh before any retry.'
                                  : 'Verification failed, expired or locked. Use a valid customer-issued code. Never guess.';
                            });
                          }
                        }
                      },
                child: const Text('Verify handover'),
              ),
            ],
          ),
        ),
      );
      if (saved == true && mounted) await refresh();
    } finally {
      code.dispose();
      recipient.dispose();
    }
  }

  Future<void> cancel(SupplierShipment shipment) async {
    if (!widget.canFulfill ||
        (shipment.status != SupplierShipmentStatus.planned &&
            shipment.status != SupplierShipmentStatus.packed)) {
      return;
    }
    final reasonController = TextEditingController();
    String? reason;
    try {
      reason = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Cancel shipment?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cancelling releases the allocated warehouse stock back to inventory. '
                'Only shipments before dispatch can be cancelled.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                minLines: 2,
                maxLines: 4,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Cancellation reason (min 8 characters)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialog, reasonController.text.trim()),
              child: const Text('Confirm cancel'),
            ),
          ],
        ),
      );
    } finally {
      reasonController.dispose();
    }
    if (reason == null || reason.length < 8 || !mounted) return;
    try {
      await widget.repository.cancel(
        supplierId: widget.supplierId,
        shipment: shipment,
        reason: reason,
      );
      if (mounted) await refresh();
    } catch (e) {
      report(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView(
          padding: const EdgeInsets.all(20),
          children: const [BuildToSkeleton(height: 120), BuildToSkeleton()]);
    }
    if (error != null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        BuildToStatePanel(
            title: 'Shipment data unavailable',
            message: error!,
            actionLabel: 'Retry shipments',
            onAction: () => unawaited(refresh())),
        if (widget.onRecheckAccess != null)
          OutlinedButton(
              onPressed: widget.onRecheckAccess,
              child: const Text('Recheck supplier access')),
      ]);
    }
    final eligible = widget.canFulfill &&
        !{
          DashboardOrderStatus.pendingAcceptance,
          DashboardOrderStatus.cancelled,
          DashboardOrderStatus.rejected,
          DashboardOrderStatus.delivered
        }.contains(widget.order.status) &&
        warehouses.any((w) => w.active);
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        key: const Key('supplier-shipments-loaded'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          Text('Order shipments',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: BuildToPalette.navy,
                borderRadius: BorderRadius.circular(20)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('BUILDTO • MATERIAL HANDOVER',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: BuildToPalette.orange)),
              const SizedBox(height: 12),
              Text(
                  '${shipments.length == 100 ? '100+' : shipments.length} verified shipments',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Supplier-arranged dispatch • customer-issued OTP',
                  style: TextStyle(color: Color(0xFFDDECF9))),
            ]),
          ),
          const SizedBox(height: 14),
          if (eligible)
            BuildToPrimaryButton(
              label: 'Plan shipment from warehouse',
              icon: Icons.add_road_rounded,
              onPressed: () => unawaited(plan()),
            ),
          if (widget.canFulfill && !warehouses.any((w) => w.active))
            const Text(
                'Activate a warehouse in Stock before allocating shipments.'),
          const SizedBox(height: 15),
          if (shipments.isEmpty)
            const BuildToStatePanel(
                title: 'No shipments planned',
                message:
                    'Only backend-confirmed warehouse allocations will appear here.',
                icon: Icons.local_shipping_outlined),
          ...shipments.map((shipment) => BuildToCard(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(shipment.shipmentNumber,
                            style: Theme.of(context).textTheme.titleMedium)),
                    BuildToStatusChip(
                        label: shipment.status.label,
                        status: shipment.status ==
                                SupplierShipmentStatus.delivered
                            ? BuildToStatus.success
                            : shipment.status == SupplierShipmentStatus.failed
                                ? BuildToStatus.danger
                                : BuildToStatus.pending),
                  ]),
                  const SizedBox(height: 9),
                  Text(
                      'Warehouse: ${warehouses.where((w) => w.id == shipment.warehouseId).map((w) => w.name).firstOrNull ?? 'Unavailable'}'),
                  if (shipment.carrierName != null)
                    Text('Carrier: ${shipment.carrierName}'),
                  if (shipment.trackingReference != null)
                    Text('Tracking: ${shipment.trackingReference}'),
                  const Divider(),
                  ...shipment.items.map((line) => Text(
                      '${widget.order.items.where((e) => e.id == line.orderItemId).map((e) => e.sku).firstOrNull ?? 'Material'} • ${line.quantity}')),
                  if (shipment.events.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('Verified movement history',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    ...shipment.events.take(5).map((event) => Text(
                        '${event.to.label} · ${event.at.toLocal().toString().split('.').first}',
                        style: Theme.of(context).textTheme.bodySmall)),
                  ],
                  const SizedBox(height: 9),
                  if (widget.canFulfill && shipment.status.nextStep != null)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(
                          progress(shipment, shipment.status.nextStep!)),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(switch (shipment.status.nextStep!) {
                        'pack' => 'Confirm packed',
                        'dispatch' => 'Confirm dispatch',
                        _ => 'Out for delivery',
                      }),
                    ),
                  if (widget.canFulfill &&
                      (shipment.status == SupplierShipmentStatus.planned ||
                          shipment.status == SupplierShipmentStatus.packed))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: OutlinedButton.icon(
                        onPressed: () => unawaited(cancel(shipment)),
                        icon: const Icon(Icons.cancel_outlined,
                            color: BuildToPalette.danger),
                        label: const Text('Cancel shipment',
                            style: TextStyle(color: BuildToPalette.danger)),
                      ),
                    ),
                  if (widget.canFulfill &&
                      shipment.status == SupplierShipmentStatus.outForDelivery)
                    BuildToPrimaryButton(
                      label: 'Verify customer handover OTP',
                      icon: Icons.verified_user_outlined,
                      onPressed: () => unawaited(handover(shipment)),
                    ),
                  if (shipment.handoverVerified)
                    const Text('Delivery verified by backend.',
                        style: TextStyle(color: BuildToPalette.success)),
                ],
              ))),
          const SizedBox(height: 16),
          const Text(
              'Delivery exception requires independent admin approval. No supplier bypass is offered.'),
          if (shipments.length == 100)
            const Text('Showing at most 100 shipments for this order.'),
        ],
      ),
    );
  }
}
