import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import '../api/supplier_v21_api.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import 'supplier_catalog_models.dart';
import 'supplier_catalog_repository.dart';

const fallbackSellingUnits = [
  CatalogUnit('BAG', 'Bag'),
  CatalogUnit('KG', 'Kg'),
  CatalogUnit('PIECE', 'Piece'),
  CatalogUnit('TONNE', 'Tonne'),
  CatalogUnit('BOX', 'Box'),
  CatalogUnit('BUNDLE', 'Bundle'),
  CatalogUnit('METER', 'Meter'),
  CatalogUnit('SQM', 'Square meter'),
  CatalogUnit('CUM', 'Cubic meter'),
  CatalogUnit('LITRE', 'Litre'),
];

class _CatalogChoice {
  const _CatalogChoice(this.value, this.label);
  final String value;
  final String label;
}

/// Supplier product form. A verified supplier publishes immediately.
/// Product and selling unit are chosen only when adding a product.
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
          ? ''
          : catalogRupeesFromPaise(widget.original!.mrpPaise!));
  late final taxBps = TextEditingController(
      text: catalogPercentFromBps(widget.original?.taxRateBps ?? 1800));
  late final productName = TextEditingController();
  String? categoryId, unit, error, uploadedImageUrl;
  Uint8List? photoBytes;
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
    for (final c in [
      sku,
      productName,
      pack,
      minimum,
      step,
      maximum,
      price,
      mrp,
      taxBps
    ]) {
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
      return 'Enter the price, such as 315 or 315.50.';
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
    TextInputType? type,
    bool optional = false,
    TextStyle? style,
    String? hint,
    String? helper,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(optional ? '$label (optional)' : label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: BuildToPalette.navy,
                    )),
            if (helper != null) ...[
              const SizedBox(height: 5),
              Text(helper,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF526782), height: 1.4)),
            ],
            const SizedBox(height: 9),
            TextFormField(
              key: ValueKey('catalog-field-$label'),
              controller: controller,
              style: style,
              keyboardType: type ??
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              scrollPadding: const EdgeInsets.only(bottom: 140),
              autocorrect: false,
              decoration: InputDecoration(
                hintText: hint,
                errorMaxLines: 3,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              validator: validator,
            ),
          ],
        ),
      );

  Future<String?> _showSearchPicker({
    required String title,
    required List<_CatalogChoice> items,
    required String? current,
  }) async {
    var searchTerm = '';
    return showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, rebuild) {
            final term = searchTerm.trim().toLowerCase();
            final shown = items
                .where((item) => item.label.toLowerCase().contains(term))
                .toList();
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: SizedBox(
                height: min(
                  530,
                  max(240, MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom - 80),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 14),
                          TextField(
                            key: const Key('catalog-option-search'),
                            autofocus: true,
                            onChanged: (text) => rebuild(() => searchTerm = text),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              hintText: 'Search options',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? const Center(
                              child: Text('No matching options found.'))
                          : ListView.separated(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: shown.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final option = shown[index];
                                return ListTile(
                                  key: Key('catalog-option-${option.value}'),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 22, vertical: 3),
                                  title: Text(option.label),
                                  trailing: option.value == current
                                      ? const Icon(Icons.check_circle_rounded,
                                          color: BuildToPalette.navy)
                                      : const Icon(Icons.chevron_right_rounded),
                                  onTap: () => Navigator.of(sheetContext)
                                      .pop(option.value),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
  }

  Widget _selectionField({
    required String label,
    required String placeholder,
    required String? current,
    required List<_CatalogChoice> choices,
    required String fieldKey,
    required ValueChanged<String> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: FormField<String>(
          key: Key(fieldKey),
          initialValue: current,
          validator: (value) =>
              value == null ? 'Choose a $label to continue.' : null,
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: BuildToPalette.navy,
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 9),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy || choices.isEmpty
                      ? null
                      : () async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          final picked = await _showSearchPicker(
                            title: 'Choose $label',
                            items: choices,
                            current: field.value,
                          );
                          if (!mounted || picked == null) return;
                          field.didChange(picked);
                          setState(() {
                            onChanged(picked);
                            error = null;
                          });
                        },
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 17),
                    side: BorderSide(
                        color: field.hasError
                            ? BuildToPalette.danger
                            : const Color(0xFFCFD8E5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          choices
                              .where((choice) => choice.value == field.value)
                              .map((choice) => choice.label)
                              .firstOrNull ??
                              placeholder,
                          style: TextStyle(
                              color: field.value == null
                                  ? const Color(0xFF64748B)
                                  : BuildToPalette.navy,
                              fontWeight: field.value == null
                                  ? FontWeight.w400
                                  : FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded),
                    ],
                  ),
                ),
              ),
              if (field.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(field.errorText!,
                      style: const TextStyle(color: BuildToPalette.danger)),
                ),
            ],
          ),
        ),
      );

  List<CatalogUnit> get sellingUnits => widget.masters.units.isEmpty
      ? fallbackSellingUnits
      : widget.masters.units;

  static const _photoTooBig = 'Choose a photo of 8 MB or smaller.';
  static const _photoTypeHint =
      'Use a JPEG, PNG, WebP, GIF, BMP, HEIC, or AVIF photo.';

  String? _photoType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'image/gif';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4d) {
      return 'image/bmp';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
      final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
      if (brand == 'avif' || brand == 'avis') return 'image/avif';
      if (const {'heic', 'heix', 'hevc', 'hevx', 'heim', 'heis'}
          .contains(brand)) {
        return 'image/heic';
      }
      if (const {'heif', 'mif1', 'msf1'}.contains(brand)) return 'image/heif';
    }
    return null;
  }

  Future<void> pickPhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 8 * 1024 * 1024) {
      setState(() => error = _photoTooBig);
      return;
    }
    if (_photoType(bytes) == null) {
      setState(() => error = _photoTypeHint);
      return;
    }
    setState(() {
      photoBytes = bytes;
      uploadedImageUrl = null;
      error = null;
    });
  }

  CatalogListingInput _input() => CatalogListingInput(
        productId: widget.original?.productId ?? '',
        sku: sku.text.trim(),
        productName: widget.original == null ? productName.text : null,
        categoryId: categoryId,
        imageUrl: uploadedImageUrl,
        unitCode: unit ?? '',
        packSize: pack.text.trim(),
        minOrderQty: minimum.text.trim(),
        stepQty: step.text.trim(),
        maxOrderQty: maximum.text.trim().isEmpty ? null : maximum.text.trim(),
        unitPrice: price.text.trim(),
        mrpPaise:
            mrp.text.trim().isEmpty ? null : catalogPaiseFromRupees(mrp.text),
        taxRateBps: catalogTaxBasisPoints(taxBps.text.trim()),
        taxInclusive: inclusive,
      );

  Future<void> save() async {
    if (busy || uncertain) return;
    if (form.currentState?.validate() != true) {
      setState(() => error = 'Complete the highlighted fields before saving.');
      return;
    }
    if (widget.original == null && productName.text.trim().isEmpty) {
      setState(() => error = 'Enter the product you have in your warehouse.');
      return;
    }
    if (widget.original == null && categoryId == null) {
      setState(() => error = 'Choose a category, such as cement or steel.');
      return;
    }
    if (unit == null) {
      setState(() => error = 'Choose how customers buy this product.');
      return;
    }
    CatalogListingInput input;
    try {
      if (photoBytes != null && uploadedImageUrl == null) {
        final contentType = _photoType(photoBytes!);
        if (contentType == null) {
          setState(() => error = _photoTypeHint);
          return;
        }
        setState(() => busy = true);
        uploadedImageUrl = await widget.repository.uploadProductPhoto(
          supplierId: widget.supplierId,
          bytes: photoBytes!,
          contentType: contentType,
        );
      }
      input = _input();
      input.validate();
    } on SupplierV21Exception catch (e) {
      setState(() {
        busy = false;
        error = e.code == 'PAYLOAD_TOO_LARGE'
            ? _photoTooBig
            : e.code == 'UNSUPPORTED_IMAGE'
                ? _photoTypeHint
                : 'The photo could not be saved. Try another photo.';
      });
      return;
    } catch (_) {
      setState(() {
        busy = false;
        error = 'Check the price, GST, and order quantities.';
      });
      return;
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
          _ => e.code == 'PAYLOAD_TOO_LARGE'
              ? _photoTooBig
              : e.code == 'UNSUPPORTED_IMAGE'
                  ? _photoTypeHint
                  : 'Could not save. Check all values and retry after review.',
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Form(
            key: form,
            child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: 36),
                children: [
              BuildToSectionHeading(
                title: widget.original == null
                    ? 'Add a product'
                    : 'Update this product',
                subtitle: 'Customers can see it as soon as you save.',
              ),
              const SizedBox(height: 14),
              if (photoBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    photoBytes!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      height: 180,
                      child: Center(child: Text('Photo selected')),
                    ),
                  ),
                )
              else if (widget.original?.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    SupplierV21Config.origin
                        .resolve(widget.original!.imageUrl!)
                        .toString(),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => unawaited(pickPhoto()),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                      photoBytes == null && widget.original?.imageUrl == null
                          ? 'Add a photo'
                          : 'Change photo'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Optional · Up to 8 MB. Add a clear photo of the product.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 12),
              if (widget.original == null) ...[
                _field(
                  'Product name',
                  productName,
                  type: TextInputType.text,
                  hint: 'e.g. UltraTech OPC Cement 50 kg',
                  helper: 'Enter the name customers should see.',
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Enter the product name.';
                    if (text.length > 240) return 'Use a shorter name.';
                    return null;
                  },
                ),
                _selectionField(
                  fieldKey: 'catalog-category-selector',
                  label: 'Product category',
                  placeholder: 'Select a category',
                  current: categoryId,
                  choices: widget.masters.categories
                      .map((category) =>
                          _CatalogChoice(category.id, category.name))
                      .toList(),
                  onChanged: (value) => categoryId = value,
                ),
                _selectionField(
                  fieldKey: 'catalog-unit-selector',
                  label: 'How do customers buy this?',
                  placeholder: 'Select a selling unit (bag, kg, piece...)',
                  current: unit,
                  choices: sellingUnits
                      .map((sellingUnit) => _CatalogChoice(
                          sellingUnit.code, sellingUnit.name))
                      .toList(),
                  onChanged: (value) => unit = value,
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Sold as ${widget.original!.unitCode}. '
                    'To use another unit, add it as a new product.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 8),
              _field(
                'Selling price (₹)',
                price,
                hint: 'e.g. 350',
                helper: 'Price for one selected selling unit.',
                validator: _price,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text('GST', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final rate in const ['0', '5', '12', '18', '28'])
                    ChoiceChip(
                      label: Text('$rate%'),
                      selected: taxBps.text.trim() == rate,
                      onSelected: busy
                          ? null
                          : (selected) {
                              if (!selected) return;
                              setState(() => taxBps.text = rate);
                            },
                    ),
                ],
              ),
              if (!const ['0', '5', '12', '18', '28']
                  .contains(taxBps.text.trim()))
                _field('GST %', taxBps, validator: (value) {
                  try {
                    catalogTaxBasisPoints((value ?? '').trim());
                    return null;
                  } on FormatException {
                    return 'Enter a GST rate from 0 to 100.';
                  }
                }),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('This price already includes GST'),
                value: inclusive,
                onChanged:
                    busy ? null : (value) => setState(() => inclusive = value),
              ),
              ExpansionTile(
                key: const Key('catalog-advanced-options'),
                tilePadding: EdgeInsets.zero,
                title: const Text('Advanced order settings'),
                subtitle: const Text(
                    'Optional. Default values work for most products.'),
                children: [
                  _field(
                    'Units per pack',
                    pack,
                    hint: '1',
                    helper: 'Number of selected selling units in one pack. '
                        'Usually 1 for bags, pieces or rolls.',
                    validator: _quantity,
                  ),
                  _field(
                    'Minimum order quantity',
                    minimum,
                    hint: '1',
                    helper: 'Smallest quantity a customer may order. '
                        'Example: 5 bags.',
                    validator: _quantity,
                  ),
                  _field(
                    'Order quantity increments',
                    step,
                    hint: '1',
                    helper: 'How many units to add each time. '
                        'Example: 5 means 5, 10, 15...',
                    validator: _quantity,
                  ),
                  _field(
                    'Maximum order quantity',
                    maximum,
                    optional: true,
                    hint: 'No limit',
                    helper: 'Leave blank when there is no per-order limit.',
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? null
                        : _quantity(value),
                  ),
                  _field('Printed MRP (₹)', mrp,
                      optional: true,
                      hint: 'e.g. 399',
                      helper: 'Maximum retail price shown on packaging.',
                      validator: (value) {
                    if ((value ?? '').trim().isEmpty) return null;
                    try {
                      catalogPaiseFromRupees(value!.trim());
                      return null;
                    } on FormatException {
                      return 'Enter rupees, such as 399 or 399.50.';
                    }
                  }),
                ],
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
                    ? 'Show to customers'
                    : 'Save changes',
                icon: Icons.check_rounded,
                busy: busy,
                onPressed: busy || uncertain ? null : () => unawaited(save()),
              ),
            ]),
          ),
        ),
      );
}
