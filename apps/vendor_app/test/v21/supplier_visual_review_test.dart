import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/api/supplier_v21_models.dart';
import 'package:vendor_app/v21/auth/supplier_auth_gate.dart';
import 'package:vendor_app/v21/catalog/supplier_catalog_repository.dart';
import 'package:vendor_app/v21/catalog/supplier_catalog_view.dart';
import 'package:vendor_app/v21/inventory/supplier_inventory_repository.dart';
import 'package:vendor_app/v21/inventory/supplier_inventory_view.dart';
import 'package:vendor_app/v21/orders/supplier_orders_repository.dart';
import 'package:vendor_app/v21/orders/supplier_orders_view.dart';
import 'package:vendor_app/v21/care/supplier_care_repository.dart';
import 'package:vendor_app/v21/care/supplier_care_view.dart';
import 'package:vendor_app/v21/delivery/supplier_delivery_repository.dart';
import 'package:vendor_app/v21/delivery/supplier_delivery_view.dart';
import 'package:vendor_app/v21/rfq/supplier_rfq_repository.dart';
import 'package:vendor_app/v21/rfq/supplier_rfq_view.dart';
import 'package:vendor_app/v21/finance/supplier_finance_repository.dart';
import 'package:vendor_app/v21/finance/supplier_finance_view.dart';
import 'package:vendor_app/v21/shipments/supplier_shipments_repository.dart';
import 'package:vendor_app/v21/design/buildto_theme.dart';
import 'package:vendor_app/v21/onboarding/supplier_evidence_link_sheet.dart';
import 'package:vendor_app/v21/screens/supplier_shell.dart';
import 'supplier_dashboard_widget_test.dart' as dashboard;
import 'supplier_auth_gate_test.dart' as auth;

void main() {
  testWidgets('supplier workflow screens render readable states on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final captureDir = Platform.environment['SPLYZO_CAPTURE_DIR'];
    final fontDir = Platform.environment['SPLYZO_VISUAL_FONT_DIR'];
    if (captureDir != null && fontDir != null) {
      await tester.runAsync(() async {
        final loader = FontLoader('Roboto');
        for (final font in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
          loader.addFont(Future.value(ByteData.sublistView(
              await File('$fontDir/$font').readAsBytes())));
        }
        await loader.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(Future.value(ByteData.sublistView(
            await File('$fontDir/MaterialIcons-Regular.otf').readAsBytes())));
        await icons.load();
      });
    }
    final client = SupplierV21Api(
        origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
        token: () async => 'fixture-only',
        httpClient: MockClient((request) async => http.Response(
            jsonEncode({
              'data': request.url.path.endsWith('/finance/statement')
                  ? {
                      'settlements': [],
                      'codCommissionReceivables': [],
                      'bankingReconciled': false,
                      'payoutExecutionEnabled': false,
                    }
                  : []
            }),
            200)));
    addTearDown(client.close);
    const supplier = dashboard.supplier;
    final catalog = SupplierCatalogRepository(client),
        orders = SupplierOrdersRepository(client),
        care = SupplierCareRepository(client);
    final dash = dashboard.TestDashboard();
    addTearDown(dash.api.close);
    final clerk = auth.UiClerk();
    final controller = auth.makeController(clerk);
    addTearDown(controller.dispose);
    addTearDown(clerk.state.dispose);
    final screens = <String, Widget>{
      '01-welcome': BuildToSupplierV21App(controller: controller),
      '02-dashboard': BuildToSupplierShell(
          verifiedSupplier: const SupplierV21Membership(
              supplierId: supplier, role: SupplierV21Role.owner),
          dashboardRepository: dash.repository,
          displayName: 'Supplier workspace'),
      '03-catalog': SupplierCatalogView(
          supplierId: supplier, repository: catalog, canWrite: true),
      '04-stock': SupplierInventoryView(
          supplierId: supplier,
          repository: SupplierInventoryRepository(client),
          catalog: catalog,
          canWrite: true),
      '05-orders': SupplierOrdersView(
          supplierId: supplier, repository: orders, canFulfill: true),
      '06-delivery': SupplierDeliveryView(
          supplierId: supplier,
          repository: SupplierDeliveryRepository(client),
          canWrite: true),
      '07-rfqs': SupplierRfqView(
          supplierId: supplier,
          repository: SupplierRfqRepository(client),
          canQuote: true),
      '08-finance': SupplierFinanceView(
          supplierId: supplier,
          finance: SupplierFinanceRepository(client),
          orders: orders,
          shipments: SupplierShipmentsRepository(client),
          care: care,
          canRead: true,
          canIssue: true,
          canRecordCod: true),
      '09-returns': SupplierCareView(
          supplierId: supplier,
          repository: care,
          ordersRepository: orders,
          canReceive: true),
      '10-upload':
          PrivateEvidenceLinkSheet(upload: (bytes, mime) async => supplier),
    };
    for (final screen in screens.entries) {
      final boundaryKey = GlobalKey();
      final widget = screen.key == '01-welcome'
          ? screen.value
          : MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: BuildToTheme.light(),
              home: Scaffold(body: SafeArea(child: screen.value)));
      await tester.pumpWidget(RepaintBoundary(key: boundaryKey, child: widget));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: screen.key);
      if (captureDir != null) {
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(captureDir).create(recursive: true);
          await File('$captureDir/${screen.key}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
