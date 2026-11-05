import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/v21/screens/supplier_shell.dart';
import 'package:vendor_app/v21/design/buildto_components.dart';
import 'package:vendor_app/v21/design/buildto_theme.dart';

Future<void> pumpPhone(WidgetTester tester, Size size,
    {double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
    child: const BuildToSupplierPreviewApp(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('BuildTo navigation presents the approved five supplier tabs',
      (tester) async {
    await pumpPhone(tester, const Size(393, 852));
    expect(find.text('BuildTo'), findsOneWidget);
    expect(find.text('Building Made Easy.'), findsOneWidget);
    expect(find.text('Your supplier workspace'), findsOneWidget);
    for (final name in ['Home', 'Orders', 'Catalog', 'Stock', 'More']) {
      expect(find.text(name), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('supplier tabs switch to honest access-required states',
      (tester) async {
    await pumpPhone(tester, const Size(393, 852));
    await tester.tap(find.text('Orders').last);
    await tester.pumpAndSettle();
    expect(find.text('Supplier orders'), findsOneWidget);
    expect(find.text('Secure workspace'), findsOneWidget);
    expect(find.textContaining('S02'), findsWidgets);
    await tester.tap(find.text('Stock').last);
    await tester.pumpAndSettle();
    expect(find.text('Warehouse stock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile layouts and large text do not overflow the shell',
      (tester) async {
    for (final size in [
      const Size(320, 800),
      const Size(360, 800),
      const Size(393, 852),
      const Size(412, 915)
    ]) {
      await pumpPhone(tester, size);
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await pumpPhone(tester, const Size(393, 852), scale: 1.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('design tokens and primitive status remain readable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: BuildToTheme.light(),
      home: const Scaffold(
          body: Center(
              child: BuildToStatusChip(
        label: 'Approval pending',
        status: BuildToStatus.pending,
      ))),
    ));
    expect(find.text('Approval pending'), findsOneWidget);
    expect(BuildToPalette.navy, const Color(0xFF002B5B));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no mock money or orders displayed as live values',
      (tester) async {
    await pumpPhone(tester, const Size(393, 852));
    expect(find.text('Account connection required'), findsOneWidget);
    expect(find.textContaining('No sample business figures'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);
    expect(find.text('Order placed successfully'), findsNothing);
  });
}
