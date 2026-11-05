import 'dart:async';
import 'dart:math';
import '../api/supplier_v21_api.dart';
import 'package:flutter/material.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_catalog_models.dart';
import 'supplier_catalog_repository.dart';

/// Search and paginate the public construction-material masters, never invent
/// new master products from a seller's free-text SKU.
class CatalogProductPicker extends StatefulWidget {
  const CatalogProductPicker(
      {super.key, required this.repository, required this.categories});
  final SupplierCatalogRepository repository;
  final List<CatalogCategory> categories;
  @override
  State<CatalogProductPicker> createState() => _CatalogProductPickerState();
}

class _CatalogProductPickerState extends State<CatalogProductPicker> {
  final search = TextEditingController();
  final products = <CatalogProduct>[];
  String? categoryId, nextCursor, message;
  bool loading = false;
  int ticket = 0;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    ticket++;
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (more && (loading || nextCursor == null)) return;
    final marker = ++ticket;
    setState(() {
      loading = true;
      message = null;
      if (!more) {
        products.clear();
        nextCursor = null;
      }
    });
    try {
      final result = await widget.repository.products(
        categoryId: categoryId,
        search: search.text,
        cursor: more ? nextCursor : null,
      );
      if (!mounted || marker != ticket) return;
      setState(() {
        final seen = products.map((p) => p.id).toSet();
        for (final product in result.items) {
          if (seen.add(product.id)) products.add(product);
        }
        nextCursor = result.nextCursor;
      });
    } catch (e) {
      if (!mounted || marker != ticket) return;
      setState(() => message =
          'Product search is unavailable. Check the filters and retry.');
    } finally {
      if (mounted && marker == ticket) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              18, 12, 18, MediaQuery.viewInsetsOf(context).bottom + 12),
          child: Column(children: [
            const BuildToSectionHeading(
              title: 'Choose construction material',
              subtitle:
                  'Products come from the approved BuildTo master catalog.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('catalog-product-search'),
              controller: search,
              textInputAction: TextInputAction.search,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'Search by material name',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Search products',
                  onPressed: () => unawaited(load()),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
              onSubmitted: (_) => unawaited(load()),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All categories'),
                    selected: categoryId == null,
                    onSelected: (_) {
                      setState(() => categoryId = null);
                      unawaited(load());
                    },
                  ),
                ),
                for (final category in widget.categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(category.name),
                      selected: categoryId == category.id,
                      onSelected: (_) {
                        setState(() => categoryId = category.id);
                        unawaited(load());
                      },
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            if (loading && products.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (message != null)
              Expanded(
                  child: Center(
                      child: BuildToStatePanel(
                title: 'Products unavailable',
                message: message!,
                actionLabel: 'Retry search',
                onAction: () => unawaited(load()),
              )))
            else if (products.isEmpty)
              const Expanded(
                  child: Center(
                      child: BuildToStatePanel(
                title: 'No matching materials',
                message: 'Try another search or an approved category.',
              )))
            else
              Expanded(
                  child: ListView.builder(
                key: const Key('catalog-product-results'),
                itemCount: products.length + (nextCursor == null ? 0 : 1),
                itemBuilder: (context, index) {
                  if (index == products.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: OutlinedButton.icon(
                        onPressed:
                            loading ? null : () => unawaited(load(more: true)),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('Load more materials'),
                      ),
                    );
                  }
                  final product = products[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: BuildToCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                        leading: const CircleAvatar(
                          backgroundColor: BuildToPalette.sky,
                          foregroundColor: BuildToPalette.navy,
                          child: Icon(Icons.construction_rounded),
                        ),
                        title: Text(product.name,
                            style: Theme.of(context).textTheme.titleMedium),
                        subtitle: Text(
                          [
                            product.categoryName,
                            product.brandName,
                            product.code
                          ].whereType<String>().join(' · '),
                          maxLines: 2,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: const Icon(Icons.add_circle_outline_rounded,
                            color: BuildToPalette.blue),
                        onTap: () => Navigator.pop(context, product),
                      ),
                    ),
                  );
                },
              )),
          ]),
        ),
      );
}

/// Draft/editor form is deliberately supplier-scoped. Immutable SKU/product
/// and unit identity are only chosen when creating a new listing.
class SupplierListingEditor extends StatefulWidget {
  const SupplierListingEditor(
      {super.key,
      required this.repository,
      required this.supplierId,
      required this.masters,
      this.original});
  final SupplierCatalogRepository repository;
  final String supplierId;
  final CatalogMasters masters;
  final CatalogListing? original;
  @override
  State<SupplierListingEditor> createState() => _SupplierListingEditorState();
}

class _SupplierListingEditorState extends State<SupplierListingEditor> {
  final form = GlobalKey<FormState>();
  late final sku = TextEditingController(text: widget.original?.sku ?? '');
  late final pack =
      TextEditingController(text: widget.original?.packSize ?? '1');
  late final minimum =
      TextEditingController(text: widget.original?.minOrderQty ?? '1');
  late final step =
      TextEditingController(text: widget.original?.stepQty ?? '1');
  late final maximum =
      TextEditingController(text: widget.original?.maxOrderQty ?? '');
  late final price =
      TextEditingController(text: widget.original?.unitPrice ?? '');
  late final mrp = TextEditingController(
      text: widget.original?.mrpPaise == null
          ? '' : catalogRupeesFromPaise(widget.original!.mrpPaise!));
  late final taxBps = TextEditingController(
      text: (widget.original?.taxRateBps ?? 1800).toString());
  CatalogProduct? product;
  String? unit, error;
  late bool inclusive = widget.original?.taxInclusive ?? true;
  bool busy = false, uncertain = false;
  // A single immutable key is retained for the entire create intent, including
  // uncertain timeouts; never replay with a fresh key.
  late final String intent = _uuidIntent();

  static String _uuidIntent() {
    // Unique per intent, from cryptographic random source; no network call.
    final bytes = List<int>.generate(16, (_) => 0);
    final secure = _secureRandom();
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = secure.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Random _secureRandom() => Random.secure();

  @override
  void initState() {
    super.initState();
    unit = widget.original?.unitCode;
  }

  @override
  void dispose() {
    for (final c in [sku, pack, minimum, step, maximum, price, mrp, taxBps]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _quantity(String? text) {
    try {
      catalogQty((text ?? '').trim());
      return null;
    } on FormatException {
      return 'Use a positive decimal (up to 3 places).';
    }
  }

  String? _price(String? text) {
    try {
      catalogPrice((text ?? '').trim());
      return null;
    } on FormatException {
      return 'Use a positive INR amount (up to 4 places).';
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
    TextInputType? type,
    bool optional = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: TextFormField(
          key: ValueKey('catalog-field-$label'),
          controller: controller,
          keyboardType:
              type ?? const TextInputType.numberWithOptions(decimal: true),
          autocorrect: false,
          decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: true,
            helperText: optional ? 'Optional' : null,
          ),
          validator: validator,
        ),
      );

  Future<void> chooseProduct() async {
    final selected = await showModalBottomSheet<CatalogProduct>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .85,
        child: CatalogProductPicker(
          repository: widget.repository,
          categories: widget.masters.categories,
        ),
      ),
    );
    if (mounted && selected != null) {
      setState(() {
        product = selected;
        error = null;
      });
    }
  }

  CatalogListingInput _input() => CatalogListingInput(
        productId: widget.original?.productId ?? product?.id ?? '',
        sku: sku.text.trim(),
        unitCode: unit ?? '',
        packSize: pack.text.trim(),
        minOrderQty: minimum.text.trim(),
        stepQty: step.text.trim(),
        maxOrderQty: maximum.text.trim().isEmpty ? null : maximum.text.trim(),
        unitPrice: price.text.trim(),
        mrpPaise: mrp.text.trim().isEmpty ? null : catalogPaiseFromRupees(mrp.text),
        taxRateBps: int.parse(taxBps.text.trim()),
        taxInclusive: inclusive,
      );

  Future<void> save() async {
    if (busy || uncertain || form.currentState?.validate() != true) return;
    if (widget.original == null && product == null) {
      setState(
          () => error = 'Choose a material from the approved product catalog.');
      return;
    }
    CatalogListingInput input;
    try {
      input = _input();
      input.validate();
    } catch (_) {
      setState(() =>
          error = 'Review SKU, quantity limits, tax rate and exact prices.');
      return;
    }
    if (widget.original?.status == CatalogListingStatus.approved) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Change an approved listing?'),
                content: const Text(
                    'Editing an approved listing removes it from the '
                    'published catalog until BuildTo admin reviews the update.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Continue editing')),
                ],
              ));
      if (!mounted || confirmed != true) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final listing = widget.original == null
          ? await widget.repository.create(
              supplierId: widget.supplierId,
              input: input,
              idempotencyKey: intent)
          : await widget.repository.update(
              supplierId: widget.supplierId,
              original: widget.original!,
              input: input);
      if (!mounted) return;
      Navigator.pop(context, listing);
    } on SupplierV21Exception catch (e) {
      if (!mounted) return;
      setState(() {
        uncertain = e.problem == SupplierV21Problem.network;
        error = switch (e.problem) {
          SupplierV21Problem.conflict =>
            'The listing changed. Close and refresh before editing again.',
          SupplierV21Problem.forbidden ||
          SupplierV21Problem.notFound =>
            'Your supplier access changed. Recheck permission before editing.',
          SupplierV21Problem.network => 'The save outcome is uncertain. '
              'Close and refresh before attempting again; never create a duplicate.',
          _ => 'Could not save. Check all values and retry after review.',
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Unable to validate this listing. Check the form values.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.viewInsetsOf(context).bottom + 18),
          child: Form(
            key: form,
            child: ListView(shrinkWrap: true, children: [
              BuildToSectionHeading(
                title: widget.original == null
                    ? 'Create supplier listing'
                    : 'Edit listing',
                subtitle: widget.original == null
                    ? 'Select a BuildTo material, then configure a draft.'
                    : 'Changes use optimistic version checks and admin moderation.',
              ),
              const SizedBox(height: 18),
              if (widget.original == null) ...[
                BuildToCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Material product',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Text(product?.name ?? 'No master product selected',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed:
                              busy ? null : () => unawaited(chooseProduct()),
                          icon: const Icon(Icons.search_rounded),
                          label: const Text('Browse approved materials'),
                        ),
                      ]),
                ),
                const SizedBox(height: 16),
                _field('Supplier SKU', sku, type: TextInputType.text,
                    validator: (v) {
                  try {
                    catalogSku(v ?? '');
                    return null;
                  } catch (_) {
                    return 'Use a valid uppercase code, max 100 characters.';
                  }
                }),
                DropdownButtonFormField<String>(
                  key: const Key('catalog-unit'),
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Selling unit'),
                  items: widget.masters.units
                      .map((u) => DropdownMenuItem(
                          value: u.code, child: Text('${u.name} (${u.code})')))
                      .toList(),
                  onChanged:
                      busy ? null : (value) => setState(() => unit = value),
                  validator: (value) =>
                      value == null ? 'Select a selling unit.' : null,
                ),
                const SizedBox(height: 15),
              ] else ...[
                BuildToCard(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.original!.sku,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                        'Selling unit: ${widget.original!.unitCode} · '
                        'Version ${widget.original!.version}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(
                        'SKU, product and unit cannot be changed. Create a new listing '
                        'to use a different identity.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                )),
                const SizedBox(height: 16),
              ],
              const BuildToSectionHeading(title: 'Pack size & ordering'),
              const SizedBox(height: 14),
              _field('Pack size', pack, validator: _quantity),
              _field('Minimum order quantity', minimum, validator: _quantity),
              _field('Quantity step', step, validator: _quantity),
              _field('Maximum order quantity', maximum,
                  optional: true,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? null : _quantity(v)),
              const SizedBox(height: 10),
              const BuildToSectionHeading(
                  title: 'Prices & tax',
                  subtitle: 'Precise INR values — not rounded or estimated.'),
              const SizedBox(height: 14),
              _field('Unit price (₹)', price, validator: _price),
              _field('MRP (₹)', mrp, optional: true, validator: (v) {
                if ((v ?? '').trim().isEmpty) return null;
                try {
                  catalogPaiseFromRupees(v!.trim());
                  return null;
                } on FormatException {
                  return 'Enter rupees up to 2 decimal places.';
                }
              }),
              _field('Tax rate (basis points)', taxBps, validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return n == null || n < 0 || n > 10000
                    ? 'Enter 0–10000 basis points (1800 = 18%).'
                    : null;
              }),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Price includes tax'),
                subtitle: const Text(
                    'Matches the tax-inclusive flag on this listing.'),
                value: inclusive,
                onChanged:
                    busy ? null : (value) => setState(() => inclusive = value),
              ),
              if (error != null) ...[
                const SizedBox(height: 6),
                Text(error!,
                    key: const Key('catalog-editor-error'),
                    style: const TextStyle(color: BuildToPalette.danger)),
              ],
              const SizedBox(height: 16),
              BuildToPrimaryButton(
                label: widget.original == null
                    ? 'Save draft listing'
                    : 'Save changes',
                icon: Icons.save_outlined,
                busy: busy,
                onPressed: busy || uncertain ? null : () => unawaited(save()),
              ),
              const SizedBox(height: 10),
              Text(
                  'A draft is not public. Submit it for independent admin review '
                  'after checking quantity tiers.',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}
