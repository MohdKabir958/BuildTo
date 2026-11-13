import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'customer_api.dart';
import 'customer_design.dart';
import 'customer_checkout.dart';
import 'customer_workspace.dart';

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = CustomerScope.of(context);
    return SignedIn(
      child: RemotePage<List<Data>>(
        load: s.api.orders,
        builder: (orders, reload) => ListView(
          padding: const EdgeInsets.all(22),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              'Your builds,\nin motion.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Every order. Every shipment. All in one place.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 24),
            if (orders.isEmpty)
              const EmptyState(
                'Your first order awaits',
                'Orders placed from your cart or an accepted quotation will appear here.',
              ),
            ...orders.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => push(context, OrderPage(field(o, 'id'))),
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              color: accent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                field(o, 'publicNumber'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            StatusPill(field(o, 'status')),
                            StatusPill(field(o, 'paymentStatus')),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${rows(o['suppliers']).length} supplier orders',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              money(o['totalPaise']),
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> launchCustomerPayment(Data payment) async {
  if (kIsWeb) {
    throw const CustomerProblem('Open the Android app to use secure checkout.');
  }
  if (payment['providerOrderId'] == null || field(payment, 'keyId').isEmpty) {
    throw const CustomerProblem(
      'Payment is being prepared. Refresh and retry shortly.',
    );
  }
  final result = Completer<void>();
  final sdk = Razorpay();
  void finish() {
    if (!result.isCompleted) {
      result.complete();
      sdk.clear();
    }
  }

  sdk.on(Razorpay.EVENT_PAYMENT_SUCCESS, (_) => finish());
  sdk.on(Razorpay.EVENT_PAYMENT_ERROR, (_) => finish());
  sdk.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) => finish());
  runZonedGuarded(
    () => sdk.open({
      'key': payment['keyId'],
      'order_id': payment['providerOrderId'],
      'amount': int.parse(field(payment, 'amountPaise')),
      'currency': 'INR',
      'name': 'Splyzo',
      'description': 'Construction materials',
      'theme': {'color': '#152A3A'},
    }),
    (_, st) {
      if (!result.isCompleted) {
        sdk.clear();
        result.completeError(
          const CustomerProblem(
            'Unable to open secure payment. Refresh your order before retrying.',
          ),
        );
      }
    },
  );
  await result.future;
}

class OrderPage extends StatefulWidget {
  const OrderPage(this.id, {super.key});
  final String id;
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> with WidgetsBindingObserver {
  String paymentKey = requestKey(), codKey = requestKey();
  VoidCallback? reload;
  String method = 'UPI';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) reload?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = CustomerScope.of(context);
    final api = s.api;
    return RemotePage<Data>(
      title: 'Order details',
      load: () => api.order(widget.id),
      builder: (o, refresh) {
        reload = refresh;
        final suppliers = rows(o['suppliers']);
        final payStatus = field(o, 'paymentStatus');
        final canPay = field(o, 'status') == 'PLACED' &&
            ['NOT_STARTED', 'NOT_CAPTURED'].contains(payStatus);
        return ListView(
          padding: const EdgeInsets.all(22),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Panel(
              color: ink,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    color: Color(0xFFFFBB91),
                    size: 30,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    field(o, 'publicNumber'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'packages/kraveo_ui/Bricolage',
                      fontWeight: FontWeight.w700,
                      fontSize: 26,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label(o['status']),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    money(o['totalPaise']),
                    style: const TextStyle(
                      fontSize: 30,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [StatusPill(payStatus)]),
            if ([
              'PENDING',
              'AUTHORIZED',
              'CAPTURED_NEEDS_REVIEW',
            ].contains(payStatus))
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Payment is being verified. Refresh this order before starting another payment.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            if (payStatus == 'PENDING' && field(o, 'status') == 'PLACED') ...[
              const SizedBox(height: 16),
              ActionButton('Resume existing payment', () async {
                final attempts = rows(
                    await api.call('/api/v2/orders/${widget.id}/payments'));
                final active = attempts
                    .where((p) => ['CREATED', 'PENDING'].contains(p['status']))
                    .toList();
                if (active.isEmpty) {
                  throw const CustomerProblem(
                      'No active payment window was found. Refresh this order for its latest status.');
                }
                await launchCustomerPayment(active.first);
                if (context.mounted) refresh();
              }, icon: Icons.lock_outline),
              const SizedBox(height: 10),
              ActionButton('Review payment attempts',
                  () async => push(context, PaymentAttemptsPage(widget.id)),
                  tonal: true),
            ],
            if (canPay) ...[
              const Section('Complete your order'),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: const [
                  DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                  DropdownMenuItem(value: 'CARD', child: Text('Card')),
                  DropdownMenuItem(
                    value: 'NET_BANKING',
                    child: Text('Net banking'),
                  ),
                  DropdownMenuItem(
                    value: 'COD',
                    child: Text('Cash on delivery (if eligible)'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  method = v!;
                  paymentKey = requestKey();
                }),
              ),
              const SizedBox(height: 12),
              ActionButton(
                method == 'COD'
                    ? 'Request cash on delivery'
                    : 'Open secure payment',
                () async {
                  if (method == 'COD') {
                    await api.call(
                      '/api/v2/orders/${widget.id}/cod',
                      method: 'POST',
                      body: {},
                      key: codKey,
                    );
                    refresh();
                    return;
                  }
                  final p = object(
                    await api.call(
                      '/api/v2/orders/${widget.id}/payments',
                      method: 'POST',
                      body: {'paymentMethod': method},
                      key: paymentKey,
                    ),
                  );
                  await launchCustomerPayment(p);
                  if (!context.mounted) return;
                  refresh();
                  notice(
                    context,
                    'Payment window closed. Your server-confirmed payment status is shown on this order.',
                  );
                },
                icon: Icons.lock_outline,
              ),
              const SizedBox(height: 10),
              ActionButton(
                'Review payment attempts',
                () async => push(context, PaymentAttemptsPage(widget.id)),
                tonal: true,
              ),
            ],
            const Section('Materials & suppliers'),
            ...suppliers.asMap().entries.map((entry) {
              final child = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Supplier order ${entry.key + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          StatusPill(field(child, 'status')),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ...rows(child['items']).map(
                        (i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      field(i, 'name'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${i['quantity']} ${i['unitCode']}',
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(money(i['lineTotalPaise'])),
                            ],
                          ),
                        ),
                      ),
                      if (child['freightSnapshot'] != null) ...[
                        const Divider(),
                        Text(
                          'Quoted freight: ${money(object(child['freightSnapshot'])['amountPaise'])}',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                      if ([
                        'DELIVERED',
                        'PARTIALLY_DELIVERED',
                      ].contains(child['status']))
                        ActionButton(
                          'Request a return',
                          () async => push(
                            context,
                            ReturnEditor(order: o, supplier: child),
                          ),
                          tonal: true,
                        ),
                    ],
                  ),
                ),
              );
            }),
            if (suppliers.any((s) => s['status'] == 'DELIVERED')) ...[
              ActionButton(
                  'Review a supplier',
                  () async => push(context,
                      ReviewPage(orderId: widget.id, suppliers: suppliers)),
                  icon: Icons.star_border,
                  tonal: true),
              const SizedBox(height: 10)
            ],
            ActionButton(
              'Track shipments',
              () async => push(context, ShipmentsPage(widget.id)),
              icon: Icons.local_shipping_outlined,
              tonal: true,
            ),
            const SizedBox(height: 10),
            ActionButton(
              'Invoices & credit notes',
              () async => push(context, InvoicesPage(widget.id)),
              icon: Icons.receipt_long_outlined,
              tonal: true,
            ),
            const Section('Price breakdown'),
            Panel(child: totals(o)),
            const Section('Delivery address'),
            Panel(child: Text(addressText(object(o['addressSnapshot'])))),
            const SizedBox(height: 18),
            ActionButton(
              'Get help with this order',
              () async => push(context, SupportPage(orderId: widget.id)),
              icon: Icons.support_agent,
              tonal: true,
            ),
            const SizedBox(height: 10),
            ActionButton('Refund status',
                () async => push(context, RefundsPage(widget.id)),
                icon: Icons.payments_outlined, tonal: true),
            const SizedBox(height: 10),
            ActionButton(
              'Return requests',
              () async => push(context, ReturnsPage(widget.id)),
              tonal: true,
            ),
            if (field(o, 'status') == 'PLACED') ...[
              const SizedBox(height: 10),
              ActionButton('Cancel unpaid order', () async {
                final ok = await confirm(
                  context,
                  'Cancel this order?',
                  'Only eligible unpaid orders can be cancelled here. Active payment sessions must be reconciled first.',
                );
                if (!ok) return;
                await api.call(
                  '/api/v2/orders/${widget.id}/cancel',
                  method: 'POST',
                  body: {},
                );
                refresh();
              }, tonal: true),
            ],
            const SizedBox(height: 10),
            ActionButton('Review items for reorder', () async {
              final ok = await confirm(
                context,
                'Add these materials to your cart?',
                'Current prices, quantity rules and availability will be checked. Matching cart quantities will be replaced.',
              );
              if (!ok) return;
              var cart = await api.cart();
              var added = 0;
              for (final child in suppliers) {
                for (final item in rows(child['items'])) {
                  try {
                    cart = await api.setLine(
                      field(item, 'listingId'),
                      field(item, 'quantity'),
                      cart['version'] as int,
                    );
                    added++;
                  } on CustomerProblem {
                    if (context.mounted) {
                      notice(
                        context,
                        '$added items added. Some materials need a new supplier offer or quantity.',
                      );
                    }
                    return;
                  }
                }
              }
              if (context.mounted) push(context, const CartPage());
            }, tonal: true),
            const SizedBox(height: 28),
          ],
        );
      },
    );
  }
}

String addressText(Data a) => [
      'recipientName',
      'line1',
      'line2',
      'locality',
      'city',
      'cityName',
      'stateCode',
      'postalCode',
    ].map((k) => field(a, k)).where((s) => s.isNotEmpty).join(', ');
Future<bool> confirm(BuildContext c, String title, String text) async =>
    await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

class PaymentAttemptsPage extends StatelessWidget {
  const PaymentAttemptsPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return RemotePage<List<Data>>(
      title: 'Payment attempts',
      load: () async => rows(await api.call('/api/v2/orders/$id/payments')),
      builder: (list, reload) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            'A payment-window response is not confirmation. Only provider-verified payments update your order.',
            style: TextStyle(color: muted),
          ),
          if (list.isEmpty)
            const EmptyState(
              'No online payments',
              'No payment attempts were found for this order.',
            ),
          ...list.map(
            (p) => Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusPill(field(p, 'status')),
                    const SizedBox(height: 12),
                    Text(
                      '${label(p['paymentMethod'])} · ${money(p['amountPaise'])}',
                    ),
                    if (['CREATED', 'PENDING'].contains(p['status'])) ...[
                      const SizedBox(height: 12),
                      ActionButton('Cancel payment session', () async {
                        if (!await confirm(
                          c,
                          'Close this payment session?',
                          'The provider will be checked before cancellation.',
                        )) {
                          return;
                        }
                        await api.call(
                          '/api/v2/orders/$id/payments/${p['id']}/cancel',
                          method: 'POST',
                          body: {},
                        );
                        reload();
                      }, tonal: true),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ShipmentsPage extends StatelessWidget {
  const ShipmentsPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return RemotePage<List<Data>>(
      title: 'Shipment tracking',
      load: () async => rows(await api.call('/api/v2/orders/$id/shipments')),
      builder: (list, reload) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            'Your supplier manages delivery. Each shipment below has its own progress.',
            style: TextStyle(color: muted),
          ),
          if (list.isEmpty)
            const EmptyState(
              'Preparing your delivery',
              'Shipment details will appear once your supplier creates a shipment.',
            ),
          ...list.map(
            (p) => Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field(p, 'shipmentNumber'),
                      style: Theme.of(c).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    StatusPill(field(p, 'status')),
                    const SizedBox(height: 18),
                    ...rows(p['events']).map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              color: green,
                              size: 19,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(label(e['toStatus']))),
                            Text(
                              field(e, 'at').split('T').first,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (p['vehicleLabel'] != null)
                      Text('Vehicle: ${p['vehicleLabel']}'),
                    if (p['carrierName'] != null)
                      Text('Carrier: ${p['carrierName']}'),
                    if (p['carrierPhoneE164'] != null)
                      SelectableText(field(p, 'carrierPhoneE164')),
                    if (p['trackingReference'] != null)
                      SelectableText(
                        'Tracking reference: ${p['trackingReference']}',
                      ),
                    if (p['status'] == 'OUT_FOR_DELIVERY') ...[
                      const SizedBox(height: 15),
                      ActionButton('Get delivery confirmation code', () async {
                        final otp = object(
                          await api.call(
                            '/api/v2/orders/$id/shipments/${p['id']}/otp',
                            method: 'POST',
                            body: {},
                          ),
                        );
                        if (!c.mounted) return;
                        await showDialog<void>(
                          context: c,
                          builder: (d) => AlertDialog(
                            title: const Text('Confirm only after receipt'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Check the delivered materials before sharing this code with your supplier.',
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  field(otp, 'otp'),
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 5,
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(d),
                                child: const Text('Done'),
                              ),
                            ],
                          ),
                        );
                      }, tonal: true),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InvoicesPage extends StatelessWidget {
  const InvoicesPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return RemotePage<List<Data>>(
      title: 'Invoices & credit notes',
      load: () async => rows(await api.call('/api/v2/orders/$id/invoices')),
      builder: (list, reload) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          if (list.isEmpty)
            const EmptyState(
              'No invoices issued yet',
              'Your supplier-issued invoices and credit notes will appear here.',
            ),
          ...list.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      field(p, 'invoiceNumber'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 10),
                    StatusPill(field(p, 'kind')),
                    const SizedBox(height: 16),
                    Text(addressText(object(p['seller']))),
                    AmountRow('Taxable amount', p['taxablePaise']),
                    AmountRow('Tax', p['taxPaise']),
                    AmountRow('Total', p['totalPaise'], total: true),
                    ...rows(p['lines']).map(
                      (l) => Text(
                        '${l['name'] ?? l['description'] ?? ''} · ${l['quantity'] ?? ''}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReturnsPage extends StatelessWidget {
  const ReturnsPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return RemotePage<List<Data>>(
      title: 'Return requests',
      load: () async => rows(await api.call('/api/v2/orders/$id/returns')),
      builder: (list, reload) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          if (list.isEmpty)
            const EmptyState(
              'No returns requested',
              'Eligible delivered materials can be selected from your order details.',
            ),
          ...list.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusPill(field(r, 'status')),
                    const SizedBox(height: 12),
                    Text(field(r, 'reason')),
                    if (r['resolutionNote'] != null)
                      Text(field(r, 'resolutionNote')),
                    const SizedBox(height: 8),
                    const Text(
                      'Return approval and refund processing are separate. Contact support for payment reconciliation.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReturnEditor extends StatefulWidget {
  const ReturnEditor({super.key, required this.order, required this.supplier});
  final Data order, supplier;
  @override
  State<ReturnEditor> createState() => _ReturnEditorState();
}

class _ReturnEditorState extends State<ReturnEditor> {
  final reason = TextEditingController();
  final quantities = <String, TextEditingController>{};
  final selected = <String>{};
  final key = requestKey();
  final evidence = <Data>[];
  @override
  void initState() {
    super.initState();
    for (final i in rows(widget.supplier['items'])) {
      quantities[field(i, 'id')] = TextEditingController(
        text: field(i, 'quantity'),
      );
    }
  }

  @override
  void dispose() {
    reason.dispose();
    for (final c in quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return Scaffold(
      appBar: AppBar(title: const Text('Request a return')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            'Select the materials and quantities you want reviewed. Eligibility is checked against delivered quantities.',
          ),
          const SizedBox(height: 20),
          ...rows(widget.supplier['items']).map(
            (i) => Column(
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(field(i, 'name')),
                  value: selected.contains(i['id']),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      selected.add(field(i, 'id'));
                    } else {
                      selected.remove(i['id']);
                    }
                  }),
                ),
                if (selected.contains(i['id']))
                  TextField(
                    controller: quantities[i['id']],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Return quantity (${i['unitCode']})',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: reason,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'What went wrong? (12+ characters)',
            ),
          ),
          const SizedBox(height: 20),
          ActionButton(
              'Attach photo or PDF',
              evidence.length >= 8
                  ? null
                  : () async {
                      final file = await openFile(acceptedTypeGroups: [
                        const XTypeGroup(label: 'Photos and PDFs', extensions: [
                          'jpg',
                          'jpeg',
                          'png',
                          'pdf'
                        ], mimeTypes: [
                          'image/jpeg',
                          'image/png',
                          'application/pdf'
                        ])
                      ]);
                      if (file == null) return;
                      if (await file.length() > 10 * 1024 * 1024) {
                        throw const CustomerProblem(
                            'Choose a file smaller than 10 MiB.');
                      }
                      final ext = file.name.split('.').last.toLowerCase();
                      final mime = ext == 'pdf'
                          ? 'application/pdf'
                          : ext == 'png'
                              ? 'image/png'
                              : ext == 'jpg' || ext == 'jpeg'
                                  ? 'image/jpeg'
                                  : null;
                      if (mime == null) {
                        throw const CustomerProblem(
                            'Choose a JPEG, PNG or PDF.');
                      }
                      final asset = object(await api
                          .call('/api/v2/media', method: 'POST', body: {
                        'purpose': 'EVIDENCE',
                        'mimeType': mime,
                        'base64': base64Encode(await file.readAsBytes())
                      }));
                      if (mounted) {
                        setState(() => evidence
                            .add({'id': asset['id'], 'name': file.name}));
                      }
                    },
              icon: Icons.attach_file,
              tonal: true),
          ...evidence.map((e) => ListTile(
              title: Text(field(e, 'name')),
              leading: const Icon(Icons.verified_user_outlined, color: green),
              trailing: IconButton(
                  tooltip: 'Remove attachment',
                  onPressed: () => setState(() => evidence.remove(e)),
                  icon: const Icon(Icons.close)))),
          const SizedBox(height: 16),
          ActionButton('Submit return request', () async {
            if (selected.isEmpty || reason.text.trim().length < 12) {
              throw const CustomerProblem(
                'Choose materials and explain the issue in at least 12 characters.',
              );
            }
            for (final id in selected) {
              if (scaled(quantities[id]!.text.trim(), 3) <= BigInt.zero) {
                throw const CustomerProblem(
                  'Return quantity must be positive.',
                );
              }
            }
            await api.call(
              '/api/v2/orders/${widget.order['id']}/returns',
              method: 'POST',
              key: key,
              body: {
                'supplierOrderId': widget.supplier['id'],
                'evidenceMediaIds': evidence.map((e) => e['id']).toList(),
                'reason': reason.text.trim(),
                'items': selected
                    .map(
                      (id) => {
                        'orderItemId': id,
                        'quantity': quantities[id]!.text.trim(),
                      },
                    )
                    .toList(),
              },
            );
            if (c.mounted) {
              Navigator.of(c).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ReturnsPage(field(widget.order, 'id')),
                ),
              );
            }
          }),
        ],
      ),
    );
  }
}

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.orderId, required this.suppliers});
  final String orderId;
  final List<Data> suppliers;
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  String? supplierOrder;
  int rating = 5;
  final comment = TextEditingController();
  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return Scaffold(
        appBar: AppBar(title: const Text('Review your supplier')),
        body: ListView(padding: const EdgeInsets.all(22), children: [
          Text('Help others build better.',
              style: Theme.of(c).textTheme.headlineSmall),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Delivered supplier order'),
              items: widget.suppliers
                  .asMap()
                  .entries
                  .where((e) => e.value['status'] == 'DELIVERED')
                  .map((e) => DropdownMenuItem(
                      value: field(e.value, 'id'),
                      child: Text('Supplier order ${e.key + 1}')))
                  .toList(),
              onChanged: (v) => supplierOrder = v),
          const SizedBox(height: 20),
          Wrap(
              children: List.generate(
                  5,
                  (i) => IconButton(
                      tooltip: '${i + 1} stars',
                      onPressed: () => setState(() => rating = i + 1),
                      icon: Icon(
                          i < rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: accent,
                          size: 32)))),
          const SizedBox(height: 20),
          TextField(
              controller: comment,
              maxLength: 1500,
              maxLines: 4,
              decoration: const InputDecoration(
                  labelText: 'Your experience (optional, 8+ characters)')),
          const SizedBox(height: 20),
          ActionButton('Submit review', () async {
            if (supplierOrder == null) {
              throw const CustomerProblem('Choose a delivered supplier order.');
            }
            if (comment.text.trim().isNotEmpty &&
                comment.text.trim().length < 8) {
              throw const CustomerProblem(
                  'Use at least 8 characters for your review.');
            }
            await api.call('/api/v2/orders/${widget.orderId}/reviews',
                method: 'POST',
                body: {
                  'supplierOrderId': supplierOrder,
                  'rating': rating,
                  if (comment.text.trim().isNotEmpty)
                    'comment': comment.text.trim()
                });
            if (c.mounted) {
              notice(c, 'Review submitted for moderation.');
              Navigator.pop(c);
            }
          }),
        ]));
  }
}

class RefundsPage extends StatelessWidget {
  const RefundsPage(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) {
    final api = CustomerScope.of(c).api;
    return RemotePage<List<Data>>(
        title: 'Refund status',
        load: () async => rows(await api.call('/api/v2/orders/$id/refunds')),
        builder: (list, reload) =>
            ListView(padding: const EdgeInsets.all(22), children: [
              const Text(
                  'Refunds are shown when recorded by the payment and reconciliation workflow. Return approval does not mean a refund is complete.',
                  style: TextStyle(color: muted)),
              if (list.isEmpty)
                const EmptyState('No refunds recorded',
                    'Contact support if you need help with a payment or return.'),
              ...list.map((r) => Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Panel(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        StatusPill(field(r, 'status')),
                        const SizedBox(height: 15),
                        Text(money(r['amountPaise']),
                            style: Theme.of(c).textTheme.headlineSmall),
                        const SizedBox(height: 10),
                        Text(field(r, 'reason')),
                        if (r['customerBankCredit'] == 'NOT_VERIFIED')
                          const Text('Bank credit awaiting confirmation',
                              style: TextStyle(fontSize: 12, color: muted)),
                        if (r['providerRefundId'] != null)
                          SelectableText('Reference: ${r['providerRefundId']}'),
                        if (r['providerCompletedAt'] != null)
                          Text(
                              'Processed by payment provider: ${field(r, 'providerCompletedAt').split('T').first}',
                              style:
                                  const TextStyle(fontSize: 12, color: muted))
                      ])))),
            ]));
  }
}
