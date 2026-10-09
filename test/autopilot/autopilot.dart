// Autopilot for the headless flight test: plans a clearance-weighted route
// (pad → pod → goal) and flies it through the real game physics with the
// same inputs a player has (rotate axis, thrust on/off, fire).
import 'dart:math' as math;
import 'dart:typed_data';
// ignore_for_file: avoid_print

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/combat.dart';
import 'package:narrow_haul/game/components/defences.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/route_planner.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';

import 'harness.dart';
import 'hazards.dart';

const double kCrossPredict = -2;
const double kCrossFlyThrough = -1;

/// Added to a hold time: cross as a fast dash instead of at cruise.
const double kCrossDash = 100;

/// How hard the bot pushes: cruise speed (m/s) and safety margin (m) kept
/// beyond the hull's circumradius.
class PilotProfile {
  const PilotProfile(this.name, {required this.cruise, this.margin = 0.18, this.widthGain = 2.2});
  final String name;
  final double cruise;
  final double margin;

  /// Allowed speed per meter of spare clearance (tunnel width cap).
  final double widthGain;
}

const kPilotProfiles = [
  PilotProfile('careful', cruise: 2.2, margin: 0.22),
  PilotProfile('steady', cruise: 3.2),
  PilotProfile('brisk', cruise: 4.4, margin: 0.15),
  PilotProfile('racer', cruise: 5.5, margin: 0.15, widthGain: 3.2),
];

enum _Phase { wait, approach, tow, land }

enum _Snipe { settle, hop, aim }

/// Something the armed bot shoots: a turret (2 hits) or the reactor
/// (destroying it shuts every turret down for good).
class _Target {
  _Target.turret(Turret this.turret) : reactor = null;
  _Target.reactor(Reactor this.reactor) : turret = null;
  final Turret? turret;
  final Reactor? reactor;

  bool get done => turret?.destroyed ?? reactor!.destroyed;

  Pt get aim => turret != null ? domeAim(turret!.spec) : reactor!.spec.center;

  /// Point whose line of sight from [from] proves a clear shot.
  /// The point on the actual shot line (from → [aim]) just outside the
  /// target's body: clear sight to it means the shell reaches the target.
  Pt sightPoint(Pt from) {
    final a = aim;
    final dx = from.x - a.x;
    final dy = from.y - a.y;
    final d = math.max(1e-6, math.sqrt(dx * dx + dy * dy));
    final r = turret != null ? 0.45 : reactor!.spec.radius + 0.15;
    return Pt(a.x + dx / d * r, a.y + dy / d * r);
  }

  int get shotsPerCycle => turret != null ? 2 : 4;

  @override
  bool operator ==(Object other) =>
      other is _Target && other.turret == turret && other.reactor == reactor;

  @override
  int get hashCode => Object.hash(turret, reactor);
}

class Autopilot {
  Autopilot(this.game, this.grid, this.profile,
      {this.crossPlan = const [], this.avoidSweeps = false, this.sweepWeight = 3, this.snipe = true, this.assault = false})
      : hazards = ObstacleHazards.of(game) {
    if (!hazards.isEmpty) {
      _cost = hazards.occupancyCost(grid, _r + _hazardMargin,
          blockAll: avoidSweeps, weight: sweepWeight);
    }
  }

  /// Route around every obstacle sweep (fails where none exists).
  final bool avoidSweeps;

  /// How strongly routes avoid often-occupied parts of a sweep.
  final double sweepWeight;

  /// Armed ships shoot turrets before passing them (else: dodge like an
  /// unarmed ship).
  final bool snipe;

  /// Shoot from inside the target turret's view (closer, quicker; the
  /// shell dodge covers its return fire) when that beats hiding — what a
  /// pilot does when there's no hidden firing spot.
  final bool assault;

  final NarrowHaulGame game;
  final NavGrid grid;
  final PilotProfile profile;

  /// Moving obstacles (exact future positions).
  final ObstacleHazards hazards;
  Float32List? _cost;

  /// Clearance kept from moving obstacles beyond the hull circumradius.
  static const double _hazardMargin = 0.3;

  /// Per path point: inside some obstacle's sweep; cumulative arc length.
  List<bool> _danger = const [];
  List<double> _arc = const [];

  /// Danger run (path index range) the bot has committed to crossing.
  int _committedEnd = -1;

  /// Frames spent holding for the current crossing.
  int _holdFrames = 0;

  /// Obstacle crossings committed so far this flight.
  int crossings = 0;

  /// No route exists (the harness stops the flight).
  bool gaveUp = false;

  /// Held short of an obstacle sweep at some point.
  bool everHeld = false;

  /// Frames spent holding short of obstacle sweeps over the whole flight.
  int heldFramesTotal = 0;

  /// Per-crossing tactic (see [_hazardCap]).
  final List<double> crossPlan;

  /// Turret the (armed) bot is going to shoot, and where it stops to do it.
  _Target? _target;
  int _fireIdx = -1;
  double _shootTime = 0;

  /// Turrets the bot gave up shooting (their exposure becomes a crossing).
  final Set<_Target> _skipTargets = {};
  int turretsKilled = 0;

  _Phase _phase = _Phase.wait;
  List<Pt> _path = const [];
  int _idx = 0;
  double _pwm = 0;
  int _frame = 0;
  double _ropeLength = 1.2;
  String lastEvent = '';

  /// Frames the ship sits on its pad before launch (the pod settles).
  static const int _padFrames = 60;

  ShipBody get _ship => game.ship!;
  CargoBody get _cargo => game.cargo!;
  double get _r => _ship.spec.circumradius;

  /// Print a state line every [traceEvery] frames (0 = off).
  int traceEvery = 0;

  String describe() {
    final p = _ship.body.position;
    return '[$_phase at (${p.x.toStringAsFixed(1)},${p.y.toStringAsFixed(1)}) '
        'v=${_ship.body.linearVelocity.length.toStringAsFixed(1)} '
        'idx=$_idx/${_path.length} fuel=${_ship.fuel.toStringAsFixed(0)} '
        'cargo=(${_cargo.body.position.x.toStringAsFixed(1)},${_cargo.body.position.y.toStringAsFixed(1)}) '
        'rope=${_ropeLength.toStringAsFixed(2)} ang=${_ship.body.angle.toStringAsFixed(2)} '
        'wall=${(grid.clearanceAt(p.x, p.y) - _r).toStringAsFixed(2)} '
        'obst=${hazards.isEmpty ? '-' : (hazards.distanceAt(p.x, p.y, 0) - _r).toStringAsFixed(2)} '
        '${exposedNow ? 'EXPOSED ' : ''}'
        '${_target != null ? 'tgt@$_fireIdx ${_snipe.name} shots=${_ship.shotsFired} ' : ''}'
        'path0=${_path.isEmpty ? '-' : '(${_path.first.x.toStringAsFixed(1)},${_path.first.y.toStringAsFixed(1)})→(${_path.last.x.toStringAsFixed(1)},${_path.last.y.toStringAsFixed(1)})'} $lastEvent]';
  }

  /// Flight samples every 0.1 s after launch (see [TrackPoint]).
  final List<TrackPoint> track = [];
  double _burned = 0;
  double? _lastFuel;

  /// Frames spent in a live turret's view after launch.
  int exposedFrames = 0;

  void _record(int frame) {
    if (_ship.launched && exposedNow) exposedFrames++;
    final fuel = _ship.fuel;
    final last = _lastFuel;
    if (last != null && fuel < last) _burned += last - fuel;
    _lastFuel = fuel;
    if (_ship.launched && frame % 6 == 0) {
      final p = _ship.body.position;
      track.add((x: p.x, y: p.y, burned: _burned, towing: game.cargoAttachment?.attached ?? false));
    }
  }

  BotInput step(int frame) {
    _frame = frame;
    _record(frame);
    if (traceEvery > 0 && frame % traceEvery == 0) print('    t=${(frame / 60).toStringAsFixed(1)} ${describe()}');
    switch (_phase) {
      case _Phase.wait:
        // Let the pod settle in its pocket (up to 4 s; the clock isn't running).
        final settling = _cargo.body.linearVelocity.length > 0.02 && frame < 240;
        if (frame < _padFrames || settling) return BotInput.idle;
        if (!_planApproach()) {
          lastEvent = 'no approach route';
          gaveUp = true;
          return BotInput.idle;
        }
        _phase = _Phase.approach;
      case _Phase.approach:
        final c = _cargo.body.position;
        if ((Vector2(_aimedAt.x, _aimedAt.y) - c).length > 0.3) {
          _planApproach();
          lastEvent = 'pod moved';
        }
        if (game.cargoAttachment?.attached ?? false) {
          final rope = game.cargoAttachment!.rope;
          // A beam reels the pod in to its hold length under the winch.
          // A rope pays out to at least its shortest tow below the winch.
          final winch = _ship.body.worldPoint(Vector2(0, _ship.spec.rearLocalY));
          _ropeLength = (rope.isBeam
                  ? rope.beamHoldLength
                  : math.max((_cargo.body.position - winch).length, rope.minTowLength)) +
              _ship.spec.rearLocalY;
          if (!_planTow()) {
            lastEvent = 'no tow route';
            gaveUp = true;
          }
          _phase = _Phase.tow;
        }
      case _Phase.tow:
        final g = game.currentLevel!.goalCenter;
        if ((_ship.body.position - Vector2(g.x, g.y)).length < 3) {
          _phase = _Phase.land;
          _planLand();
        }
      case _Phase.land:
        break;
    }
    return _fly();
  }

  // ── Planning ─────────────────────────────────────────────────────────────

  double get _minClear => _r + profile.margin;

  /// [_plan], but through the first uncollected fuel canister within 2.5 m
  /// of the route (a pilot grabs fuel that's right there).
  List<Pt>? _planVia(Pt from, Pt to, {double tolerance = 0.25}) {
    final path = _plan(from, to, tolerance: tolerance);
    if (path == null) return null;
    // Only canisters that are safe to fetch (no sweep), and none while a
    // turret is still live (the sniping route comes first).
    final turrets = liveTurrets(game);
    if (turrets.isNotEmpty) return path;
    final cells = [
      for (final c in game.world.children)
        if (c is FuelCell &&
            !c.collected &&
            !turrets.any((t) => turretSees(grid, t.spec, c.spec.pos, extra: 0.6)) &&
            !(!hazards.isEmpty && hazards.sweeps(c.spec.pos, _r + _hazardMargin)))
          c.spec.pos,
    ];
    var bestK = path.length;
    Pt? via;
    for (final c in cells) {
      for (var k = 0; k < path.length; k++) {
        final dx = path[k].x - c.x;
        final dy = path[k].y - c.y;
        if (dx * dx + dy * dy < 2.5 * 2.5) {
          if (k < bestK && dx * dx + dy * dy > 0.3 * 0.3) {
            bestK = k;
            via = c;
          }
          break;
        }
      }
    }
    if (via == null) return path;
    final a = _plan(from, via, tolerance: 0.3);
    final b = _plan(via, to, tolerance: tolerance);
    if (a == null || b == null) return path;
    return [...a, ...b.skip(1)];
  }

  List<Pt>? _plan(Pt from, Pt to, {double tolerance = 0.25}) {
    for (final extra in [0.0, -0.06, -0.12]) {
      final raw = grid.findPath(from, to,
          minClear: _minClear + extra, tolerance: tolerance, extraCost: _cost);
      if (raw != null) return smoothPath(grid, raw, minClear: _minClear + extra);
    }
    return null;
  }

  Pt _pt(Vector2 v) => Pt(v.x, v.y);

  Pt _aimedAt = const Pt(0, 0);

  bool _planApproach() {
    final c = _cargo.body.position;
    _aimedAt = Pt(c.x, c.y);
    // Hover point right above the pod (the winch hook catches on the way down).
    final target = _bestHoverAbove(c, 0.85);
    final from = _pt(_ship.body.position);
    var path = _planVia(from, target, tolerance: 0.2);
    if (path == null) return false;
    // Armed: clear turrets that cover the tow route first, while the ship
    // is light — a detour through a spot each one can be shot from.
    final ways = _towRouteFiringSpots(target, path);
    if (ways.isNotEmpty) {
      final legs = <Pt>[];
      var at = from;
      for (final w in [...ways, target]) {
        final leg = _plan(at, w, tolerance: w == target ? 0.2 : 0.3);
        if (leg == null) {
          legs.clear();
          break;
        }
        legs.addAll(legs.isEmpty ? leg : leg.skip(1));
        at = w;
      }
      if (legs.isNotEmpty) path = legs;
    }
    _setPath(path);
    return true;
  }

  /// For each live turret that sees the planned tow route but not [approach]:
  /// a roomy point on the tow route (or near it) with a clear shot at it.
  List<Pt> _towRouteFiringSpots(Pt hover, List<Pt> approach) {
    if (!_ship.spec.armed || !snipe) return const [];
    final turrets = liveTurrets(game);
    if (turrets.isEmpty) return const [];
    final g = game.currentLevel!.goalCenter;
    final tow = _plan(hover, Pt(g.x, g.y - 1), tolerance: 0.4);
    if (tow == null) return const [];
    final out = <Pt>[];
    for (final t in turrets) {
      if (approach.any((p) => turretSees(grid, t.spec, p))) continue; // met on the way anyway
      if (!tow.any((p) => turretSees(grid, t.spec, p))) continue;
      final tgt = _Target.turret(t);
      Pt? best;
      var bestCost = double.infinity;
      for (final p in tow) {
        final clear = grid.clearanceAt(p.x, p.y);
        if (clear < _r + 0.45) continue;
        final front = tgt.sightPoint(p);
        final d = math.sqrt((p.x - front.x) * (p.x - front.x) + (p.y - front.y) * (p.y - front.y));
        if (d > 7 || d < 2 || !caveSight(grid, p, front, margin: 0.06)) continue;
        if (turrets.any((o) => o != t && turretSees(grid, o.spec, p, extra: 0.6))) continue;
        final aim = tgt.aim;
        final fromUp = math.atan2(aim.x - p.x, -(aim.y - p.y)).abs();
        final cost = fromUp * 0.5 + 0.12 * d + 0.4 / clear;
        if (cost < bestCost) {
          bestCost = cost;
          best = p;
        }
      }
      if (best != null) out.add(best);
    }
    // Nearest first from the ship.
    final here = _pt(_ship.body.position);
    out.sort((a, b) => _d2p(a, here).compareTo(_d2p(b, here)));
    return out;
  }

  Pt _bestHoverAbove(Vector2 c, double h) {
    for (final dy in [h, h - 0.15, h - 0.3, h + 0.15]) {
      final p = Pt(c.x, c.y - dy);
      if (grid.clearanceAt(p.x, p.y) >= _r + 0.08) return p;
    }
    return Pt(c.x, c.y - h);
  }

  /// Ship height over the pad so both ship and the hanging pod sit inside
  /// the goal rectangle.
  Pt _goalShipTarget() {
    final l = game.currentLevel!;
    final g = l.goalCenter;
    final want = g.y + l.goalHalfHeight - 0.2 - _ropeLength;
    final y = want.clamp(g.y - l.goalHalfHeight + 0.4, g.y + 0.2);
    return Pt(g.x, y);
  }

  bool _planTow() {
    final path = _planVia(_pt(_ship.body.position), _goalShipTarget(), tolerance: 0.3);
    if (path == null) return false;
    _setPath(path);
    return true;
  }

  void _planLand() {
    final path = _plan(_pt(_ship.body.position), _goalShipTarget(), tolerance: 0.1);
    if (path != null) _setPath(path);
  }

  void _setPath(List<Pt> path) {
    _path = path;
    _idx = 0;
    _committedEnd = -1;
    _arc = [0];
    for (var k = 1; k < path.length; k++) {
      _arc.add(_arc.last + math.sqrt(_d2p(path[k - 1], path[k])));
    }
    _refreshThreats();
  }

  /// Marks obstacle sweeps and turret exposure on the path. An armed ship
  /// picks the first turret it can snipe from outside its view; exposure it
  /// can't remove that way becomes a crossing like an obstacle sweep.
  void _refreshThreats() {
    final sweep = [
      for (final p in _path) !hazards.isEmpty && hazards.sweeps(p, _r + _hazardMargin),
    ];
    final turrets = liveTurrets(game);
    final seenBy = [
      for (final p in _path) [for (final t in turrets) if (turretSees(grid, t.spec, p)) t],
    ];
    _target = null;
    _fireIdx = -1;
    final firstExposed = seenBy.indexWhere((l) => l.isNotEmpty, _idx);
    if (_ship.spec.armed && snipe && firstExposed >= 0) {
      // Reactor first: destroying it silences every turret at once.
      final reactor = liveReactor(game);
      if (reactor != null) {
        final rt = _Target.reactor(reactor);
        final k = _skipTargets.contains(rt) ? -1 : _firingPoint(rt, firstExposed);
        if (k >= 0) {
          _target = rt;
          _fireIdx = k;
          _shootTime = 0;
        }
      }
      for (var e = firstExposed; e < _path.length && _target == null; e++) {
        for (final t in seenBy[e]) {
          final tt = _Target.turret(t);
          if (_skipTargets.contains(tt)) continue;
          final k = _firingPoint(tt, e);
          if (k >= 0) {
            _target = tt;
            _fireIdx = k;
            _shootTime = 0;
            break;
          }
        }
      }
    }
    final tgt = _target;
    _danger = [
      for (var k = 0; k < _path.length; k++)
        sweep[k] ||
            (tgt == null
                ? seenBy[k].isNotEmpty
                : k < _fireIdx
                    ? seenBy[k].any((t) => !assault || t != tgt.turret)
                    // Past the firing point the target is gone (the reactor
                    // takes every turret with it).
                    : tgt.reactor == null && seenBy[k].any((t) => t != tgt.turret)),
    ];
  }

  /// Path index before [exposedAt] (within 15 m) out of every turret's view
  /// with a clear shot at [t] — preferring shots that need the nose close to
  /// "up" (aiming down means falling); -1 if none.
  int _firingPoint(_Target t, int exposedAt) {
    var best = -1;
    var bestCost = double.infinity;
    final aim = t.aim;
    final turrets = liveTurrets(game);
    final open = assault && t.turret != null;
    final last = open ? _path.length - 1 : exposedAt - 1;
    for (var k = last; k >= _idx; k--) {
      if (_arc[exposedAt] - _arc[k] >= 15) break;
      if (_arc[k] - _arc[exposedAt] > 6) continue;
      final p = _path[k];
      // Towing, the hover wanders more (the pod swings): hide deeper.
      final pad = _phase == _Phase.approach || _phase == _Phase.wait ? 0.1 : 0.35;
      if (turrets.any((o) => o == t.turret
          ? !open && turretSees(grid, o.spec, p, extra: 0.9, arcPad: pad)
          : turretSees(grid, o.spec, p, extra: 0.6, arcPad: pad))) {
        continue;
      }
      final front = t.sightPoint(p);
      final d = math.sqrt((p.x - front.x) * (p.x - front.x) + (p.y - front.y) * (p.y - front.y));
      // Shells must clear the rock by more than the map's few cm of error.
      // Not right under its nose either: a falling, turned ship needs room.
      if (d > (open ? 8 : 10) || (open && d < 3) || !caveSight(grid, p, front, margin: 0.06)) continue;
      final clear = grid.clearanceAt(p.x, p.y);
      if (clear < _r + 0.35) continue;
      final fromUp = math.atan2(aim.x - p.x, -(aim.y - p.y)).abs();
      // Assault: roomy spots (a steady hover under fire), as little of the
      // route under fire as possible.
      final cost = open
          ? fromUp * 0.5 +
              0.12 * d +
              0.4 / clear +
              0.3 * math.max(0.0, _arc[k] - _arc[exposedAt]) +
              // Hovering in its view means dodging while aiming.
              (turretSees(grid, t.turret!.spec, p, extra: 0.9) ? 1.0 : 0.0)
          : fromUp + 0.05 * (_arc[exposedAt] - _arc[k]) + 0.03 * d;
      if (cost < bestCost) {
        bestCost = cost;
        best = k;
      }
    }
    return best;
  }



  /// Ship is currently in some live turret's view.
  bool get exposedNow {
    final p = _pt(_ship.body.position);
    return liveTurrets(game).any((t) => turretSees(grid, t.spec, p, extra: 0));
  }

  /// Sniping at the firing point, in cycles: settle, hop up a little, turn
  /// and fire a pair of shots while drifting, recover, repeat.
  _Snipe _snipe = _Snipe.settle;
  double _snipeTime = 0;
  int _shotsAtStart = 0;

  BotInput? _shoot() {
    final t = _target;
    if (t == null) return null;
    if (t.done) {
      turretsKilled++;
      lastEvent = 'killed#$turretsKilled@$_frame';
      _snipe = _Snipe.settle;
      _refreshThreats();
      return null;
    }
    final body = _ship.body;
    final p = body.position;
    final v = body.linearVelocity;
    final hold = _path[_fireIdx];
    final off = Vector2(hold.x - p.x, hold.y - p.y);
    final drift = _snipe == _Snipe.settle ? 0.9 : 2.2;
    final near = _arc[_fireIdx] - _arc[_idx] < 0.6 && off.length < drift;
    if (!near) {
      _snipe = _Snipe.settle;
      return null;
    }
    _shootTime += kStepDt;
    if (_shootTime > 15) {
      // Can't hit it from here: treat its exposure as a crossing instead.
      _skipTargets.add(t);
      lastEvent = 'skip turret@$_frame';
      _snipe = _Snipe.settle;
      _refreshThreats();
      return null;
    }
    _snipeTime += kStepDt;
    final g = _ship.localAccel;
    final up = g.length > 0.05 ? -g / g.length : Vector2(0, -1);
    switch (_snipe) {
      case _Snipe.settle:
        final settled = _shootTime > 1.5 || assault ? v.length < 0.6 && off.length < 0.7 : v.length < 0.35 && off.length < 0.4;
        // Under fire, a shot that points up needs no hop: fire right away.
        final aimUp = Vector2(t.aim.x - p.x, t.aim.y - p.y).normalized().dot(up) > 0.2;
        if (assault && aimUp && v.length < 1.0 && off.length < 0.8) {
          _snipe = _Snipe.aim;
          _snipeTime = 0;
          _shotsAtStart = _ship.shotsFired;
        } else if (settled) {
          _snipe = _Snipe.hop;
          _snipeTime = 0;
        }
        return null; // normal flight holds the point
      case _Snipe.hop:
        // Rise first so the aim turn (and turning back) doesn't cost height;
        // the steeper the shot points down, the bigger the hop.
        final aimPt = t.aim;
        final aimDir = Vector2(aimPt.x - p.x, aimPt.y - p.y)..normalize();
        // …but never into a low ceiling (hop height ≈ v²/2g + drift).
        final headroom = grid.clearanceAt(p.x + up.x * 0.8, p.y + up.y * 0.8) - _r;
        final hopSpeed = math.min(0.6 + 1.2 * ((1 - aimDir.dot(up)) / 2), 0.3 + 1.2 * math.max(0, headroom));
        if (v.dot(up) > hopSpeed || _snipeTime > 1.5 || g.length < 0.05) {
          _snipe = _Snipe.aim;
          _snipeTime = 0;
          _shotsAtStart = _ship.shotsFired;
        }
        return _steer(up, up * (hopSpeed + 0.2) - v, fire: false);
      case _Snipe.aim:
        final aim = t.aim;
        final dir = Vector2(aim.x - p.x, aim.y - p.y)..normalize();
        // Shells inherit the hull's velocity: point the nose so that
        // v_ship + muzzle·nose runs along the line of sight.
        final muzzle = _ship.spec.muzzleSpeed;
        final vPerp = v - dir * v.dot(dir);
        final along = math.sqrt(math.max(0, muzzle * muzzle - vPerp.length2));
        final nose = (dir * along - vPerp)..normalize();
        final fired = _ship.shotsFired - _shotsAtStart;
        if (fired >= t.shotsPerCycle || _snipeTime > 1.6 + 0.5 * t.shotsPerCycle) {
          _snipe = _Snipe.settle;
          return null;
        }
        // Lean against the drift (as far as the nose allows); the aim window
        // is the dome's size at this range.
        final dist = Vector2(aim.x - p.x, aim.y - p.y).length;
        return _steer(nose, off * 0.6 - v * 1.0,
            fire: true, aimTolerance: (0.3 / math.max(dist, 1)).clamp(0.025, 0.06));
    }
  }

  /// Point the nose along [heading]; thrust toward [accelWanted] (+ gravity
  /// compensation) only as far as the nose allows.
  BotInput _steer(Vector2 heading, Vector2 accelWanted, {required bool fire, double aimTolerance = 0}) {
    final body = _ship.body;
    final desired = math.atan2(heading.x, -heading.y);
    var err = (desired - body.angle) % (2 * math.pi);
    if (err > math.pi) err -= 2 * math.pi;
    final omega = _ship.spec.rotationSpeedRadPerSec;
    final rotate = (err / (omega * 0.1)).clamp(-1.0, 1.0);
    final aT = _thrustAccel(_phase == _Phase.tow || _phase == _Phase.land);
    final aCmd = accelWanted * 2.4 - _ship.localAccel;
    final nose = Vector2(math.sin(body.angle), -math.cos(body.angle));
    final duty = (aCmd.dot(nose) / aT).clamp(0.0, 1.0);
    _pwm += duty;
    final thrust = _pwm >= 1;
    if (thrust) _pwm -= 1;
    return BotInput(rotate: rotate, thrust: thrust, fire: fire && err.abs() < aimTolerance);
  }

  /// Speed cap from the next obstacle sweep (or turret exposure) on the
  /// path. What the bot does at crossing n is `crossPlan[n]`:
  /// [kCrossPredict] (default) waits for a gap its obstacle prediction says
  /// is clear, [kCrossFlyThrough] doesn't stop, and a value ≥ 0 holds a
  /// metre short, then goes after that many seconds (+[kCrossDash]: as a
  /// fast dash). The flight test searches these per crossing — a player's
  /// trial and error.
  double _hazardCap(double speed, double aT, double brake) {
    if (_idx <= _committedEnd) return double.infinity;
    var a = -1;
    for (var k = _idx; k < _path.length; k++) {
      if (_danger[k]) {
        a = k;
        break;
      }
    }
    if (a < 0) return double.infinity;
    var b = a;
    while (b + 1 < _path.length && _danger[b + 1]) {
      b++;
    }
    final toStart = _arc[a] - _arc[_idx];
    final holdBrake = 0.5 * brake;
    if (toStart > 3.0 + speed * speed / (2 * holdBrake)) return double.infinity;
    final holdCap = math.sqrt(2 * holdBrake * math.max(0, toStart - 1.0));
    final option = crossings < crossPlan.length ? crossPlan[crossings] : kCrossPredict;
    _dash = false;
    if (option == kCrossFlyThrough) {
      _commit(b);
      return double.infinity;
    }
    final holding = toStart < 1.8 && speed < 0.5;
    if (holding) {
      _holdFrames++;
      heldFramesTotal++;
      everHeld = true;
    }
    final held = _holdFrames / 60;
    if (option >= 0) {
      if (holding && held >= option % kCrossDash) {
        _dash = option >= kCrossDash;
        _commit(b);
        return double.infinity;
      }
      return holdCap;
    }
    return _predictedGo(a, b, speed, aT, held) ? double.infinity : holdCap;
  }

  bool _dash = false;

  void _commit(int runEnd) {
    _committedEnd = math.min(runEnd + 3, _path.length - 1);
    crossings++;
    _holdFrames = 0;
    lastEvent = 'cross#$crossings@$_frame';
  }

  /// Prediction-based go: simulate the passage (nominal and sluggish, after
  /// the turn from a hover) with timing slack; the longer the wait, the less
  /// slack it insists on.
  bool _predictedGo(int a, int b, double speed, double aT, double held) {
    final crossSpeed = math.min(profile.cruise, 3.0);
    final endS = _arc[math.min(b + 3, _path.length - 1)];
    final scenarios = held < 4 ? const [(0.3, 1.0), (0.15, 0.7)] : const [(0.3, 1.0)];
    final slacks = held < 8 ? const [-0.2, 0.0, 0.2] : const [0.0];
    final clear = _r + (held < 8 ? 0.15 : 0.04);
    final ahead = _pointAhead(_idx, 0.8);
    final here = _ship.body.position;
    final dir = Vector2(ahead.x - here.x, ahead.y - here.y);
    if (dir.length > 1e-6) dir.normalize();
    final want = dir * (0.5 * aT) - _ship.localAccel;
    var turn = (math.atan2(want.x, -want.y) - _ship.body.angle) % (2 * math.pi);
    if (turn > math.pi) turn -= 2 * math.pi;
    final delay = speed < 0.6 ? turn.abs() / _ship.spec.rotationSpeedRadPerSec + 0.1 : 0.0;
    for (final (accelK, speedK) in scenarios) {
      var s = _arc[_idx];
      var v = speed;
      var t = 0.0;
      while (s < endS && t < 8) {
        t += 0.05;
        if (t >= delay) v = math.min(crossSpeed * speedK, v + accelK * aT * 0.05);
        s += v * 0.05;
        final p = _pointAtArc(s);
        for (final slack in slacks) {
          if (hazards.distanceAt(p.x, p.y, math.max(0, t + slack)) < clear) return false;
        }
      }
    }
    _commit(b);
    return true;
  }

  /// Ship is inside a committed crossing.
  bool get inCrossing => _idx <= _committedEnd;

  /// Distance from the hull to the nearest moving obstacle right now.
  double get obstacleGap {
    if (hazards.isEmpty) return double.infinity;
    final p = _ship.body.position;
    return hazards.distanceAt(p.x, p.y, 0) - _r;
  }

  Pt _pointAtArc(double s) {
    for (var k = 1; k < _path.length; k++) {
      if (_arc[k] >= s) {
        final seg = _arc[k] - _arc[k - 1];
        final t = seg <= 0 ? 0.0 : (s - _arc[k - 1]) / seg;
        return Pt(
          _path[k - 1].x + (_path[k].x - _path[k - 1].x) * t,
          _path[k - 1].y + (_path[k].y - _path[k - 1].y) * t,
        );
      }
    }
    return _path.last;
  }

  BotInput _fly() {
    if (_target != null && _path.isNotEmpty) {
      final shot = _shoot();
      if (shot != null) return shot;
    }
    final body = _ship.body;
    final p = body.position;
    final v = body.linearVelocity;
    if (_path.isEmpty) return const BotInput(thrust: false);

    // Progress: nearest path point in a forward window.
    var best = _idx;
    var bestD = double.infinity;
    for (int k = _idx; k <= math.min(_endIdx, _idx + 40); k++) {
      final d = _d2(_path[k], p);
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    _idx = best;
    if (math.sqrt(bestD) > 1.2 && _frame % 30 == 0) _replan();

    final towing = _phase == _Phase.tow || _phase == _Phase.land;
    final speed = v.length;
    final look = (0.55 + 0.3 * speed).clamp(0.6, 1.6);
    final target = _pointAhead(_idx, look);
    final remaining = _remainingFrom(_idx) + math.sqrt(bestD) * 0.5;

    // Speed limits: cruise, braking distance, tunnel width, upcoming turn.
    final aT = _thrustAccel(towing);
    final brake = 0.3 * aT;
    var vMax = profile.cruise * (towing ? 0.85 : 1);
    vMax = math.min(vMax, math.sqrt(2 * brake * math.max(0, remaining - 0.15)) + 0.05);
    final tight = _minClearAhead(_idx, 2.0 + speed) - _r;
    vMax = math.min(vMax, 0.35 + profile.widthGain * math.max(0, tight));
    vMax = math.min(vMax, profile.cruise * (1 - 0.55 * _turnAhead(_idx, 2.5) / math.pi));
    if (_phase == _Phase.land) vMax = math.min(vMax, 0.9);
    // Ease into a firing point: overshooting means flying into the view.
    if (_target != null) vMax = math.min(vMax, math.sqrt(2 * 0.12 * aT * math.max(0, remaining - 0.1)) + 0.05);
    final hazardCap = _hazardCap(speed, aT, brake);
    vMax = math.min(vMax, hazardCap);

    // Committed to a crossing: don't dawdle inside the sweep.
    if (_idx <= _committedEnd) vMax = math.max(vMax, _dash ? 4.5 : math.min(profile.cruise, 3.0));

    var dir = Vector2(target.x - p.x, target.y - p.y);
    final dl = dir.length;
    if (dl > 1e-6) dir /= dl;
    var vDes = dir * math.min(vMax, dl * 2.5);
    vDes = _dodgeShells(p, v, vDes, dir);

    // Commanded thrust = velocity error feedback − local pull.
    final g = _ship.localAccel;
    final aCmd = (vDes - v) * 2.4 - g;
    if (aCmd.length > aT) aCmd.scale(aT / aCmd.length);

    var want = aCmd.length < 0.05 * aT ? -g : aCmd;
    // Never point the nose down to speed a descent (gravity does that and a
    // flipped ship can't recover in a tight cave): coast instead.
    var coast = false;
    if (g.length > 0.2) {
      final up = -g / g.length;
      final cosUp = want.dot(up) / math.max(want.length, 1e-9);
      if (cosUp < math.cos(1.75)) {
        want = up;
        coast = true;
      }
    }
    final desired = math.atan2(want.x, -want.y);
    var err = (desired - body.angle) % (2 * math.pi);
    if (err > math.pi) err -= 2 * math.pi;
    final omega = _ship.spec.rotationSpeedRadPerSec;
    var rotate = (err / (omega * 0.12)).clamp(-1.0, 1.0);
    if (rotate.abs() < 0.012) rotate = 0;

    final nose = Vector2(math.sin(body.angle), -math.cos(body.angle));
    var duty = 0.0;
    if (err.abs() < 0.7 && !coast) duty = (aCmd.dot(nose) / aT).clamp(0.0, 1.0);
    _pwm += duty;
    final thrust = _pwm >= 1;
    if (thrust) _pwm -= 1;
    // Launch needs an input; a descent start would otherwise sit on the pad.
    if (!_ship.launched && !thrust && rotate.abs() <= 0.05) rotate = 0.06;
    return BotInput(rotate: rotate, thrust: thrust);
  }

  /// Reactive dodge: if an enemy shell's straight path will pass close to
  /// the ship, pick between the planned velocity, stopping and a boost
  /// along the route — whichever keeps the most distance over the next 1.2 s.
  Vector2 _dodgeShells(Vector2 p, Vector2 v, Vector2 vDes, Vector2 dir) {
    final shells = [
      for (final c in game.world.children)
        if (c is Shell && !c.fromPlayer) c,
    ];
    if (shells.isEmpty) return vDes;
    double closest(Vector2 vTarget) {
      var m = double.infinity;
      var sv = v.clone();
      final sp = p.clone();
      for (var t = 0.05; t <= 1.2; t += 0.05) {
        // Velocity eases toward the target with the controller's ~0.4 s lag.
        sv += (vTarget - sv) * 0.12;
        sp.add(sv * 0.05);
        // A dodge into rock is no dodge.
        if (grid.clearanceAt(sp.x, sp.y) < _r + 0.08) return 0;
        for (final sh in shells) {
          final q = sh.pos + sh.vel * t;
          m = math.min(m, (q - sp).length);
        }
      }
      return m;
    }

    final planned = closest(vDes);
    if (planned > _r + 0.45) return vDes;
    var best = vDes;
    var bestGap = planned;
    for (final option in [Vector2.zero(), dir * (vDes.length + 2.0), -dir * 1.0]) {
      final gap = closest(option);
      if (gap > bestGap + 0.05) {
        best = option;
        bestGap = gap;
      }
    }
    if (!identical(best, vDes)) lastEvent = 'dodge@$_frame';
    return best;
  }

  double _thrustAccel(bool towing) {
    final m = _ship.body.mass + (towing ? _cargo.body.mass : 0);
    return _ship.spec.thrustForce / m;
  }

  void _replan() {
    if (_phase == _Phase.approach && _ship.spec.armed && snipe) {
      if (_planApproach()) lastEvent = 'replan@$_frame';
      return;
    }
    final to = _path.last;
    final path = _planVia(_pt(_ship.body.position), to, tolerance: 0.25);
    if (path != null) {
      _setPath(path);
      lastEvent = 'replan@$_frame';
    }
  }

  /// Where the ship should come to rest: the firing point while a turret
  /// is targeted, else the end of the path.
  int get _endIdx => _target != null && _fireIdx >= 0 ? _fireIdx : _path.length - 1;

  Pt _pointAhead(int from, double dist) {
    var left = dist;
    final end = _endIdx;
    if (from >= end) return _path[end];
    for (int k = from + 1; k <= end; k++) {
      final seg = math.sqrt(_d2p(_path[k - 1], _path[k]));
      if (seg >= left) {
        final t = left / seg;
        return Pt(
          _path[k - 1].x + (_path[k].x - _path[k - 1].x) * t,
          _path[k - 1].y + (_path[k].y - _path[k - 1].y) * t,
        );
      }
      left -= seg;
    }
    return _path.last;
  }

  double _remainingFrom(int from) {
    var len = 0.0;
    for (int k = from + 1; k < _path.length; k++) {
      len += math.sqrt(_d2p(_path[k - 1], _path[k]));
    }
    return len;
  }

  double _minClearAhead(int from, double dist) {
    var m = double.infinity;
    var len = 0.0;
    for (int k = from; k < _path.length && len <= dist; k++) {
      m = math.min(m, grid.clearanceAt(_path[k].x, _path[k].y));
      if (k > from) len += math.sqrt(_d2p(_path[k - 1], _path[k]));
    }
    return m;
  }

  /// Total heading change (rad) over the next [dist] m of path.
  double _turnAhead(int from, double dist) {
    var turn = 0.0;
    var len = 0.0;
    double? last;
    for (int k = from + 1; k < _path.length && len <= dist; k++) {
      final a = math.atan2(_path[k].y - _path[k - 1].y, _path[k].x - _path[k - 1].x);
      if (last != null) {
        var d = (a - last) % (2 * math.pi);
        if (d > math.pi) d -= 2 * math.pi;
        turn += d.abs();
      }
      last = a;
      len += math.sqrt(_d2p(_path[k - 1], _path[k]));
    }
    return math.min(turn, math.pi);
  }

  static double _d2(Pt a, Vector2 b) => (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y);
  static double _d2p(Pt a, Pt b) => (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y);
}
