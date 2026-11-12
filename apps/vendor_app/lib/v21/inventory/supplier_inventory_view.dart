import 'dart:async';
import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../catalog/supplier_catalog_models.dart';
import '../catalog/supplier_catalog_repository.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_inventory_models.dart';
import 'supplier_inventory_repository.dart';

/// Supplier-only warehouse/stock screen. The backend alone commits stock.
class SupplierInventoryView extends StatefulWidget {
  const SupplierInventoryView({
    super.key,
    required this.supplierId,
    required this.repository,
    required this.catalog,
    required this.canWrite,
    this.onRecheckAccess,
  });
  final String supplierId;
  final SupplierInventoryRepository repository;
  final SupplierCatalogRepository catalog;
  final bool canWrite;
  final VoidCallback? onRecheckAccess;

  @override
  State<SupplierInventoryView> createState() => _SupplierInventoryViewState();
}

class _SupplierInventoryViewState extends State<SupplierInventoryView> {
  List<SupplierWarehouse> warehouses = const [];
  List<SupplierStockBalance> balances = const [];
  List<CatalogListing> listings = const [];
  bool loading = true;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(SupplierInventoryView old) {
    super.didUpdateWidget(old);
    if (old.supplierId != widget.supplierId ||
        old.canWrite != widget.canWrite ||
        old.repository != widget.repository) {
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
      warehouses = const [];
      balances = const [];
      listings = const [];
    });
    try {
      final rows = await Future.wait<Object>([
        widget.repository.warehouses(widget.supplierId),
        widget.repository.balances(widget.supplierId),
        widget.catalog.listings(widget.supplierId),
      ]);
      if (!mounted || ticket != generation) return;
      final fetchedWarehouses = rows[0] as List<SupplierWarehouse>;
      final fetchedBalances = rows[1] as List<SupplierStockBalance>;
      final fetchedListings = rows[2] as List<CatalogListing>;
      // Supplier-scoped endpoints are independently bounded; a stock row
      // may refer to a listing outside the latest catalog page.
      setState(() {
        warehouses = fetchedWarehouses;
        balances = fetchedBalances;
        listings = fetchedListings;
        loading = false;
      });
    } catch (e) {
      if (!mounted || ticket != generation) return;
      setState(() {
        loading = false;
        error = switch (e) {
          SupplierV21Exception(problem: SupplierV21Problem.authentication) =>
            'Your session expired. Sign in again.',
          SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
          SupplierV21Exception(
            problem: SupplierV21Problem.notFound,
          ) =>
            'Supplier permissions changed. Recheck your membership.',
          _ =>
            'Inventory cannot be verified. Previously loaded stock is hidden.',
        };
      });
    }
  }

  SupplierStockBalance? balance(String listingId, String warehouseId) {
    for (final row in balances) {
      if (row.listingId == listingId && row.warehouseId == warehouseId) {
        return row;
      }
    }
    return null;
  }

  String listingLabel(String id) {
    for (final row in listings) {
      if (row.id == id) return row.sku;
    }
    return 'Unknown listing';
  }

  Future<void> warehouseForm() async {
    final code = TextEditingController();
    final name = TextEditingController();
    var busy = false;
    String? notice;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, change) => AlertDialog(
            title: const Text('New warehouse'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('New warehouses are inactive until activated.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: code,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Warehouse code',
                    ),
                  ),
                  TextField(
                    controller: name,
                    maxLength: 150,
                    decoration: const InputDecoration(
                      labelText: 'Warehouse name',
                    ),
                  ),
                  if (notice != null)
                    Text(
                      notice!,
                      style: const TextStyle(color: BuildToPalette.danger),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        change(() {
                          busy = true;
                          notice = null;
                        });
                        try {
                          await widget.repository.createWarehouse(
                            widget.supplierId,
                            code: code.text,
                            name: name.text,
                          );
                          if (dialog.mounted) Navigator.pop(dialog, true);
                        } catch (e) {
                          if (dialog.mounted) {
                            change(() {
                              notice = e is SupplierV21Exception &&
                                      e.problem == SupplierV21Problem.network
                                  ? 'Outcome uncertain. Refresh warehouses before trying again.'
                                  : 'Warehouse not saved. Check the code and permissions.';
                              busy = false;
                            });
                          }
                        }
                      },
                child: const Text('Create inactive'),
              ),
            ],
          ),
        ),
      );
      if (saved == true && mounted) await refresh();
    } finally {
      code.dispose();
      name.dispose();
    }
  }

  Future<void> _toggleWarehouseActive(SupplierWarehouse warehouse) async {
    if (!widget.canWrite) return;
    final nextState = !warehouse.active;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title:
            Text(nextState ? 'Activate warehouse?' : 'Deactivate warehouse?'),
        content: Text(
          nextState
              ? 'Enable ${warehouse.name} for verified stock operations?'
              : 'Deactivate ${warehouse.name}? Stock in this warehouse cannot be dispatched until re-activated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(nextState ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.updateWarehouse(
        widget.supplierId,
        warehouse,
        active: nextState,
      );
      if (mounted) await refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unable to ${nextState ? "activate" : "deactivate"}. Refresh your warehouse list.',
            ),
          ),
        );
        await refresh();
      }
    }
  }

  Future<void> history(SupplierWarehouse warehouse) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .76,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: FutureBuilder<List<SupplierStockMovement>>(
              future: widget.repository.movements(
                widget.supplierId,
                warehouse.id,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const BuildToStatePanel(
                    title: 'Movements unavailable',
                    message: 'Refresh your supplier permissions and try again.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(
                  children: [
                    Text(
                      'Movements • ${warehouse.code}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children: snapshot.data!
                            .map(
                              (movement) => BuildToCard(
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${movement.kind} · ${movement.delta}',
                                  ),
                                  subtitle: Text(
                                    '${listingLabel(movement.listingId)}\n${movement.reason}',
                                  ),
                                  isThreeLine: true,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    if (snapshot.data!.length == 100)
                      const Text('Showing the latest 100 movements'),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> stockAction({required bool transfer}) async {
    final active = warehouses.where((w) => w.active).toList();
    if (!widget.canWrite || active.isEmpty || listings.isEmpty) return;
    String? listingId = listings.first.id;
    String? fromId = active.first.id;
    String? toId = active.length > 1 ? active[1].id : null;
    String kind = 'RECEIPT';
    final quantity = TextEditingController();
    final reason = TextEditingController();
    final intent = supplierInventoryIntent();
    bool busy = false;
    String? notice;
    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheet) => StatefulBuilder(
          builder: (sheet, change) => Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.viewInsetsOf(sheet).bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transfer ? 'Transfer material' : 'Record stock movement',
                    style: Theme.of(sheet).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Only server-confirmed inventory changes are recorded.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: listingId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Material SKU',
                    ),
                    items: listings
                        .map(
                          (l) =>
                              DropdownMenuItem(value: l.id, child: Text(l.sku)),
                        )
                        .toList(),
                    onChanged: busy ? null : (v) => change(() => listingId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: fromId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: transfer ? 'From warehouse' : 'Warehouse',
                    ),
                    items: active
                        .map(
                          (w) => DropdownMenuItem(
                            value: w.id,
                            child: Text(w.name),
                          ),
                        )
                        .toList(),
                    onChanged: busy ? null : (v) => change(() => fromId = v),
                  ),
                  if (transfer) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: toId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'To warehouse',
                      ),
                      items: active
                          .map(
                            (w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(w.name),
                            ),
                          )
                          .toList(),
                      onChanged: busy ? null : (v) => change(() => toId = v),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      decoration: const InputDecoration(
                        labelText: 'Movement type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'RECEIPT',
                          child: Text('Receipt • add stock'),
                        ),
                        DropdownMenuItem(
                          value: 'DAMAGE',
                          child: Text('Damage • remove stock'),
                        ),
                        DropdownMenuItem(
                          value: 'ADJUSTMENT',
                          child: Text('Adjustment • signed quantity'),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (v) => change(() => kind = v ?? 'RECEIPT'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Exact quantity (up to 3 decimals)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Audit reason',
                    ),
                  ),
                  if (notice != null)
                    Text(
                      notice!,
                      style: const TextStyle(color: BuildToPalette.danger),
                    ),
                  const SizedBox(height: 12),
                  BuildToPrimaryButton(
                    label:
                        transfer ? 'Confirm stock transfer' : 'Record movement',
                    busy: busy,
                    onPressed: () async {
                      change(() {
                        busy = true;
                        notice = null;
                      });
                      try {
                        final source = balance(listingId!, fromId!);
                        if (transfer) {
                          await widget.repository.transfer(
                            supplierId: widget.supplierId,
                            listingId: listingId!,
                            fromWarehouseId: fromId!,
                            toWarehouseId: toId!,
                            quantity: quantity.text.trim(),
                            expectedFromVersion: source?.version ?? 0,
                            expectedToVersion:
                                balance(listingId!, toId!)?.version ?? 0,
                            reason: reason.text,
                            intent: intent,
                          );
                        } else {
                          final value = quantity.text.trim();
                          final signed =
                              kind == 'DAMAGE' && !value.startsWith('-')
                                  ? '-$value'
                                  : value;
                          await widget.repository.adjust(
                            supplierId: widget.supplierId,
                            listingId: listingId!,
                            warehouseId: fromId!,
                            kind: kind,
                            delta: signed,
                            expectedVersion: source?.version ?? 0,
                            reason: reason.text,
                            intent: intent,
                          );
                        }
                        if (sheet.mounted) Navigator.pop(sheet, true);
                      } catch (e) {
                        if (sheet.mounted) {
                          change(() {
                            notice = switch (e) {
                              SupplierV21Exception(
                                problem: SupplierV21Problem.conflict,
                              ) =>
                                'Stock changed. Close and refresh before retrying.',
                              SupplierV21Exception(
                                problem: SupplierV21Problem.network,
                              ) =>
                                'Outcome uncertain. Close and refresh; do not repeat this operation blindly.',
                              FormatException() =>
                                'Check quantity, warehouse selection and reason.',
                              _ =>
                                'Could not confirm stock change. Refresh before trying again.',
                            };
                            busy = false;
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
      quantity.dispose();
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          BuildToSkeleton(height: 145),
          SizedBox(height: 12),
          BuildToSkeleton(),
          SizedBox(height: 12),
          BuildToSkeleton(),
        ],
      );
    }
    if (error != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          BuildToStatePanel(
            title: 'Inventory unavailable',
            message: error!,
            actionLabel: 'Retry inventory',
            onAction: () => unawaited(refresh()),
          ),
          if (widget.onRecheckAccess != null)
            OutlinedButton(
              onPressed: widget.onRecheckAccess,
              child: const Text('Recheck supplier access'),
            ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        key: const Key('supplier-stock-loaded'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Warehouse stock',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                onPressed: () => unawaited(refresh()),
                tooltip: 'Refresh inventory',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: BuildToPalette.navy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SPLYZO • INVENTORY CONTROL',
                  style: TextStyle(
                    color: BuildToPalette.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${warehouses.length == 100 ? '100+' : warehouses.length} warehouses • ${balances.length == 200 ? '200+' : balances.length} balances',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Reserved stock is never available for transfer.',
                  style: TextStyle(color: Color(0xFFDDECF9)),
                ),
              ],
            ),
          ),
          if (widget.canWrite) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => unawaited(warehouseForm()),
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Add warehouse'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      warehouses.any((w) => w.active) && listings.isNotEmpty
                          ? () => unawaited(stockAction(transfer: false))
                          : null,
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('Adjust stock'),
                ),
                OutlinedButton.icon(
                  onPressed: warehouses.where((w) => w.active).length > 1 &&
                          listings.isNotEmpty
                      ? () => unawaited(stockAction(transfer: true))
                      : null,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Transfer'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          const BuildToSectionHeading(
            title: 'Warehouses',
            subtitle: 'Your warehouses and their current status.',
          ),
          const SizedBox(height: 10),
          if (warehouses.isEmpty)
            const BuildToStatePanel(
              title: 'No warehouses yet',
              message:
                  'Create a warehouse and activate it before posting stock.',
            ),
          ...warehouses.map(
            (w) => BuildToCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warehouse_outlined,
                        color: BuildToPalette.navy,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              w.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              w.code,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      BuildToStatusChip(
                        label: w.active ? 'Active' : 'Inactive',
                        status: w.active
                            ? BuildToStatus.success
                            : BuildToStatus.warning,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => unawaited(history(w)),
                        child: const Text('Movements'),
                      ),
                      if (widget.canWrite)
                        TextButton(
                          onPressed: () => unawaited(_toggleWarehouseActive(w)),
                          child: Text(w.active ? 'Deactivate' : 'Activate'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const BuildToSectionHeading(
            title: 'Live stock balances',
            subtitle: 'Exact quantities, held reservations and availability.',
          ),
          const SizedBox(height: 10),
          if (balances.isEmpty)
            const BuildToStatePanel(
              title: 'No stock posted',
              message:
                  'Approved suppliers can record receipts in active warehouses.',
            ),
          ...balances.map(
            (b) => BuildToCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listingLabel(b.listingId),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    warehouses
                            .where((w) => w.id == b.warehouseId)
                            .map((w) => w.name)
                            .firstOrNull ??
                        'Warehouse unavailable',
                  ),
                  const Divider(),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      Text('On hand: ${b.onHandQty}'),
                      Text('Reserved: ${b.reservedQty}'),
                      Text(
                        'Available: ${b.availableQty}',
                        style: const TextStyle(
                          color: BuildToPalette.navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version ${b.version}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (balances.length == 200)
            const Text('Showing the first 200 supplier balances.'),
        ],
      ),
    );
  }
}
