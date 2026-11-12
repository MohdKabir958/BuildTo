import 'dart:async';
import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_catalog_details.dart';
import 'supplier_catalog_editor.dart';
import 'supplier_catalog_models.dart';
import 'supplier_catalog_repository.dart';

/// Own supplier listing view. No admin approval controls or legacy API calls.
class SupplierCatalogView extends StatefulWidget {
  const SupplierCatalogView(
      {super.key,
      required this.supplierId,
      required this.repository,
      required this.canWrite,
      this.onRecheckAccess});
  final String supplierId;
  final SupplierCatalogRepository repository;
  final bool canWrite;
  final VoidCallback? onRecheckAccess;
  @override
  State<SupplierCatalogView> createState() => _SupplierCatalogViewState();
}

class _SupplierCatalogViewState extends State<SupplierCatalogView> {
  final search = TextEditingController();
  List<CatalogListing> listings = const [];
  CatalogMasters? masters;
  CatalogListingStatus? filter;
  bool loading = true;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(SupplierCatalogView old) {
    super.didUpdateWidget(old);
    if (old.supplierId != widget.supplierId ||
        old.canWrite != widget.canWrite ||
        !identical(old.repository, widget.repository)) {
      search.clear();
      filter = null;
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    generation++;
    search.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final current = ++generation;
    setState(() {
      loading = true;
      error = null;
      masters = null;
      listings = const [];
    });
    try {
      final result = await Future.wait<Object>([
        widget.repository.listings(widget.supplierId),
        if (widget.canWrite) widget.repository.masters(),
      ]);
      if (!mounted || current != generation) return;
      setState(() {
        listings = result[0] as List<CatalogListing>;
        masters = widget.canWrite ? result[1] as CatalogMasters : null;
        loading = false;
      });
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(() {
        error = switch (e) {
          SupplierV21Exception(problem: SupplierV21Problem.authentication) =>
            'Your Clerk session expired. Verify your account again.',
          SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
          SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
            'Supplier permission changed. Recheck your active membership.',
          SupplierV21Exception(problem: SupplierV21Problem.network) =>
            'Cannot reach Splyzo. Previous listing data has been hidden.',
          _ =>
            'Unable to verify the current catalog. No stale data is displayed.',
        };
        loading = false;
      });
    }
  }

  bool get bounded => listings.length == 100;
  int count(CatalogListingStatus state) =>
      listings.where((listing) => listing.status == state).length;

  Future<void> create() async {
    if (!widget.canWrite || masters == null) return;
    final result = await showModalBottomSheet<CatalogListing>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: SupplierListingEditor(
            repository: widget.repository,
            supplierId: widget.supplierId,
            masters: masters!),
      ),
    );
    if (mounted && result != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Customers can see this product now.'),
      ));
      await refresh();
    }
  }

  Future<void> details(CatalogListing listing) async {
    final result = await showModalBottomSheet<CatalogListing>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: SupplierListingDetails(
            supplierId: widget.supplierId,
            listing: listing,
            repository: widget.repository,
            masters: masters ?? const CatalogMasters([], []),
            canWrite: widget.canWrite),
      ),
    );
    if (mounted && result != null) await refresh();
  }

  BuildToStatus stateChip(CatalogListingStatus state) => switch (state) {
        CatalogListingStatus.approved => BuildToStatus.success,
        CatalogListingStatus.pending => BuildToStatus.pending,
        CatalogListingStatus.rejected => BuildToStatus.warning,
        CatalogListingStatus.suspended => BuildToStatus.danger,
        _ => BuildToStatus.neutral,
      };
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView(
          key: const Key('catalog-loading'),
          padding: const EdgeInsets.all(20),
          children: const [
            BuildToSkeleton(height: 150),
            SizedBox(height: 15),
            BuildToSkeleton(height: 140),
            SizedBox(height: 12),
            BuildToSkeleton(height: 140)
          ]);
    }
    if (error != null) {
      return ListView(
          key: const Key('catalog-error'),
          padding: const EdgeInsets.all(20),
          children: [
            BuildToStatePanel(
                title: 'Catalog unavailable',
                message: error!,
                icon: Icons.shield_outlined,
                actionLabel: 'Retry supplier catalog',
                onAction: () => unawaited(refresh())),
            if (widget.onRecheckAccess != null)
              OutlinedButton.icon(
                  onPressed: widget.onRecheckAccess,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Recheck supplier permissions')),
          ]);
    }
    final keyword = search.text.trim().toUpperCase();
    final shown = listings
        .where((x) =>
            (filter == null || x.status == filter) &&
            (keyword.isEmpty ||
                x.sku.contains(keyword) ||
                (x.productName ?? '').toUpperCase().contains(keyword)))
        .toList();
    return RefreshIndicator(
      color: BuildToPalette.navy,
      onRefresh: refresh,
      child: ListView(
        key: const Key('supplier-catalog-loaded'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Material catalog',
                      style: Theme.of(context).textTheme.headlineMedium),
                  Text('Your products and the prices customers pay.',
                      style: Theme.of(context).textTheme.bodyMedium),
                ])),
            IconButton(
                tooltip: 'Refresh supplier listings',
                onPressed: () => unawaited(refresh()),
                icon: const Icon(Icons.refresh_rounded)),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              gradient: const LinearGradient(colors: [
                BuildToPalette.navyDeep,
                BuildToPalette.navy,
                Color(0xFF0A588E),
              ]),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.inventory_2_outlined, color: BuildToPalette.orange),
                SizedBox(width: 8),
                Expanded(
                    child: Text('SPLYZO • PRODUCT WORKSPACE',
                        style: TextStyle(
                            color: Colors.white,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                            fontSize: 11))),
              ]),
              const SizedBox(height: 15),
              Text(
                  bounded
                      ? '${listings.length}+ listings'
                      : '${listings.length} listings',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 26)),
              const SizedBox(height: 8),
              const Text('Products • Prices • Availability',
                  style: TextStyle(color: Color(0xFFE5F2FE), fontSize: 13)),
              if (widget.canWrite) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                    key: const Key('catalog-create'),
                    style: FilledButton.styleFrom(
                        backgroundColor: BuildToPalette.orange,
                        foregroundColor: BuildToPalette.navyDeep),
                    onPressed: () => unawaited(create()),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Add a product')),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: _CatalogCount(
                    'Approved',
                    count(CatalogListingStatus.approved),
                    bounded,
                    Icons.verified_outlined,
                    BuildToPalette.success)),
            const SizedBox(width: 8),
            Expanded(
                child: _CatalogCount(
                    'In review',
                    count(CatalogListingStatus.pending),
                    bounded,
                    Icons.hourglass_top_rounded,
                    BuildToPalette.blue)),
            const SizedBox(width: 8),
            Expanded(
                child: _CatalogCount(
                    'Drafts',
                    count(CatalogListingStatus.draft),
                    bounded,
                    Icons.edit_note_rounded,
                    BuildToPalette.orange)),
          ]),
          const SizedBox(height: 19),
          TextField(
              key: const Key('catalog-sku-search'),
              controller: search,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'Search your products',
                  hintText: 'e.g. cement, steel, sand'),
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                          label: const Text('All'),
                          selected: filter == null,
                          onSelected: (_) => setState(() => filter = null))),
                  for (final state in CatalogListingStatus.values)
                    Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                            label: Text(state.label),
                            selected: filter == state,
                            onSelected: (_) => setState(() => filter = state))),
                ],
              )),
          const SizedBox(height: 16),
          if (shown.isEmpty)
            BuildToStatePanel(
                title: listings.isEmpty
                    ? 'No supplier listings yet'
                    : 'No matching listings',
                message: listings.isEmpty
                    ? 'Add a product you keep in your warehouse.'
                    : 'Try another product name.',
                icon: Icons.category_outlined)
          else
            for (final listing in shown) ...[
              BuildToCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                    key: Key('catalog-listing-${listing.id}'),
                    contentPadding: const EdgeInsets.all(14),
                    leading: listing.imageUrl == null
                        ? const CircleAvatar(
                            backgroundColor: BuildToPalette.sky,
                            foregroundColor: BuildToPalette.navy,
                            child: Icon(Icons.construction_rounded))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              SupplierV21Config.origin
                                  .resolve(listing.imageUrl!)
                                  .toString(),
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.image_not_supported_outlined),
                            ),
                          ),
                    title: Text(listing.productName ?? listing.sku,
                        style: Theme.of(context).textTheme.titleMedium),
                    subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 5),
                          Text(
                              '${catalogInr(listing.unitPrice)} / ${listing.unitCode}'),
                          const SizedBox(height: 7),
                          BuildToStatusChip(
                              label: listing.status.label,
                              status: stateChip(listing.status)),
                        ]),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => unawaited(details(listing))),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 15),
          Text(
              bounded
                  ? 'At most 100 recent listings. Counts are lower bounds, not lifetime totals.'
                  : 'Listings become public after approval.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _CatalogCount extends StatelessWidget {
  const _CatalogCount(
      this.label, this.value, this.bounded, this.icon, this.accent);
  final String label;
  final int value;
  final bool bounded;
  final IconData icon;
  final Color accent;
  @override
  Widget build(BuildContext context) => BuildToCard(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(height: 10),
          Text(bounded ? '$value+' : '$value',
              style: Theme.of(context).textTheme.headlineSmall),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}
