import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/rope_physics_coupling.dart';
import 'package:narrow_haul/game/components/ship_body.dart';

/// Preview line before attach; after attach, follows the physics rope segment endpoints.
class RopeLine extends Component {
  RopeLine({
    required this.ship,
    required this.cargo,
    required this.progress,
    required this.attached,
    required this.getCoupling,
  }) : super(priority: -400);

  final ShipBody ship;
  final CargoBody cargo;
  final double Function() progress;
  final bool Function() attached;
  final RopePhysicsCoupling? Function() getCoupling;

  @override
  void render(Canvas canvas) {
    final p = progress();
    if (p <= 0.01) return;

    final seg = getCoupling()?.ropeSegment;
    final Vector2 a;
    final Vector2 b;
    if (attached() && seg != null) {
      a = seg.endShipWorld;
      b = seg.endCargoWorld;
    } else {
      a = ship.body.worldPoint(Vector2(0, ShipBody.rearLocalY));
      b = cargo.body.worldCenter;
    }

    final baseAlpha = p * (attached() ? 1.0 : 0.68);
    final paint = Paint()
      ..color = Color.fromARGB((baseAlpha * 230).round().clamp(0, 255), 148, 210, 189)
      ..strokeWidth = attached() ? 0.06 : 0.045
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
  }
}
