import 'package:customer_app/widgets/ui/customer_photo_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('customer showroom photo tiles open the requested category',
      (tester) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 245,
            child: CustomerPhotoRail(onCategorySelected: (name) {
              chosen = name;
            }),
          ),
        ),
      ),
    );

    expect(find.text('Shop by Material'), findsOneWidget);
    expect(find.text('Cement & Concrete'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    await tester.tap(find.text('Cement & Concrete'));
    expect(chosen, 'Cement & Concrete');
  });
}
