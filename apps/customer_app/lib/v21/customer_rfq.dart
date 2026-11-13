import 'package:flutter/material.dart';
import 'customer_api.dart';
import 'customer_design.dart';
import 'customer_catalog.dart';
import 'customer_checkout.dart';
import 'customer_orders.dart';

class RfqsPage extends StatelessWidget {
  const RfqsPage({super.key});
  @override
  Widget build(BuildContext c) {
    final s = CustomerScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk quotations')),
      body: SignedIn(
        child: RemotePage<List<Data>>(
          load: () async => rows(await s.api.call('/api/v2/rfqs')),
          builder: (list, reload) => ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Text(
                'Big plans.\nBetter sourcing.',
                style: Theme.of(c).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Compare material prices, freight and delivery terms from invited suppliers.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 22),
              ActionButton('Request a quotation', () async {
                await Navigator.push(
                  c,
                  MaterialPageRoute(builder: (_) => const NewRfqPage()),
                );
                reload();
              }, icon: Icons.add),
              const Section('Your requests'),
              if (list.isEmpty)
                const EmptyState(
                  'Your next project starts here',
                  'Create a material request and invite suppliers.',
                ),
              ...list.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    padding: 6,
                    child: ListTile(
                      title: Text(field(r, 'publicNumber')),
                      subtitle: Text(
                        '${rows(r['items']).length} materials · ${label(r['status'])}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => push(c, RfqDetailPage(field(r, 'id'))),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NewRfqPage extends StatefulWidget {
  const NewRfqPage({super.key, this.product});
  final Data? product;
  @override
  State<NewRfqPage> createState() => _NewRfqPageState();
}

class _NewRfqPageState extends State<NewRfqPage> {
  final lines = <Data>[];
  final suppliers = <String, String>{};
  final invited = <String>{};
  final notes = TextEditingController();
  final key = requestKey();
  String? addressId, createdId;
  Data? submitted;
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> addMaterial(Data product) async {
    final api = CustomerScope.of(context).api;
    final offers = await api.offers(field(product, 'id'));
    if (!mounted) return;
    if (offers.isEmpty) {
      throw const CustomerProblem(
        'No supplier offers are available to invite for this material yet.',
      );
    }
    final unit = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Choose a selling unit'),
        children: offers
            .map((o) => field(o, 'unitCode'))
            .toSet()
            .map(
              (u) => SimpleDialogOption(
                onPressed: () => Navigator.pop(c, u),
                child: Text(u),
              ),
            )
            .toList(),
      ),
    );
    if (unit == null || !mounted) return;
    final quantity = await ask(
      context,
      'Required quantity',
      'Quantity in $unit',
      initial: field(
        offers.firstWhere((o) => o['unitCode'] == unit),
        'minOrderQty',
        '1',
      ),
      numeric: true,
    );
    if (quantity == null) return;
    if (scaled(quantity, 3) <= BigInt.zero) {
      throw const CustomerProblem('Quantity must be positive.');
    }
    setState(() {
      lines.add({
        'productId': product['id'],
        'description': product['name'],
        'quantity': quantity,
        'unitCode': unit,
      });
      for (final o in offers.where((o) => o['unitCode'] == unit)) {
        suppliers[field(o, 'supplierId')] = field(
          o,
          'supplierName',
          'Approved supplier',
        );
      }
    });
  }

  @override
  Widget build(BuildContext c) {
    final s = CustomerScope.of(c);
    return Scaffold(
      appBar: AppBar(title: const Text('Request a quotation')),
      body: SignedIn(
        child: RemotePage<List<Data>>(
          load: s.api.addresses,
          builder: (addresses, reload) => ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Text(
                'Tell us what you’re building.',
                style: Theme.of(c).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Choose materials and a delivery site, then invite suppliers to quote.',
                style: TextStyle(color: muted),
              ),
              AbsorbPointer(
                absorbing: submitted != null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Section('Materials'),
                    ...lines.asMap().entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Panel(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${e.value['description']}\n${e.value['quantity']} ${e.value['unitCode']}',
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove material',
                                    onPressed: () =>
                                        setState(() => lines.removeAt(e.key)),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    if (lines.length < 30)
                      ActionButton(
                        'Add material',
                        () async {
                          final p = widget.product != null && lines.isEmpty
                              ? widget.product
                              : await Navigator.push<Data>(
                                  c,
                                  MaterialPageRoute(
                                    builder: (_) => const MaterialPicker(),
                                  ),
                                );
                          if (p != null) await addMaterial(p);
                        },
                        icon: Icons.add,
                        tonal: true,
                      ),
                    const Section('Delivery site'),
                    DropdownButtonFormField<String>(
                      initialValue: addressId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        label: RequiredLabel('Saved delivery address'),
                      ),
                      items: addresses
                          .map(
                            (a) => DropdownMenuItem(
                              value: field(a, 'id'),
                              child: Text(
                                '${a['label']} · ${a['postalCode']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => addressId = v),
                    ),
                    if (addresses.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Add a delivery address from your profile first.',
                        ),
                      ),
                    const Section('Invite suppliers'),
                    if (suppliers.isEmpty)
                      const Text(
                        'Supplier choices appear after adding a material.',
                        style: TextStyle(color: muted),
                      ),
                    ...suppliers.entries.map(
                      (e) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.value),
                        subtitle: Text(
                          'Reference ${e.key.substring(0, 8)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        value: invited.contains(e.key),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            invited.add(e.key);
                          } else {
                            invited.remove(e.key);
                          }
                        }),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: notes,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Material and delivery notes (optional)',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ActionButton(
                submitted == null
                    ? 'Send to suppliers'
                    : 'Finish sending request',
                () async {
                  if (submitted == null) {
                    if (lines.isEmpty || addressId == null || invited.isEmpty) {
                      throw const CustomerProblem(
                        'Add materials, select an address and invite suppliers.',
                      );
                    }
                    final a = addresses.firstWhere((a) => a['id'] == addressId);
                    setState(
                      () => submitted = {
                        'siteSnapshot': {
                          'city': a['cityName'],
                          'postalCode': a['postalCode'],
                          'siteNotes':
                              '${a['line1']}, ${a['locality']}'.substring(
                            0,
                            ('${a['line1']}, ${a['locality']}')
                                .length
                                .clamp(0, 300),
                          ),
                        },
                        'items': lines
                            .map((l) => Map<String, dynamic>.from(l))
                            .toList(),
                        if (notes.text.trim().isNotEmpty)
                          'notes': notes.text.trim(),
                      },
                    );
                  }
                  if (createdId == null) {
                    final r = object(
                      await s.api.call(
                        '/api/v2/rfqs',
                        method: 'POST',
                        key: key,
                        body: submitted,
                      ),
                    );
                    createdId = field(r, 'id');
                  }
                  final current = object(
                    await s.api.call('/api/v2/rfqs/$createdId'),
                  );
                  if (current['status'] == 'DRAFT') {
                    await s.api.call(
                      '/api/v2/rfqs/$createdId/open',
                      method: 'POST',
                      body: {},
                    );
                  }
                  for (final supplier in invited) {
                    await s.api.call(
                      '/api/v2/rfqs/$createdId/invitations/$supplier',
                      method: 'POST',
                      body: {},
                    );
                  }
                  if (c.mounted) {
                    Navigator.of(c).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => RfqDetailPage(createdId!),
                      ),
                    );
                  }
                },
                icon: Icons.send_outlined,
              ),
              if (submitted != null)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'This request is retained for safe retry after a connection interruption.',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 25),
            ],
          ),
        ),
      ),
    );
  }
}

class MaterialPicker extends StatefulWidget {
  const MaterialPicker({super.key});
  @override
  State<MaterialPicker> createState() => _MaterialPickerState();
}

class _MaterialPickerState extends State<MaterialPicker> {
  String search = '';
  String? cursor;
  final text = TextEditingController();
  final items = <Data>[];
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a material')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: text,
              onSubmitted: (v) => setState(() {
                search = v.trim();
                cursor = null;
                items.clear();
              }),
              decoration: const InputDecoration(
                labelText: 'Search materials',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: RemotePage<Data>(
              key: ValueKey(search),
              load: () async {
                final page = await api.products(search: search, cursor: cursor);
                for (final item in rows(page)) {
                  if (!items.any((x) => x['id'] == item['id'])) items.add(item);
                }
                return page;
              },
              builder: (page, reload) => ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  ...items.map(
                    (p) => ListTile(
                      leading: Icon(
                        materialIcon(field(p, 'name')),
                        color: accent,
                      ),
                      title: Text(field(p, 'name')),
                      subtitle: Text(field(object(p['category']), 'name')),
                      trailing: const Icon(Icons.add_circle_outline),
                      onTap: () => Navigator.pop(c, p),
                    ),
                  ),
                  if (items.isEmpty)
                    const EmptyState(
                      'No materials found',
                      'Try a different search.',
                    ),
                  if (page['nextCursor'] != null)
                    OutlinedButton(
                      onPressed: () {
                        cursor = field(page, 'nextCursor');
                        reload();
                      },
                      child: const Text('Load more'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RfqDetailPage extends StatelessWidget {
  const RfqDetailPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return RemotePage<Data>(
      title: 'Quotation request',
      load: () async => {
        'rfq': await api.call('/api/v2/rfqs/$id'),
        'quotes': await api.call('/api/v2/rfqs/$id/quotes'),
      },
      builder: (data, reload) {
        final rfq = object(data['rfq']);
        final quotes = rows(data['quotes']);
        quotes.sort(
          (a, b) => (BigInt.tryParse(field(a, 'totalPaise')) ?? BigInt.zero)
              .compareTo(
            BigInt.tryParse(field(b, 'totalPaise')) ?? BigInt.zero,
          ),
        );
        return ListView(
          padding: const EdgeInsets.all(22),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              field(rfq, 'publicNumber'),
              style: Theme.of(c).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(field(rfq, 'status')),
            ),
            const Section('Requested materials'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rows(rfq['items'])
                    .map(
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '${i['description']}\n${i['quantity']} ${i['unitCode']}',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const Section('Supplier quotations'),
            if (quotes.isEmpty)
              const EmptyState(
                'Waiting for supplier quotations',
                'Invited suppliers will submit prices and delivery terms here.',
              ),
            ...quotes.map(
              (q) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              field(q, 'quoteNumber'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          StatusPill(field(q, 'status')),
                        ],
                      ),
                      const SizedBox(height: 14),
                      totals(q),
                      if (q['deliveryTerms'] != null)
                        Text(
                          field(q, 'deliveryTerms'),
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      if (q['validUntil'] != null)
                        Text(
                          'Valid until ${field(q, 'validUntil').split('T').first}',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      const SizedBox(height: 16),
                      if (q['status'] == 'SUBMITTED' && rfq['status'] == 'OPEN')
                        ActionButton('Accept this quotation', () async {
                          if (!await confirm(
                            c,
                            'Accept this quotation?',
                            'Review material units, freight and delivery terms before choosing this supplier.',
                          )) {
                            return;
                          }
                          await api.call(
                            '/api/v2/rfqs/$id/quotes/${q['id']}/award',
                            method: 'POST',
                            body: {},
                          );
                          reload();
                        }),
                      if (q['status'] == 'ACCEPTED')
                        ActionButton(
                          'Continue to checkout',
                          () async => push(
                            c,
                            CheckoutPage(
                              cartVersion: 0,
                              rfqId: id,
                              acceptedQuoteId: field(q, 'id'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (['DRAFT', 'OPEN'].contains(rfq['status']))
              ActionButton('Cancel request', () async {
                if (!await confirm(
                  c,
                  'Cancel this request?',
                  'Suppliers will no longer be able to quote.',
                )) {
                  return;
                }
                await api.call(
                  '/api/v2/rfqs/$id/cancel',
                  method: 'POST',
                  body: {},
                );
                reload();
              }, tonal: true),
            const SizedBox(height: 25),
          ],
        );
      },
    );
  }
}
