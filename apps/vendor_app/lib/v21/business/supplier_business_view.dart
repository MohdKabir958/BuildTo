import 'package:flutter/material.dart';
import '../api/supplier_v21_models.dart';
import '../delivery/supplier_delivery_repository.dart';
import '../delivery/supplier_delivery_view.dart';
import '../rfq/supplier_rfq_repository.dart';
import '../rfq/supplier_rfq_view.dart';
import '../design/buildto_theme.dart';

/// Two independent business workspaces sharing a verified supplier identity.
/// Role gates mirror backend permissions; every request is still authorized
/// afresh by the V2.1 server.
class SupplierBusinessView extends StatefulWidget {
  const SupplierBusinessView({
    super.key,
    required this.supplierId,
    required this.role,
    required this.delivery,
    required this.rfqs,
    this.onRecheckAccess,
  });

  final String supplierId;
  final SupplierV21Role role;
  final SupplierDeliveryRepository delivery;
  final SupplierRfqRepository rfqs;
  final VoidCallback? onRecheckAccess;

  @override
  State<SupplierBusinessView> createState() => _SupplierBusinessViewState();
}

class _SupplierBusinessViewState extends State<SupplierBusinessView> {
  int section = 0;

  @override
  void didUpdateWidget(SupplierBusinessView old) {
    super.didUpdateWidget(old);
    if (old.supplierId != widget.supplierId || old.role != widget.role) {
      section = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManageDelivery = {
      SupplierV21Role.owner,
      SupplierV21Role.manager,
      SupplierV21Role.fulfillment,
    }.contains(widget.role);
    final canQuote = {
      SupplierV21Role.owner,
      SupplierV21Role.manager,
      SupplierV21Role.catalog,
    }.contains(widget.role);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ChoiceChip(
              avatar: const Icon(Icons.local_shipping_outlined, size: 17),
              selectedColor: BuildToPalette.sky,
              label: const Text('Delivery areas'),
              selected: section == 0,
              onSelected: (_) => setState(() => section = 0),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.request_quote_outlined, size: 17),
              selectedColor: BuildToPalette.sky,
              label: const Text('RFQs & quotes'),
              selected: section == 1,
              onSelected: (_) => setState(() => section = 1),
            ),
          ],
        ),
      ),
      Expanded(child: section == 0
          ? SupplierDeliveryView(
              key: ValueKey('delivery-${widget.supplierId}'),
              supplierId: widget.supplierId,
              repository: widget.delivery,
              canWrite: canManageDelivery,
              onRecheckAccess: widget.onRecheckAccess,
            )
          : SupplierRfqView(
              key: ValueKey('rfq-${widget.supplierId}'),
              supplierId: widget.supplierId,
              repository: widget.rfqs,
              canQuote: canQuote,
              onRecheckAccess: widget.onRecheckAccess,
            )),
    ]);
  }
}
