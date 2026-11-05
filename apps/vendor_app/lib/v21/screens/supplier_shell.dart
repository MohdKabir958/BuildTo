import 'package:flutter/material.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import '../api/supplier_v21_models.dart';
import '../dashboard/supplier_dashboard_repository.dart';
import '../dashboard/supplier_dashboard_view.dart';
import '../catalog/supplier_catalog_repository.dart';
import '../catalog/supplier_catalog_view.dart';
import '../inventory/supplier_inventory_repository.dart';
import '../inventory/supplier_inventory_view.dart';
import '../delivery/supplier_delivery_repository.dart';
import '../delivery/supplier_delivery_view.dart';

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
  const BuildToSupplierShell({
    super.key,
    this.verifiedSupplier,
    this.dashboardRepository,
    this.catalogRepository,
    this.inventoryRepository,
    this.deliveryRepository,
    this.displayName,
    this.onSwitchSupplier,
    this.onSignOut,
    this.onRefresh,
    this.onOpenApplications,
    this.canSwitchSupplier = false,
  });

  final SupplierV21Membership? verifiedSupplier;
  final SupplierDashboardRepository? dashboardRepository;
  final SupplierCatalogRepository? catalogRepository;
  final SupplierInventoryRepository? inventoryRepository;
  final SupplierDeliveryRepository? deliveryRepository;
  final String? displayName;
  final VoidCallback? onSwitchSupplier,
      onSignOut,
      onRefresh,
      onOpenApplications;
  final bool canSwitchSupplier;

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
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  narrow ? 12 : 20,
                  16,
                  narrow ? 12 : 20,
                  10,
                ),
                child: Row(
                  children: [
                    const Expanded(child: BuildToBrandMark(compact: true)),
                    const SizedBox(width: 8),
                    BuildToStatusChip(
                      label: widget.verifiedSupplier == null
                          ? 'Staging'
                          : 'Verified',
                      status: widget.verifiedSupplier == null
                          ? BuildToStatus.pending
                          : BuildToStatus.success,
                    ),
                  ],
                ),
              ),
              const Divider(),
              if (widget.verifiedSupplier != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.business_outlined,
                        size: 18,
                        color: BuildToPalette.navy,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.displayName ?? 'Supplier workspace',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Supplier • ${widget.verifiedSupplier!.supplierId.substring(widget.verifiedSupplier!.supplierId.length - 8)} · ${widget.verifiedSupplier!.role.name.toUpperCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Supplier account actions',
                        onSelected: (value) {
                          if (value == 'refresh') widget.onRefresh?.call();
                          if (value == 'switch') {
                            widget.onSwitchSupplier?.call();
                          }
                          if (value == 'signout') widget.onSignOut?.call();
                          if (value == 'applications') {
                            widget.onOpenApplications?.call();
                          }
                        },
                        itemBuilder: (context) => [
                          if (widget.onRefresh != null)
                            const PopupMenuItem(
                              value: 'refresh',
                              child: Text('Refresh permissions'),
                            ),
                          if (widget.canSwitchSupplier &&
                              widget.onSwitchSupplier != null)
                            const PopupMenuItem(
                              value: 'switch',
                              child: Text('Switch supplier'),
                            ),
                          if (widget.onOpenApplications != null)
                            const PopupMenuItem(
                              value: 'applications',
                              child: Text('Supplier applications'),
                            ),
                          if (widget.onSignOut != null)
                            const PopupMenuItem(
                              value: 'signout',
                              child: Text('Sign out'),
                            ),
                        ],
                        icon: const Icon(Icons.more_vert_rounded),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: selected.index,
                  children: [
                    if (widget.verifiedSupplier != null &&
                        widget.dashboardRepository != null)
                      SupplierDashboardView(
                        supplierId: widget.verifiedSupplier!.supplierId,
                        role: widget.verifiedSupplier!.role,
                        repository: widget.dashboardRepository!,
                        onRecheckAccess: widget.onRefresh,
                        onNavigate: (destination) => setState(() {
                          selected = switch (destination) {
                            DashboardDestination.orders =>
                              BuildToSupplierTab.orders,
                            DashboardDestination.catalog =>
                              BuildToSupplierTab.catalog,
                            DashboardDestination.stock =>
                              BuildToSupplierTab.stock,
                            DashboardDestination.more =>
                              BuildToSupplierTab.more,
                          };
                        }),
                      )
                    else
                      _HomeTab(verifiedSupplier: widget.verifiedSupplier),
                    _RestrictedTab(
                      verifiedSupplier: widget.verifiedSupplier,
                      title: 'Supplier orders',
                      subtitle:
                          'Review committed orders, prepare shipments and track handover.',
                      icon: Icons.receipt_long_outlined,
                    ),
                    if (widget.verifiedSupplier != null &&
                        widget.catalogRepository != null &&
                        selected == BuildToSupplierTab.catalog)
                      SupplierCatalogView(
                        key: ValueKey(widget.verifiedSupplier!.supplierId),
                        supplierId: widget.verifiedSupplier!.supplierId,
                        repository: widget.catalogRepository!,
                        canWrite: const {
                          SupplierV21Role.owner,
                          SupplierV21Role.manager,
                          SupplierV21Role.catalog,
                        }.contains(widget.verifiedSupplier!.role),
                        onRecheckAccess: widget.onRefresh,
                      )
                    else if (widget.verifiedSupplier != null &&
                        widget.catalogRepository != null)
                      const SizedBox.shrink()
                    else
                      _RestrictedTab(
                        verifiedSupplier: widget.verifiedSupplier,
                        title: 'Material catalog',
                        subtitle:
                            'Manage construction material listings, price tiers and approvals.',
                        icon: Icons.category_outlined,
                      ),
                    if (widget.verifiedSupplier != null &&
                        widget.inventoryRepository != null &&
                        widget.catalogRepository != null &&
                        selected == BuildToSupplierTab.stock)
                      SupplierInventoryView(
                        key: ValueKey(widget.verifiedSupplier!.supplierId),
                        supplierId: widget.verifiedSupplier!.supplierId,
                        repository: widget.inventoryRepository!,
                        catalog: widget.catalogRepository!,
                        canWrite: const {
                          SupplierV21Role.owner,
                          SupplierV21Role.manager,
                          SupplierV21Role.inventory,
                        }.contains(widget.verifiedSupplier!.role),
                        onRecheckAccess: widget.onRefresh,
                      )
                    else if (widget.verifiedSupplier != null &&
                        widget.inventoryRepository != null)
                      const SizedBox.shrink()
                    else
                      _RestrictedTab(
                        verifiedSupplier: widget.verifiedSupplier,
                        title: 'Warehouse stock',
                        subtitle:
                            'See warehouse balances, movements and controlled stock changes.',
                        icon: Icons.warehouse_outlined,
                      ),
                    if (widget.verifiedSupplier != null &&
                        widget.deliveryRepository != null &&
                        selected == BuildToSupplierTab.more)
                      SupplierDeliveryView(
                        key: ValueKey(widget.verifiedSupplier!.supplierId),
                        supplierId: widget.verifiedSupplier!.supplierId,
                        repository: widget.deliveryRepository!,
                        canWrite: const {
                          SupplierV21Role.owner,
                          SupplierV21Role.manager,
                          SupplierV21Role.fulfillment,
                        }.contains(widget.verifiedSupplier!.role),
                        onRecheckAccess: widget.onRefresh,
                      )
                    else if (widget.verifiedSupplier != null &&
                        widget.deliveryRepository != null)
                      const SizedBox.shrink()
                    else
                      _RestrictedTab(
                        verifiedSupplier: widget.verifiedSupplier,
                        onOpenApplications: widget.onOpenApplications,
                        title: 'Business workspace',
                        subtitle:
                            'RFQs, delivery areas, returns, finance and account settings.',
                        icon: Icons.business_center_outlined,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected.index,
        onDestinationSelected: (index) => setState(() {
          selected = BuildToSupplierTab.values[index];
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Catalog',
          ),
          NavigationDestination(
            icon: Icon(Icons.warehouse_outlined),
            selectedIcon: Icon(Icons.warehouse_rounded),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_rounded),
            selectedIcon: Icon(Icons.menu_open_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({this.verifiedSupplier});
  final SupplierV21Membership? verifiedSupplier;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            'Your supplier workspace',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Construction materials, managed with confidence.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  BuildToPalette.navyDeep,
                  BuildToPalette.navy,
                  Color(0xFF07528B),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      color: BuildToPalette.orange,
                      size: 21,
                    ),
                    SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        'BUILDTO SUPPLIER',
                        style: TextStyle(
                          color: BuildToPalette.white,
                          letterSpacing: 1.4,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  'A better way to\nrun your material business.',
                  style: TextStyle(
                    color: BuildToPalette.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.16,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Listings • Inventory • Orders • Fulfillment',
                  style: TextStyle(
                    color: Color(0xFFE2F1FF),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: BuildToPalette.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: BuildToPalette.white.withValues(alpha: .28),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: BuildToPalette.white,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          verifiedSupplier == null
                              ? 'Secure account access coming in S02'
                              : 'Supplier identity verified by BuildTo',
                          style: const TextStyle(
                            color: BuildToPalette.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const BuildToSectionHeading(
            title: 'Manage your business',
            subtitle:
                'Each workspace connects to your own authorized supplier account.',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 360 ? 1 : 2;
              return GridView.count(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: columns == 1 ? 2.35 : 1.33,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: const [
                  _ActionTile(
                    icon: Icons.receipt_long_rounded,
                    title: 'Orders',
                    subtitle: 'Fulfillment queue',
                    accent: BuildToPalette.orange,
                  ),
                  _ActionTile(
                    icon: Icons.inventory_2_outlined,
                    title: 'Listings',
                    subtitle: 'Products & pricing',
                    accent: BuildToPalette.blue,
                  ),
                  _ActionTile(
                    icon: Icons.warehouse_outlined,
                    title: 'Inventory',
                    subtitle: 'Warehouses & stock',
                    accent: BuildToPalette.success,
                  ),
                  _ActionTile(
                    icon: Icons.request_quote_outlined,
                    title: 'RFQs',
                    subtitle: 'Quotes & requests',
                    accent: BuildToPalette.navy,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          BuildToStatePanel(
            icon: verifiedSupplier == null
                ? Icons.shield_outlined
                : Icons.verified_user_outlined,
            title: verifiedSupplier == null
                ? 'Account connection required'
                : 'Supplier access verified',
            message: verifiedSupplier == null
                ? 'This is the S01 design foundation. Clerk sign-in and your live supplier dashboard will be enabled in the next PR. No sample business figures are displayed.'
                : 'Your active supplier membership was checked with the BuildTo backend. '
                    'Catalog, order, inventory and finance screens activate in their dedicated PRs; '
                    'no sample business figures are shown.',
          ),
        ],
      );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) => BuildToCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: accent, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}

class _RestrictedTab extends StatelessWidget {
  const _RestrictedTab({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.verifiedSupplier,
    this.onOpenApplications,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final SupplierV21Membership? verifiedSupplier;
  final VoidCallback? onOpenApplications;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
        children: [
          BuildToSectionHeading(title: title, subtitle: subtitle),
          const SizedBox(height: 22),
          if (onOpenApplications != null && verifiedSupplier != null) ...[
            BuildToPrimaryButton(
              label: 'Supplier applications',
              icon: Icons.fact_check_outlined,
              onPressed: onOpenApplications,
            ),
            const SizedBox(height: 16),
          ],
          BuildToStatePanel(
            title: verifiedSupplier == null
                ? 'Secure workspace'
                : 'Supplier access verified',
            message: verifiedSupplier == null
                ? 'Sign in with an approved supplier account to view real data. Clerk authentication and supplier permissions are scheduled for S02.'
                : 'You have an active, backend-verified ${verifiedSupplier!.role.name.toUpperCase()} membership. This feature will connect to real data in its dedicated PR.',
            icon: icon,
          ),
        ],
      );
}
