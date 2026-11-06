import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../api/supplier_v21_api.dart';
import '../api/supplier_v21_models.dart';
import '../business/supplier_business_view.dart';
import '../care/supplier_care_repository.dart';
import '../catalog/supplier_catalog_repository.dart';
import '../dashboard/supplier_dashboard_repository.dart';
import '../delivery/supplier_delivery_repository.dart';
import '../design/buildto_components.dart';
import '../design/buildto_theme.dart';
import '../finance/supplier_finance_repository.dart';
import '../inventory/supplier_inventory_repository.dart';
import '../onboarding/supplier_application_models.dart';
import '../onboarding/supplier_registration_wizard.dart';
import '../orders/supplier_orders_repository.dart';
import '../rfq/supplier_rfq_repository.dart';
import '../screens/supplier_shell.dart';
import '../shipments/supplier_shipments_repository.dart';

/// Explicitly compiled client showroom. No Clerk, network, production credentials,
/// payments or persistence. Reuses the production V2.1 supplier views and parsers.
class BuildToSupplierClientPreviewApp extends StatefulWidget {
  const BuildToSupplierClientPreviewApp({super.key});

  @override
  State<BuildToSupplierClientPreviewApp> createState() =>
      _BuildToSupplierClientPreviewAppState();
}

class _BuildToSupplierClientPreviewAppState
    extends State<BuildToSupplierClientPreviewApp> {
  static const supplier = '123e4567-e89b-42d3-a456-426614174000';
  static const order1 = '123e4567-e89b-42d3-a456-426614174010';
  static const order2 = '123e4567-e89b-42d3-a456-426614174011';
  static const order3 = '123e4567-e89b-42d3-a456-426614174012';
  static const warehouse = '123e4567-e89b-42d3-a456-426614174020';
  static const category = '123e4567-e89b-42d3-a456-426614174030';
  static const city = '123e4567-e89b-42d3-a456-426614174040';
  static const area = '123e4567-e89b-42d3-a456-426614174041';
  static const rfq = '123e4567-e89b-42d3-a456-426614174050';
  static const rfqItem = '123e4567-e89b-42d3-a456-426614174051';
  static const shipment = '123e4567-e89b-42d3-a456-426614174060';
  static const now = '2026-11-06T09:00:00.000Z';

  String page = 'welcome';
  bool acceptedFirstOrder = false;
  SupplierApplicationSummary? submittedApplication;

  late final SupplierV21Api api = SupplierV21Api(
    origin: Uri.parse('https://demo.invalid'),
    token: () async => 'local-ui-preview-only',
    httpClient: MockClient((request) async => _respond(request)),
  );

  @override
  void dispose() {
    api.close();
    super.dispose();
  }

  String uid(int suffix) =>
      '123e4567-e89b-42d3-a456-' + (426614174000 + suffix).toString();

  Map<String, Object?> order(String id, String status, String sku,
      String quantity, String total, int line) => {
        'id': id,
        'purchaseOrderId': uid(line + 200),
        'status': status,
        'totalPaise': total,
        'createdAt': now,
        'items': [
          {
            'id': uid(line + 100),
            'sku': sku,
            'quantity': quantity,
            'unitCode': 'BAG',
          }
        ],
      };

  List<Map<String, Object?>> get orders => [
        order(order1, acceptedFirstOrder ? 'CONFIRMED' : 'PENDING_ACCEPTANCE',
            'ULTRATECH-OPC43', '40.000', '1620000', 1),
        order(order2, 'CONFIRMED', 'ACC-CEMENT', '25.000', '980000', 2),
        order(order3, 'DELIVERED', 'DALMIA-PPC', '60.000', '2220000', 3),
      ];

  Map<String, Object?> listing(int n, String sku, String status) => {
        'id': uid(70 + n),
        'supplierId': supplier,
        'productId': uid(80 + n),
        'sku': sku,
        'unitCode': 'BAG',
        'status': status,
        'active': status == 'APPROVED',
        'version': 1,
        'packSize': '1',
        'minOrderQty': '10',
        'stepQty': '5',
        'maxOrderQty': '1000',
        'unitPrice': n == 1 ? '385.0000' : '399.0000',
        'mrpPaise': '45000',
        'taxRateBps': 1800,
        'taxInclusive': true,
        'priceTiers': [],
      };

  List<Map<String, Object?>> get listings => [
        listing(1, 'ULTRATECH-OPC43', 'APPROVED'),
        listing(2, 'ACC-CEMENT', 'APPROVED'),
        listing(3, 'DALMIA-PPC', 'PENDING'),
        listing(4, 'TMT-FE550D', 'DRAFT'),
      ];

  Map<String, Object?> get warehouseData => {
        'id': warehouse,
        'supplierId': supplier,
        'code': 'HYD-YARD-01',
        'name': 'Hyderabad Main Warehouse',
        'active': true,
      };

  Map<String, Object?> get stockBalance => {
        'id': uid(91),
        'listingId': uid(71),
        'warehouseId': warehouse,
        'onHandQty': '850.000',
        'reservedQty': '125.000',
        'availableQty': '725.000',
        'version': 4,
      };

  Map<String, Object?> get rfqData => {
        'id': rfq,
        'publicNumber': 'RFQ-2026-1048',
        'status': 'OPEN',
        'invitedAt': now,
        'createdAt': now,
        'responseDueAt': null,
        'notes': 'Bulk supply for commercial project',
        'siteSnapshot': {
          'city': 'Hyderabad',
          'postalCode': '500001',
          'siteNotes': 'Delivery to site gate B',
        },
        'items': [
          {
            'id': rfqItem,
            'description': 'OPC 43 Grade Cement',
            'quantity': '200.000',
            'unitCode': 'BAG',
            'productId': null,
            'specification': {'grade': '43'},
          }
        ],
      };

  Map<String, Object?> get statement => {
        'settlements': [
          {
            'id': uid(92),
            'supplierId': supplier,
            'settlementKey': 'NOV-2026',
            'periodStart': '2026-11-01T00:00:00.000Z',
            'periodEnd': '2026-11-06T00:00:00.000Z',
            'status': 'OPEN',
            'grossPaise': '1620000',
            'commissionPaise': '81000',
            'refundPaise': '0',
            'adjustmentPaise': '0',
            'payablePaise': '1539000',
            'payoutState': 'NOT_DISBURSED',
            'createdAt': now,
            'transfers': <Object>[],
            'lines': [
              {
                'supplierOrderId': order1,
                'grossPaise': '1620000',
                'commissionPaise': '81000',
                'refundPaise': '0',
                'adjustmentPaise': '0',
                'netPaise': '1539000',
              }
            ],
          }
        ],
        'codCommissionReceivables': <Object>[],
        'bankingReconciled': false,
        'payoutExecutionEnabled': false,
      };

  Map<String, Object?> get sampleShipment => {
        'id': shipment,
        'shipmentNumber': 'BT-SHP-1001',
        'supplierOrderId': order2,
        'supplierId': supplier,
        'warehouseId': warehouse,
        'status': 'PACKED',
        'carrierName': 'BuildTo Logistics (demo)',
        'trackingReference': 'BT-DEMO-001',
        'handoverVerified': false,
        'createdAt': now,
        'deliveredAt': null,
        'items': [
          {
            'id': uid(93),
            'orderItemId': uid(102),
            'quantity': '25.000',
            'deliveredQty': '0',
            'rejectedQty': '0',
          }
        ],
        'events': <Object>[],
      };

  http.Response ok(Object? data, {int status = 200}) => http.Response(
        jsonEncode({'data': data, 'requestId': 'local-client-demo'}),
        status,
        headers: {'content-type': 'application/json'},
      );

  http.Response _respond(http.Request request) {
    final path = request.url.path;
    if (request.method != 'GET') {
      if (path.endsWith('/accept')) {
        acceptedFirstOrder = true;
        return ok({
          'id': order1,
          'status': 'CONFIRMED',
          'replayed': false,
        });
      }
      // Client preview is deliberately read-only for financial/stock actions.
      return http.Response(
        jsonEncode({
          'error': {'code': 'PREVIEW_READ_ONLY'}
        }),
        409,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path == '/api/v2/catalog/categories') {
      return ok([
        {'id': category, 'name': 'Cement & Concrete'}
      ]);
    }
    if (path == '/api/v2/catalog/units') {
      return ok([
        {'code': 'BAG', 'name': 'Bag'}
      ]);
    }
    if (path == '/api/v2/catalog/products') {
      return ok({
        'items': [
          {
            'id': uid(81),
            'code': 'ULTRATECH-OPC43',
            'name': 'UltraTech OPC 43 Cement',
            'category': {'id': category, 'name': 'Cement & Concrete'},
            'brand': null,
            'description': '43 grade cement for construction',
          }
        ],
        'nextCursor': null,
      });
    }
    if (path == '/api/v2/delivery/cities') {
      return ok([
        {'id': city, 'name': 'Hyderabad', 'stateCode': 'TS', 'countryCode': 'IN'}
      ]);
    }
    if (path == '/api/v2/delivery/areas') {
      return ok([
        {
          'id': area,
          'cityId': city,
          'name': 'West Hyderabad',
          'postalCodes': ['500001', '500002'],
        }
      ]);
    }
    if (path.endsWith('/delivery')) {
      return ok([
        {
          'areaId': area,
          'areaName': 'West Hyderabad',
          'cityId': city,
          'active': true,
          'minimumPaise': '50000',
          'rates': [
            {
              'id': uid(94),
              'baseFeePaise': '12500',
              'handlingFeePaise': '2500',
              'freeAbovePaise': null,
            },
          ],
        },
      ]);
    }
    if (path.endsWith('/inventory/warehouses')) {
      return ok([warehouseData]);
    }
    if (path.endsWith('/inventory/balances')) {
      return ok([stockBalance]);
    }
    if (path.contains('/inventory/warehouses/') &&
        path.endsWith('/movements')) {
      return ok([]);
    }
    if (path.endsWith('/listings')) return ok(listings);
    if (path.endsWith('/orders')) return ok(orders);
    if (path.endsWith('/rfqs')) return ok([rfqData]);
    if (path.endsWith('/quotes')) return ok([]);
    if (path.endsWith('/finance/statement')) return ok(statement);
    if (path.endsWith('/finance/payouts') ||
        path.endsWith('/finance/beneficiaries') ||
        path.endsWith('/invoices') ||
        path.endsWith('/cod')) {
      return ok([]);
    }
    if (path.endsWith('/reviews/manage')) {
      return ok([
        {
          'id': uid(96),
          'customerId': uid(97),
          'supplierOrderId': order3,
          'supplierId': supplier,
          'rating': 5,
          'comment': 'On-time supply and quality materials.',
          'status': 'PUBLISHED',
          'createdAt': now,
        }
      ]);
    }
    if (path.endsWith('/returns')) return ok([]);
    if (path.endsWith('/shipments')) {
      return ok(path.contains(order2) ? [sampleShipment] : []);
    }
    return ok([]);
  }

  void navigate(String to) => setState(() => page = to);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BuildTo Supplier · Client Preview',
        theme: BuildToTheme.light(),
        debugShowCheckedModeBanner: false,
        home: switch (page) {
          'workspace' => _workspace(),
          'register' => _registration(),
          'status' => _applicationStatus(),
          'signin' => _signin(),
          _ => _welcome(),
        },
      );

  Widget _previewLabel() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: BuildToPalette.orange,
        child: const Text(
          'CLIENT UI PREVIEW  •  SAMPLE DATA  •  NO LIVE TRANSACTIONS',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: BuildToPalette.navyDeep,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _workspace() => Scaffold(
        body: Column(children: [
          _previewLabel(),
          Expanded(
            child: BuildToSupplierShell(
              verifiedSupplier: const SupplierV21Membership(
                supplierId: supplier,
                role: SupplierV21Role.owner,
              ),
              displayName: 'BuildTo Materials · Hyderabad',
              dashboardRepository: SupplierDashboardRepository(api),
              catalogRepository: SupplierCatalogRepository(api),
              inventoryRepository: SupplierInventoryRepository(api),
              deliveryRepository: SupplierDeliveryRepository(api),
              rfqRepository: SupplierRfqRepository(api),
              ordersRepository: SupplierOrdersRepository(api),
              shipmentsRepository: SupplierShipmentsRepository(api),
              careRepository: SupplierCareRepository(api),
              financeRepository: SupplierFinanceRepository(api),
              onSignOut: () => navigate('welcome'),
              onOpenApplications: () => navigate('register'),
              onRefresh: () => setState(() {}),
            ),
          ),
        ]),
      );

  Widget _welcome() => Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BuildToBrandMark(),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      BuildToPalette.navyDeep,
                      BuildToPalette.navy,
                    ]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.storefront_rounded,
                          color: BuildToPalette.orange, size: 42),
                      SizedBox(height: 18),
                      Text(
                        'One workspace.\nEvery supplier operation.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          height: 1.17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Explore the real BuildTo supplier UI using illustrative sample information.',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 19),
                _previewLabel(),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => navigate('workspace'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Explore complete supplier app'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54)),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => navigate('register'),
                  icon: const Icon(Icons.app_registration_rounded),
                  label: const Text('Preview supplier registration'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50)),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => navigate('signin'),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Preview sign-in screen'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Includes dashboard, orders & shipments, product listings, '
                  'inventory, delivery coverage, RFQs, returns, reviews, '
                  'GST invoices and finance. The preview never connects '
                  'to a backend or processes a payment.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _signin() => Scaffold(
        appBar: AppBar(title: const Text('Supplier sign in')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BuildToBrandMark(),
                const SizedBox(height: 34),
                Text('Welcome back',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Text('Sign in to manage your supplier business.'),
                const SizedBox(height: 22),
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                const TextField(
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => navigate('workspace'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: const Text('Continue to demo workspace'),
                ),
                TextButton(
                  onPressed: () => navigate('register'),
                  child: const Text('New supplier? Register your business'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Preview only: credentials are not read, sent, or stored.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: BuildToPalette.blue),
                )
              ],
            ),
          ),
        ),
      );

  Widget _registration() => Scaffold(
        appBar: AppBar(
          title: const Text('Register your business'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => navigate('welcome'),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SupplierRegistrationWizard(
              email: 'client-preview@example.com',
              cancel: () => navigate('welcome'),
              submit: (draft) async => SupplierApplicationSummary(
                id: uid(99),
                slug: draft.slug,
                legalName: draft.legalName,
                displayName: draft.displayName,
                approval: SupplierApplicationStatus.pending,
                gstRegistration: draft.gstRegistration,
                createdAt: DateTime.now().toUtc(),
                gstin: draft.gstin.isEmpty ? null : draft.gstin,
              ),
              completed: (summary) {
                submittedApplication = summary;
                navigate('status');
              },
            ),
          ),
        ),
      );

  Widget _applicationStatus() => Scaffold(
        appBar: AppBar(
          title: const Text('Supplier application'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => navigate('welcome'),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _previewLabel(),
              const SizedBox(height: 24),
              const Icon(Icons.pending_actions_rounded,
                  size: 64, color: BuildToPalette.orange),
              const SizedBox(height: 18),
              Text('Application submitted (demo)',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                (submittedApplication?.displayName ?? 'Sample supplier') +
                    ' is awaiting review. This is a simulated status; '
                        'nothing has been sent to BuildTo.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 26),
              FilledButton(
                onPressed: () => navigate('workspace'),
                child: const Text('Explore approved supplier workspace'),
              ),
              TextButton(
                onPressed: () => navigate('welcome'),
                child: const Text('Return to welcome'),
              ),
            ],
          ),
        ),
      );
}
