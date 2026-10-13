import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/ship/loadout.dart';

/// Winch ↔ cargo using [RopeJoint] (max length), or [DistanceJoint] if span is very short.
/// A catch further out than [RopeSpec.minTowLength] winches in to it.
/// An elastic [RopeSpec] adds a one-sided spring inside a looser hard cap;
/// [RopeSpec.swingDamping] damps the pod's swing relative to the ship.
class RopePhysicsCoupling extends Component with HasGameReference<Forge2DGame> {
  RopePhysicsCoupling({
    required this.ship,
    required this.cargo,
    required this.ropeMaxLengthMeters,
    this.rope = kStockRope,
  });

  final ShipBody ship;
  final CargoBody cargo;
  final RopeSpec rope;

  /// Level design cap ([LevelData.ropeMaxLength]); tow length at attach is `min(dist, this)`.
  final double ropeMaxLengthMeters;

  Joint? _ropeJoint;
  Joint? _distanceJoint;

  /// [RopeJoint.maxLength] or [DistanceJoint]'s fixed length after attach.
  double? _tetherLengthMeters;

  double? get tetherLengthMeters => _tetherLengthMeters;

  /// True once ship–cargo tow joint exists.
  bool get isTethered => _ropeJoint != null || _distanceJoint != null;

  /// Slightly above Forge2D linearSlop (~0.005) so [RopeJointDef.maxLength] is valid.
  static const double _minRopeMaxLength = 0.0125;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    if (rope.podMassAdd > 0) _addLineWeight(rope.podMassAdd);

    final anchorShip = ship.body.worldPoint(Vector2(0, ship.rearLocalY));
    final anchorCargo = cargo.body.worldCenter;
    final delta = anchorCargo - anchorShip;
    final caught = delta.length;
    if (caught < 0.04) return;
    // A close catch pays the line out to the shortest tow: slack until the
    // ship climbs, so the pod hangs clear of the hull.
    final dist = math.max(caught, rope.minTowLength);

    // Very short: fixed distance keeps stability (same as prior bar fallback).
    if (dist < 0.12) {
      final def = DistanceJointDef<Body, Body>()..collideConnected = false;
      def.initialize(ship.body, cargo.body, anchorShip, anchorCargo);
      _distanceJoint = DistanceJoint(def);
      _tetherLengthMeters = def.length;
      game.world.createJoint(_distanceJoint!);
      return;
    }

    final maxLength = dist.clamp(_minRopeMaxLength, ropeMaxLengthMeters);
    _restLength = maxLength;
    _settleLength = math.min(maxLength, rope.minTowLength);
    final def = RopeJointDef<Body, Body>()..collideConnected = false;
    def.bodyA = ship.body;
    def.bodyB = cargo.body;
    def.localAnchorA.setFrom(ship.body.localPoint(anchorShip));
    def.localAnchorB.setFrom(cargo.body.localPoint(anchorCargo));
    def.maxLength = rope.isElastic
        ? math.min(maxLength * (1 + rope.maxStretch), ropeMaxLengthMeters)
        : maxLength;
    _ropeJoint = RopeJoint(def);
    _tetherLengthMeters = maxLength;
    game.world.createJoint(_ropeJoint!);
  }

  final List<(Fixture, double)> _baseDensity = [];

  /// A heavy line loads the pod: scale its density while towed.
  void _addLineWeight(double frac) {
    for (final f in cargo.body.fixtures) {
      _baseDensity.add((f, f.density));
      f.density *= 1 + frac;
    }
    cargo.body.resetMassData();
  }

  /// Elastic rope: unstretched length (the spring pulls beyond this).
  double? _restLength;

  /// A far catch winches in to this (the shortest tow), so the tow is the
  /// same length however far away the hook caught.
  double? _settleLength;

  /// Winch-in speed after a far catch (m/s).
  static const double winchInSpeed = 0.5;

  /// The winch reels in only while the pod is within ~72° of local down (below the winch).
  static const double _winchInCos = 0.3;

  /// How far the elastic line is stretched right now, 0..1 of its give.
  double stretch = 0;

  void _winchIn(double dt) {
    final joint = _ropeJoint;
    final rest = _restLength;
    final settle = _settleLength;
    if (joint is! RopeJoint || rest == null || settle == null || rest <= settle) return;
    // Only while the pod hangs under the ship: reeling in a pod caught from
    // the side would drag a light ship into the rock beside it.
    final d = cargo.body.worldCenter - _winch;
    final g = game.world.gravity;
    final down = g.length2 > 1e-4 ? g.normalized() : ship.body.worldVector(Vector2(0, 1));
    if (d.dot(down) < _winchInCos * d.length) return;
    final next = math.max(settle, rest - winchInSpeed * dt);
    _restLength = next;
    _tetherLengthMeters = next;
    joint.maxLength = rope.isElastic
        ? math.min(next * (1 + rope.maxStretch), ropeMaxLengthMeters)
        : next;
    cargo.body.setAwake(true);
  }

  Vector2 get _winch => ship.body.worldPoint(Vector2(0, ship.rearLocalY));

  @override
  void update(double dt) {
    super.update(dt);
    if (_ropeJoint == null) return;
    _winchIn(dt);
    final rest = _restLength;
    if (rest == null) return;
    if (!rope.isElastic && rope.swingDamping <= 0) return;

    final a = _winch;
    final b = cargo.body.worldCenter;
    final d = b - a;
    final len = d.length;
    if (len < 1e-4) return;
    final n = d / len;
    final vA = ship.body.linearVelocityFromWorldPoint(a);
    final vRel = cargo.body.linearVelocity - vA;
    final mS = ship.body.mass;
    final mC = cargo.body.mass;
    final mEff = mS * mC / (mS + mC);
    final force = Vector2.zero();

    if (rope.isElastic) {
      final ext = len - rest;
      stretch = (ext / math.max(rest * rope.maxStretch, 1e-3)).clamp(0.0, 1.0);
      if (ext > 0) {
        final w = 2 * math.pi * rope.stiffnessHz;
        final k = mEff * w * w;
        final c = 2 * rope.dampingRatio * mEff * w;
        // One-sided: a rope pulls, never pushes.
        final pull = math.max(0.0, k * ext + c * vRel.dot(n));
        force.add(n * -pull);
      }
    }
    if (rope.swingDamping > 0) {
      final perp = vRel - n * vRel.dot(n);
      force.add(perp * (-rope.swingDamping * mEff));
    }
    cargo.body.applyForce(force);
    ship.body.applyForce(-force, point: a);
  }

  @override
  void onRemove() {
    if (_ropeJoint != null) {
      game.world.destroyJoint(_ropeJoint!);
      _ropeJoint = null;
    }
    if (_distanceJoint != null) {
      game.world.destroyJoint(_distanceJoint!);
      _distanceJoint = null;
    }
    _tetherLengthMeters = null;
    if (_baseDensity.isNotEmpty) {
      for (final (f, d) in _baseDensity) {
        f.density = d;
      }
      _baseDensity.clear();
      cargo.body.resetMassData();
    }
    super.onRemove();
  }
}
