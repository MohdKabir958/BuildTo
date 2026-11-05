import 'dart:async';
import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_catalog_editor.dart';
import 'supplier_catalog_models.dart';
import 'supplier_catalog_repository.dart';

/// Read-only listing details plus explicitly permissioned actions. Supplier
/// cannot approve its own listing: only admin catalog review changes approval.
class SupplierListingDetails extends StatefulWidget {
  const SupplierListingDetails(
      {super.key,
      required this.supplierId,
      required this.listing,
      required this.repository,
      required this.masters,
      required this.canWrite});
  final String supplierId;
  final CatalogListing listing;
  final SupplierCatalogRepository repository;
  final CatalogMasters masters;
  final bool canWrite;
  @override
  State<SupplierListingDetails> createState() => _SupplierListingDetailsState();
}

class _SupplierListingDetailsState extends State<SupplierListingDetails> {
  bool busy = false;
  String? error;

  Future<void> edit() async {
    final changed = await showModalBottomSheet<CatalogListing>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .92,
        child: SupplierListingEditor(
          repository: widget.repository,
          supplierId: widget.supplierId,
          masters: widget.masters,
          original: widget.listing,
        ),
      ),
    );
    if (mounted && changed != null) Navigator.pop(context, changed);
  }

  Future<void> prices() async {
    final changed = await showModalBottomSheet<CatalogListing>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .85,
        child: SupplierTierEditor(
            supplierId: widget.supplierId,
            listing: widget.listing,
            repository: widget.repository),
      ),
    );
    if (mounted && changed != null) Navigator.pop(context, changed);
  }

  Future<void> submit() async {
    if (busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit for BuildTo review?'),
        content: const Text('This sends your listing to the admin moderation '
            'queue. Submitting does not approve or publish it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit draft')),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final changed = await widget.repository
          .submit(supplierId: widget.supplierId, listing: widget.listing);
      if (!mounted) return;
      Navigator.pop(context, changed);
    } on SupplierV21Exception catch (e) {
      if (!mounted) return;
      setState(() => error = switch (e.problem) {
            SupplierV21Problem.conflict =>
              'A newer version exists. Close and refresh the listing before submitting.',
            SupplierV21Problem.forbidden ||
            SupplierV21Problem.notFound =>
              'Supplier permission changed. Recheck access before continuing.',
            SupplierV21Problem.network =>
              'Submission outcome is uncertain. Close and refresh to check status.',
            _ =>
              'Cannot submit this listing. Verify the product and try again.',
          });
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not verify submission response.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  BuildToStatus get chip => switch (widget.listing.status) {
        CatalogListingStatus.approved => BuildToStatus.success,
        CatalogListingStatus.pending => BuildToStatus.pending,
        CatalogListingStatus.rejected => BuildToStatus.warning,
        CatalogListingStatus.suspended => BuildToStatus.danger,
        _ => BuildToStatus.neutral,
      };

  Widget item(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleMedium)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    return SafeArea(
        child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        const BuildToSectionHeading(
          title: 'Listing details',
          subtitle: 'Own construction material · backend-verified scope.',
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: BuildToPalette.navy,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.inventory_2_rounded,
                  color: BuildToPalette.orange, size: 26),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(listing.sku,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 14),
            Text('${catalogInr(listing.unitPrice)} / ${listing.unitCode}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 11),
            BuildToStatusChip(label: listing.status.label, status: chip),
          ]),
        ),
        const SizedBox(height: 15),
        BuildToCard(
            child: Column(children: [
          item('Version', listing.version.toString()),
          item('Pack size', listing.packSize),
          item('Minimum order', listing.minOrderQty),
          item('Quantity step', listing.stepQty),
          item('Maximum order', listing.maxOrderQty ?? 'Not set'),
          item('GST rate', '${listing.taxRateBps} bps'),
          item('Tax includes', listing.taxInclusive ? 'Yes' : 'No'),
          item(
              'Current published',
              listing.active && listing.status == CatalogListingStatus.approved
                  ? 'Yes'
                  : 'No'),
        ])),
        const SizedBox(height: 17),
        const BuildToSectionHeading(
            title: 'Volume price tiers',
            subtitle: 'Lower unit prices at increasing minimum quantities.'),
        const SizedBox(height: 10),
        if (listing.tiers.isEmpty)
          const BuildToStatePanel(
            title: 'No volume tiers configured',
            message: 'Only the base unit price is set for this listing.',
            icon: Icons.view_list_outlined,
          )
        else
          BuildToCard(
              child: Column(children: [
            for (final tier in listing.tiers)
              item('From ${tier.minQty} ${listing.unitCode}',
                  catalogInr(tier.pricePerUnit)),
          ])),
        const SizedBox(height: 16),
        if (listing.status == CatalogListingStatus.pending)
          const BuildToStatePanel(
              title: 'Awaiting independent review',
              message: 'This listing is not published. A BuildTo catalog '
                  'administrator must approve the submitted version.',
              icon: Icons.fact_check_outlined),
        if (listing.status == CatalogListingStatus.approved)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                  'Editing or replacing price tiers will unpublish '
                  'this version until an admin reviews the changes.',
                  style: TextStyle(color: BuildToPalette.warning))),
        if (widget.canWrite) ...[
          const SizedBox(height: 16),
          if (listing.status.canEdit)
            BuildToPrimaryButton(
                label: 'Edit listing',
                icon: Icons.edit_outlined,
                onPressed: busy ? null : () => unawaited(edit())),
          if (listing.status.canPrice) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : () => unawaited(prices()),
              icon: const Icon(Icons.price_change_outlined),
              label: const Text('Manage quantity pricing'),
            ),
          ],
          if (listing.status.canSubmit) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy ? null : () => unawaited(submit()),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Submit for admin review'),
            ),
          ],
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!,
              key: const Key('catalog-detail-error'),
              style: const TextStyle(color: BuildToPalette.danger)),
        ],
        if (busy) const Center(child: CircularProgressIndicator()),
      ],
    ));
  }
}

class _TierFields {
  _TierFields({String minimum = '', String price = ''})
      : min = TextEditingController(text: minimum),
        cost = TextEditingController(text: price);
  final TextEditingController min, cost;
  void dispose() {
    min.dispose();
    cost.dispose();
  }
}

class SupplierTierEditor extends StatefulWidget {
  const SupplierTierEditor(
      {super.key,
      required this.supplierId,
      required this.listing,
      required this.repository});
  final String supplierId;
  final CatalogListing listing;
  final SupplierCatalogRepository repository;
  @override
  State<SupplierTierEditor> createState() => _SupplierTierEditorState();
}

class _SupplierTierEditorState extends State<SupplierTierEditor> {
  late final List<_TierFields> rows = [
    for (final tier in widget.listing.tiers)
      _TierFields(minimum: tier.minQty, price: tier.pricePerUnit),
  ];
  bool busy = false, uncertain = false;
  String? error;

  @override
  void dispose() {
    for (final row in rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || uncertain) return;
    List<CatalogTier> tiers;
    try {
      tiers = rows
          .map((r) => CatalogTier(r.min.text.trim(), r.cost.text.trim()))
          .toList(growable: false);
      validateCatalogTiers(tiers,
          minOrderQty: widget.listing.minOrderQty,
          unitPrice: widget.listing.unitPrice);
    } catch (_) {
      setState(() => error = 'Check exact quantity and price values: '
          'minimums must rise and unit prices cannot increase.');
      return;
    }
    if (widget.listing.status == CatalogListingStatus.approved) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace approved pricing?'),
          content: const Text('This unpublishes the listing until admin '
              'approval of the new pricing version.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace prices')),
          ],
        ),
      );
      if (!mounted || ok != true) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final changed = await widget.repository.replaceTiers(
          supplierId: widget.supplierId, listing: widget.listing, tiers: tiers);
      if (mounted) Navigator.pop(context, changed);
    } on SupplierV21Exception catch (e) {
      if (!mounted) return;
      setState(() {
        uncertain = e.problem == SupplierV21Problem.network;
        error = switch (e.problem) {
          SupplierV21Problem.conflict =>
            'A newer listing version exists. Close and refresh before editing pricing.',
          SupplierV21Problem.network =>
            'Pricing outcome is uncertain. Close and refresh before another change.',
          SupplierV21Problem.forbidden ||
          SupplierV21Problem.notFound =>
            'Supplier permissions changed. Close and recheck access.',
          _ => 'Pricing was not confirmed. Review the tier rules.',
        };
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to save price tiers.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
          child: ListView(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        children: [
          const BuildToSectionHeading(
              title: 'Quantity pricing',
              subtitle: 'Offer precise volume discounts without rounding.'),
          const SizedBox(height: 14),
          BuildToCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    'Base: ${catalogInr(widget.listing.unitPrice)} / '
                    '${widget.listing.unitCode}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 7),
                Text('Minimum order: ${widget.listing.minOrderQty}',
                    style: Theme.of(context).textTheme.bodySmall),
              ])),
          const SizedBox(height: 14),
          for (var index = 0; index < rows.length; index++)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BuildToCard(
                    child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Text('Tier ${index + 1}',
                            style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(
                      tooltip: 'Remove tier ${index + 1}',
                      onPressed: busy
                          ? null
                          : () => setState(() {
                                final row = rows.removeAt(index);
                                row.dispose();
                              }),
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: BuildToPalette.danger),
                    ),
                  ]),
                  TextField(
                    key: ValueKey('catalog-tier-min-$index'),
                    controller: rows[index].min,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Minimum quantity'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: ValueKey('catalog-tier-price-$index'),
                    controller: rows[index].cost,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Unit price (₹)'),
                  ),
                ]))),
          OutlinedButton.icon(
            onPressed: busy || rows.length >= 12
                ? null
                : () => setState(() => rows.add(_TierFields())),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add quantity tier'),
          ),
          const SizedBox(height: 8),
          Text(
              'Up to 12 tiers. Each minimum must be greater than the previous '
              'quantity and at least the listing MOQ; prices cannot rise.',
              style: Theme.of(context).textTheme.bodySmall),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!,
                key: const Key('catalog-tier-error'),
                style: const TextStyle(color: BuildToPalette.danger)),
          ],
          const SizedBox(height: 20),
          BuildToPrimaryButton(
              label:
                  rows.isEmpty ? 'Remove all tiers' : 'Save quantity pricing',
              busy: busy,
              icon: Icons.save_outlined,
              onPressed: busy || uncertain ? null : () => unawaited(save())),
        ],
      ));
}
