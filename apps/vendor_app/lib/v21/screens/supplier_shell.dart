import 'package:flutter/material.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';

/// S01 visual shell. It does not activate the legacy restaurant APIs or
/// represent unauthenticated fixture values as live supplier data.
/// S02 will replace this access gate with verified Clerk + V2.1 membership.
class BuildToSupplierPreviewApp extends StatelessWidget {
  const BuildToSupplierPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BuildTo Supplier',
    debugShowCheckedModeBanner: false,
    theme: BuildToTheme.light(),
    home: const BuildToSupplierShell(),
  );
}

enum BuildToSupplierTab { home, orders, catalog, stock, more }

class BuildToSupplierShell extends StatefulWidget {
  const BuildToSupplierShell({super.key});

  @override
  State<BuildToSupplierShell> createState() => _BuildToSupplierShellState();
}

class _BuildToSupplierShellState extends State<BuildToSupplierShell> {
  BuildToSupplierTab selected = BuildToSupplierTab.home;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 350;
    return Scaffold(
      body: SafeArea(
        child: BuildToPageWidth(
          child: Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(narrow ? 12 : 20, 16, narrow ? 12 : 20, 10),
              child: Row(children: [
                const Expanded(child: BuildToBrandMark(compact: true)),
                const SizedBox(width: 8),
                const BuildToStatusChip(label: 'Staging', status: BuildToStatus.pending),
              ]),
            ),
            const Divider(),
            Expanded(child: IndexedStack(index: selected.index, children: const [
              _HomeTab(),
              _RestrictedTab(
                title: 'Supplier orders',
                subtitle: 'Review committed orders, prepare shipments and track handover.',
                icon: Icons.receipt_long_outlined,
              ),
              _RestrictedTab(
                title: 'Material catalog',
                subtitle: 'Manage construction material listings, price tiers and approvals.',
                icon: Icons.category_outlined,
              ),
              _RestrictedTab(
                title: 'Warehouse stock',
                subtitle: 'See warehouse balances, movements and controlled stock changes.',
                icon: Icons.warehouse_outlined,
              ),
              _RestrictedTab(
                title: 'Business workspace',
                subtitle: 'RFQs, delivery areas, returns, finance and account settings.',
                icon: Icons.business_center_outlined,
              ),
            ])),
          ]),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected.index,
        onDestinationSelected: (index) => setState(() {
          selected = BuildToSupplierTab.values[index];
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Catalog'),
          NavigationDestination(icon: Icon(Icons.warehouse_outlined), selectedIcon: Icon(Icons.warehouse_rounded), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.menu_rounded), selectedIcon: Icon(Icons.menu_open_rounded), label: 'More'),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
    children: [
      Text('Your supplier workspace', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 6),
      Text('Construction materials, managed with confidence.',
        style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 20),
      Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [BuildToPalette.navyDeep, BuildToPalette.navy, Color(0xFF07528B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.verified_outlined, color: BuildToPalette.orange, size: 21),
            SizedBox(width: 9),
            Flexible(child: Text('BUILDTO SUPPLIER',
              style: TextStyle(color: BuildToPalette.white, letterSpacing: 1.4, fontSize: 11, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 22),
          const Text('A better way to\nrun your material business.',
            style: TextStyle(color: BuildToPalette.white, fontSize: 25, fontWeight: FontWeight.w800, height: 1.16)),
          const SizedBox(height: 12),
          const Text('Listings • Inventory • Orders • Fulfillment',
            style: TextStyle(color: Color(0xFFE2F1FF), fontSize: 12, height: 1.5)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: BuildToPalette.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: BuildToPalette.white.withValues(alpha: .28)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: BuildToPalette.white),
              SizedBox(width: 7),
              Flexible(child: Text('Secure account access coming in S02',
                style: TextStyle(color: BuildToPalette.white, fontSize: 12, fontWeight: FontWeight.w600))),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 24),
      const BuildToSectionHeading(
        title: 'Manage your business',
        subtitle: 'Each workspace connects to your own authorized supplier account.',
      ),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth < 360 ? 1 : 2;
        return GridView.count(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 2.35 : 1.33,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            _ActionTile(icon: Icons.receipt_long_rounded, title: 'Orders', subtitle: 'Fulfillment queue', accent: BuildToPalette.orange),
            _ActionTile(icon: Icons.inventory_2_outlined, title: 'Listings', subtitle: 'Products & pricing', accent: BuildToPalette.blue),
            _ActionTile(icon: Icons.warehouse_outlined, title: 'Inventory', subtitle: 'Warehouses & stock', accent: BuildToPalette.success),
            _ActionTile(icon: Icons.request_quote_outlined, title: 'RFQs', subtitle: 'Quotes & requests', accent: BuildToPalette.navy),
          ],
        );
      }),
      const SizedBox(height: 22),
      const BuildToStatePanel(
        icon: Icons.shield_outlined,
        title: 'Account connection required',
        message: 'This is the S01 design foundation. Clerk sign-in and your live supplier dashboard will be enabled in the next PR. No sample business figures are displayed.',
      ),
    ],
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.accent});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) => BuildToCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, color: accent, size: 24),
      ),
      const SizedBox(height: 12),
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 3),
      Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
    ]),
  );
}

class _RestrictedTab extends StatelessWidget {
  const _RestrictedTab({required this.title, required this.subtitle, required this.icon});
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
    children: [
      BuildToSectionHeading(title: title, subtitle: subtitle),
      const SizedBox(height: 22),
      BuildToStatePanel(
        title: 'Secure workspace',
        message: 'Sign in with an approved supplier account to view real data. Clerk authentication and supplier permissions are scheduled for S02.',
        icon: icon,
      ),
    ],
  );
}
