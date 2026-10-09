import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ProgressService.init();
  });

  testWidgets('Android back steps back through menus; exits only from menu', (
    tester,
  ) async {
    final game = NarrowHaulGame();
    Widget blank(BuildContext _, Game _) => const SizedBox.shrink();
    await tester.pumpWidget(
      GameWidget(
        game: game,
        overlayBuilderMap: {
          for (final k in [
            'menu', 'levelSelect', 'achievements', 'cosmetics',
            'pilotProfile', 'settings', 'pause', 'briefing',
          ])
            k: blank,
        },
      ),
    );
    final active = game.overlays.activeOverlays;
    // Fresh prefs: the first-launch credits are up; they close on back too.
    expect(game.handleBack(), isTrue);
    expect(game.creditsVisible.value, isFalse);

    game.overlays
      ..clear()
      ..add('levelSelect');
    expect(game.handleBack(), isTrue);
    expect(active, ['menu']);

    // The briefing closes alone: over the map, the map stays…
    game.overlays
      ..clear()
      ..add('levelSelect');
    game.openBriefing(3);
    expect(game.handleBack(), isTrue);
    expect(active, ['levelSelect']);

    // …and over the hangar (the daily), back must not close the app.
    game.overlays
      ..clear()
      ..add('menu');
    game.openDailyBriefing();
    expect(game.handleBack(), isTrue, reason: 'daily briefing over the hangar');
    expect(active, ['menu']);

    game.overlays
      ..clear()
      ..add('settings');
    expect(game.handleBack(), isTrue);
    expect(active, ['menu']);

    // The credits (drawn above the game) close first.
    game.creditsVisible.value = true;
    expect(game.handleBack(), isTrue);
    expect(game.creditsVisible.value, isFalse);
    expect(active, ['menu']);

    // So does the launch intro.
    game.introVisible.value = true;
    expect(game.handleBack(), isTrue);
    expect(game.introVisible.value, isFalse);
    expect(active, ['menu']);

    expect(game.handleBack(), isFalse, reason: 'menu lets the app close');
  });
}
