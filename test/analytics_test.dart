import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';

import 'autopilot/harness.dart';

void main() {
  group('Analytics values', () {
    tearDown(() => Analytics.sink = null);

    test('bools become 0/1, doubles are rounded, nulls dropped', () {
      Map<String, Object>? sent;
      Analytics.sink = (_, p) => sent = p;
      Analytics.log('x', {'b': true, 'd': 1.23456, 'n': null, 's': 'tut_01'});
      expect(sent, {'b': 1, 'd': 1.23, 's': 'tut_01'});
    });

    test('a throwing sink never reaches the game', () {
      Analytics.sink = (_, _) => throw StateError('offline');
      expect(() => Analytics.log('x'), returnsNormally);
    });
  });

  group('flight events', () {
    final h = GameHarness();
    setUpAll(h.boot);
    // The log is capped (oldest entries drop off), so marks into it only
    // hold on a fresh one.
    setUp(Analytics.debugLog.clear);

    List<(String, Map<String, Object>)> since(int mark) =>
        Analytics.debugLog.sublist(mark);

    test('start → fail → retry → deliver, with attempts and level ids', () async {
      final id = LevelRegistry.defAt(0).saveId;
      var mark = Analytics.debugLog.length;
      await h.loadLevel(0);
      final start = since(mark).singleWhere((e) => e.$1 == 'level_start');
      expect(start.$2['level_name'], id);
      expect(start.$2['attempt'], 1);
      expect(start.$2['mode'], 'normal');
      expect(start.$2['ship'], isNotEmpty);

      mark = Analytics.debugLog.length;
      h.game.onShipShot();
      expect(h.game.runState, RunState.gameOver);
      final fail = since(mark).singleWhere((e) => e.$1 == 'level_fail');
      expect(fail.$2['level_name'], id);
      expect(fail.$2['cause'], 'shot');
      expect(fail.$2['attempt'], 1);
      expect(fail.$2.keys, containsAll(['x', 'y', 'fuel_left_pct', 'towing']));

      mark = Analytics.debugLog.length;
      await h.loadLevel(0);
      expect(
        since(mark).singleWhere((e) => e.$1 == 'level_start').$2['attempt'],
        2,
      );

      mark = Analytics.debugLog.length;
      await h.game.debugDeliver();
      final names = [for (final e in since(mark)) e.$1];
      expect(names, contains('level_end'));
      final end = since(mark).singleWhere((e) => e.$1 == 'level_end');
      expect(end.$2['level_name'], id);
      expect(end.$2['first_clear'], 1);
      expect(end.$2['attempt'], 2);
      expect(end.$2['stars'], inInclusiveRange(1, 3));

      // A delivery starts a new attempt series.
      mark = Analytics.debugLog.length;
      await h.loadLevel(0);
      expect(
        since(mark).singleWhere((e) => e.$1 == 'level_start').$2['attempt'],
        1,
      );
    });

    test('leaving a flight for the menu is a quit', () async {
      await h.loadLevel(0);
      final mark = Analytics.debugLog.length;
      h.game.backToMenu();
      final quit = since(mark).singleWhere((e) => e.$1 == 'level_quit');
      expect(quit.$2['reason'], 'menu');
    });
  });
}
