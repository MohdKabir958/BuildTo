import 'dart:async';
import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../care/supplier_care_repository.dart';
import '../dashboard/supplier_dashboard_models.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import '../inventory/supplier_inventory_repository.dart';
import '../orders/supplier_orders_repository.dart';
import '../shipments/supplier_shipments_repository.dart';
import 'supplier_finance_repository.dart';

/// The supplier has no permissions to approve finance or mark funds bank-paid.
/// Every projection is server-owned, and access changes clear old data.
class SupplierFinanceView extends StatefulWidget {
  const SupplierFinanceView({
    super.key,
    required this.supplierId,
    required this.finance,
    required this.orders,
    required this.shipments,
    required this.care,
    required this.canRead,
    required this.canIssue,
    required this.canRecordCod,
    this.onRecheckAccess,
  });
  final String supplierId;
  final SupplierFinanceRepository finance;
  final SupplierOrdersRepository orders;
  final SupplierShipmentsRepository shipments;
  final SupplierCareRepository care;
  final bool canRead, canIssue, canRecordCod;
  final VoidCallback? onRecheckAccess;
  @override
  State<SupplierFinanceView> createState() => _SupplierFinanceViewState();
}

class _SupplierFinanceViewState extends State<SupplierFinanceView> {
  SupplierFinanceStatement? statement;
  List<SupplierBeneficiary> beneficiaries = const [];
  List<SupplierPayout> payouts = const [];
  List<SupplierOrder> orders = const [];
  List<SupplierInvoice> invoices = const [];
  List<SupplierCodReceipt> cod = const [];
  List<SupplierReturn> returns = const [];
  List<SupplierShipment> shipments = const [];
  String? chosenOrder;
  String? error;
  bool loading = true, orderLoading = false, actionBusy = false;
  int generation = 0, orderGeneration = 0, tab = 0;

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  @override
  void didUpdateWidget(SupplierFinanceView old) {
    super.didUpdateWidget(old);
    if (old.supplierId != widget.supplierId ||
        old.finance != widget.finance ||
        old.canRead != widget.canRead ||
        old.canIssue != widget.canIssue ||
        old.canRecordCod != widget.canRecordCod) {
      chosenOrder = null;
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    generation++;
    orderGeneration++;
    super.dispose();
  }

  Future<void> refresh() async {
    final ticket = ++generation;
    ++orderGeneration;
    setState(() {
      loading = true;
      error = null;
      orders = const [];
      invoices = const [];
      cod = const [];
      returns = const [];
      shipments = const [];
      statement = null;
      beneficiaries = const [];
      payouts = const [];
    });
    try {
      final read = widget.canRead;
      final data = await Future.wait<Object>([
        widget.orders.orders(widget.supplierId),
        if (read) widget.finance.statement(widget.supplierId),
        if (read) widget.finance.beneficiaries(widget.supplierId),
        if (read) widget.finance.payouts(widget.supplierId),
      ]);
      if (!mounted || ticket != generation) return;
      final nextOrders = data[0] as List<SupplierOrder>;
      final id = nextOrders.any((order) => order.id == chosenOrder)
          ? chosenOrder
          : nextOrders.firstOrNull?.id;
      setState(() {
        orders = nextOrders;
        statement = read ? data[1] as SupplierFinanceStatement : null;
        beneficiaries = read ? data[2] as List<SupplierBeneficiary> : const [];
        payouts = read ? data[3] as List<SupplierPayout> : const [];
        chosenOrder = id;
        loading = false;
      });
      if (id != null) await loadOrder(id);
    } catch (e) {
      if (!mounted || ticket != generation) return;
      setState(() {
        loading = false;
        statement = null;
        orders = const [];
        beneficiaries = const [];
        payouts = const [];
        error = switch (e) {
          SupplierV21Exception(problem: SupplierV21Problem.authentication) =>
            'Clerk session expired. Sign in to continue.',
          SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
          SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
            'Supplier finance permission or business access changed.',
          _ => 'Finance records could not be verified. Old data is hidden.',
        };
      });
    }
  }

  Future<void> loadOrder(String orderId) async {
    final ticket = ++orderGeneration;
    setState(() {
      chosenOrder = orderId;
      orderLoading = true;
      invoices = const [];
      cod = const [];
      returns = const [];
      shipments = const [];
    });
    try {
      final data = await Future.wait<Object>([
        if (widget.canRead) widget.finance.invoices(widget.supplierId, orderId),
        if (widget.canRead)
          widget.finance.codReceipts(widget.supplierId, orderId),
        if (widget.canRead) widget.care.returns(widget.supplierId, orderId),
        if (widget.canRecordCod)
          widget.shipments.list(widget.supplierId, orderId),
      ]);
      if (!mounted || ticket != orderGeneration) return;
      var i = 0;
      final nextInvoices = widget.canRead
          ? data[i++] as List<SupplierInvoice>
          : <SupplierInvoice>[];
      final nextCod = widget.canRead
          ? data[i++] as List<SupplierCodReceipt>
          : <SupplierCodReceipt>[];
      final nextReturns = widget.canRead
          ? data[i++] as List<SupplierReturn>
          : <SupplierReturn>[];
      final nextShipments = widget.canRecordCod
          ? data[i++] as List<SupplierShipment>
          : <SupplierShipment>[];
      setState(() {
        invoices = nextInvoices;
        cod = nextCod;
        returns = nextReturns;
        shipments = nextShipments;
        orderLoading = false;
      });
    } catch (e) {
      if (!mounted || ticket != orderGeneration) return;
      setState(() {
        orderLoading = false;
        invoices = const [];
        cod = const [];
        returns = const [];
        shipments = const [];
      });
      _notice(
          'Order finance records unavailable or access revoked. Recheck permissions.');
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _failure(Object error) => switch (error) {
        SupplierV21Exception(problem: SupplierV21Problem.conflict) =>
          'Backend state conflict. Payment, tax registration or return approval may be incomplete.',
        SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
        SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
          'Supplier permission changed. Recheck your role.',
        SupplierV21Exception(problem: SupplierV21Problem.network) =>
          'Outcome unknown. Refresh before trying again; do not duplicate an invoice or receipt.',
        FormatException() => 'Check the receipt reference and entered details.',
        _ => 'Action was not confirmed. Refresh the server records.',
      };

  Future<void> _issueInvoice(SupplierOrder order) async {
    if (!widget.canIssue || actionBusy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Issue GST document?'),
        content: const Text(
            'Splyzo creates the invoice number, GST, taxable amounts and snapshots from the authoritative order. You cannot supply prices or tax. This is a statutory record.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Issue server-calculated document')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => actionBusy = true);
    try {
      final invoice =
          await widget.finance.issueInvoice(widget.supplierId, order.id);
      _notice('Document ${invoice.number} issued by Splyzo.');
    } catch (e) {
      _notice(_failure(e));
    } finally {
      if (mounted) {
        setState(() => actionBusy = false);
        await loadOrder(order.id);
      }
    }
  }

  Future<void> _issueCredit(SupplierReturn item) async {
    if (!widget.canIssue ||
        actionBusy ||
        item.status != SupplierReturnStatus.received) {
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Issue full-return GST credit note?'),
        content: const Text(
            'Only a complete physically received return qualifies, and the issuer must be independent of its goods receiver. Splyzo validates this and calculates all tax. Issuing a credit note is not a refund.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ask backend to issue')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => actionBusy = true);
    try {
      final note = await widget.finance
          .issueCreditNote(supplierId: widget.supplierId, returnId: item.id);
      _notice(
          'GST credit note ${note.invoiceNumber} issued; refund not processed.');
    } catch (e) {
      _notice(_failure(e));
    } finally {
      if (mounted) {
        setState(() => actionBusy = false);
        final id = chosenOrder;
        if (id != null) await loadOrder(id);
      }
    }
  }

  Future<void> _recordCod(SupplierOrder order) async {
    if (!widget.canRecordCod ||
        actionBusy ||
        order.status != DashboardOrderStatus.delivered) {
      return;
    }
    final delivered = shipments
        .where((s) =>
            s.status == SupplierShipmentStatus.delivered && s.handoverVerified)
        .toList();
    if (delivered.isEmpty) {
      _notice('A verified delivered shipment is required to record COD.');
      return;
    }
    final receipt = TextEditingController();
    final note = TextEditingController();
    var selected = delivered.first.id;
    final intent = supplierInventoryIntent();
    bool busy = false, uncertain = false;
    String? error;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, change) => AlertDialog(
                  title: const Text('Record supplier-held COD'),
                  content: SingleChildScrollView(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                          'This records a cash-collection claim, NOT verified payment. Independent Splyzo finance review is required.'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          initialValue: selected,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Verified delivered shipment'),
                          items: delivered
                              .map((s) => DropdownMenuItem(
                                  value: s.id, child: Text(s.shipmentNumber)))
                              .toList(),
                          onChanged: busy || uncertain
                              ? null
                              : (value) =>
                                  change(() => selected = value ?? selected)),
                      const SizedBox(height: 8),
                      TextField(
                          controller: receipt,
                          maxLength: 100,
                          decoration: const InputDecoration(
                              labelText: 'Cash receipt number')),
                      const SizedBox(height: 5),
                      TextField(
                          controller: note,
                          maxLength: 300,
                          decoration: const InputDecoration(
                              labelText: 'Audit note (optional)')),
                      if (error != null)
                        Text(error!,
                            style:
                                const TextStyle(color: BuildToPalette.danger)),
                    ],
                  )),
                  actions: [
                    TextButton(
                        onPressed:
                            busy ? null : () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: busy || uncertain
                            ? null
                            : () async {
                                change(() {
                                  busy = true;
                                  error = null;
                                });
                                try {
                                  await widget.finance.recordCod(
                                      supplierId: widget.supplierId,
                                      orderId: order.id,
                                      shipmentId: selected,
                                      receiptNumber: receipt.text,
                                      note: note.text,
                                      intent: intent);
                                  if (ctx.mounted) Navigator.pop(ctx, true);
                                } catch (e) {
                                  if (!ctx.mounted) return;
                                  change(() {
                                    busy = false;
                                    uncertain = e is SupplierV21Exception &&
                                        e.problem == SupplierV21Problem.network;
                                    error = uncertain
                                        ? 'Outcome uncertain. Close and refresh; never submit a new receipt intent.'
                                        : 'Receipt not accepted. Confirm customer COD selection, delivery and reference.';
                                  });
                                }
                              },
                        child: const Text('Record unverified collection')),
                  ],
                )),
      );
      if (saved == true) {
        _notice(
            'COD recorded as unverified. Await independent finance review.');
      }
    } finally {
      receipt.dispose();
      note.dispose();
      if (mounted) await loadOrder(order.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canRead && !widget.canRecordCod) {
      return const BuildToStatePanel(
        title: 'Finance access restricted',
        message:
            'Only approved finance or fulfillment roles may view this workspace.',
        icon: Icons.lock_outline,
      );
    }
    if (loading) {
      return ListView(
          padding: const EdgeInsets.all(20),
          children: const [BuildToSkeleton(height: 140), BuildToSkeleton()]);
    }
    if (error != null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        BuildToStatePanel(
            title: 'Finance unavailable',
            message: error!,
            actionLabel: 'Retry',
            onAction: () => unawaited(refresh())),
        if (widget.onRecheckAccess != null)
          OutlinedButton(
              onPressed: widget.onRecheckAccess,
              child: const Text('Recheck access')),
      ]);
    }

    final order = orders.where((o) => o.id == chosenOrder).firstOrNull;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        key: const Key('supplier-finance-loaded'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Text('Finance & GST',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: BuildToPalette.navy,
                borderRadius: BorderRadius.circular(20)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('BUILDTO • VERIFIED MONEY RECORDS',
                  style: TextStyle(
                      color: BuildToPalette.orange,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Clear cash. Clear accountability.',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                  widget.canRead
                      ? 'Payout intent and provider-processed status do not prove a bank credit.'
                      : 'Cash collected at delivery is not verified until independent finance review.',
                  style: const TextStyle(color: Color(0xFFDDECF9))),
            ]),
          ),
          const SizedBox(height: 15),
          if (widget.canRead)
            Wrap(spacing: 7, runSpacing: 6, children: [
              for (final item in const [
                'Statements',
                'Invoices & credit',
                'COD receipts'
              ])
                ChoiceChip(
                    label: Text(item),
                    selected: tab ==
                        const [
                          'Statements',
                          'Invoices & credit',
                          'COD receipts'
                        ].indexOf(item),
                    onSelected: (_) => setState(() => tab = const [
                          'Statements',
                          'Invoices & credit',
                          'COD receipts'
                        ].indexOf(item))),
            ]),
          const SizedBox(height: 12),
          if (widget.canRead && tab == 0) ...[
            const BuildToSectionHeading(
                title: 'Settlement statements',
                subtitle: 'Backend-authoritative, at most 100 recent entries.'),
            const SizedBox(height: 10),
            if (statement!.settlements.isEmpty)
              const BuildToStatePanel(
                  title: 'No settlement statements',
                  message:
                      'Only independently approved finance statements appear here.'),
            ...statement!.settlements.map((s) => BuildToCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(financeMoney(s.payablePaise),
                                  style:
                                      Theme.of(context).textTheme.titleLarge)),
                          BuildToStatusChip(
                              label: s.status,
                              status: s.status == 'PAID'
                                  ? BuildToStatus.warning
                                  : BuildToStatus.neutral),
                        ]),
                        Text(
                            'Gross: ${financeMoney(s.grossPaise)} · Commission: ${financeMoney(s.commissionPaise)}'),
                        Text(
                            'Refund allocation: ${financeMoney(s.refundPaise)}'),
                        Text(
                            'Provider / evidence: ${s.payoutState.replaceAll('_', ' ')}'),
                        const Text('Bank credit not verified by supplier API.',
                            style: TextStyle(color: BuildToPalette.warning)),
                      ]),
                )),
            const SizedBox(height: 20),
            const BuildToSectionHeading(title: 'COD commission receivables'),
            if (statement!.receivables.isEmpty)
              const Text('No COD commission receivables reported.'),
            ...statement!.receivables.map((c) => BuildToCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Commission: ${financeMoney(c.commissionPaise)}'),
                      Text(
                          'Offset: ${financeMoney(c.offsetPaise)} · ${c.status}'),
                    ]))),
            const SizedBox(height: 20),
            const BuildToSectionHeading(title: 'Masked payout beneficiaries'),
            if (beneficiaries.isEmpty)
              const Text('No verified payout beneficiary on record.'),
            ...beneficiaries.map((b) => BuildToCard(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Bank: ${b.maskedBank ?? 'Masked account unavailable'}'),
                    Text(b.active && b.verified
                        ? 'Validated by bank verification'
                        : 'Not approved for payouts'),
                  ],
                ))),
            const SizedBox(height: 20),
            const BuildToSectionHeading(title: 'Payout evidence'),
            if (payouts.isEmpty) const Text('No payout intents recorded.'),
            ...payouts.map((p) => BuildToCard(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(financeMoney(p.amountPaise),
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('Provider status: ${p.status}'),
                    Text('Evidence: ${p.meaning.replaceAll('_', ' ')}'),
                    Text(
                        'Destination: ${p.maskedBank ?? 'Masked account unavailable'}'),
                    const Text('Provider status is not a bank statement.',
                        style: TextStyle(color: BuildToPalette.warning)),
                  ],
                ))),
            if (statement!.settlements.length == 100 ||
                statement!.receivables.length == 100 ||
                payouts.length == 100)
              const Text(
                  'Records are bounded to 100; no account-wide totals inferred.'),
          ],
          if ((!widget.canRead || tab == 1 || tab == 2)) ...[
            const BuildToSectionHeading(
                title: 'Supplier order finance',
                subtitle:
                    'Only actual supplier orders and verified financial documents.'),
            const SizedBox(height: 12),
            if (orders.isEmpty)
              const BuildToStatePanel(
                  title: 'No supplier orders',
                  message: 'No eligible order records are available.')
            else
              DropdownButtonFormField<String>(
                key: ValueKey(chosenOrder),
                initialValue: chosenOrder,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Select order'),
                items: orders
                    .map((o) => DropdownMenuItem<String>(
                        value: o.id,
                        child: Text(
                            'Order ${o.id.substring(o.id.length - 8).toUpperCase()} · ${o.status.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: actionBusy
                    ? null
                    : (id) {
                        if (id != null) unawaited(loadOrder(id));
                      },
              ),
            const SizedBox(height: 14),
            if (orderLoading) const BuildToSkeleton(height: 130),
            if (!orderLoading &&
                order != null &&
                widget.canRead &&
                tab == 1) ...[
              Text('Server-priced invoices',
                  style: Theme.of(context).textTheme.titleMedium),
              if (invoices.isEmpty) const Text('No issued GST document yet.'),
              ...invoices.map((invoice) => BuildToCard(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(invoice.number,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                          '${invoice.kind.replaceAll('_', ' ')} · ${invoice.status}'),
                      Text('Taxable: ${financeMoney(invoice.taxablePaise)}'),
                      Text('GST: ${financeMoney(invoice.taxPaise)}'),
                      Text('Total: ${financeMoney(invoice.totalPaise)}'),
                      const Text(
                          'Legal invoice data is backend-issued; no PDF export endpoint is assumed.'),
                    ],
                  ))),
              if (widget.canIssue &&
                  invoices.isEmpty &&
                  {
                    DashboardOrderStatus.dispatched,
                    DashboardOrderStatus.partiallyDelivered,
                    DashboardOrderStatus.delivered
                  }.contains(order.status))
                BuildToPrimaryButton(
                    label: 'Issue server-calculated GST document',
                    icon: Icons.receipt_long_outlined,
                    busy: actionBusy,
                    onPressed: () => unawaited(_issueInvoice(order))),
              const SizedBox(height: 14),
              Text('Received-return credit notes',
                  style: Theme.of(context).textTheme.titleMedium),
              ...returns
                  .where((r) => r.status == SupplierReturnStatus.received)
                  .map((r) => BuildToCard(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Return ${r.id.substring(r.id.length - 8).toUpperCase()}'),
                          const Text(
                              'Full-return only; independent issuer required.'),
                          if (widget.canIssue)
                            OutlinedButton(
                                onPressed: actionBusy
                                    ? null
                                    : () => unawaited(_issueCredit(r)),
                                child: const Text(
                                    'Request statutory GST credit note')),
                        ],
                      ))),
            ],
            if (!orderLoading &&
                order != null &&
                (!widget.canRead || tab == 2)) ...[
              if (widget.canRead) ...[
                Text('Recorded COD collections',
                    style: Theme.of(context).textTheme.titleMedium),
                if (cod.isEmpty) const Text('No COD cash receipt recorded.'),
                ...cod.map((c) => BuildToCard(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.receiptNumber,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                            'Supplier held: ${financeMoney(c.collectedPaise)}'),
                        Text('Independent review: ${c.status}'),
                        if (c.status == 'RECORDED')
                          const Text(
                              'Claim recorded, cash is not yet verified.',
                              style: TextStyle(color: BuildToPalette.warning)),
                      ],
                    ))),
              ],
              if (widget.canRecordCod &&
                  order.status == DashboardOrderStatus.delivered)
                BuildToPrimaryButton(
                    label: 'Record verified-handover COD claim',
                    icon: Icons.payments_outlined,
                    busy: actionBusy,
                    onPressed: () => unawaited(_recordCod(order))),
              if (!widget.canRecordCod)
                const Text(
                    'Cash collection entry requires the fulfillment role.'),
            ],
          ],
        ],
      ),
    );
  }
}
