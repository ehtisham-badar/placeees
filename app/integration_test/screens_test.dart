// Walks the main screens in demo mode and captures screenshots.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screens_test.dart --dart-define=DEMO_AUTOSTART=true -d <device>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:trace/features/map/drop_marker.dart';
import 'package:trace/main.dart' as app;
import 'package:trace/ui/buttons.dart';

Future<void> settle(WidgetTester tester, [Duration d = const Duration(seconds: 2)]) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> waitFor(WidgetTester tester, Finder f, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) throw TestFailure('Timed out waiting for $f');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Finder marker(String teaser) =>
    find.byWidgetPredicate((w) => w is DropMarker && w.drop.teaser == teaser);

Finder orb(String label) => find.byWidgetPredicate((w) => w is OrbButton && w.tooltip == label);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screens', (tester) async {
    app.main();
    await binding.convertFlutterSurfaceToImage();

    await waitFor(tester, marker('Read this if today was heavy.'));
    await settle(tester, const Duration(seconds: 4)); // tiles + fonts
    await binding.takeScreenshot('01-map');

    // A conditional drop with its rule revealed.
    await tester.tap(marker('Only makes sense in the right light.'), warnIfMissed: false);
    await settle(tester);
    await binding.takeScreenshot('02-card-conditional');

    // The hot/cold compass.
    await tester.tap(find.text('Find the exact spot'));
    await settle(tester, const Duration(seconds: 3));
    await binding.takeScreenshot('03-compass');
    await tester.tap(find.text('Demo: take a few steps'));
    await settle(tester, const Duration(seconds: 3));
    await binding.takeScreenshot('04-compass-close');
    await tester.tap(orb('Stop hunting'));
    await settle(tester);

    // The composer with a rule chosen.
    await tester.tap(orb('Close'));
    await settle(tester);
    await tester.tap(find.text('Leave a drop here'));
    await settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await settle(tester);
    await tester.tap(find.text('Make it wait for a moment'));
    await settle(tester);
    await tester.tap(find.text('Sunset'));
    await tester.tap(find.text('Rain'));
    await settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await settle(tester);
    await binding.takeScreenshot('05-composer-rules');
  });
}
