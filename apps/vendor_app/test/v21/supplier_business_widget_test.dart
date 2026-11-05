import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor_app/v21/api/supplier_v21_api.dart';
import 'package:vendor_app/v21/api/supplier_v21_models.dart';
import 'package:vendor_app/v21/business/supplier_business_view.dart';
import 'package:vendor_app/v21/delivery/supplier_delivery_repository.dart';
import 'package:vendor_app/v21/rfq/supplier_rfq_repository.dart';

const supplier = '123e4567-e89b-42d3-a456-426614174000';

void main() {
  testWidgets('viewer cannot call restricted RFQs when switching business tabs',
      (tester) async {
    final paths = <String>[];
    final api = SupplierV21Api(
      origin: Uri.parse('https://buildto-v21-staging.onrender.com'),
      token: () async => 'verified-clerk-token',
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(jsonEncode({'data': <Object>[]}), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: SupplierBusinessView(
        supplierId: supplier,
        role: SupplierV21Role.viewer,
        delivery: SupplierDeliveryRepository(api),
        rfqs: SupplierRfqRepository(api),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Delivery coverage'), findsOneWidget);
    await tester.tap(find.text('RFQs & quotes'));
    await tester.pumpAndSettle();
    expect(find.text('RFQ access restricted'), findsOneWidget);
    expect(paths.where((p) => p.endsWith('/rfqs')), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
