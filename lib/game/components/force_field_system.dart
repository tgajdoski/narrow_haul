import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/level/cave/field_sampler.dart';

/// Applies a level's force fields (gravity zones, wind, wells) to the ship and
/// cargo. Forge2D world gravity stays the uniform base; this adds only the
/// *difference* `mass × (local − base)`, so a level without fields is
/// untouched. Kinematic obstacles are unaffected by design.
class ForceFieldSystem extends Component {
  ForceFieldSystem({
    required this.sampler,
    required this.ship,
    required this.cargo,
  });

  final FieldSampler sampler;
  final ShipBody ship;
  final CargoBody cargo;

  double _time = 0;

  /// Seconds since the level spawned (drives wind gusts).
  double get time => _time;

  /// Last sampled acceleration at the ship (m/s²) — for HUD / assists.
  final Vector2 shipAccel = Vector2.zero();

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    final base = sampler.baseAccel;

    if (ship.isMounted) {
      final p = ship.body.worldCenter;
      final a = sampler.accelAt(p.x, p.y, t: _time);
      shipAccel.setValues(a.x, a.y);
      // The ship floats on its pad until first input (gravityScale = 0).
      if (ship.launched) _applyDelta(ship.body, a.x - base.x, a.y - base.y);
    }

    if (cargo.isMounted && cargo.body.bodyType == BodyType.dynamic) {
      final p = cargo.body.worldCenter;
      final a = sampler.accelAt(p.x, p.y, t: _time, cargo: true);
      _applyDelta(cargo.body, a.x - base.x, a.y - base.y);
    }
  }

  static void _applyDelta(Body body, double dx, double dy) {
    if (dx.abs() < 1e-9 && dy.abs() < 1e-9) return;
    body.applyForce(Vector2(dx * body.mass, dy * body.mass));
  }
}
