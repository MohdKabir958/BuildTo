import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/buildto_components.dart';
import '../design/buildto_tokens.dart';

enum SupplierTab { home, orders, catalog, stock, more }

extension SupplierTabLabel on SupplierTab {
  String get label => switch (this) {
    SupplierTab.home => 'Home',
    SupplierTab.orders => 'Orders',
    SupplierTab.catalog => 'Catalog',
    SupplierTab.stock => 'Stock',
    SupplierTab.more => 'More',
  };
  IconData get icon => switch (this) {
    SupplierTab.home => Icons.home_outlined,
    SupplierTab.orders => Icons.inventory_2_outlined,
    SupplierTab.catalog => Icons.category_outlined,
    SupplierTab.stock => Icons.warehouse_outlined,
    SupplierTab.more => Icons.grid_view_rounded,
  };
  IconData get activeIcon => switch (this) {
    SupplierTab.home => Icons.home_rounded,
    SupplierTab.orders => Icons.inventory_2_rounded,
    SupplierTab.catalog => Icons.category_rounded,
    SupplierTab.stock => Icons.warehouse_rounded,
    SupplierTab.more => Icons.grid_view_rounded,
  };
}

/// A functional, honest navigation shell demonstrating the approved BuildTo
/// visual system. All supplier data stays unloaded until Clerk + V2.1 RBAC is
/// wired in S02. No fake orders, earnings, stock values, or mutation buttons.
class SupplierShell extends StatefulWidget {
  const SupplierShell({super.key});

  @override
  State<SupplierShell> createState() => _SupplierShellState();
}

class _SupplierShellState extends State<SupplierShell> {
  SupplierTab _selected = SupplierTab.home;

  void _select(SupplierTab tab) {
    if (_selected != tab) setState(() => _selected = tab);
  }

  void _about() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BuildtoWordmark(),
              const SizedBox(height: 24),
              Text('Supplier workspace preview',
                style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 9),
              Text(
                'This S01 build demonstrates the approved BuildTo design system. '
                'Live supplier accounts and orders stay unavailable until '
                'Clerk identity and database authorization are implemented in S02.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              const BuildtoStatusPill(
                label: 'No demo business data',
                tone: BuildtoTone.information,
                icon: Icons.verified_user_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: BuildtoPalette.white,
      systemNavigationBarColor: BuildtoPalette.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
    child: PopScope(
      canPop: _selected == SupplierTab.home,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _select(SupplierTab.home);
      },
      child: Scaffold(
        body: Column(
          children: [
            _ShellHeader(onAbout: _about),
            Expanded(
              child: IndexedStack(
                index: _selected.index,
                children: [
                  _HomePage(onSelect: _select, onAbout: _about),
                  const _ModulePage(
                    tab: SupplierTab.orders,
                    eyebrow: 'FULFILLMENT',
                    title: 'Your orders',
                    subtitle: 'Every committed material order, clear and actionable.',
                    icon: Icons.local_shipping_outlined,
                    deliveryPr: 'S09–S10',
                    features: [
                      ('Accept only valid orders', Icons.check_circle_outline),
                      ('Pack and dispatch by shipment', Icons.inventory_2_outlined),
                      ('Confirm handover with customer OTP', Icons.shield_outlined),
                    ],
                  ),
                  const _ModulePage(
                    tab: SupplierTab.catalog,
                    eyebrow: 'PRODUCTS',
                    title: 'Material catalog',
                    subtitle: 'Professional listings with transparent pricing and approvals.',
                    icon: Icons.layers_outlined,
                    deliveryPr: 'S05',
                    features: [
                      ('Your listings and review status', Icons.verified_outlined),
                      ('Price tiers and order quantities', Icons.price_change_outlined),
                      ('Material categories and specifications', Icons.category_outlined),
                    ],
                  ),
                  const _ModulePage(
                    tab: SupplierTab.stock,
                    eyebrow: 'WAREHOUSING',
                    title: 'Stock control',
                    subtitle: 'Keep inventory exact across every approved warehouse.',
                    icon: Icons.warehouse_outlined,
                    deliveryPr: 'S06',
                    features: [
                      ('Stock balance per warehouse', Icons.view_list_outlined),
                      ('Audited quantity adjustments', Icons.tune_outlined),
                      ('Warehouse transfers and history', Icons.swap_horiz_rounded),
                    ],
                  ),
                  _MorePage(onAbout: _about),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _SupplierBottomNavigation(
          selected: _selected, onSelected: _select,
        ),
      ),
    ),
  );
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({required this.onAbout});
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) => Material(
    color: BuildtoPalette.white,
    child: SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: BuildtoPalette.borderLight)),
        ),
        child: BuildtoContent(
          child: Row(
            children: [
              const Expanded(child: Align(
                alignment: Alignment.centerLeft,
                child: BuildtoWordmark(compact: true),
              )),
              IconButton(
                key: const Key('about-preview'),
                tooltip: 'About this preview',
                onPressed: onAbout,
                icon: const Icon(Icons.info_outline_rounded),
                color: BuildtoPalette.navy,
                iconSize: 23,
                constraints: const BoxConstraints(
                  minWidth: BuildtoSpace.minTouch,
                  minHeight: BuildtoSpace.minTouch),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SupplierBottomNavigation extends StatelessWidget {
  const _SupplierBottomNavigation({
    required this.selected, required this.onSelected,
  });
  final SupplierTab selected;
  final ValueChanged<SupplierTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BuildtoPalette.white,
      elevation: 6,
      shadowColor: BuildtoPalette.navy.withValues(alpha: .12),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: BuildtoPalette.border)),
          ),
          padding: const EdgeInsets.fromLTRB(6, 7, 6, 4),
          child: Row(
            children: [
              for (final tab in SupplierTab.values)
                Expanded(
                  child: Semantics(
                    selected: tab == selected,
                    button: true,
                    label: tab.label + ' tab',
                    child: InkWell(
                      key: Key('tab-' + tab.name),
                      onTap: () => onSelected(tab),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tab == selected ? tab.activeIcon : tab.icon,
                              size: 22,
                              color: tab == selected
                                ? BuildtoPalette.amber : BuildtoPalette.navy,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tab.label,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: tab == selected
                                    ? FontWeight.w800 : FontWeight.w600,
                                color: tab == selected
                                    ? BuildtoPalette.caution : BuildtoPalette.navy,
                              ),
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
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.onSelect, required this.onAbout});
  final ValueChanged<SupplierTab> onSelect;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _ScrollableContent(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const BuildtoStatusPill(
          label: 'V2.1 WORKSPACE PREVIEW',
          tone: BuildtoTone.information,
          icon: Icons.auto_awesome_outlined,
        ),
        const SizedBox(height: 15),
        Text('Your business, in command.',
          style: text.headlineSmall),
        const SizedBox(height: 7),
        Text(
          'A focused home for material suppliers — designed to make '
          'every working day simpler.',
          style: text.bodyMedium?.copyWith(color: BuildtoPalette.muted),
        ),
        const SizedBox(height: 21),
        _FeatureHero(onExplore: () => onSelect(SupplierTab.orders)),
        const SizedBox(height: 28),
        const BuildtoSectionHeading(
          title: 'Your workspace',
          subtitle: 'Everything you need, organized around the job.',
        ),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final cols = width >= 570 ? 3 : 2;
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final extent = scale > 1.18 ? 287.0 : width < 340 ? 254.0 : 236.0;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: extent,
              children: [
                BuildtoActionTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Orders',
                  subtitle: 'Accept, prepare and fulfill.',
                  onTap: () => onSelect(SupplierTab.orders),
                ),
                BuildtoActionTile(
                  icon: Icons.layers_outlined,
                  title: 'Catalog',
                  subtitle: 'List and price materials.',
                  onTap: () => onSelect(SupplierTab.catalog),
                  accent: BuildtoPalette.navyBright,
                ),
                BuildtoActionTile(
                  icon: Icons.warehouse_outlined,
                  title: 'Inventory',
                  subtitle: 'Track accurate stock.',
                  onTap: () => onSelect(SupplierTab.stock),
                  accent: BuildtoPalette.success,
                ),
                BuildtoActionTile(
                  icon: Icons.request_quote_outlined,
                  title: 'RFQs',
                  subtitle: 'Prepare supplier quotations.',
                  onTap: () => onSelect(SupplierTab.more),
                  accent: BuildtoPalette.caution,
                ),
                BuildtoActionTile(
                  icon: Icons.map_outlined,
                  title: 'Service areas',
                  subtitle: 'Control approved coverage.',
                  onTap: () => onSelect(SupplierTab.more),
                ),
                BuildtoActionTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Finance',
                  subtitle: 'Review true payout status.',
                  onTap: () => onSelect(SupplierTab.more),
                  accent: BuildtoPalette.navyBright,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 25),
        const BuildtoSectionHeading(title: 'Connected the right way'),
        const SizedBox(height: 13),
        BuildtoPanel(
          background: BuildtoPalette.paleBlue,
          border: const Color(0xFFCDE7FC),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.shield_outlined,
              size: 24, color: BuildtoPalette.navy),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Security before data',
                  style: text.titleMedium),
                const SizedBox(height: 5),
                Text(
                  'Real orders, stock and financial values remain hidden '
                  'until your Clerk session and supplier permissions are '
                  'verified by BuildTo V2.1.',
                  style: text.bodySmall?.copyWith(color: BuildtoPalette.navy),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onAbout,
                  child: const Text('About this preview'),
                ),
              ],
            )),
          ]),
        ),
        const SizedBox(height: 25),
      ]),
    );
  }
}

class _FeatureHero extends StatelessWidget {
  const _FeatureHero({required this.onExplore});
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [BuildtoPalette.navyDeep,
                   BuildtoPalette.navy,
                   BuildtoPalette.navyBright],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        const Positioned(
          right: -23, top: 4, bottom: -12,
          child: IgnorePointer(
            child: SizedBox(width: 184,
              child: CustomPaint(painter: _ConstructionHeroPainter())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 23),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.construction_rounded,
                  color: BuildtoPalette.amber, size: 17),
                SizedBox(width: 7),
                Text('BUILT FOR SUPPLIERS', style: TextStyle(
                  color: Color(0xFFFFD991), fontSize: 11,
                  letterSpacing: 1.25, fontWeight: FontWeight.w800,
                )),
              ]),
              const SizedBox(height: 13),
              const Text(
                'Build better.\nDeliver smarter.',
                style: TextStyle(
                  color: Colors.white, fontSize: 27,
                  fontWeight: FontWeight.w900, height: 1.17,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 11),
              const ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 246),
                child: Text(
                  'One place for materials, orders and delivery.',
                  style: TextStyle(
                    color: Color(0xFFE5F0FB), fontSize: 13.5,
                    height: 1.45, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 22),
              TextButton.icon(
                key: const Key('explore-orders'),
                onPressed: onExplore,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: BuildtoPalette.navy,
                  minimumSize: const Size(48, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('Explore workspace'),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _ConstructionHeroPainter extends CustomPainter {
  const _ConstructionHeroPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .09)
      ..strokeWidth = 1;
    final block = Paint()..color = Colors.white.withValues(alpha: .13);
    final blockBright = Paint()..color = Colors.white.withValues(alpha: .20);
    final orange = Paint()..color = BuildtoPalette.amber.withValues(alpha: .83);

    for (var i = 0; i < 7; i++) {
      canvas.drawLine(Offset(size.width * i / 6, size.height),
        Offset(size.width * i / 6, 0), grid);
    }
    for (var i = 1; i < 9; i++) {
      final y = size.height * i / 9;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    canvas.drawRect(Rect.fromLTWH(45, size.height * .39, 65,
      size.height * .61), block);
    canvas.drawRect(Rect.fromLTWH(109, size.height * .18, 55,
      size.height * .82), blockBright);
    canvas.drawRect(Rect.fromLTWH(3, size.height * .63, 45,
      size.height * .37), blockBright);

    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 6; j++) {
        canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(116 + i * 12.0, size.height * .25 + j * 29.0,
            6, 14), const Radius.circular(1)), block);
      }
    }
    // Crane beam with warm amber detail, referring to the PDF construction hero.
    canvas.drawRect(Rect.fromLTWH(75, 19, 5, 96), orange);
    canvas.drawRect(Rect.fromLTWH(40, 23, 130, 5), orange);
    canvas.drawLine(const Offset(80, 23),
      const Offset(116, 5), orange..strokeWidth = 2);
    canvas.drawLine(const Offset(152, 25),
      const Offset(152, 93), orange..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _ConstructionHeroPainter oldDelegate) => false;
}

class _ModulePage extends StatelessWidget {
  const _ModulePage({
    required this.tab, required this.eyebrow,
    required this.title, required this.subtitle,
    required this.icon, required this.deliveryPr, required this.features,
  });
  final SupplierTab tab;
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final String deliveryPr;
  final List<(String, IconData)> features;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _ScrollableContent(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const BuildtoStatusPill(
          label: 'DESIGN PREVIEW',
          tone: BuildtoTone.information,
        ),
        const SizedBox(height: 20),
        Text(eyebrow, style: const TextStyle(
          color: BuildtoPalette.caution, fontWeight: FontWeight.w800,
          fontSize: 11, letterSpacing: 1.5)),
        const SizedBox(height: 7),
        Text(title, style: text.headlineSmall),
        const SizedBox(height: 8),
        Text(subtitle, style: text.bodyMedium?.copyWith(
          color: BuildtoPalette.muted)),
        const SizedBox(height: 24),
        BuildtoStatePanel(
          icon: icon,
          title: 'Ready for the next phase',
          message: 'Live ' + tab.label.toLowerCase() +
            ' are not loaded in S01. '
            'Sign-in and supplier-scoped data begin after S02.',
          tone: BuildtoTone.information,
        ),
        const SizedBox(height: 26),
        BuildtoSectionHeading(
          title: 'Planned capabilities',
          subtitle: 'Scheduled for ' + deliveryPr,
        ),
        const SizedBox(height: 12),
        BuildtoPanel(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
          child: Column(children: [
            for (var i = 0; i < features.length; i++) ...[
              if (i > 0) const Divider(
                color: BuildtoPalette.borderLight, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(children: [
                  Icon(features[i].$2, size: 23,
                    color: BuildtoPalette.navy),
                  const SizedBox(width: 13),
                  Expanded(child: Text(features[i].$1,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600))),
                  const Icon(Icons.schedule_outlined, size: 18,
                    color: BuildtoPalette.muted),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 26),
      ]),
    );
  }
}

class _MorePage extends StatelessWidget {
  const _MorePage({required this.onAbout});
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final modules = <(IconData, String, String)>[
      (Icons.request_quote_outlined, 'RFQs & quotations',
       'Invitations and versioned quotes · S08'),
      (Icons.local_shipping_outlined, 'Delivery coverage',
       'Approved service areas and flat fees · S07'),
      (Icons.assignment_return_outlined, 'Returns & feedback',
       'Physical receipt and reviews · S11'),
      (Icons.account_balance_wallet_outlined, 'Finance & GST',
       'Invoices, COD, statements and payouts · S12'),
      (Icons.person_outline_rounded, 'Business profile',
       'Clerk, approval and permissions · S02–S03'),
    ];
    return _ScrollableContent(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('More', style: text.headlineSmall),
        const SizedBox(height: 7),
        Text('Your business tools in one place.',
          style: text.bodyMedium?.copyWith(color: BuildtoPalette.muted)),
        const SizedBox(height: 20),
        const BuildtoSectionHeading(title: 'Workspace'),
        const SizedBox(height: 13),
        BuildtoPanel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < modules.length; i++) ...[
              if (i > 0) const Divider(
                indent: 16, endIndent: 16,
                height: 1, color: BuildtoPalette.borderLight),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: Key('more-' + i.toString()),
                  onTap: onAbout,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(children: [
                      Container(
                        height: 43, width: 43,
                        decoration: BoxDecoration(
                          color: BuildtoPalette.paleBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(modules[i].$1, color: BuildtoPalette.navy),
                      ),
                      const SizedBox(width: 13),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(modules[i].$2, style: text.titleMedium),
                          const SizedBox(height: 3),
                          Text(modules[i].$3, style: text.bodySmall),
                        ],
                      )),
                      const Icon(Icons.chevron_right_rounded,
                        color: BuildtoPalette.navy, size: 22),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 22),
        const BuildtoStatusPill(
          label: 'PREVIEW • NO LIVE USER DATA',
          tone: BuildtoTone.information,
        ),
        const SizedBox(height: 26),
      ]),
    );
  }
}

class _ScrollableContent extends StatelessWidget {
  const _ScrollableContent({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scrollbar(
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(
        horizontal: BuildtoSpace.pageGutter, vertical: 24),
      child: BuildtoContent(child: child),
    ),
  );
}
