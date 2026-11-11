import 'dart:async';
import 'package:flutter/material.dart';
import '../api/supplier_v21_api.dart';
import '../catalog/supplier_catalog_models.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import '../delivery/supplier_delivery_models.dart';
import 'supplier_rfq_models.dart';
import 'supplier_rfq_repository.dart';

/// Invited, open construction RFQs only. Quotes and revisions are exclusively
/// server-priced; an accepted quote is not a funded or fulfilled order.
class SupplierRfqView extends StatefulWidget {
  const SupplierRfqView({
    super.key,
    required this.supplierId,
    required this.repository,
    required this.canQuote,
    this.onRecheckAccess,
  });
  final String supplierId;
  final SupplierRfqRepository repository;
  final bool canQuote;
  final VoidCallback? onRecheckAccess;

  @override
  State<SupplierRfqView> createState() => _SupplierRfqViewState();
}

class _SupplierRfqViewState extends State<SupplierRfqView> {
  List<SupplierRfq> invitations = const [];
  bool busy = true;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.canQuote) {
      unawaited(refresh());
    } else {
      busy = false;
    }
  }

  @override
  void didUpdateWidget(SupplierRfqView old) {
    super.didUpdateWidget(old);
    if (widget.supplierId != old.supplierId ||
        widget.canQuote != old.canQuote ||
        widget.repository != old.repository) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> refresh() async {
    final ticket = ++generation;
    setState(() {
      busy = widget.canQuote;
      invitations = const [];
      error = null;
    });
    if (!widget.canQuote) return;
    try {
      final result = await widget.repository.invitations(widget.supplierId);
      if (!mounted || ticket != generation) return;
      setState(() {
        invitations = result;
        busy = false;
      });
    } catch (e) {
      if (!mounted || ticket != generation) return;
      setState(() {
        busy = false;
        error = switch (e) {
          SupplierV21Exception(problem: SupplierV21Problem.authentication) =>
            'Your Clerk session expired. Sign in again.',
          SupplierV21Exception(problem: SupplierV21Problem.forbidden) ||
          SupplierV21Exception(problem: SupplierV21Problem.notFound) =>
            'Supplier RFQ access was changed or revoked.',
          _ =>
            'Could not verify invitations. Previously loaded RFQs are hidden.',
        };
      });
    }
  }

  Future<void> openRfq(SupplierRfq request) async {
    if (!widget.canQuote) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => FractionallySizedBox(
        heightFactor: .93,
        child: _RfqDetails(
          key: ValueKey(request.id),
          request: request,
          supplierId: widget.supplierId,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted) await refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canQuote) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          BuildToStatePanel(
            title: 'RFQ access restricted',
            message:
                'A current OWNER, MANAGER or CATALOG supplier role is required to read invited RFQs and submit quotes.',
            icon: Icons.shield_outlined,
          ),
        ],
      );
    }
    if (busy) {
      return ListView(padding: const EdgeInsets.all(20), children: const [
        BuildToSkeleton(height: 145),
        SizedBox(height: 15),
        BuildToSkeleton(),
        SizedBox(height: 15),
        BuildToSkeleton(),
      ]);
    }
    if (error != null) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        BuildToStatePanel(
          title: 'Invitations unavailable',
          message: error!,
          actionLabel: 'Retry invitations',
          onAction: () => unawaited(refresh()),
        ),
        if (widget.onRecheckAccess != null)
          OutlinedButton(
            onPressed: widget.onRecheckAccess,
            child: const Text('Recheck supplier access'),
          ),
      ]);
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        key: const Key('supplier-rfq-loaded'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          Row(children: [
            Expanded(
                child: Text('Quotation requests',
                    style: Theme.of(context).textTheme.headlineMedium)),
            IconButton(
              tooltip: 'Refresh RFQs',
              onPressed: () => unawaited(refresh()),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: BuildToPalette.navy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BUILDTO • MATERIAL PROCUREMENT',
                    style: TextStyle(
                        color: BuildToPalette.orange,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
                const SizedBox(height: 12),
                Text(
                    '${invitations.length == 100 ? '100+' : invitations.length} open invitations',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                const Text(
                    'Price every requested material. A submitted or awarded quote is not a paid order.',
                    style: TextStyle(color: Color(0xFFE0EEFA))),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const BuildToSectionHeading(
            title: 'Invited RFQs',
            subtitle: 'Only invitations authorized for your verified supplier.',
          ),
          const SizedBox(height: 12),
          if (invitations.isEmpty)
            const BuildToStatePanel(
              title: 'No open invitations',
              message:
                  'When customers invite this supplier to an open construction RFQ, it appears here.',
              icon: Icons.request_quote_outlined,
            ),
          ...invitations.map((request) => BuildToCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.description_outlined,
                          color: BuildToPalette.navy),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(request.publicNumber,
                              style: Theme.of(context).textTheme.titleMedium)),
                      const BuildToStatusChip(
                          label: 'OPEN', status: BuildToStatus.pending),
                    ]),
                    const SizedBox(height: 8),
                    Text('${request.items.length} material lines'),
                    if (request.responseDueAt != null)
                      Text(
                          'Response due: ${request.responseDueAt!.toLocal().toString().split('.').first}',
                          style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(openRfq(request)),
                      icon: const Icon(Icons.request_quote_outlined),
                      label: const Text('View and quote'),
                    ),
                  ],
                ),
              )),
          if (invitations.length == 100)
            const Text('Showing the latest 100 active invited RFQs.'),
        ],
      ),
    );
  }
}

class _RfqDetails extends StatefulWidget {
  const _RfqDetails({
    super.key,
    required this.request,
    required this.supplierId,
    required this.repository,
  });
  final SupplierRfq request;
  final String supplierId;
  final SupplierRfqRepository repository;
  @override
  State<_RfqDetails> createState() => _RfqDetailsState();
}

class _RfqDetailsState extends State<_RfqDetails> {
  late Future<List<SupplierQuote>> quoteFuture;

  @override
  void initState() {
    super.initState();
    quoteFuture = loadQuotes();
  }

  Future<List<SupplierQuote>> loadQuotes() =>
      widget.repository.quotes(widget.supplierId, widget.request.id);

  void reload() => setState(() {
        quoteFuture = loadQuotes();
      });

  Future<void> quote(List<SupplierQuote> previous) async {
    if (!widget.request.isWithinDeadline) return;
    final latest = previous.isEmpty ? null : previous.first;
    if (latest != null &&
        !{
          SupplierQuoteStatus.submitted,
          SupplierQuoteStatus.revised,
          SupplierQuoteStatus.withdrawn
        }.contains(latest.status)) {
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => FractionallySizedBox(
        heightFactor: .96,
        child: _QuoteEditor(
          request: widget.request,
          supplierId: widget.supplierId,
          repository: widget.repository,
          latest: latest,
        ),
      ),
    );
    if (saved == true && mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      child: Column(children: [
        Text('RFQ • ${request.publicNumber}',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('Exact quantities and all requested units must match.'),
        const Divider(height: 24),
        Expanded(
            child: FutureBuilder<List<SupplierQuote>>(
          future: quoteFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const BuildToStatePanel(
                title: 'Quote history unavailable',
                message:
                    'Cannot verify current revisions. No quote can be sent until the server responds.',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final previous = snapshot.data!;
            final latest = previous.isEmpty ? null : previous.first;
            final canRevise = latest == null ||
                {
                  SupplierQuoteStatus.submitted,
                  SupplierQuoteStatus.revised,
                  SupplierQuoteStatus.withdrawn
                }.contains(latest.status);
            return ListView(children: [
              Text(
                  'Delivery site: ${request.siteCity} • PIN ${request.sitePostalCode}',
                  style: Theme.of(context).textTheme.titleMedium),
              if (request.siteNotes != null)
                Text('Site notes: ${request.siteNotes}'),
              const SizedBox(height: 12),
              const BuildToSectionHeading(title: 'Requested materials'),
              const SizedBox(height: 9),
              ...request.items.map((item) => BuildToCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.description,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('${item.quantity} ${item.unitCode}'),
                        ...item.specification.entries.map((entry) => Text(
                              '${entry.key}: ${entry.value}',
                              style: Theme.of(context).textTheme.bodySmall,
                            )),
                      ],
                    ),
                  )),
              if (request.notes != null)
                Text('Customer notes: ${request.notes}'),
              const SizedBox(height: 18),
              const BuildToSectionHeading(
                title: 'Quote revisions',
                subtitle:
                    'A customer award is not payment or order fulfillment.',
              ),
              const SizedBox(height: 8),
              if (previous.isEmpty) const Text('No quotation submitted yet.'),
              ...previous.map((quote) => BuildToCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  'Version ${quote.version} · ${quote.quoteNumber}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium)),
                          BuildToStatusChip(
                              label: quote.status.label,
                              status:
                                  quote.status == SupplierQuoteStatus.accepted
                                      ? BuildToStatus.success
                                      : quote.status ==
                                              SupplierQuoteStatus.submitted
                                          ? BuildToStatus.pending
                                          : BuildToStatus.neutral),
                        ]),
                        const SizedBox(height: 7),
                        Text(
                            'Quoted total (provisional): ${rfqMoney(quote.totalPaise)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        Text(
                            'Includes GST estimate ${rfqMoney(quote.taxPaise)} and delivery ${rfqMoney(quote.deliveryPaiseValue)}'),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              if (canRevise && request.isWithinDeadline)
                BuildToPrimaryButton(
                  label: previous.isEmpty
                      ? 'Prepare quotation'
                      : 'Revise quotation',
                  icon: Icons.edit_note_rounded,
                  onPressed: () => unawaited(quote(previous)),
                ),
              if (!request.isWithinDeadline)
                const Text(
                    'RFQ response deadline passed. New quotes are disabled.'),
            ]);
          },
        )),
      ]),
    );
  }
}

class _QuoteEditor extends StatefulWidget {
  const _QuoteEditor({
    required this.request,
    required this.supplierId,
    required this.repository,
    this.latest,
  });
  final SupplierRfq request;
  final String supplierId;
  final SupplierRfqRepository repository;
  final SupplierQuote? latest;

  @override
  State<_QuoteEditor> createState() => _QuoteEditorState();
}

class _QuoteEditorState extends State<_QuoteEditor> {
  late final List<TextEditingController> prices;
  late final List<TextEditingController> taxes;
  final delivery = TextEditingController(text: '0');
  final terms = TextEditingController();
  late final String intent = supplierQuoteIntent();
  bool saving = false;
  bool outcomeUncertain = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final last = {
      for (final line in widget.latest?.lines ?? <SupplierQuoteLine>[])
        line.rfqItemId: line,
    };
    prices = widget.request.items
        .map((item) => TextEditingController(
              text: last[item.id]?.unitPrice ?? '',
            ))
        .toList();
    taxes = widget.request.items
        .map((item) => TextEditingController(
              text: last[item.id] == null
                  ? '18'
                  : catalogPercentFromBps(last[item.id]!.taxRateBps),
            ))
        .toList();
    if (widget.latest != null) {
      delivery.text = catalogRupeesFromPaise(widget.latest!.deliveryPaiseValue);
      terms.text = widget.latest!.deliveryTerms ?? '';
    }
  }

  @override
  void dispose() {
    for (final controller in [...prices, ...taxes, delivery, terms]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (saving || outcomeUncertain) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final lines = <SupplierQuoteLineInput>[];
      for (var i = 0; i < widget.request.items.length; i++) {
        final item = widget.request.items[i];
        final price = prices[i].text.trim();
        final taxRate = catalogTaxBasisPoints(taxes[i].text.trim());
        catalogPrice(price);
        lines.add(SupplierQuoteLineInput(
          rfqItemId: item.id,
          quantity: item.quantity,
          unitCode: item.unitCode,
          unitPrice: price,
          taxRateBps: taxRate,
        ));
      }
      final freight = deliveryRupeesToPaise(delivery.text.trim());
      await widget.repository.submit(
        supplierId: widget.supplierId,
        rfq: widget.request,
        lines: lines,
        deliveryPaiseValue: freight,
        deliveryTerms: terms.text.trim().isEmpty ? null : terms.text.trim(),
        intent: intent,
      );
      if (mounted) Navigator.pop(context, true);
    } on SupplierV21Exception catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        outcomeUncertain = e.problem == SupplierV21Problem.network;
        error = switch (e.problem) {
          SupplierV21Problem.network =>
            'Submission may have committed. Close and refresh quote history before trying again.',
          SupplierV21Problem.conflict =>
            'This RFQ or quotation was revised. Refresh the invitation.',
          SupplierV21Problem.authentication ||
          SupplierV21Problem.forbidden ||
          SupplierV21Problem.notFound =>
            'Supplier access is not verified. Do not submit again.',
          _ => 'Quote was not confirmed. Check values or contact support.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'Enter valid, exact unit prices, GST percentages and freight.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 10, 20, MediaQuery.viewInsetsOf(context).bottom + 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Supplier quotation',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 5),
          const Text(
              'Every material is required. Final totals and GST are calculated by Splyzo.'),
          const Divider(height: 24),
          Expanded(
              child: ListView(children: [
            for (var i = 0; i < widget.request.items.length; i++)
              BuildToCard(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.request.items[i].description,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                      '${widget.request.items[i].quantity} ${widget.request.items[i].unitCode}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: prices[i],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Unit price excluding GST (₹)',
                      helperText: 'Exact amount, up to 4 decimals',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: taxes[i],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'GST estimate (%)',
                    ),
                  ),
                ],
              )),
            const SizedBox(height: 10),
            TextField(
              controller: delivery,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quoted delivery charge (₹)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: terms,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Delivery terms (optional)',
              ),
            ),
            const SizedBox(height: 8),
            if (error != null)
              Text(error!,
                  style: const TextStyle(color: BuildToPalette.danger)),
            const SizedBox(height: 12),
            BuildToPrimaryButton(
              label: outcomeUncertain
                  ? 'Refresh quote history first'
                  : 'Submit server-priced quotation',
              busy: saving,
              onPressed: outcomeUncertain ? null : () => unawaited(submit()),
            ),
            const SizedBox(height: 12),
            const Text(
                'Submitting another revision replaces your previous submitted version. Customer award and payment are separate steps.'),
          ])),
        ],
      ),
    );
  }
}
