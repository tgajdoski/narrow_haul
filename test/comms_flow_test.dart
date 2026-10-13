// The radio lines a flight opens with: a ship is introduced on its first
// flight only, and a mission's story plays until its first clear, once per
// app session.
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';

void main() {
  final h = GameHarness();
  // A coin-bought Mule: owned, but never type-rated.
  setUpAll(() => h.boot(prefs: {'ship_owned_mule': true, 'ship_preferred': 'mule'}));

  /// Flies [seconds] of game time with no input (the ship hovers on its pad).
  Future<void> wait(double seconds) => h.step((seconds * 60).round());

  test('OPS introduces a ship on its first flight only', () async {
    final p = ProgressService.instance;
    final i = levelIndexOf('mine_02');
    expect(LevelRegistry.isShipNew('mule'), isTrue);

    await h.loadLevel(i);
    expect(h.game.ship!.spec.id, 'mule');
    await wait(3);
    expect(h.game.debugComms!.current?.id, 'ship');
    expect(p.shipIntroSeen('mule'), isTrue);
    expect(LevelRegistry.isShipNew('mule'), isFalse);

    await h.loadLevel(levelIndexOf('mine_03'));
    await wait(3);
    expect(h.game.debugComms!.hasSaid('ship'), isFalse);
  });

  test('story beats play until the first clear, once per session', () async {
    final first = levelIndexOf('mine_01');
    await h.loadLevel(first);
    await wait(0.1);
    expect(h.game.debugComms!.hasSaid('story_0'), isTrue);

    // Back to the hangar and launched again: already told this session.
    await h.loadLevel(first);
    await wait(0.1);
    expect(h.game.debugComms!.hasSaid('story_0'), isFalse);

    // A mission already cleared doesn't retell its story.
    await ProgressService.instance.saveStarsById('mine_04', 2);
    await h.loadLevel(levelIndexOf('mine_04'));
    await wait(0.1);
    expect(h.game.debugComms!.hasSaid('story_0'), isFalse);
  });
}
