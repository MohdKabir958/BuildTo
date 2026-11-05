import 'dart:async';
import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../catalog/supplier_catalog_models.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_delivery_models.dart';
import 'supplier_delivery_repository.dart';

/// Admin-authored service areas only. Supplier prices are quoted by the
/// backend again at checkout; this screen never promises final freight.
class SupplierDeliveryView extends StatefulWidget {
  const SupplierDeliveryView({
    super.key,
    required this.supplierId,
    required this.repository,
    required this.canWrite,
    this.onRecheckAccess,
  });
  final String supplierId;
  final SupplierDeliveryRepository repository;
  final bool canWrite;
  final VoidCallback? onRecheckAccess;

  @override
  State<SupplierDeliveryView> createState() => _SupplierDeliveryViewState();
}

class _SupplierDeliveryViewState extends State<SupplierDeliveryView> {
  List<SupplierCoverage> coverage = const [];
  List<SupplierCity> cities = const [];
  String? error;
  bool loading = true;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(SupplierDeliveryView old) {
    super.didUpdateWidget(old);
    if (widget.supplierId != old.supplierId ||
        widget.canWrite != old.canWrite ||
        widget.repository != old.repository) {
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
      coverage = const [];
      cities = const [];
    });
    try {
      final result = await Future.wait<Object>([
        widget.repository.coverage(widget.supplierId),
        widget.repository.cities(),
      ]);
      if (!mounted || ticket != generation) return;
      setState(() {
        coverage = result[0] as List<SupplierCoverage>;
        cities = result[1] as List<SupplierCity>;
        loading = false;
      });
    } catch (e) {
      if (!mounted || ticket != generation) return;
      setState(() {
        loading = false;
        error = switch (e) {
          SupplierV21Exception(problem: SupplierV21Problem.authentication) =>
            'Your Clerk session expired.',
          SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
          SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
            'Supplier access changed. Recheck your membership.',
          _ => 'Delivery coverage could not be verified. Old data is hidden.',
        };
      });
    }
  }

  Future<void> mutate(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) await refresh();
    } catch (e) {
      if (!mounted) return;
      final message = switch (e) {
        SupplierV21Exception(problem: SupplierV21Problem.network) =>
          'Network outcome is uncertain. Refresh coverage before retrying.',
        SupplierV21Exception(problem: SupplierV21Problem.conflict) =>
          'Area settings changed. Refresh and try again.',
        SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
        SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
          'Your supplier permission changed. Recheck access.',
        FormatException() => 'Check exact rupee amounts and selected area.',
        _ => 'Settings were not confirmed. Refresh before trying again.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      await refresh();
    }
  }

  Future<void> chooseArea() async {
    if (!widget.canWrite || cities.isEmpty) return;
    String cityId = cities.first.id;
    String? selected;
    Future<List<SupplierArea>> future = widget.repository.areas(cityId);
    final minimum = TextEditingController(text: '0');
    var saving = false;
    String? note;
    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (sheet) => StatefulBuilder(
          builder: (sheet, change) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.viewInsetsOf(sheet).bottom + 24),
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Configure delivery area',
                    style: Theme.of(sheet).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                    'Only cities and PIN areas approved by BuildTo admins appear.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: cityId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'City'),
                  items: cities
                      .map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('${c.name} • ${c.stateCode}'),
                          ))
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          change(() {
                            cityId = value;
                            selected = null;
                            future = widget.repository.areas(cityId);
                          });
                        },
                ),
                const SizedBox(height: 14),
                FutureBuilder<List<SupplierArea>>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('Could not verify active areas.');
                    }
                    if (!snapshot.hasData)
                      return const LinearProgressIndicator();
                    final areas = snapshot.data!;
                    if (areas.isEmpty) {
                      return const Text(
                          'No active BuildTo areas in this city.');
                    }
                    return DropdownButtonFormField<String>(
                      key: ValueKey(cityId),
                      initialValue: selected,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Approved area'),
                      items: areas
                          .map((area) => DropdownMenuItem(
                                value: area.id,
                                child: Text(
                                    '${area.name} • ${area.pins.length} PINs',
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: saving
                          ? null
                          : (value) => change(() => selected = value),
                    );
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: minimum,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Minimum order amount (₹)',
                    helperText: 'Exact rupees, at most two decimal places',
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 12),
                  Text(note!,
                      style: const TextStyle(color: BuildToPalette.danger)),
                ],
                const SizedBox(height: 18),
                BuildToPrimaryButton(
                  label: 'Enable coverage',
                  busy: saving,
                  onPressed: selected == null
                      ? null
                      : () async {
                          change(() {
                            saving = true;
                            note = null;
                          });
                          try {
                            await widget.repository.setCoverage(
                              supplierId: widget.supplierId,
                              areaId: selected!,
                              active: true,
                              minimumPaise:
                                  deliveryRupeesToPaise(minimum.text.trim()),
                            );
                            if (sheet.mounted) Navigator.pop(sheet, true);
                          } catch (_) {
                            if (sheet.mounted)
                              change(() {
                                note =
                                    'Cannot confirm coverage. Close and refresh before retrying.';
                                saving = false;
                              });
                          }
                        },
                ),
              ],
            )),
          ),
        ),
      );
      if (saved == true && mounted) await refresh();
    } finally {
      minimum.dispose();
    }
  }

  Future<void> editMinimum(SupplierCoverage item) async {
    final controller = TextEditingController(
      text: catalogRupeesFromPaise(item.minimumPaise),
    );
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Minimum order amount'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Minimum (₹)'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Save minimum')),
          ],
        ),
      );
      if (confirmed != true) return;
      await mutate(() => widget.repository.setCoverage(
          supplierId: widget.supplierId,
          areaId: item.areaId,
          active: item.active,
          minimumPaise: deliveryRupeesToPaise(controller.text.trim())));
    } finally {
      controller.dispose();
    }
  }

  Future<void> toggle(SupplierCoverage item) async {
    final next = !item.active;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(next ? 'Enable area?' : 'Disable area?'),
        content: Text(next
            ? 'Enable supplier coverage in ${item.areaName}?'
            : 'Stop offering new deliveries to ${item.areaName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(next ? 'Enable' : 'Disable')),
        ],
      ),
    );
    if (confirmed != true) return;
    await mutate(() => widget.repository.setCoverage(
        supplierId: widget.supplierId,
        areaId: item.areaId,
        active: next,
        minimumPaise: item.minimumPaise));
  }

  Future<void> flatRate(SupplierCoverage item) async {
    if (!item.active) return;
    final current = item.rates.isEmpty ? null : item.rates.single;
    final base = TextEditingController(
        text:
            current == null ? '0' : catalogRupeesFromPaise(current.basePaise));
    final handling = TextEditingController(
        text: current == null
            ? '0'
            : catalogRupeesFromPaise(current.handlingPaise));
    final freeAbove = TextEditingController(
        text: current?.freeAbovePaise == null
            ? ''
            : catalogRupeesFromPaise(current!.freeAbovePaise!));
    bool saving = false;
    String? note;
    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (sheet) => StatefulBuilder(
          builder: (sheet, change) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.viewInsetsOf(sheet).bottom + 24),
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Flat delivery fee',
                    style: Theme.of(sheet).textTheme.headlineSmall),
                Text(item.areaName,
                    style: Theme.of(sheet).textTheme.bodyMedium),
                const SizedBox(height: 12),
                const Text(
                    'Freight is revalidated at checkout. Distance or weight pricing is not available here.'),
                const SizedBox(height: 14),
                TextField(
                    controller: base,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Base freight (₹)')),
                const SizedBox(height: 12),
                TextField(
                    controller: handling,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Handling fee (₹)')),
                const SizedBox(height: 12),
                TextField(
                    controller: freeAbove,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Free delivery above (₹), optional')),
                if (note != null)
                  Text(note!,
                      style: const TextStyle(color: BuildToPalette.danger)),
                const SizedBox(height: 18),
                BuildToPrimaryButton(
                  label: 'Save flat freight',
                  busy: saving,
                  onPressed: () async {
                    change(() {
                      saving = true;
                      note = null;
                    });
                    try {
                      await widget.repository.configureFlatRate(
                        supplierId: widget.supplierId,
                        areaId: item.areaId,
                        baseFeePaise: deliveryRupeesToPaise(base.text.trim()),
                        handlingFeePaise:
                            deliveryRupeesToPaise(handling.text.trim()),
                        freeAbovePaise: freeAbove.text.trim().isEmpty
                            ? null
                            : deliveryRupeesToPaise(freeAbove.text.trim()),
                      );
                      if (sheet.mounted) Navigator.pop(sheet, true);
                    } catch (_) {
                      if (sheet.mounted)
                        change(() {
                          note =
                              'Cannot confirm the rate. Close and refresh before retrying.';
                          saving = false;
                        });
                    }
                  },
                ),
              ],
            )),
          ),
        ),
      );
      if (saved == true && mounted) await refresh();
    } finally {
      base.dispose();
      handling.dispose();
      freeAbove.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView(padding: const EdgeInsets.all(20), children: const [
        BuildToSkeleton(height: 150),
        SizedBox(height: 15),
        BuildToSkeleton(),
        SizedBox(height: 15),
        BuildToSkeleton(),
      ]);
    }
    if (error != null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        BuildToStatePanel(
            title: 'Delivery settings unavailable',
            message: error!,
            actionLabel: 'Retry',
            onAction: () => unawaited(refresh())),
        if (widget.onRecheckAccess != null)
          OutlinedButton(
              onPressed: widget.onRecheckAccess,
              child: const Text('Recheck supplier access')),
      ]);
    }
    final activeCount = coverage.where((a) => a.active).length;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        key: const Key('supplier-delivery-loaded'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          Row(children: [
            Expanded(
                child: Text('Delivery coverage',
                    style: Theme.of(context).textTheme.headlineMedium)),
            IconButton(
                tooltip: 'Refresh delivery coverage',
                onPressed: () => unawaited(refresh()),
                icon: const Icon(Icons.refresh_rounded)),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: BuildToPalette.navy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BUILDTO • LOCAL DELIVERY',
                    style: TextStyle(
                        color: BuildToPalette.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                    '${activeCount == 100 ? '100+' : activeCount} active areas',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Text(
                    'Serviceability and the final freight charge are verified during checkout.',
                    style: TextStyle(color: Color(0xFFDDECF9))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (widget.canWrite)
            BuildToPrimaryButton(
              label: 'Add approved delivery area',
              icon: Icons.add_location_alt_outlined,
              onPressed: cities.isEmpty ? null : () => unawaited(chooseArea()),
            ),
          const SizedBox(height: 22),
          const BuildToSectionHeading(
            title: 'Configured service areas',
            subtitle: 'Admin-controlled PIN coverage and supplier flat rates.',
          ),
          const SizedBox(height: 12),
          if (coverage.isEmpty)
            const BuildToStatePanel(
              title: 'No delivery areas configured',
              message:
                  'Choose an active admin-approved city and PIN area to get started.',
              icon: Icons.location_off_outlined,
            ),
          ...coverage.map((item) => BuildToCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.local_shipping_outlined,
                          color: BuildToPalette.navy),
                      const SizedBox(width: 9),
                      Expanded(
                          child: Text(item.areaName,
                              style: Theme.of(context).textTheme.titleMedium)),
                      BuildToStatusChip(
                        label: item.active ? 'Serving' : 'Paused',
                        status: item.active
                            ? BuildToStatus.success
                            : BuildToStatus.warning,
                      ),
                    ]),
                    const SizedBox(height: 9),
                    Text('Minimum order: ${deliveryMoney(item.minimumPaise)}'),
                    if (item.rates.isEmpty)
                      const Text('Flat freight not yet configured.')
                    else ...[
                      Text(
                          'Base delivery: ${deliveryMoney(item.rates.single.basePaise)}'),
                      Text(
                          'Handling: ${deliveryMoney(item.rates.single.handlingPaise)}'),
                      if (item.rates.single.freeAbovePaise != null)
                        Text(
                            'Free above ${deliveryMoney(item.rates.single.freeAbovePaise!)}'),
                    ],
                    if (widget.canWrite) ...[
                      const Divider(),
                      Wrap(spacing: 8, runSpacing: 5, children: [
                        TextButton(
                            onPressed: () => unawaited(toggle(item)),
                            child: Text(
                                item.active ? 'Pause area' : 'Enable area')),
                        TextButton(
                            onPressed: () => unawaited(editMinimum(item)),
                            child: const Text('Minimum')),
                        OutlinedButton(
                          onPressed: item.active
                              ? () => unawaited(flatRate(item))
                              : null,
                          child: const Text('Flat delivery fee'),
                        ),
                      ]),
                    ],
                  ],
                ),
              )),
          if (coverage.length == 100)
            const Text('Showing up to 100 supplier delivery areas.'),
        ],
      ),
    );
  }
}
