import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor_app/v21/design/buildto_theme.dart';
import 'package:vendor_app/v21/onboarding/supplier_evidence_link_sheet.dart';

void main() {
  testWidgets(
      'document picker uploads selected bytes and never asks for storage UUIDs',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        theme: BuildToTheme.light(),
        home: Scaffold(
          body: PrivateEvidenceLinkSheet(
            pickFile: () async => XFile.fromData(Uint8List.fromList([1, 2, 3]),
                path: 'registration.png'),
            upload: (bytes, mime) async {
              calls++;
              expect(bytes, [1, 2, 3]);
              expect(mime, 'image/png');
              return '123e4567-e89b-12d3-a456-426614174000';
            },
          ),
        )));
    expect(find.text('Private media reference'), findsNothing);
    await tester.tap(find.text('Choose document'));
    await tester.pumpAndSettle();
    expect(find.text('registration.png'), findsOneWidget);
    await tester.tap(find.text('Upload document'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'oversized document remains unsubmitted and upload sheet fits narrow large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
        theme: BuildToTheme.light(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(
            body: PrivateEvidenceLinkSheet(
          pickFile: () async => XFile.fromData(Uint8List(10 * 1024 * 1024 + 1),
              path: 'large.pdf'),
          upload: (unusedBytes, unusedMime) async =>
              throw StateError('Must not upload oversized files'),
        ))));
    await tester.tap(find.text('Choose document'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a file up to 10 MB.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
