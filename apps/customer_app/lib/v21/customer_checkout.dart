import 'package:flutter/material.dart';
import 'customer_api.dart';
import 'customer_design.dart';
import 'customer_orders.dart';
import 'customer_workspace.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    final s = CustomerScope.of(context);
    final body = SignedIn(
      child: RemotePage<Data>(
        title: embedded ? null : 'Your cart',
        load: s.api.cart,
        builder: (cart, reload) {
          final items = rows(cart);
          final groups = <String, List<Data>>{};
          for (final item in items) {
            groups.putIfAbsent(field(item, 'supplierId'), () => []).add(item);
          }
          return ListView(
            padding: const EdgeInsets.all(22),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (embedded)
                Text(
                  'Your cart',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              if (items.isEmpty)
                EmptyState(
                  'Room for your next build',
                  'Choose materials and a supplier offer to get started.',
                  icon: Icons.shopping_bag_outlined,
                  action: OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Browse materials'),
                  ),
                ),
              ...groups.values.map(
                (group) => Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.storefront_outlined,
                              size: 19,
                              color: green,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                field(group.first, 'supplierName'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 30),
                        ...group.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: paper,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.inventory_2_outlined,
                                        color: muted,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            field(item, 'displayName'),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            '${price(item['unitPrice'])} / ${item['unitCode']}',
                                            style: const TextStyle(
                                              color: muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (item['available'] != true)
                                            const Text(
                                              'Currently unavailable',
                                              style: TextStyle(
                                                color: Colors.red,
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove item',
                                      onPressed: () async {
                                        try {
                                          await s.api.removeLine(
                                            field(item, 'listingId'),
                                            cart['version'] as int,
                                          );
                                          reload();
                                        } catch (e) {
                                          if (context.mounted) {
                                            notice(
                                              context,
                                              e is CustomerProblem
                                                  ? e.message
                                                  : 'Unable to update cart.',
                                            );
                                          }
                                          reload();
                                        }
                                      },
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Text(
                                      '${item['quantity']} ${item['unitCode']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () async {
                                        final value = await ask(
                                          context,
                                          'Update quantity',
                                          'Quantity in ${item['unitCode']}',
                                          initial: field(item, 'quantity'),
                                          numeric: true,
                                        );
                                        if (value == null) return;
                                        try {
                                          if (scaled(value, 3) <= BigInt.zero) {
                                            throw const FormatException(
                                              'Quantity must be positive.',
                                            );
                                          }
                                          await s.api.setLine(
                                            field(item, 'listingId'),
                                            value,
                                            cart['version'] as int,
                                          );
                                          reload();
                                        } catch (e) {
                                          if (context.mounted) {
                                            notice(
                                              context,
                                              e is CustomerProblem
                                                  ? e.message
                                                  : e is FormatException
                                                      ? e.message
                                                      : 'Unable to update quantity.',
                                            );
                                          }
                                          reload();
                                        }
                                      },
                                      child: const Text('Edit quantity'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 20),
                Panel(
                    child: Column(children: [
                  AmountRow(
                      'Estimated materials',
                      items.fold<BigInt>(BigInt.zero,
                          (sum, item) => sum + estimatedLinePaise(item))),
                  const Text(
                      'Before delivery, tax adjustments and quantity pricing. Your final checkout quote confirms the total.',
                      style: TextStyle(fontSize: 11, color: muted))
                ])),
                const SizedBox(height: 22),
                const Panel(
                  child: Row(
                    children: [
                      Icon(Icons.local_shipping_outlined, color: green),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Final stock, tax and delivery charges are checked for your selected site at checkout.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ActionButton(
                  'Review checkout',
                  items.any((i) => i['available'] != true)
                      ? null
                      : () async => push(
                            context,
                            CheckoutPage(cartVersion: cart['version'] as int),
                          ),
                  icon: Icons.arrow_forward_rounded,
                ),
              ],
            ],
          );
        },
      ),
    );
    return embedded ? body : Scaffold(body: SafeArea(child: body));
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
        decoration: InputDecoration(labelText: hint),
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
            'One step closer\nto your next build.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 10),
          const Text(
            'Confirm your delivery site and review your order.',
            style: TextStyle(color: muted),
          ),
          const Section('01  Delivery address'),
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
            const Section('02  Promotion'),
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
                      final result = await s.api.preview(
                        addressId!,
                        widget.cartVersion,
                        requestedKey,
                        site: siteId,
                        promotion: promo.text.trim(),
                      );
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
              const Section('03  Order summary'),
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
            const Section('02  Accepted supplier quotation'),
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
