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

  testWidgets('settings offers privacy, support, licenses and reset', (
    tester,
  ) async {
    await pump(tester, SettingsOverlay(game: NarrowHaulGame()));
    for (final label in ['Privacy policy', 'Support', 'Licenses', 'Reset progress']) {
      await tester.scrollUntilVisible(find.text(label), 50);
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  test('reset progress keeps settings, purchases and paid cosmetics', () async {
    SharedPreferences.setMockInitialValues({
      'stars2_tut_01': 3,
      'xp_total': 900,
      'cosmetic_currency': 250,
      'cosmetic_unlocked_ship_red': true,
      'cosmetic_unlocked_ship_supporter': true,
      'achievements': <String>['first_flight'],
      'left_handed': true,
      'ads_removed': true,
      'iap_granted_nh_supporter_pack': true,
      'save_v3': true,
    });
    await ProgressService.init();
    final p = ProgressService.instance;
    await p.resetProgress(keepCosmeticIds: {'ship_supporter'});
    final prefs = await SharedPreferences.getInstance();
    expect(p.getStarsById('tut_01'), 0);
    expect(prefs.containsKey('xp_total'), isFalse);
    expect(p.getCosmeticCurrency(), 0);
    expect(p.isCosmeticUnlocked('ship_red'), isFalse);
    expect(prefs.containsKey('achievements'), isFalse);
    expect(p.isCosmeticUnlocked('ship_supporter'), isTrue);
    expect(p.leftHanded, isTrue);
    expect(prefs.getBool('ads_removed'), isTrue);
    expect(prefs.getBool('iap_granted_nh_supporter_pack'), isTrue);
    expect(prefs.getBool('save_v3'), isTrue);
  });
}
