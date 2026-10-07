import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/combat/aim.dart';
import 'package:narrow_haul/game/components/combat.dart';
import 'package:narrow_haul/game/components/defences.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/level_validator.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/specs/world_redoubt.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/services/contracts_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// Records what the defences report, without a running game.
class _FakeHost implements CombatHost {
  final events = <String>[];

  @override
  ShipBody? get combatShip => null;
  @override
  Body? get combatCargo => null;
  @override
  bool get combatLive => true;
  @override
  bool get turretsDisabled => false;
  @override
  void spawnShell(Shell shell) => events.add('shell');
  @override
  void onShipShot() => events.add('shot');
  @override
  void onTurretDestroyed(Offset at) => events.add('turret');
  @override
  void onReactorDisabledTurrets(double seconds) => events.add('disable $seconds');
  @override
  void onReactorDestroyed(Offset at, double escapeSeconds) =>
      events.add('meltdown $escapeSeconds');
  @override
  void onFuelCollected(double amount, Offset at) => events.add('fuel $amount');
}

LevelSpec _withDefences(
  LevelSpec s, {
  List<ObstacleSpec>? obstacles,
  List<PickupSpec>? pickups,
}) =>
    LevelSpec(
      id: s.id,
      seed: s.seed,
      name: s.name,
      themeId: s.themeId,
      worldW: s.worldW,
      worldH: s.worldH,
      tunnels: s.tunnels,
      chambers: s.chambers,
      shipSpawn: s.shipSpawn,
      cargoSpawn: s.cargoSpawn,
      goal: s.goal,
      obstacles: obstacles ?? s.obstacles,
      pickups: pickups ?? s.pickups,
      modifiers: s.modifiers,
      noise: s.noise,
    );

void main() {
  group('lead aim', () {
    test('stationary target: aim straight at it', () {
      expect(leadAngle(0, 0, 3, 4, 0, 0, 5), closeTo(math.atan2(4, 3), 1e-9));
    });

    test('moving target: the shell meets it', () {
      const speed = 4.5;
      const tx = 6.0, ty = 0.0, vx = 0.0, vy = 1.5;
      final a = leadAngle(0, 0, tx, ty, vx, vy, speed);
      // Find the meeting time along the shell's ray and compare positions.
      double? hit;
      for (var t = 0.0; t < 5; t += 0.001) {
        final sx = math.cos(a) * speed * t;
        final sy = math.sin(a) * speed * t;
        final dx = sx - (tx + vx * t);
        final dy = sy - (ty + vy * t);
        if (dx * dx + dy * dy < 0.0004) {
          hit = t;
          break;
        }
      }
      expect(hit, isNotNull, reason: 'lead shot never meets the target');
      expect(a, greaterThan(0), reason: 'aims ahead (downward) of the target');
    });

    test('target outrunning the shell: falls back to direct aim', () {
      expect(leadAngle(0, 0, 5, 0, 20, 0, 4), closeTo(0, 1e-9));
    });

    test('angleDelta wraps to the short way round', () {
      expect(angleDelta(3.0, -3.0), closeTo(2 * math.pi - 6, 1e-9));
      expect(angleDelta(-3.0, 3.0), closeTo(6 - 2 * math.pi, 1e-9));
      expect(angleDelta(0.2, 0.5), closeTo(0.3, 1e-9));
    });
  });

  group('line of sight', () {
    test('a static box blocks the ray, open space does not', () {
      final world = Forge2DWorld(gravity: Vector2.zero());
      world.createBody(BodyDef()..position = Vector2(5, 0))
        .createFixture(FixtureDef(PolygonShape()..setAsBoxXY(0.5, 0.5)));
      expect(hasLineOfSight(world, Vector2(0, 0), Vector2(10, 0)), isFalse);
      expect(hasLineOfSight(world, Vector2(0, 3), Vector2(10, 3)), isTrue);
    });

    test('sensors and the ignored body are transparent', () {
      final world = Forge2DWorld(gravity: Vector2.zero());
      final own = world.createBody(BodyDef()..position = Vector2(1, 0))
        ..createFixture(FixtureDef(CircleShape()..radius = 0.5));
      world.createBody(BodyDef()..position = Vector2(5, 0))
          .createFixture(FixtureDef(CircleShape()..radius = 0.5, isSensor: true));
      expect(hasLineOfSight(world, Vector2(0, 0), Vector2(10, 0), ignore: own), isTrue);
    });
  });

  group('defences', () {
    test('reactor: disable at the threshold, meltdown at zero hp, once', () {
      final host = _FakeHost();
      final reactor = Reactor(
        spec: const ReactorSpec(Pt(0, 0), hp: 5, disableHits: 2, disableSeconds: 8, escapeSeconds: 20),
        theme: redoubtTheme,
        host: host,
      );
      for (var i = 0; i < 7; i++) {
        reactor.takeHit();
      }
      expect(host.events, ['disable 8.0', 'meltdown 20.0']);
      expect(reactor.destroyed, isTrue);
    });

    test('turret: destroyed after its hp, reported once', () {
      final host = _FakeHost();
      final turret = Turret(
        spec: const TurretSpec(Pt(0, 0), facing: kFaceUp, hp: 2),
        theme: redoubtTheme,
        host: host,
      );
      turret.takeHit();
      expect(turret.destroyed, isFalse);
      turret.takeHit();
      turret.takeHit();
      expect(turret.destroyed, isTrue);
      expect(host.events, ['turret']);
    });
  });

  group('validator combat rules', () {
    final base = (redoubtLevels.first as CaveLevelDef).spec; // rating_talon

    test('the shipped type rating is clean', () {
      expect(validateCaveSpec(base, ship: kTalon), isEmpty);
    });

    test('a turret that can see the goal pad is rejected', () {
      final g = base.goal.center;
      // On the pad chamber floor, facing up at the pad.
      final spec = _withDefences(base, obstacles: [
        TurretSpec(Pt(g.x - 1.5, g.y + 1.6), facing: kFaceUp, range: 9),
      ]);
      expect(validateCaveSpec(spec, ship: kTalon),
          contains(predicate<String>((s) => s.contains('can see the goal'))));
    });

    test('a turret floating in open space is rejected', () {
      final spec = _withDefences(base, obstacles: [
        const TurretSpec(Pt(17, 10.5), facing: kFaceUp),
      ]);
      expect(validateCaveSpec(spec, ship: kTalon),
          contains(predicate<String>((s) => s.contains('not on a wall'))));
    });

    test('a reactor needs an armed ship', () {
      final spec = _withDefences(base, obstacles: [
        const ReactorSpec(Pt(17, 10.5)),
      ]);
      expect(validateCaveSpec(spec, ship: kKestrel),
          contains(predicate<String>((s) => s.startsWith('REACTOR') && s.contains('unarmed'))));
      expect(
        validateCaveSpec(spec, ship: kTalon).where((s) => s.startsWith('REACTOR')),
        isEmpty,
      );
    });

    test('a fuel canister buried in rock is rejected', () {
      final spec = _withDefences(base, pickups: [const FuelCellSpec(Pt(17, 1))]);
      expect(validateCaveSpec(spec, ship: kTalon),
          contains(predicate<String>((s) => s.startsWith('PICKUP'))));
    });

    test('every reactor level is flown by an armed ship', () {
      for (final def in redoubtLevels.whereType<CaveLevelDef>()) {
        if (def.spec.obstacles.any((o) => o is ReactorSpec)) {
          expect(shipById(def.spec.shipId ?? redoubtShipId).armed, isTrue,
              reason: def.spec.id);
        }
      }
    });
  });

  group('contracts', () {
    test('turret contract counts kills and is gated on armed worlds', () {
      const c = Contract(ContractKind.destroyTurrets, target: 4);
      const e = DeliveryEvent(
        worldIndex: 6,
        challenge: false,
        clean: true,
        fuelFraction: 0.5,
        seconds: 60,
        newStars: 0,
        personalBest: false,
        turretsDestroyed: 3,
      );
      expect(contractProgress(c, e), 3);
      for (int d = 1; d <= 60; d++) {
        final list = generateContracts(DateTime(2026, 2, d),
            unlockedWorlds: [0], starsRemaining: 10, dailyDone: false);
        expect(list.map((c) => c.kind), isNot(contains(ContractKind.destroyTurrets)));
      }
      final offered = [
        for (int d = 1; d <= 60; d++)
          ...generateContracts(DateTime(2026, 2, d),
              unlockedWorlds: [0], starsRemaining: 10, dailyDone: false, armedUnlocked: true),
      ];
      expect(offered.map((c) => c.kind), contains(ContractKind.destroyTurrets));
    });
  });
}
