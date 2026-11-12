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
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: TextFormField(
          key: ValueKey('catalog-field-$label'),
          controller: controller,
          style: style,
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
      setState(() => error = 'Check the price, GST, and order quantities.');
      return;
    }
    if (widget.original == null && productName.text.trim().isEmpty) {
      setState(() =>
          error = 'Enter the product you have in your warehouse.');
      return;
    }
    if (widget.original == null &&
        widget.masters.categories.isNotEmpty &&
        categoryId == null) {
      setState(() => error = 'Choose a category, such as cement or steel.');
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
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.viewInsetsOf(context).bottom + 18),
          child: Form(
            key: form,
            child: ListView(shrinkWrap: true, children: [
              BuildToSectionHeading(
                title: widget.original == null
                    ? 'Add a product'
                    : 'Update this product',
                subtitle: 'Customers can see it as soon as you save.',
              ),
              const SizedBox(height: 18),
              if (widget.original == null) ...[
                _field(
                  'What do you have in the warehouse?',
                  productName,
                  type: TextInputType.text,
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'Enter the product name.';
                    if (text.length > 240) return 'Use a shorter name.';
                    return null;
                  },
                ),
                if (widget.masters.categories.isNotEmpty) ...[
                  Text('Category',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final category in widget.masters.categories)
                        ChoiceChip(
                          label: Text(category.name),
                          selected: categoryId == category.id,
                          onSelected: busy
                              ? null
                              : (_) => setState(() {
                                    categoryId = category.id;
                                    error = null;
                                  }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Text('How do you sell it?',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                FormField<String>(
                  key: const Key('catalog-unit'),
                  validator: (_) =>
                      unit == null ? 'Choose bag, kg, piece, or another unit.' : null,
                  builder: (state) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final sellingUnit in sellingUnits)
                            ChoiceChip(
                              label: Text(sellingUnit.name),
                              selected: unit == sellingUnit.code,
                              onSelected: busy
                                  ? null
                                  : (_) => setState(() {
                                        unit = sellingUnit.code;
                                        error = null;
                                      }),
                            ),
                        ],
                      ),
                      if (state.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(state.errorText!,
                              style: const TextStyle(
                                  color: BuildToPalette.danger)),
                        ),
                    ],
                  ),
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
                  label: Text(photoBytes == null &&
                          widget.original?.imageUrl == null
                      ? 'Add a photo'
                      : 'Change photo'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'JPEG, PNG, WebP, GIF, BMP, HEIC, or AVIF, up to 8 MB. The product can still be saved without a photo.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _field(
                'Your price (₹)',
                price,
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
              if (!const ['0', '5', '12', '18', '28'].contains(taxBps.text.trim()))
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
                tilePadding: EdgeInsets.zero,
                title: const Text('More options'),
                subtitle: const Text(
                    'Pack size and order limits. Leave these as 1 for most products.'),
                children: [
                  _field('Pack size', pack, validator: _quantity),
                  _field('Smallest order', minimum, validator: _quantity),
                  _field('Order step', step, validator: _quantity),
                  _field('Largest order', maximum,
                      optional: true,
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? null
                          : _quantity(value)),
                  _field('Printed price / MRP (₹)', mrp,
                      optional: true, validator: (value) {
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
