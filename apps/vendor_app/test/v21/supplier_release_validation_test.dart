import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/api/supplier_v21_models.dart';
import 'package:vendor_app/v21/business/supplier_business_view.dart';
import 'package:vendor_app/v21/care/supplier_care_repository.dart';
import 'package:vendor_app/v21/delivery/supplier_delivery_repository.dart';
import 'package:vendor_app/v21/finance/supplier_finance_repository.dart';
import 'package:vendor_app/v21/orders/supplier_orders_repository.dart';
import 'package:vendor_app/v21/rfq/supplier_rfq_repository.dart';
import 'package:vendor_app/v21/shipments/supplier_shipments_repository.dart';
import 'package:vendor_app/v21/design/buildto_theme.dart';

const supplier = '123e4567-e89b-42d3-a456-426614174000';
const second = '123e4567-e89b-42d3-a456-426614174001';

Object fixture(String path) => path.endsWith('/finance/statement')
    ? <String, Object?>{
        'settlements': <Object>[],
        'codCommissionReceivables': <Object>[],
        'bankingReconciled': false,
        'payoutExecutionEnabled': false,
      }
    : <Object>[];

SupplierV21Api api(List<String> requests) => SupplierV21Api(
      origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
      token: () async => 'verified-test-session',
      httpClient: MockClient((request) async {
        requests.add(request.url.path);
        expect(
            request.headers['Authorization'], 'Bearer verified-test-session');
        return http.Response(
            jsonEncode({'data': fixture(request.url.path)}), 200);
      }),
    );

SupplierBusinessView workspace(SupplierV21Api client, SupplierV21Role role,
        {String supplierId = supplier}) =>
    SupplierBusinessView(
      supplierId: supplierId,
      role: role,
      delivery: SupplierDeliveryRepository(client),
      rfqs: SupplierRfqRepository(client),
      orders: SupplierOrdersRepository(client),
      care: SupplierCareRepository(client),
      finance: SupplierFinanceRepository(client),
      shipments: SupplierShipmentsRepository(client),
    );

void main() {
  testWidgets('viewer has no finance navigation or finance API calls',
      (tester) async {
    final calls = <String>[];
    final client = api(calls);
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(
        theme: BuildToTheme.light(),
        home: Scaffold(body: workspace(client, SupplierV21Role.viewer))));
    await tester.pumpAndSettle();
    expect(find.text('Finance & GST'), findsNothing);
    expect(calls.where((p) => p.contains('/finance/')), isEmpty);
    expect(calls.where((p) => p.endsWith('/invoices')), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finance role sees honest provider-only evidence across devices',
      (tester) async {
    final calls = <String>[];
    final client = api(calls);
    addTearDown(client.close);
    for (final size in [
      const Size(320, 800),
      const Size(360, 800),
      const Size(393, 852),
      const Size(412, 915),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
          theme: BuildToTheme.light(),
          home: Scaffold(body: workspace(client, SupplierV21Role.finance))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finance & GST'));
      await tester.pumpAndSettle();
      expect(find.text('Clear cash. Clear accountability.'), findsOneWidget);
      expect(find.textContaining('Payout intent'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
      await tester.pumpWidget(const SizedBox.shrink());
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    expect(calls.any((p) => p.endsWith('/finance/statement')), isTrue);
    expect(calls.any((p) => p.endsWith('/finance/payouts')), isTrue);
  });

  testWidgets('switching suppliers reloads finance from new supplier ID',
      (tester) async {
    final calls = <String>[];
    final client = api(calls);
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: workspace(client, SupplierV21Role.finance))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finance & GST'));
    await tester.pumpAndSettle();
    expect(
        calls.any((p) => p.contains('/suppliers/$supplier/finance/')), isTrue);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: workspace(client, SupplierV21Role.finance,
                supplierId: second))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finance & GST'));
    await tester.pumpAndSettle();
    expect(calls.any((p) => p.contains('/suppliers/$second/finance/')), isTrue);
    expect(tester.takeException(), isNull);
  });
}
