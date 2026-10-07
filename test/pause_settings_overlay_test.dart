import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/ui/pause_settings_overlays.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ProgressService.init();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    // Small landscape phone — the tightest layout we ship.
    tester.view.physicalSize = const Size(667, 375);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('pause overlay lays out on a small landscape phone', (
    tester,
  ) async {
    await pump(tester, PauseOverlay(game: NarrowHaulGame()));
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings toggles persist', (tester) async {
    await pump(tester, SettingsOverlay(game: NarrowHaulGame()));
    expect(tester.takeException(), isNull);
    expect(ProgressService.instance.leftHanded, isFalse);
    await tester.tap(find.text('Left-handed controls'));
    await tester.pumpAndSettle();
    expect(ProgressService.instance.leftHanded, isTrue);
    await tester.tap(find.text('Sound effects'));
    await tester.pumpAndSettle();
    expect(ProgressService.instance.soundEnabled, isFalse);
  });
}
