import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/combat.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/physics_core.dart';
import 'package:narrow_haul/game/ship/loadout.dart';

/// Tractor beam tow: no joint. Each step a capped force holds the pod
/// [holdLength] from the winch (a firm spring along the beam) and eases it
/// back under the ship (a weak sideways spring toward local down, leaning
/// to the ship's belly; the belly alone in zero-g), so the pod still hangs,
/// lags and swings. The reaction goes on the ship, so the pod's weight
/// still loads it. Rock between ship and pod, running out of
/// range or out of fuel breaks the beam ([broken]).
class TractorBeamCoupling extends Component with HasGameReference<Forge2DGame> {
  TractorBeamCoupling({
    required this.ship,
    required this.cargo,
    required this.rope,
  });

  final ShipBody ship;
  final CargoBody cargo;
  final RopeSpec rope;

  /// Set once the beam fails; the attachment then drops the pod.
  bool broken = false;

  /// Pull used this step as a share of the cap (0..1), for the flicker.
  double strain = 0;

  /// Current hold distance; eases from the lock-on distance to the rest
  /// hold so a far pod is reeled in, not snapped.
  late double holdLength;

  double _blockedFor = 0;

  static const double _blockGrace = 0.25;

  /// Force cap is set for a standard pod, so a heavy pod lags more.
  static final double _baseCargoMass = math.pi * kCargoRadius * kCargoRadius * kCargoDensity;

  Vector2 get winch => ship.body.worldPoint(Vector2(0, ship.rearLocalY));

  bool get isTethered => !broken;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    holdLength = (cargo.body.worldCenter - winch).length.clamp(0.4, rope.beamRange);
  }

  /// Unit vector the beam rests along: local down, leaning toward the
  /// ship's belly by [RopeSpec.beamAxisBias]; the belly alone in zero-g.
  Vector2 _restDir() {
    final belly = ship.body.worldVector(Vector2(0, 1));
    final g = game.world.gravity;
    if (g.length2 <= 1e-4) return belly;
    final dir = g.normalized() * (1 - rope.beamAxisBias) + belly * rope.beamAxisBias;
    return dir.length2 > 1e-6 ? dir.normalized() : g.normalized();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (broken || dt <= 0) return;

    final a = winch;
    final c = cargo.body.worldCenter;
    final span = (c - a).length;

    if (ship.fuel <= 0 || span > rope.beamRange * 1.1) {
      broken = true;
      return;
    }
    if (!hasLineOfSight(game.world, a, c, ignore: cargo.body)) {
      _blockedFor += dt;
      if (_blockedFor >= _blockGrace) {
        broken = true;
        return;
      }
    } else {
      _blockedFor = 0;
    }

    // Reel a far pod in at a steady rate.
    holdLength = math.max(rope.beamHoldLength, holdLength - 1.6 * dt);

    final d = c - a;
    if (span < 1e-4) return;
    final n = d / span;
    final vRel = cargo.body.linearVelocity - ship.body.linearVelocityFromWorldPoint(a);

    // Along the beam: a spring to the hold length carries the pod's weight
    // and gives a little on hard stops.
    final w = 2 * math.pi * rope.stiffnessHz;
    final radial = -(span - holdLength) * w * w - vRel.dot(n) * 2 * rope.dampingRatio * w;
    final accel = n * radial;

    // Sideways: a weak spring back toward the rest direction (mostly local
    // down, leaning toward the ship's belly) with light damping, so the pod
    // lags on a turn and swings on a stop instead of hanging like a rod.
    final ws = 2 * math.pi * rope.beamSwingHz;
    final target = _restDir();
    final toTarget = target * span - d;
    final sideErr = toTarget - n * toTarget.dot(n);
    final sideVel = vRel - n * vRel.dot(n);
    accel
      ..add(sideErr * (ws * ws))
      ..add(sideVel * (-2 * rope.beamSwingDamping * ws));

    final mC = cargo.body.mass;
    final maxForce = rope.beamMaxAccel * _baseCargoMass;
    final force = accel * mC;
    final f = force.length;
    strain = (f / maxForce).clamp(0.0, 1.0);
    if (f > maxForce) force.scale(maxForce / f);

    cargo.body.applyForce(force);
    ship.body.applyForce(-force, point: a);

    ship.fuel = math.max(0, ship.fuel - rope.beamFuelFracPerSec * ship.maxFuel * ship.fuelDrainMultiplier * dt);
  }
}
