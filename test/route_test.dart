// Route guide: recorded-flight model, crash streak, the guide/demo wiring in
// the real game, and every bundled route still matching its level. The
// turret levels' demo flights are in route_demo_test.dart.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/route_planner.dart';
import 'package:narrow_haul/game/level/level_data.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/level/tiled_level_loader.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/route/crash_streak.dart';
import 'package:narrow_haul/game/route/flight_route.dart';
import 'package:narrow_haul/game/route/route_repository.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/ui/route_guide_overlays.dart';

import 'autopilot/harness.dart';
import 'helpers/caves.dart';

FlightRoute _line({
  String id = 'tut_01',
  String ship = 'kestrel',
  required double x0,
  required double y0,
  required double x1,
  required double y1,
  double seconds = 4,
  List<double> shots = const [],
}) {
  final samples = <RouteSample>[];
  for (var k = 0; k <= seconds * 10; k++) {
    final u = k / (seconds * 10);
    final x = x0 + (x1 - x0) * u;
    final y = y0 + (y1 - y0) * u;
    samples.add(RouteSample(
      t: k / 10,
      x: x,
      y: y,
      angle: 0.2 * u,
      cx: x,
      cy: y + 1.5,
      towing: u >= 0.5,
      thrust: k.isEven,
    ));
  }
  return FlightRoute(
    saveId: id,
    shipId: ship,
    samples: samples,
    launchT: 0.5,
    attachT: seconds / 2,
    seconds: seconds - 0.5,
    stars: 3,
    fuelLeft: 0.8,
    shots: shots,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('FlightRoute', () {
    test('JSON round-trip keeps samples, flags and markers', () {
      final r = _line(x0: 1, y0: 2, x1: 5, y1: 2, shots: const [1.2]);
      final back = FlightRoute.fromJson(
        jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>,
      );
      expect(back.samples.length, r.samples.length);
      expect(back.launchT, 0.5);
      expect(back.attachT, 2);
      expect(back.shots, [1.2]);
      expect(back.samples[25].towing, isTrue);
      expect(back.samples[3].thrust, isFalse);
      expect(back.samples.last.x, closeTo(5, 1e-9));
    });

    test('rejects another format version', () {
      final j = _line(x0: 0, y0: 0, x1: 1, y1: 0).toJson()..['v'] = 99;
      expect(() => FlightRoute.fromJson(j), throwsFormatException);
    });

    test('poseAt interpolates between samples and clamps at the ends', () {
      final r = _line(x0: 0, y0: 0, x1: 4, y1: 0);
      expect(r.poseAt(-1).x, 0);
      expect(r.poseAt(99).x, closeTo(4, 1e-9));
      // A straight, evenly sampled line: Catmull-Rom is exact.
      expect(r.poseAt(1.05).x, closeTo(1.05, 1e-9));
      expect(r.poseAt(1.05).cy, closeTo(1.5, 1e-9));
      expect(r.poseAt(3.0).towing, isTrue);
      expect(r.poseAt(1.0).towing, isFalse);
    });

    test('fire marks: one per burst, at the pose, along the nose', () {
      final r = _line(x0: 0, y0: 0, x1: 4, y1: 0, shots: const [1.0, 1.27, 3.0]);
      final marks = r.fireMarks();
      expect(marks.length, 2);
      expect(marks[0].shots, 2);
      expect(marks[1].shots, 1);
      expect(marks[0].x, closeTo(1.0, 1e-6));
      final a = r.poseAt(1.0).angle;
      expect(marks[0].dirX, closeTo(math.sin(a), 1e-9));
      expect(marks[0].dirY, closeTo(-math.cos(a), 1e-9));
    });

    test('poseAt turns the short way across ±π', () {
      const a = RouteSample(t: 0, x: 0, y: 0, angle: 3.0, cx: 0, cy: 0);
      const b = RouteSample(t: 1, x: 0, y: 0, angle: -3.0, cx: 0, cy: 0);
      final r = FlightRoute(
          saveId: 'x', shipId: 'kestrel', samples: const [a, b], launchT: 0, attachT: null, seconds: 1);
      final mid = r.poseAt(0.5).angle;
      expect(math.cos(mid), closeTo(-1, 0.01)); // through π, not through 0
    });
  });

  group('FlightRecorder', () {
    test('samples every 0.1 s and marks launch, attach and shots', () {
      final rec = FlightRecorder(saveId: 'tut_01', shipId: 'kestrel');
      for (var f = 0; f < 120; f++) {
        if (f == 70) rec.shot();
        rec.tick(1 / 60,
            x: f / 60, y: 0, angle: 0, cx: 0, cy: 0,
            launched: f >= 30, towing: f >= 60, thrust: f.isOdd);
      }
      final r = rec.finish(
          x: 2, y: 0, angle: 0, cx: 0, cy: 0, seconds: 1.5, stars: 3, fuelLeft: 0.7);
      expect(r.samples.length, inInclusiveRange(20, 22));
      for (var k = 1; k < r.samples.length - 1; k++) {
        expect(r.samples[k].t - r.samples[k - 1].t, closeTo(0.1, 0.02));
      }
      expect(r.launchT, closeTo(31 / 60, 1e-9));
      expect(r.attachT, closeTo(61 / 60, 1e-9));
      expect(r.shots.single, closeTo(70 / 60, 1e-9));
      expect(r.samples.last.x, 2);
    });
  });

  group('CrashStreak', () {
    test('offers after 3 crashes in a row on the same level', () {
      final s = CrashStreak();
      s.onCrash('a');
      s.onCrash('a');
      expect(s.shouldOfferFor('a'), isFalse);
      s.onCrash('a');
      expect(s.shouldOfferFor('a'), isTrue);
      expect(s.shouldOfferFor('b'), isFalse);
    });

    test('a delivery or another level resets it', () {
      final s = CrashStreak()
        ..onCrash('a')
        ..onCrash('a')
        ..onCrash('a')
        ..onDelivered();
      expect(s.shouldOfferFor('a'), isFalse);
      s
        ..onCrash('a')
        ..onCrash('a')
        ..onCrash('b')
        ..onCrash('a');
      expect(s.count, 1);
      expect(s.shouldOfferFor('a'), isFalse);
    });
  });

  group('in game', () {
    late GameHarness h;
    late LevelData level;

    setUpAll(() async {
      h = GameHarness();
      await h.boot();
      await h.loadLevel(0);
      level = h.game.currentLevel!;
      // A synthetic route for tut_01 (straight through rock: the demo is
      // kinematic, so even that can't crash).
      RouteRepository.debugSet(
        'tut_01',
        _line(
          x0: level.shipSpawn.x,
          y0: level.shipSpawn.y,
          x1: level.goalCenter.x,
          y1: level.goalCenter.y,
        ),
      );
    });

    Future<void> crash() async {
      await h.loadLevel(0);
      h.game.onShipShot(); // same crash path as a wall hit
      expect(h.game.runState, RunState.gameOver);
    }

    test('route help appears on the third crash in a row', () async {
      await crash();
      await crash();
      expect(h.game.currentRoute, isNotNull);
      expect(h.game.canShowRoute, isFalse);
      await crash();
      expect(h.game.canShowRoute, isTrue);
    });

    test('no help without a route', () async {
      RouteRepository.debugSet('tut_02', null);
      for (var k = 0; k < 3; k++) {
        await h.loadLevel(1);
        h.game.onShipShot();
      }
      expect(h.game.currentRoute, isNull);
      expect(h.game.canShowRoute, isFalse);
    });

    testWidgets('game-over buttons follow canShowRoute', (tester) async {
      Future<void> pump() async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: RouteHelpButtons(game: h.game)),
        ));
      }

      await tester.runAsync(() async {
        RouteRepository.debugSet('tut_02', null);
        await h.loadLevel(1);
        h.game.onShipShot();
      });
      await pump();
      expect(find.text('SHOW ROUTE'), findsNothing);
      expect(find.text('WATCH A DEMO'), findsNothing);

      // Three crashes on tut_01.
      await tester.runAsync(() async {
        for (var k = 0; k < 3; k++) {
          await crash();
        }
      });
      await pump();
      expect(find.text('SHOW ROUTE'), findsOneWidget);
      expect(find.text('WATCH A DEMO'), findsOneWidget);
    });

    test('a guided flight is capped at 2★ and the guide persists', () async {
      for (var k = 0; k < 3; k++) {
        await crash();
      }
      final g = h.game;
      await g.showRoute();
      await g.ready();
      expect(ProgressService.instance.isRouteUnlocked('tut_01'), isTrue);
      expect(g.routeGuideOn, isTrue);
      expect(g.routeGuideAvailable, isTrue);
      expect(g.guidedThisRun, isFalse); // not until launch
      await h.fly((_) => const BotInput(thrust: true), maxSeconds: 0.1);
      expect(g.guidedThisRun, isTrue);
      expect(g.debugStars(1.0, 1), 2);
      // Switched off, the next flight can earn 3★ again.
      g.setRouteGuide(false);
      await h.loadLevel(0);
      await h.fly((_) => const BotInput(thrust: true), maxSeconds: 0.1);
      expect(g.guidedThisRun, isFalse);
      expect(g.debugStars(1.0, 1), 3);
      // Still guided after a retry with the guide on.
      g.setRouteGuide(true);
      await h.loadLevel(0);
      expect(g.routeGuideOn, isTrue);
      // An unlocked route is offered on any later crash.
      g.onShipShot();
      expect(g.canShowRoute, isTrue);
    });

    test('demo flight replays the route: no crash, no delivery, no stats', () async {
      await crash();
      final flights = ProgressService.instance.getStat(ProgressService.statFlights);
      final crashes = ProgressService.instance.getStat(ProgressService.statCrashes);
      final g = h.game;
      await g.startDemoFlight();
      await g.ready();
      expect(g.demoMode, isTrue);
      final route = g.currentRoute!;
      final r = await h.fly((_) => BotInput.idle, maxSeconds: route.endT + 1);
      expect(r.outcome, FlightOutcome.timedOut); // ran out the clock, never crashed
      expect(g.demoFinished.value, isTrue);
      final end = route.samples.last;
      expect(g.ship!.body.position.x, closeTo(end.x, 0.05));
      expect(g.ship!.body.position.y, closeTo(end.y, 0.05));
      expect(g.cargoAttachment!.attached, isTrue);
      expect(ProgressService.instance.getStat(ProgressService.statFlights), flights);
      expect(ProgressService.instance.getStat(ProgressService.statCrashes), crashes);
      await g.takeControlsFromDemo();
      await g.ready();
      expect(g.demoMode, isFalse);
    });
  });

  group('bundled routes', () {
    final dir = Directory('assets/routes');
    final files = dir.existsSync()
        ? {
            for (final f in dir.listSync().whereType<File>())
              if (f.path.endsWith('.json')) f.uri.pathSegments.last.replaceAll('.json', ''),
          }
        : <String>{};

    setUpAll(prebuildAllCaves);

    test('every bundled route matches its level', () async {
      for (var i = 0; i < LevelRegistry.totalLevels; i++) {
        final def = LevelRegistry.defAt(i);
        if (!files.contains(def.saveId)) continue;
        final route = FlightRoute.fromJson(
          jsonDecode(File('assets/routes/${def.saveId}.json').readAsStringSync())
              as Map<String, dynamic>,
        );
        final id = def.saveId;
        expect(route.saveId, id);
        expect(route.shipId, LevelRegistry.shipFor(i).id, reason: '$id: recorded with another ship');
        final data = switch (def) {
          CaveLevelDef d => buildCaveLevelData(d),
          TmxLevelDef d => await loadLevelFromTmx(d.assetPath, levelIndex: i),
        };
        final first = route.samples.first;
        expect(_d(first.x, first.y, data.shipSpawn.x, data.shipSpawn.y), lessThan(0.5),
            reason: '$id: route starts off the spawn pad (stale? re-export)');
        final attachT = route.attachT;
        expect(attachT, isNotNull, reason: '$id: the pod is never hooked');
        // Pods drop, roll or get blown about before pickup, so check the
        // hook itself: the ship is right at the pod when the rope attaches.
        final at = route.poseAt(attachT!);
        expect(_d(at.x, at.y, at.cx, at.cy), lessThan(2.0),
            reason: '$id: rope attaches with the ship away from the pod');
        final end = route.samples.last;
        // Delivery counts once any part of the hull reaches the pad box.
        final reach = LevelRegistry.shipFor(i).circumradius + 0.4;
        expect((end.x - data.goalCenter.x).abs(), lessThan(data.goalHalfWidth + reach),
            reason: '$id: route ends off the pad');
        expect((end.y - data.goalCenter.y).abs(), lessThan(data.goalHalfHeight + reach),
            reason: '$id: route ends off the pad');
        final grid = switch (def) {
          CaveLevelDef d => NavGrid.forCave(d.spec),
          TmxLevelDef() => NavGrid.forRects(
              [
                for (final w in data.walls)
                  (cx: w.center.x, cy: w.center.y, hw: w.halfWidth, hh: w.halfHeight),
              ],
              data.worldSize.x,
              data.worldSize.y,
            ),
        };
        for (final s in route.flown) {
          expect(grid.clearanceAt(s.x, s.y), greaterThan(0),
              reason: '$id: route goes through rock at t=${s.t} (stale? re-export)');
        }
        expect(grid.clearanceAt(at.cx, at.cy), greaterThan(0),
            reason: '$id: pod hooked inside rock (stale? re-export)');
      }
    });

    test('every level the bot can fly has a route', () {
      final missing = [
        for (final def in LevelRegistry.flat)
          if (!files.contains(def.saveId)) def.saveId,
      ];
      expect(missing, isEmpty, reason: 'export with --dart-define=EXPORT_ROUTES=true');
    }, skip: files.isEmpty ? 'no routes exported yet (see assets/routes/README.md)' : false);
  });
}

double _d(double ax, double ay, double bx, double by) =>
    math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));
