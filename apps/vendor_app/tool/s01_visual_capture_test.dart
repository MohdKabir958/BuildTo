// Screenshot capture for **manual** PDF fidelity review, not a regression gate.
// Run explicitly with --update-goldens and inspect the uploaded CI artifact.
// Kept outside test/ so the existing full-suite test run does not require
// checked-in binary goldens before their human review/approval.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/v21/supplier_foundation_app.dart';

void main() {
  Future<void> setUpFrame(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(const RepaintBoundary(
      key: Key('s01-review-frame'),
      child: SupplierFoundationApp(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('home at approved reference phone width: 393', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await setUpFrame(tester, const Size(393, 852));
    await expectLater(
      find.byKey(const Key('s01-review-frame')),
      matchesGoldenFile('goldens/s01-home-393.png'),
    );
  });

  testWidgets('home at compact Android phone width: 360', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await setUpFrame(tester, const Size(360, 800));
    await expectLater(
      find.byKey(const Key('s01-review-frame')),
      matchesGoldenFile('goldens/s01-home-360.png'),
    );
  });

  testWidgets('orders state at approved reference phone width: 393',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await setUpFrame(tester, const Size(393, 852));
    await tester.tap(find.byKey(const Key('tab-orders')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('s01-review-frame')),
      matchesGoldenFile('goldens/s01-orders-393.png'),
    );
  });
}
