// Autopilot flight test: flies every level through the real game physics
// and checks each one is 3★-able with a human margin.
//
//   flutter test test/autopilot --dart-define=STORE_CAPTURE=true \
//     [--dart-define=LEVELS=alien_01,mine_03] [--dart-define=CLEAN=true]
//
// Debug knobs: PROFILE=<name>, TRACE=<frames>, NOSEARCH=true, DODGE=true.
// STORE_CAPTURE gives full release gravity (debug builds fly at 70%).
// Writes build/autopilot_report.md and build/autopilot_report.json.
@Tags(['autopilot'])
library;
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/route_planner.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

import 'autopilot.dart';
import 'harness.dart';

const _levels = String.fromEnvironment('LEVELS');
const _cleanOnly = bool.fromEnvironment('CLEAN');
const _trace = int.fromEnvironment('TRACE');
const _profile = String.fromEnvironment('PROFILE');
const _noSearch = bool.fromEnvironment('NOSEARCH');
const _dodgeOnly = bool.fromEnvironment('DODGE');

/// A player is assumed to need this much more fuel and time than the bot's
/// best flight (calibrate against real runs: the debug `RUN` log line).
const double kHumanFuelFactor = 1.3;
const double kHumanTimeFactor = 1.3;

/// Levels the bot can't fly with hazards on are judged on the clean run
/// plus this allowance for dodging/shooting — and need a human playtest.
const double kHazardFuelAllowance = 0.15;
const double kHazardTimeAllowance = 20;

/// Matches `FuelCell.pickupRadius`.
const double kPickupRadius = 0.8;

/// Levels known to beat the bot (turret kills in tight vertical shafts with
/// no hidden firing spot); verified by human playtest instead.
const kNeedsHumanPlaytest = {'redoubt_02', 'redoubt_04'};

enum Verdict { pass, tight, botFail }

class LevelReport {
  LevelReport(this.def, this.shipId, this.real, this.clean,
      {required this.grid, required this.anchors, required this.pickups});

  /// Fuel canisters in the level.
  final List<FuelCellSpec> pickups;
  final LevelDef def;
  final String shipId;
  final FlightResult? real;
  final FlightResult? clean;
  final NavGrid grid;

  /// Spawn, pod and pad centres (canisters keep clear of them).
  final List<Pt> anchors;

  /// Canisters (position, units) that would close [fuelDeficit].
  late final List<(Pt, double)> canisters = _suggestCanisters();

  /// Fuel units a player gets back from the canisters on [r]'s route, and
  /// the track index of the last pickup (-1 if none).
  (double, int) _creditAndLast(FlightResult r) {
    final pending = [...pickups];
    var credit = 0.0;
    var last = -1;
    for (var k = 0; k < r.track.length; k++) {
      final t = r.track[k];
      pending.removeWhere((c) {
        if (_dist(c.pos, Pt(t.x, t.y)) > kPickupRadius) return false;
        credit += math.max(0, math.min(c.amount, t.burned * kHumanFuelFactor - credit));
        last = k;
        return true;
      });
    }
    return (credit, last);
  }

  double _credit(FlightResult r) => _creditAndLast(r).$1;

  List<(Pt, double)> _suggestCanisters() {
    if (fuelDeficit <= 0) return const [];
    final source = delivered ? real : clean;
    if (source == null || source.track.isEmpty) return const [];
    final tank = shipById(shipId).maxFuel;
    // Round up to 5 units; split when one canister would be over 40% of the tank.
    var total = (fuelDeficit * tank / 5).ceil() * 5.0;
    total = math.max(total, 5);
    final count = total > 0.4 * tank ? 2 : 1;
    final each = (total / count / 5).ceil() * 5.0;
    final goal = anchors.last;
    final out = <(Pt, double)>[];
    // Refunds already collected leave less room in the tank; new canisters
    // go after the last one collected.
    final (credited, lastPickup) = _creditAndLast(source);
    var need = credited;
    var from = lastPickup + 25;
    for (var n = 0; n < count; n++) {
      // The pickup only counts in full once a player has burned this much
      // (the tank caps the rest); a player burns ~kHumanFuelFactor × the bot.
      need += each;
      final want = need + 0.05 * tank;
      Pt? spot;
      for (var k = from; k < source.track.length; k++) {
        final t = source.track[k];
        if (t.burned * kHumanFuelFactor < want) continue;
        final p = Pt(t.x, t.y);
        if (anchors.any((a) => _dist(a, p) < 2.5)) continue;
        if (_dist(goal, p) < 4) continue;
        if (pickups.any((c) => _dist(c.pos, p) < 3) || out.any((c) => _dist(c.$1, p) < 3)) continue;
        if (grid.clearanceAt(p.x, p.y) < 0.75) continue;
        spot = p;
        from = k + 25; // the next one at least ~2.5 s later
        break;
      }
      if (spot == null) break;
      out.add((Pt((spot.x * 10).round() / 10, (spot.y * 10).round() / 10), each));
    }
    return out;
  }

  double get budget => 1 - def.stars.star3Fuel;
  double get timeLimit => def.stars.star3Time;
  bool get delivered => real?.outcome == FlightOutcome.delivered;

  /// Fuel fraction / seconds a player is expected to need.
  double? get humanFuel => delivered
      ? _playerFuel(real!, 0)
      : clean?.outcome == FlightOutcome.delivered
          ? _playerFuel(clean!, kHazardFuelAllowance)
          : null;

  /// A player burns kHumanFuelFactor × the bot's gross burn (+ [allowance]
  /// of the tank); each canister on the flown route refunds what the
  /// player's tank has room for at that moment (`onFuelCollected` caps at
  /// the tank).
  double _playerFuel(FlightResult r, double allowance) {
    final tank = shipById(shipId).maxFuel;
    if (r.track.isEmpty) return (r.fuelUsed + allowance) * kHumanFuelFactor;
    final credit = _credit(r);
    final gross = r.track.last.burned * kHumanFuelFactor + allowance * kHumanFuelFactor * tank;
    return (gross - credit) / tank;
  }
  double? get humanTime => delivered
      ? real!.seconds * kHumanTimeFactor
      : clean?.outcome == FlightOutcome.delivered
          ? (clean!.seconds + kHazardTimeAllowance) * kHumanTimeFactor
          : null;

  Verdict get verdict {
    if (!delivered) return Verdict.botFail;
    return humanFuel! <= budget && humanTime! <= timeLimit ? Verdict.pass : Verdict.tight;
  }

  /// Extra fuel (fraction of the tank) a player needs for 3★.
  double get fuelDeficit => math.max(0, (humanFuel ?? 1) - budget);

  Map<String, Object?> toJson() => {
        'id': def.saveId,
        'ship': shipId,
        'verdict': verdict.name,
        'budgetFuel': budget,
        'star3Time': timeLimit,
        'real': _resultJson(real),
        'clean': _resultJson(clean),
        'humanFuel': humanFuel,
        'humanTime': humanTime,
        'fuelDeficit': fuelDeficit,
        'canisters': [
          for (final (p, a) in canisters) {'x': p.x, 'y': p.y, 'amount': a},
        ],
      };
}

Map<String, Object?>? _resultJson(FlightResult? r) => r == null
    ? null
    : {
        'outcome': r.outcome.name,
        'fuelUsed': r.fuelUsed,
        'seconds': r.seconds,
        'stars': r.stars,
        'note': r.note.trim(),
      };

void main() {
  test('every level is 3★-able', () async {
    expect(kStoreCapture, isTrue, reason: 'run with --dart-define=STORE_CAPTURE=true');
    final h = GameHarness();
    await h.boot();
    final wanted = _levels.isEmpty ? null : _levels.split(',').toSet();
    final reports = <LevelReport>[];
    for (var i = 0; i < LevelRegistry.totalLevels; i++) {
      final def = LevelRegistry.defAt(i);
      if (wanted != null && !wanted.contains(def.saveId)) continue;
      await h.loadLevel(i);
      final grid = _gridFor(def, h);
      final real = _cleanOnly ? null : await _bestOver(h, i, grid, def, clean: false);
      final clean = await _bestOver(h, i, grid, def, clean: true);
      final l = h.game.currentLevel!;
      final report = LevelReport(def, LevelRegistry.shipFor(i).id, real, clean,
          grid: grid,
          anchors: [
            for (final v in [l.shipSpawn, l.cargoSpawn, l.goalCenter]) Pt(v.x, v.y),
          ],
          pickups: l.pickups.whereType<FuelCellSpec>().toList());
      reports.add(report);
      print('${def.saveId.padRight(13)} ${report.verdict.name.padRight(7)} '
          'real: ${real ?? '-'} | clean: $clean');
    }
    _writeReport(reports);
    final bad = [
      for (final r in reports)
        if (r.verdict != Verdict.pass && !kNeedsHumanPlaytest.contains(r.def.saveId)) r.def.saveId,
    ];
    if (!_cleanOnly) expect(bad, isEmpty, reason: 'levels not 3★-able with a human margin');
  }, timeout: const Timeout(Duration(hours: 2)));
}

/// Best delivery over the pilot profiles (stars first, then fuel margin).
Future<FlightResult?> _bestOver(GameHarness h, int index, NavGrid grid, LevelDef def,
    {required bool clean}) async {
  FlightResult? best;
  for (final profile in kPilotProfiles) {
    if (_profile.isNotEmpty && profile.name != _profile) continue;
    await h.loadLevel(index, skipHazards: clean);
    final r = await _flySearching(h, index, grid, profile, clean: clean);
    if (_profile.isNotEmpty || _trace > 0) print('  ${def.saveId} ${profile.name} $r');
    final tagged = _tag(r, profile.name);
    if (best == null || (r.outcome == FlightOutcome.delivered && !_better(best, r, def))) {
      best = tagged;
    }
  }
  return best;
}

void _writeReport(List<LevelReport> reports) {
  String pct(double? f) => f == null ? '–' : '${(f * 100).round()}%';
  String secs(double? s) => s == null ? '–' : '${s.toStringAsFixed(0)} s';
  final b = StringBuffer()
    ..writeln('# Autopilot 3★ report')
    ..writeln()
    ..writeln('Fuel = share of the tank burned. "Player" = bot × $kHumanFuelFactor '
        '(fuel) / × $kHumanTimeFactor (time); bot failures use the clean run + '
        '${(kHazardFuelAllowance * 100).round()}% fuel / ${kHazardTimeAllowance.round()} s.')
    ..writeln()
    ..writeln('| Level | Ship | Verdict | Bot fuel | Bot time | Bot ★ | Clean fuel | '
        'Player fuel | 3★ fuel budget | Player time | 3★ time | Missing fuel |')
    ..writeln('|---|---|---|---|---|---|---|---|---|---|---|---|');
  for (final r in reports) {
    final real = r.delivered ? r.real : null;
    final cleanOk = r.clean?.outcome == FlightOutcome.delivered ? r.clean : null;
    b.writeln('| ${r.def.saveId} | ${r.shipId} | ${r.verdict.name} | '
        '${pct(real?.fuelUsed)} | ${secs(real?.seconds)} | ${real?.stars ?? '–'} | '
        '${pct(cleanOk?.fuelUsed)} | ${pct(r.humanFuel)} | ${pct(r.budget)} | '
        '${secs(r.humanTime)} | ${secs(r.timeLimit)} | '
        '${r.fuelDeficit > 0 ? pct(r.fuelDeficit) : ''} |');
  }
  b
    ..writeln()
    ..writeln('## Suggested fuel canisters')
    ..writeln()
    ..writeln('On the bot\'s route, where enough fuel has been burned for the '
        'pickup to count in full. Cave specs: `pickups:`; TMX: a `fuel` marker '
        '(pixels = m × 32, float property `amount`).')
    ..writeln();
  for (final r in reports) {
    if (r.canisters.isEmpty) continue;
    b.writeln('- **${r.def.saveId}** (missing ${(r.fuelDeficit * 100).round()}%): '
        '${r.canisters.map((c) => 'FuelCellSpec(Pt(${c.$1.x}, ${c.$1.y}), amount: ${c.$2.round()})').join(', ')}');
  }
  Directory('build').createSync(recursive: true);
  File('build/autopilot_report.md').writeAsStringSync(b.toString());
  File('build/autopilot_report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert([for (final r in reports) r.toJson()]));
}

/// Crossing tactics tried, in order, at each obstacle crossing.
final _tactics = [
  kCrossPredict,
  kCrossFlyThrough,
  for (var k = 0; k <= 20; k++) k * 0.2,
  for (var k = 0; k <= 20; k++) kCrossDash + k * 0.2,
];

/// Flies [index] with [profile]; when an obstacle wrecks the ship at
/// crossing n, retries with the next tactic for that crossing (earlier
/// crossings keep what worked) — deterministic trial and error.
Future<FlightResult> _flySearching(GameHarness h, int index, NavGrid grid, PilotProfile profile,
    {required bool clean}) async {
  if (clean) return _flyPlans(h, index, grid, profile, clean: true);
  // First choice: a route around every sweep, if the cave has one.
  if (!_noSearch) {
    final around = Autopilot(h.game, grid, profile, avoidSweeps: true)..traceEvery = _trace;
    final flown = await h.fly(around.step, describe: around.describe, abort: () => around.gaveUp);
    final r = FlightResult(
        outcome: flown.outcome,
        fuelLeft: flown.fuelLeft,
        seconds: flown.seconds,
        stars: flown.stars,
        note: flown.note,
        track: around.track);
    await h.loadLevel(index);
    if (r.outcome == FlightOutcome.delivered) {
      final searched = await _flyPlans(h, index, grid, profile, clean: false);
      return _better(r, searched, h.game.currentLevelDef) ? _tag(r, 'around') : searched;
    }
  }
  if (_noSearch) return _flyPlans(h, index, grid, profile, snipe: !_dodgeOnly, clean: false);
  FlightResult? best;
  final armed = h.game.ship!.spec.armed;
  for (final snipe in armed ? const [true, false] : const [true]) {
    for (final weight in const [3.0, 15.0]) {
      final r = await _flyPlans(h, index, grid, profile,
          sweepWeight: weight, snipe: snipe, clean: false);
      if (best == null || !_better(best, r, h.game.currentLevelDef)) {
        best = _tag(r, 'w=$weight${armed ? (snipe ? ' snipe' : ' dodge') : ''}');
      }
      await h.loadLevel(index);
      if (r.outcome == FlightOutcome.delivered) break;
    }
    if (best!.outcome == FlightOutcome.delivered) break;
  }
  return best!;
}

bool _better(FlightResult a, FlightResult b, LevelDef def) =>
    b.outcome != FlightOutcome.delivered || _score(a, def) >= _score(b, def);

FlightResult _tag(FlightResult r, String note) => FlightResult(
    outcome: r.outcome,
    fuelLeft: r.fuelLeft,
    seconds: r.seconds,
    stars: r.stars,
    note: '${r.note} $note',
    track: r.track);

Future<FlightResult> _flyPlans(GameHarness h, int index, NavGrid grid, PilotProfile profile,
    {double sweepWeight = 3, bool snipe = true, required bool clean}) async {
  final plan = <int>[]; // tactic index per crossing
  var tries = 0;
  var killed = 0;
  var track = const <TrackPoint>[];
  late FlightResult r;
  while (true) {
    if (tries > 0) await h.loadLevel(index, skipHazards: clean);
    tries++;
    final bot = Autopilot(h.game, grid, profile,
        crossPlan: [for (final t in plan) _tactics[t]], sweepWeight: sweepWeight, snipe: snipe)
      ..traceEvery = _trace;
    r = await h.fly(bot.step, describe: bot.describe, abort: () => bot.gaveUp);
    killed = bot.turretsKilled;
    track = bot.track;
    // Search only crashes the hazards had a hand in (hit, or holding/crossing
    // near one); a plain wall crash with no hazard nearby is final.
    final hazardRelated =
        bot.obstacleGap <= 0.35 || bot.crossings > 0 || bot.everHeld || bot.exposedNow;
    if (r.outcome != FlightOutcome.crashed || !hazardRelated || tries >= 120 || _noSearch) break;
    // The crossing that went wrong: the one in progress, else the next one.
    final k = bot.inCrossing ? bot.crossings - 1 : bot.crossings;
    while (plan.length <= k) {
      plan.add(0);
    }
    plan.removeRange(k + 1, plan.length);
    if (plan[k] + 1 >= _tactics.length) break;
    plan[k]++;
  }
  return FlightResult(
    outcome: r.outcome,
    fuelLeft: r.fuelLeft,
    seconds: r.seconds,
    stars: r.stars,
    note: '${r.note} tries=$tries plan=${plan.map((t) => _tactics[t]).toList()}'
        '${killed > 0 ? ' kills=$killed' : ''}',
    track: track,
  );
}

double _dist(Pt a, Pt b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

/// Higher is better: stars first, then fuel margin.
double _score(FlightResult r, LevelDef def) =>
    r.stars * 10 + (r.fuelLeft - def.stars.star3Fuel) - r.seconds / def.stars.star3Time * 0.01;

NavGrid _gridFor(LevelDef def, GameHarness h) {
  return switch (def) {
    CaveLevelDef d => NavGrid.forCave(d.spec),
    TmxLevelDef() => () {
        final l = h.game.currentLevel!;
        return NavGrid.forRects(
          [
            for (final w in l.walls)
              (cx: w.center.x, cy: w.center.y, hw: w.halfWidth, hh: w.halfHeight),
          ],
          l.worldSize.x,
          l.worldSize.y,
        );
      }(),
  };
}
