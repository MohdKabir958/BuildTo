import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kraveo_ui/kraveo_ui.dart';

class _UnavailableArtwork extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    throw StateError('Asset unavailable');
  }
}

void main() {
  testWidgets('an unavailable splash releases Flutter and reveals the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      DefaultAssetBundle(
        bundle: _UnavailableArtwork(),
        child: const SplyzoStartup(child: SizedBox.expand()),
      ),
    );
    expect(find.byType(SplyzoSplashScreen), findsOneWidget);

    // Drive the error frame and then the frame permitted by the splash.
    await tester.pump();
    await tester.pump();
    expect(tester.binding.sendFramesToEngine, isTrue);
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.byType(SplyzoSplashScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
