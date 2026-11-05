import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/v21/design/buildto_components.dart';
import 'package:vendor_app/v21/design/buildto_theme.dart';
import 'package:vendor_app/v21/design/buildto_tokens.dart';
import 'package:vendor_app/v21/supplier_foundation_app.dart';

void main() {
  test('BuildTo brand tokens match the existing approved customer theme', () {
    expect(BuildtoPalette.navy, const Color(0xFF002B5B));
    expect(BuildtoPalette.amber, const Color(0xFFF59E0B));
    expect(BuildtoSupplierTheme.light.colorScheme.primary, BuildtoPalette.navy);
    expect(BuildtoSupplierTheme.light.scaffoldBackgroundColor,
        BuildtoPalette.canvas);
  });

  testWidgets('S01 home is honest about the preview and has no fake metrics',
      (tester) async {
    await tester.pumpWidget(const SupplierFoundationApp());
    expect(find.text('Your business, in command.'), findsOneWidget);
    expect(find.text('V2.1 WORKSPACE PREVIEW'), findsOneWidget);
    expect(find.text('Build better.\nDeliver smarter.'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);
    expect(find.byType(BuildtoWordmark), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all five tabs navigate, including the hero shortcut',
      (tester) async {
    await tester.pumpWidget(const SupplierFoundationApp());
    await tester.tap(find.byKey(const Key('explore-orders')));
    await tester.pumpAndSettle();
    expect(find.text('Your orders'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-catalog')));
    await tester.pumpAndSettle();
    expect(find.text('Material catalog'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-stock')));
    await tester.pumpAndSettle();
    expect(find.text('Stock control'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-more')));
    await tester.pumpAndSettle();
    expect(find.text('More'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-home')));
    await tester.pumpAndSettle();
    expect(find.text('Your business, in command.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('information controls explain preview instead of pretending to save',
      (tester) async {
    await tester.pumpWidget(const SupplierFoundationApp());
    await tester.tap(find.byKey(const Key('about-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Supplier workspace preview'), findsOneWidget);
    expect(find.textContaining('No demo business data'), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 393.0, 412.0, 600.0]) {
    testWidgets('home and navigation do not overflow at width ' +
        width.toString(), (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const SupplierFoundationApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('tab-stock')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('larger system text does not hide the primary content',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
      child: const SupplierFoundationApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Your business, in command.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status, progress and loading patterns are reusable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: BuildtoSupplierTheme.light,
      home: const Scaffold(body: Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BuildtoStatusPill(label: 'Under review', tone: BuildtoTone.warning),
          BuildtoLoadingPanel(label: 'Checking permissions'),
          BuildtoStepIndicator(
            labels: ['Application', 'Review', 'Decision'],
            currentStep: 0,
          ),
        ],
      ))),
    ));
    expect(find.text('Under review'), findsOneWidget);
    expect(find.text('Checking permissions'), findsOneWidget);
    expect(find.text('Application'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
