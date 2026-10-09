// Async robustness of the level lifecycle: a load abandoned mid-way leaves
// nothing behind, and a failed delivery booking still reaches the result
// screen instead of freezing on the pad.
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/components/wall_box.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';

import 'autopilot/harness.dart';

void main() {
  final h = GameHarness();
  setUpAll(h.boot);

  bool hasLevelBodies() => h.game.world.children
      .any((c) => c is ShipBody || c is CargoBody || c is WallBox);

  test('backing out to the menu mid-load leaves no level behind', () async {
    final game = h.game;
    await h.loadLevel(0);
    expect(hasLevelBodies(), isTrue);

    // Start a fresh load and leave once it has put its first walls down.
    game.levelIndex = 1;
    final load = game.loadCurrentLevel();
    var spins = 0;
    while (!game.world.children.any((c) => c is WallBox) && spins++ < 2000) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(spins, lessThan(2000), reason: 'the load never added a wall');
    game.backToMenu();
    await load;
    await game.ready();
    for (var i = 0; i < 5; i++) {
      game.update(1 / 60);
      await Future<void>.delayed(Duration.zero);
    }

    expect(game.runState, RunState.menu);
    expect(game.ship, isNull);
    expect(game.currentLevel, isNull);
    expect(hasLevelBodies(), isFalse);
    expect(game.overlays.isActive('menu'), isTrue);
  });

  test('a delivery whose booking throws still shows the result screen', () async {
    final game = h.game;
    await h.loadLevel(0);
    game.debugBeforeBooking = () => throw StateError('disk full');
    addTearDown(() => game.debugBeforeBooking = null);

    await game.debugDeliver();
    expect(game.runState, RunState.won);
    expect(game.lastRunReward, isNull);
    for (var i = 0; i < 180 && !game.overlays.isActive('levelComplete'); i++) {
      game.update(1 / 60);
      await Future<void>.delayed(Duration.zero);
    }
    expect(game.overlays.isActive('levelComplete'), isTrue);
    expect(LevelRegistry.defAt(0).saveId, isNotEmpty);
  });
}
