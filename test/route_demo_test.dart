// Every turret level's bundled route, replayed as a demo flight in the real
// game: turret fire never reaches the demo ship and each recorded shot burst
// knocks something out. Re-export a level (LEVELS=<id> EXPORT_ROUTES=true)
// when this fails after editing it. Kept apart from route_test.dart because
// it's the slowest flight test: separate files run in parallel.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/defences.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/route/flight_route.dart';
import 'package:narrow_haul/game/route/route_repository.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

import 'autopilot/harness.dart';

void main() {
  final turretLevels = [
    for (var i = 0; i < LevelRegistry.totalLevels; i++)
      if (LevelRegistry.defAt(i) case final CaveLevelDef def
          when def.spec.obstacles.any((o) => o is TurretSpec) &&
              File('assets/routes/${def.saveId}.json').existsSync())
        i,
  ];
  final h = GameHarness();
  setUpAll(h.boot);

  test('there are turret levels with routes', () {
    expect(turretLevels, isNotEmpty);
  });

  for (final i in turretLevels) {
    final id = LevelRegistry.defAt(i).saveId;
    test('$id: demo flight fights the turrets and is never hit', () async {
      final route = FlightRoute.fromJson(
        jsonDecode(File('assets/routes/$id.json').readAsStringSync()) as Map<String, dynamic>,
      );
      RouteRepository.debugSet(id, route);
      await h.loadLevel(i);
      await ProgressService.instance.setRouteUnlocked(id);
      final g = h.game;
      await g.startDemoFlight();
      await g.ready();
      expect(g.demoMode, isTrue);
      await h.fly((_) => BotInput.idle, maxSeconds: route.endT + 0.5);
      final turrets = [for (final c in g.world.children) if (c is Turret) c];
      final reactorDown = g.world.children.any((c) => c is Reactor && c.destroyed);
      printOnFailure('$id: hits=${g.demoShellHits} turrets down='
          '${turrets.where((t) => t.destroyed).length}/${turrets.length} reactor down=$reactorDown');
      expect(g.demoShellHits, 0, reason: 'turret fire hits the demo ship (re-export)');
      // The armed ship takes out what its route meets.
      if (LevelRegistry.shipFor(i).armed && route.shots.isNotEmpty) {
        final kills = turrets.where((t) => t.destroyed).length + (reactorDown ? 1 : 0);
        expect(kills, greaterThanOrEqualTo(1), reason: 'demo shots hit nothing');
        // Each burst knocks something out (a missed burst may be fired
        // again, so at most one per target).
        final targets = turrets.length + g.world.children.whereType<Reactor>().length;
        expect(kills + (g.turretsDisabled ? 1 : 0),
            greaterThanOrEqualTo(math.min(route.fireMarks().length, targets)),
            reason: 'a demo shot burst misses its target');
      }
      await g.takeControlsFromDemo();
      await g.ready();
    });
  }
}
