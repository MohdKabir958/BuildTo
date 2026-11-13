import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'customer_api.dart';
import 'customer_design.dart';
import 'customer_orders.dart';
import 'customer_workspace.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key, this.embedded = false, this.onBrowse});
  final bool embedded;
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    final session = CustomerScope.of(context);
    final body = SignedIn(
      child: RemotePage<Data>(
        title: embedded ? null : 'Your cart',
        load: session.api.cart,
        builder: (cart, reload) => _CartContents(
          cart: cart,
          reload: reload,
          embedded: embedded,
          onBrowse: onBrowse,
        ),
      ),
    );
    return embedded ? body : Scaffold(body: SafeArea(child: body));
  }
}

class _CartContents extends StatefulWidget {
  const _CartContents({
    required this.cart,
    required this.reload,
    required this.embedded,
    required this.onBrowse,
  });
  final Data cart;
  final VoidCallback reload;
  final bool embedded;
  final VoidCallback? onBrowse;

  @override
  State<_CartContents> createState() => _CartContentsState();
}

class _CartContentsState extends State<_CartContents> {
  Data? updated;
  String? pending;
  String? error;

  Data get cart => updated ?? widget.cart;

  @override
  void didUpdateWidget(covariant _CartContents oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.cart['version'] as int) >= (cart['version'] as int)) {
      updated = null;
    }
  }

  Future<void> change(Data item, {String? quantity}) async {
    if (pending != null) return;
    final id = field(item, 'listingId');
    final api = CustomerScope.of(context).api;
    final version = cart['version'] as int;
    setState(() {
      pending = id;
      error = null;
    });
    try {
      final result = quantity == null
          ? await api.removeLine(id, version)
          : await api.setLine(id, quantity, version);
      if (mounted) setState(() => updated = result);
    } on CustomerProblem catch (problem) {
      if (!mounted) return;
      setState(() => error = problem.message);
      if (problem.code == 'CART_VERSION_CONFLICT') widget.reload();
    } catch (_) {
      if (mounted)
        setState(() => error = 'Couldn’t update your cart. Try again.');
    } finally {
      if (mounted) setState(() => pending = null);
    }
  }

  Future<void> edit(Data item) async {
    final quantity = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _QuantitySheet(item),
    );
    if (mounted &&
        quantity != null &&
        scaled(quantity, 3) != scaled(field(item, 'quantity'), 3)) {
      await change(item, quantity: quantity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = CustomerScope.of(context);
    final items = rows(cart);
    final groups = <String, List<Data>>{};
    for (final item in items) {
      (groups[field(item, 'supplierId')] ??= []).add(item);
    }
    final subtotal = items.fold<BigInt>(
        BigInt.zero, (sum, item) => sum + estimatedLinePaise(item));
    final canCheckout =
        pending == null && items.every((item) => item['available'] == true);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (widget.embedded)
                Text('Your cart',
                    style: Theme.of(context).textTheme.headlineLarge),
              if (items.isNotEmpty) ...[
                Text(
                    '${items.length} ${items.length == 1 ? 'item' : 'items'} · '
                    '${groups.length} ${groups.length == 1 ? 'supplier' : 'suppliers'}',
                    style: const TextStyle(color: muted)),
                const SizedBox(height: 16),
                Panel(
                  color: const Color(0xFFEAF2EE),
                  padding: 14,
                  child: Row(
                    children: [
                      const Icon(Icons.local_shipping_outlined, color: green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                            session.address == null
                                ? 'Choose a delivery address at checkout'
                                : 'Deliver to ${field(session.address!, 'label')}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        )),
                  ),
                ),
              if (items.isEmpty)
                EmptyState(
                  'Your cart is empty',
                  'Browse materials to get started.',
                  icon: Icons.shopping_bag_outlined,
                  action: OutlinedButton(
                    onPressed: widget.onBrowse ??
                        () => Navigator.of(context).maybePop(),
                    child: const Text('Browse materials'),
                  ),
                ),
              for (final group in groups.values)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Panel(
                    padding: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.storefront_outlined,
                                color: green, size: 19),
                            const SizedBox(width: 9),
                            Expanded(
                                child: Text(
                                    field(group.first, 'supplierName',
                                        'Supplier'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800))),
                          ],
                        ),
                        for (final item in group) ...[
                          const Divider(height: 22, color: line),
                          _CartItem(
                            item: item,
                            enabled: pending == null,
                            saving: pending == field(item, 'listingId'),
                            onQuantity: (quantity) =>
                                change(item, quantity: quantity),
                            onEdit: () => edit(item),
                            onRemove: () => change(item),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (items.isNotEmpty)
          Material(
            color: Colors.white,
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AmountRow('Materials subtotal', subtotal, total: true),
                  const Text('Delivery and taxes are calculated at checkout.',
                      style: TextStyle(color: muted, fontSize: 11)),
                  const SizedBox(height: 10),
                  ActionButton(
                    'Review checkout',
                    canCheckout
                        ? () async {
                            await Navigator.of(context)
                                .push(MaterialPageRoute<void>(
                              builder: (_) => CheckoutPage(
                                  cartVersion: cart['version'] as int),
                            ));
                            if (mounted) widget.reload();
                          }
                        : null,
                    icon: Icons.arrow_forward_rounded,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CartItem extends StatelessWidget {
  const _CartItem(
      {required this.item,
      required this.enabled,
      required this.saving,
      required this.onQuantity,
      required this.onEdit,
      required this.onRemove});
  final Data item;
  final bool enabled, saving;
  final ValueChanged<String> onQuantity;
  final VoidCallback onEdit, onRemove;

  @override
  Widget build(BuildContext context) {
    final quantity = field(item, 'quantity');
    final unit = field(item, 'unitCode').toLowerCase();
    final available = item['available'] == true;
    String? next(int direction) {
      final minimum = item['minOrderQty'];
      final step = item['stepQty'];
      if (minimum == null || step == null) return null;
      final value = quantityStep(quantity, '$minimum', '$step',
          item['maxOrderQty']?.toString(), direction);
      return scaled(value, 3) == scaled(quantity, 3) ? null : value;
    }

    final less = next(-1), more = next(1);
    final uri =
        CustomerScope.of(context).api.imageUri(item['imageUrl']?.toString());
    const fallback = Icon(Icons.inventory_2_outlined, color: muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                  color: paper, borderRadius: BorderRadius.circular(12)),
              child: uri == null
                  ? fallback
                  : Image.network(
                      uri.toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => fallback,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field(item, 'displayName'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${price(item['unitPrice'])} / $unit',
                    style: const TextStyle(color: muted, fontSize: 12)),
                if (!available)
                  Text('Currently unavailable',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ],
            )),
            IconButton(
              tooltip: 'Remove item',
              onPressed: enabled ? onRemove : null,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                  color: paper, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Decrease quantity',
                    onPressed: enabled && available && less != null
                        ? () => onQuantity(less)
                        : null,
                    icon: const Icon(Icons.remove_rounded, size: 18),
                  ),
                  Flexible(
                    child: TextButton(
                      onPressed: enabled && available ? onEdit : null,
                      child: Text('$quantity $unit',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Increase quantity',
                    onPressed: enabled && available && more != null
                        ? () => onQuantity(more)
                        : null,
                    icon: const Icon(Icons.add_rounded, size: 18),
                  ),
                ],
              ),
            ),
            if (saving)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Text(money(estimatedLinePaise(item)),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
      ],
    );
  }
}

class _QuantitySheet extends StatefulWidget {
  const _QuantitySheet(this.item);
  final Data item;

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  final form = GlobalKey<FormState>();
  late final controller =
      TextEditingController(text: field(widget.item, 'quantity'));

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final minimum = item['minOrderQty']?.toString();
    final step = item['stepQty']?.toString();
    final maximum = item['maxOrderQty']?.toString();
    final unit = field(item, 'unitCode').toLowerCase();
    void submit() {
      if (!form.currentState!.validate()) return;
      Navigator.pop(context, decimal(scaled(controller.text.trim(), 3), 3));
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            22, 0, 22, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
          key: form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Update quantity',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(field(item, 'displayName'),
                  style: const TextStyle(color: muted)),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                    label: const RequiredLabel('Quantity'),
                    suffixText: unit,
                    errorMaxLines: 3),
                onFieldSubmitted: (_) => submit(),
                validator: (value) {
                  try {
                    final amount = scaled(value?.trim() ?? '', 3);
                    if (amount <= BigInt.zero)
                      return 'Enter a quantity greater than zero.';
                    if (minimum != null && amount < scaled(minimum, 3)) {
                      return 'Minimum order is $minimum $unit.';
                    }
                    if (maximum != null && amount > scaled(maximum, 3)) {
                      return 'Maximum order is $maximum $unit.';
                    }
                    if (minimum != null &&
                        step != null &&
                        (amount - scaled(minimum, 3)) % scaled(step, 3) !=
                            BigInt.zero) {
                      return 'Start at $minimum and add $step $unit at a time.';
                    }
                    return null;
                  } on FormatException catch (problem) {
                    return problem.message;
                  }
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: submit, child: const Text('Save quantity')),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> ask(
  BuildContext context,
  String title,
  String hint, {
  String initial = '',
  bool numeric = false,
  int min = 1,
}) async {
  final control = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: control,
        autofocus: true,
        maxLines: numeric ? 1 : 3,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(label: RequiredLabel(hint)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (control.text.trim().length < min) {
              notice(c, 'Enter at least $min characters.');
              return;
            }
            Navigator.pop(c, control.text.trim());
          },
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return result;
}

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({
    super.key,
    required this.cartVersion,
    this.rfqId,
    this.acceptedQuoteId,
  });
  final int cartVersion;
  final String? rfqId, acceptedQuoteId;
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  Data? quote;
  String? addressId, siteId;
  String previewKey = requestKey(), placeKey = requestKey();
  final promo = TextEditingController();
  @override
  void dispose() {
    promo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = CustomerScope.of(context);
    return RemotePage<List<Data>>(
      title: 'Checkout',
      load: s.api.addresses,
      builder: (addresses, reload) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            'Review your order',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 10),
          const Text(
            'Confirm your delivery site and review your order.',
            style: TextStyle(color: muted),
          ),
          const Section('Delivery address'),
          if (addresses.isEmpty)
            const EmptyState(
              'Add your delivery address',
              'Choose an active delivery city and save your site details.',
            ),
          RadioGroup<String>(
              groupValue: addressId,
              onChanged: (value) => setState(() {
                    addressId = value;
                    siteId = null;
                    quote = null;
                    previewKey = requestKey();
                  }),
              child: Column(
                  children: addresses
                      .map((a) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Panel(
                              padding: 4,
                              child: RadioListTile<String>(
                                  value: field(a, 'id'),
                                  title: Text(field(a, 'label'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                      '${a['recipientName']}\n${a['line1']}, ${a['locality']}\n${a['cityName']} ${a['postalCode']}',
                                      style: const TextStyle(
                                          fontSize: 12, color: muted)),
                                  isThreeLine: true))))
                      .toList())),
          ActionButton(
            'Add address',
            () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddressEditor()),
              );
              reload();
            },
            icon: Icons.add,
            tonal: true,
          ),
          if (addressId != null && widget.rfqId == null) ...[
            const SizedBox(height: 12),
            ActionButton(
              siteId == null
                  ? 'Link a construction site (optional)'
                  : 'Construction site linked',
              () async {
                final sites = rows(await s.api.call('/api/v2/me/sites'));
                if (!context.mounted) return;
                final selected = await showDialog<Data>(
                  context: context,
                  builder: (c) => SimpleDialog(
                    title: const Text('Choose a construction site'),
                    children: [
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(c, <String, dynamic>{}),
                        child: const Text('No linked site'),
                      ),
                      ...sites
                          .where(
                            (a) =>
                                a['active'] == true &&
                                a['addressId'] == addressId,
                          )
                          .map(
                            (a) => SimpleDialogOption(
                              onPressed: () => Navigator.pop(c, a),
                              child: Text(field(a, 'name')),
                            ),
                          ),
                      if (sites.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Create sites from your profile.'),
                        ),
                    ],
                  ),
                );
                if (selected != null) {
                  setState(() {
                    siteId = selected['id']?.toString();
                    quote = null;
                    previewKey = requestKey();
                  });
                }
              },
              tonal: true,
            ),
          ],
          if (widget.rfqId == null) ...[
            const Section('Promotion'),
            TextField(
              controller: promo,
              onChanged: (_) => setState(() {
                quote = null;
                previewKey = requestKey();
              }),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Promotion code (optional)',
                prefixIcon: Icon(Icons.local_offer_outlined),
              ),
            ),
            const SizedBox(height: 20),
            ActionButton(
              'Check delivery & final price',
              addressId == null
                  ? null
                  : () async {
                      final requestedKey = previewKey;
                      final Data result;
                      try {
                        result = await s.api.preview(
                          addressId!,
                          widget.cartVersion,
                          requestedKey,
                          site: siteId,
                          promotion: promo.text.trim(),
                        );
                      } on CustomerProblem catch (problem) {
                        if (!mounted || requestedKey != previewKey) return;
                        if (!kReleaseMode &&
                            s.api.origin.origin ==
                                'https://buildto-v21-staging.onrender.com' &&
                            problem.code ==
                                'COMMISSION_POLICY_NOT_CONFIGURED') {
                          await Navigator.of(context)
                              .push(MaterialPageRoute<void>(
                            builder: (_) => const _DemoOrderPage(),
                          ));
                          return;
                        }
                        rethrow;
                      }
                      if (mounted && requestedKey == previewKey) {
                        setState(() {
                          if (quote?['id'] != result['id']) {
                            placeKey = requestKey();
                          }
                          quote = result;
                        });
                      }
                    },
            ),
            if (quote != null) ...[
              const Section('Order summary'),
              Panel(child: totals(quote!)),
              const SizedBox(height: 10),
              Text(
                'Price quote valid until ${DateTime.tryParse(field(quote!, 'expiresAt'))?.toLocal().toString().substring(0, 16) ?? field(quote!, 'expiresAt')}. Payment is selected after placing your order.',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 20),
              ActionButton(
                'Place order · ${money(quote!['totalPaise'])}',
                () async {
                  final expiry = DateTime.tryParse(field(quote!, 'expiresAt'));
                  if (expiry == null || !expiry.isAfter(DateTime.now())) {
                    setState(() => quote = null);
                    throw const CustomerProblem(
                      'Your price quote expired. Check the latest price.',
                    );
                  }
                  final order = await s.api.place(
                    field(quote!, 'id'),
                    placeKey,
                  );
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => OrderPage(field(order, 'id')),
                      ),
                    );
                  }
                },
                icon: Icons.lock_outline_rounded,
              ),
            ],
          ] else ...[
            const Section('Accepted supplier quotation'),
            const Panel(
              child: Text(
                'The accepted quotation fixes the material and freight amounts. Delivery eligibility is rechecked for this address.',
              ),
            ),
            const SizedBox(height: 20),
            ActionButton(
              'Place quoted order',
              addressId == null
                  ? null
                  : () async {
                      final order = object(
                        await s.api.call(
                          '/api/v2/rfqs/${widget.rfqId}/quotes/${widget.acceptedQuoteId}/order',
                          method: 'POST',
                          key: placeKey,
                          body: {
                            'addressId': addressId,
                            'clientRequestId': placeKey,
                          },
                        ),
                      );
                      if (context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => OrderPage(field(order, 'id')),
                          ),
                        );
                      }
                    },
            ),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _DemoOrderPage extends StatelessWidget {
  const _DemoOrderPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Order preview')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const CircleAvatar(
                        radius: 38,
                        backgroundColor: Color(0xFFEAF2EE),
                        child:
                            Icon(Icons.check_rounded, color: green, size: 40),
                      ),
                      const SizedBox(height: 20),
                      const Text('STAGING PREVIEW',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: green, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('Order placed',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 10),
                      const Text(
                        'This is a demo confirmation. Your cart is still saved. No real order or payment was created.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
