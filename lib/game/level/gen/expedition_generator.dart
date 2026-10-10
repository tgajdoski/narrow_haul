// Authoring-time Expedition generator (docs/STORY.md §3). Pure Dart: the
// tool `dart run tool/generate_expedition.dart` runs it, writes the chosen
// levels as const data (`specs/expeditions_gen.dart`), and the game never
// generates anything at runtime. Every candidate must pass the validator on
// every leg; the autopilot then proves 3★ before a level ships.

import 'dart:math' as math;

import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/level_validator.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// What a stretch of tunnel holds. Rooms are laid left to right along a
/// leg; the pod's pocket and the staging pad are added by the generator.
enum Room {
  /// Open tunnel, a gentle bend.
  plain,

  /// A narrow neck (the ship's clearance plus a little).
  squeeze,

  /// The tunnel climbs / drops 4–6 m.
  climb,
  drop,

  /// A chamber with a rotating bar, a pendulum or a crusher block.
  bar,
  pendulum,
  block,

  /// A chamber where nothing falls.
  zeroG,

  /// A chamber with an updraft / a gusting crosswind.
  updraft,
  crosswind,

  /// A gravity well in the rock above the tunnel.
  well,

  /// A gun on the chamber ceiling (armed ships only).
  turret,

  /// A fuel canister on the way.
  canister,
}

/// An Expedition to generate: the theme, ship and physics, and per leg the
/// rooms between its start and its pad (the pod's pocket goes after
/// [podAfter] of them).
class ExpeditionOutline {
  const ExpeditionOutline({
    required this.id,
    required this.name,
    required this.themeId,
    required this.seed,
    required this.shipId,
    required this.legs,
    this.modifiers = const LevelModifiers(),
    this.worldH = 34,
    this.podAfter = 1,
    this.noiseAmplitude = 0.22,
  });

  final String id;
  final String name;
  final String themeId;
  final int seed;
  final String shipId;
  final List<List<Room>> legs;
  final LevelModifiers modifiers;
  final double worldH;
  final int podAfter;
  final double noiseAmplitude;
}

/// A generated, validated Expedition.
class GeneratedExpedition {
  const GeneratedExpedition({
    required this.outline,
    required this.spec,
    required this.stars,
    required this.attempt,
    required this.routeLength,
    required this.legFuel,
  });

  final ExpeditionOutline outline;
  final LevelSpec spec;
  final StarSpec stars;

  /// Which reseed passed (the spec's [LevelSpec.seed] is outline seed + it).
  final int attempt;

  /// Metres along the estimated route, all legs.
  final double routeLength;

  /// Estimated burn per leg (tank fraction).
  final List<double> legFuel;
}

/// Tries reseeds of [o] until [keep] pass validation (or [attempts] run
/// out) and returns the one whose route length is closest to [targetLength]
/// metres; null if none passes. [onAttempt] reports each try (tooling).
GeneratedExpedition? generateExpedition(
  ExpeditionOutline o, {
  int attempts = 30,
  int keep = 3,
  double targetLength = 0,
  void Function(int attempt, List<String> issues)? onAttempt,
}) {
  final ship = shipById(o.shipId);
  final passed = <GeneratedExpedition>[];
  for (var a = 0; a < attempts && passed.length < keep; a++) {
    final spec = _lay(o, ship, a);
    final issues = validateCaveSpec(spec, ship: ship);
    onAttempt?.call(a, issues);
    if (issues.isNotEmpty) continue;
    final legs = analyzeLegs(spec, ship: ship);
    if (legs.any((l) => l == null)) continue;
    final length = legs.fold(0.0, (s, l) => s + l!.pathLength);
    final fuel = [for (final l in legs) l!.fuelFraction];
    passed.add(GeneratedExpedition(
      outline: o,
      spec: spec,
      stars: _stars(length, fuel, spec.legs.length,
          guns: spec.obstacles.any((ob) => ob is TurretSpec)),
      attempt: a,
      routeLength: length,
      legFuel: fuel,
    ));
  }
  if (passed.isEmpty) return null;
  final target = targetLength > 0 ? targetLength : 40.0 * o.legs.length;
  passed.sort((x, y) => (x.routeLength - target).abs().compareTo((y.routeLength - target).abs()));
  return passed.first;
}

/// Star targets from the estimate: 3★ keeps a margin over the estimated
/// mean burn per leg (more with [guns]: every cannon shot costs fuel the
/// estimate doesn't see); the clock allows ~1.3 m/s plus 10 s a leg. The
/// autopilot report says whether they're fair.
StarSpec _stars(double length, List<double> legFuel, int legs, {bool guns = false}) {
  final mean = legFuel.reduce((a, b) => a + b) / legFuel.length;
  double r05(double v) => (v * 20).round() / 20;
  final star3 = r05((1 - mean * 1.6 - (guns ? 0.12 : 0)).clamp(0.35, 0.65));
  return StarSpec(
    star3Fuel: star3,
    star2Fuel: r05((star3 - 0.3).clamp(0.15, 0.4)),
    star3Time: ((length / 1.3 + 10 * legs) / 10).round() * 10.0,
  );
}

// ── Layout ───────────────────────────────────────────────────────────────────

class _Builder {
  _Builder(this.o, this.ship, int attempt)
      : rng = math.Random(o.seed * 7919 + attempt),
        seed = o.seed + attempt;

  final ExpeditionOutline o;
  final ShipSpec ship;
  final math.Random rng;
  final int seed;

  final tunnels = <TunnelSpec>[];
  final chambers = <ChamberSpec>[];
  final obstacles = <ObstacleSpec>[];
  final fields = <FieldSpec>[];
  final pickups = <PickupSpec>[];
  final legs = <LegSpec>[];

  double get wide => math.max(1.7, ship.circumradius + 0.95);
  double get narrow => ship.circumradius + 0.6;
  double get yMin => 6.5;
  double get yMax => o.worldH - 11;

  double r(double a, double b) => a + rng.nextDouble() * (b - a);
  double q(double v) => (v * 10).round() / 10;
  Pt p(double x, double y) => Pt(q(x), q(y));

  // The tunnel being laid (one per leg).
  final _pts = <Pt>[];
  final _w = <double>[];
  void add(double x, double y, double w) {
    _pts.add(p(x, y));
    _w.add(q(w));
  }

  void flush() {
    if (_pts.length >= 2) tunnels.add(TunnelSpec(List.of(_pts), widths: List.of(_w)));
    _pts.clear();
    _w.clear();
  }

  double x = 6;
  late double y = q(r(yMin + 2, yMax - 2));

  LevelSpec build() {
    chambers.add(ChamberSpec(p(x, y), 2.6));
    final spawn = p(x, y);
    for (var k = 0; k < o.legs.length; k++) {
      add(x, y, wide);
      // Leave a pad (or the spawn) level, never straight down a shaft.
      x += r(5.5, 7);
      y = q((y + r(-1.2, 1.2)).clamp(yMin, yMax));
      add(x, y, wide);
      final rooms = o.legs[k];
      Pt? pod;
      for (var i = 0; i <= rooms.length; i++) {
        if (i == math.min(o.podAfter, rooms.length) && pod == null) pod = _pocket();
        if (i < rooms.length) _room(rooms[i]);
      }
      final pad = _pad();
      flush();
      // A pod near a field waits locked until hooked.
      final clamped = fields.any((f) => _near(f, pod!, 8));
      legs.add(LegSpec(pod!, GoalSpec(Pt(pad.x, q(pad.y + 1.2))), cargoClamped: clamped));
    }
    return LevelSpec.expedition(
      id: o.id,
      seed: seed,
      name: o.name,
      themeId: o.themeId,
      worldW: (x + 7).ceilToDouble(),
      worldH: o.worldH,
      modifiers: o.modifiers,
      noise: NoiseSpec(amplitude: o.noiseAmplitude),
      tunnels: List.unmodifiable(tunnels),
      chambers: List.unmodifiable(chambers),
      obstacles: List.unmodifiable(obstacles),
      fields: List.unmodifiable(fields),
      pickups: List.unmodifiable(pickups),
      shipSpawn: spawn,
      shipId: o.shipId,
      legs: List.unmodifiable(legs),
    );
  }

  /// The pod's pocket: a dip under the tunnel (it joins above the pocket's
  /// centre, so the pod rests in a bowl).
  Pt _pocket() {
    x += r(4, 5);
    final depth = r(3.5, 5.5);
    add(x, y + depth, wide);
    final pod = p(x, y + depth + 1);
    chambers.add(ChamberSpec(pod, 1.8));
    x += r(4, 5);
    add(x, y, wide);
    return pod;
  }

  /// The staging pad's chamber, on the tunnel.
  Pt _pad() {
    x += r(6, 8);
    y = q((y + r(-1, 1)).clamp(yMin, yMax));
    final c = p(x, y);
    add(c.x, c.y, wide);
    chambers.add(ChamberSpec(c, 3.0, 2.4));
    return c;
  }

  /// A chamber on the tunnel at the cursor (after a short run to it).
  Pt _chamber(double rx, double ry) {
    x += r(6, 7.5);
    final c = p(x, y);
    add(c.x, c.y, wide);
    chambers.add(ChamberSpec(c, rx, ry));
    x += r(1, 2);
    return c;
  }

  void _room(Room room) {
    switch (room) {
      case Room.plain:
        x += r(6, 8);
        y = q((y + r(-2, 2)).clamp(yMin, yMax));
        add(x, y, wide);
      case Room.squeeze:
        x += r(4, 5);
        add(x, y + r(-0.6, 0.6), wide);
        x += r(3, 4);
        add(x, y + r(-0.4, 0.4), narrow);
        x += r(3, 4);
        add(x, y, wide);
      case Room.climb || Room.drop:
        final dy = r(4, 6) * (room == Room.climb ? -1 : 1);
        x += r(5, 6);
        add(x, y + dy * 0.4, wide);
        x += r(4, 5);
        y = q((y + dy).clamp(yMin, yMax));
        add(x, y, wide);
      case Room.bar:
        final c = _chamber(3.4, 3.2);
        obstacles.add(RotatingBarSpec(c,
            halfLength: 1.6, radPerSec: q(r(0.8, 1.1)) * (rng.nextBool() ? 1 : -1)));
      case Room.pendulum:
        final c = _chamber(3.4, 3.2);
        obstacles.add(PendulumSpec(Pt(c.x, q(c.y - 2.6)),
            length: 2.4, amplitudeRad: 0.8, periodSec: q(r(2.5, 3.0)), phase: q(r(0, 2))));
      case Room.block:
        final c = _chamber(3.0, 3.2);
        obstacles.add(SlidingBlockSpec(Pt(c.x, q(c.y - 2.2)), Pt(c.x, q(c.y + 2.2)),
            halfW: 0.55, halfH: 0.7, periodSec: q(r(3.2, 3.8)), phase: q(r(0, 1))));
      case Room.zeroG:
        final c = _chamber(3.6, 2.6);
        fields.add(GravityZoneSpec(c, halfW: 3, halfH: 2, gx: 0, gy: 0, feather: 1.2));
      case Room.updraft:
        final c = _chamber(3.0, 2.8);
        fields.add(WindZoneSpec(c,
            halfW: 2.5, halfH: 2.5, ax: 0, ay: -0.25, gustAmp: 0.4, gustPeriod: 4));
      case Room.crosswind:
        final c = _chamber(3.6, 2.6);
        fields.add(WindZoneSpec(c,
            halfW: 3, halfH: 2.2, ax: rng.nextBool() ? 0.22 : -0.22, ay: 0, gustAmp: 0.5, gustPeriod: 3.5));
      case Room.well:
        final c = _chamber(3.6, 2.6);
        fields.add(GravityWellSpec(Pt(c.x, q(c.y - 3.8)), strength: 2.5, coreRadius: 1.0, maxG: 1.4));
      case Room.turret:
        final c = _chamber(3.6, 2.8);
        obstacles.add(TurretSpec(Pt(c.x, q(c.y - 2.75)),
            facing: kFaceDown, range: 7, phase: q(r(0, 1.5))));
      case Room.canister:
        x += r(5, 6);
        add(x, y, wide);
        pickups.add(FuelCellSpec(p(x, y), amount: 25));
    }
  }

  static bool _near(FieldSpec f, Pt a, double d) {
    final c = switch (f) {
      GravityZoneSpec() => f.center,
      WindZoneSpec() => f.center,
      GravityWellSpec() => f.center,
    };
    return (c.x - a.x) * (c.x - a.x) + (c.y - a.y) * (c.y - a.y) < d * d;
  }
}

LevelSpec _lay(ExpeditionOutline o, ShipSpec ship, int attempt) => _Builder(o, ship, attempt).build();

// ── Dart output ──────────────────────────────────────────────────────────────

String _n(double v) {
  final s = v.toStringAsFixed(2);
  final t = s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
  return t.contains('.') ? t : '$t.0';
}

String _pt(Pt p) => 'Pt(${_n(p.x)}, ${_n(p.y)})';

/// [g] as a `CaveLevelDef(...)` expression (const data, `dart format` it).
String expeditionToDart(GeneratedExpedition g) {
  final s = g.spec;
  final o = g.outline;
  final b = StringBuffer();
  final rooms = [for (final l in o.legs) l.map((r) => r.name).join(' ')].join(' | ');
  b.writeln('  // ${o.id} · generated from seed ${o.seed} (attempt ${g.attempt}): $rooms');
  b.writeln('  // route ~${g.routeLength.round()} m, burn per leg '
      '${g.legFuel.map((f) => '${(f * 100).round()}%').join(' / ')}');
  b.writeln('  CaveLevelDef(');
  b.writeln('    stars: const StarSpec(star3Fuel: ${_n(g.stars.star3Fuel)}, '
      'star2Fuel: ${_n(g.stars.star2Fuel)}, star3Time: ${_n(g.stars.star3Time)}),');
  b.writeln('    spec: LevelSpec.expedition(');
  b.writeln("      id: '${s.id}',");
  b.writeln('      seed: ${s.seed},');
  b.writeln("      name: ${_str(s.name)},");
  b.writeln("      themeId: '${s.themeId}',");
  b.writeln("      shipId: '${s.shipId}',");
  b.writeln('      worldW: ${_n(s.worldW)},');
  b.writeln('      worldH: ${_n(s.worldH)},');
  final m = s.modifiers;
  b.writeln('      modifiers: const LevelModifiers(gravityMul: ${_n(m.gravityMul)}, '
      'fuelDrainMul: ${_n(m.fuelDrainMul)}, cargoDensityMul: ${_n(m.cargoDensityMul)}'
      '${m.wallFriction != null ? ', wallFriction: ${_n(m.wallFriction!)}' : ''}),');
  b.writeln('      noise: const NoiseSpec(amplitude: ${_n(s.noise.amplitude)}),');
  b.writeln('      tunnels: const [');
  for (final t in s.tunnels) {
    b.writeln('        TunnelSpec([${t.points.map(_pt).join(', ')}],');
    b.writeln('            widths: [${t.radii.map(_n).join(', ')}]),');
  }
  b.writeln('      ],');
  b.writeln('      chambers: const [');
  for (final c in s.chambers) {
    b.writeln('        ChamberSpec(${_pt(c.center)}, ${_n(c.rx)}, ${_n(c.ry)}),');
  }
  b.writeln('      ],');
  if (s.obstacles.isNotEmpty) {
    b.writeln('      obstacles: const [');
    for (final ob in s.obstacles) {
      b.writeln('        ${_obstacle(ob)},');
    }
    b.writeln('      ],');
  }
  if (s.fields.isNotEmpty) {
    b.writeln('      fields: const [');
    for (final f in s.fields) {
      b.writeln('        ${_field(f)},');
    }
    b.writeln('      ],');
  }
  if (s.pickups.isNotEmpty) {
    b.writeln('      pickups: const [');
    for (final pk in s.pickups) {
      final c = pk as FuelCellSpec;
      b.writeln('        FuelCellSpec(${_pt(c.pos)}, amount: ${_n(c.amount)}),');
    }
    b.writeln('      ],');
  }
  b.writeln('      shipSpawn: const ${_pt(s.shipSpawn)},');
  b.writeln('      legs: const [');
  for (final l in s.legs) {
    b.writeln('        LegSpec(${_pt(l.cargoSpawn)}, GoalSpec(${_pt(l.goal.center)})'
        '${l.cargoClamped ? ', cargoClamped: true' : ''}),');
  }
  b.writeln('      ],');
  b.writeln('    ),');
  b.writeln('  ),');
  return b.toString();
}

String _str(String v) => v.contains("'") ? '"$v"' : "'$v'";

String _obstacle(ObstacleSpec o) => switch (o) {
      RotatingBarSpec s =>
        'RotatingBarSpec(${_pt(s.center)}, halfLength: ${_n(s.halfLength)}, radPerSec: ${_n(s.radPerSec)})',
      PendulumSpec s => 'PendulumSpec(${_pt(s.pivot)}, length: ${_n(s.length)}, '
          'amplitudeRad: ${_n(s.amplitudeRad)}, periodSec: ${_n(s.periodSec)}, phase: ${_n(s.phase)})',
      SlidingBlockSpec s => 'SlidingBlockSpec(${_pt(s.from)}, ${_pt(s.to)}, halfW: ${_n(s.halfW)}, '
          'halfH: ${_n(s.halfH)}, periodSec: ${_n(s.periodSec)}, phase: ${_n(s.phase)})',
      TurretSpec s => 'TurretSpec(${_pt(s.base)}, facing: kFaceDown, range: ${_n(s.range)}, phase: ${_n(s.phase)})',
      ReactorSpec s => 'ReactorSpec(${_pt(s.center)})',
    };

String _field(FieldSpec f) => switch (f) {
      GravityZoneSpec s => 'GravityZoneSpec(${_pt(s.center)}, halfW: ${_n(s.halfW)}, halfH: ${_n(s.halfH)}, '
          'gx: ${_n(s.gx)}, gy: ${_n(s.gy)}, feather: ${_n(s.feather)})',
      WindZoneSpec s => 'WindZoneSpec(${_pt(s.center)}, halfW: ${_n(s.halfW)}, halfH: ${_n(s.halfH)}, '
          'ax: ${_n(s.ax)}, ay: ${_n(s.ay)}, gustAmp: ${_n(s.gustAmp)}, gustPeriod: ${_n(s.gustPeriod)})',
      GravityWellSpec s => 'GravityWellSpec(${_pt(s.center)}, strength: ${_n(s.strength)}, '
          'coreRadius: ${_n(s.coreRadius)}, maxG: ${_n(s.maxG)})',
    };
