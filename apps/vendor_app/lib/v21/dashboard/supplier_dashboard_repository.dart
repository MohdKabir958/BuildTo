import '../api/supplier_v21_api.dart';
import '../api/supplier_v21_models.dart';
import 'supplier_dashboard_models.dart';

/// Composes the EXISTING authenticated supplier-owned V2.1 GET endpoints.
/// The backend enforces active membership on every read. No new server
/// endpoint, financial calculation, local cache or legacy restaurant API.
class SupplierDashboardRepository {
  const SupplierDashboardRepository(this.client);

  final SupplierV21Api client;

  Future<SupplierDashboardSnapshot> load({
    required String supplierId,
    required SupplierV21Role role,
  }) async {
    if (!RegExp(
      r'^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$',
    ).hasMatch(supplierId)) {
      throw const FormatException('Invalid verified supplier ID');
    }
    final base = '/api/v2/suppliers/$supplierId';
    // RFQ_QUOTE is not granted to INVENTORY, FULFILLMENT, FINANCE or VIEWER.
    final canReadInvitations = {
      SupplierV21Role.owner,
      SupplierV21Role.manager,
      SupplierV21Role.catalog,
    }.contains(role);
    final responses = await Future.wait([
      client.get('$base/orders'),
      client.get('$base/listings'),
      client.get('$base/inventory/warehouses'),
      if (canReadInvitations) client.get('$base/rfqs'),
    ]);

    final orders = dashboardRecords(
      responses[0].data, DashboardOrder.fromJson,
      (DashboardOrder order) => order.id,
    );
    final listings = dashboardRecords(
      responses[1].data,
      (value) => DashboardListing.fromJson(value, supplierId),
      (DashboardListing listing) => listing.id,
    );
    final warehouses = dashboardRecords(
      responses[2].data,
      (value) => DashboardWarehouse.fromJson(value, supplierId),
      (DashboardWarehouse warehouse) => warehouse.id,
    );
    final invitations = canReadInvitations
        ? dashboardRecords(
            responses[3].data,
            DashboardInvitation.fromJson,
            (DashboardInvitation invitation) => invitation.id,
          )
        : null;

    final orderLimit = orders.length == 100;
    final listingLimit = listings.length == 100;
    final warehouseLimit = warehouses.length == 100;
    return SupplierDashboardSnapshot(
      supplierId: supplierId,
      refreshedAt: DateTime.now().toUtc(),
      awaitingAcceptance: DashboardCount(
        orders.where((order) =>
            order.status == DashboardOrderStatus.pendingAcceptance).length,
        bounded: orderLimit,
      ),
      inFulfillment: DashboardCount(
        orders.where((order) => order.status.fulfillmentInProgress).length,
        bounded: orderLimit,
      ),
      publishedListings: DashboardCount(
        listings.where((listing) => listing.published).length,
        bounded: listingLimit,
      ),
      activeWarehouses: DashboardCount(
        warehouses.where((warehouse) => warehouse.active).length,
        bounded: warehouseLimit,
      ),
      openInvitations: invitations == null
          ? null
          : DashboardCount(invitations.length, bounded: invitations.length == 100),
      recentOrders: List.unmodifiable(orders.take(5)),
    );
  }
}
