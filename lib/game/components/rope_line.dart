import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/rope_physics_coupling.dart';
import 'package:narrow_haul/game/components/ship_body.dart';

/// Preview: hook → cargo. When attached: winch → cargo with Bézier slack under [RopeJoint] max length.
class RopeLine extends Component {
  RopeLine({
    required this.ship,
    required this.cargo,
    required this.progress,
    required this.attached,
    required this.getCoupling,
  }) : super(priority: -380);

  final ShipBody ship;
  final CargoBody cargo;
  final double Function() progress;
  final bool Function() attached;
  final RopePhysicsCoupling? Function() getCoupling;

  static const double _slackDipScale = 0.85;

  @override
  void render(Canvas canvas) {
    final p = progress();
    if (p <= 0.01) return;

    final winch = ship.body.worldPoint(Vector2(0, ShipBody.rearLocalY));
    final cargoCenter = cargo.body.worldCenter;

    final Vector2 a;
    final Vector2 b;
    if (attached()) {
      a = winch;
      b = cargoCenter;
    } else {
      a = ship.body.worldPoint(ShipBody.hookLocal);
      b = cargoCenter;
    }

    final baseAlpha = p * (attached() ? 1.0 : 0.55);
    final paint = Paint()
      ..color = Color.fromARGB((baseAlpha * 230).round().clamp(0, 255), 148, 210, 189)
      ..strokeWidth = attached() ? 0.06 : 0.045
      ..style = PaintingStyle.stroke;

    final coupling = getCoupling();
    final maxLen = coupling?.tetherLengthMeters;
    final chord = b - a;
    final chordLen = chord.length;
    if (chordLen < 1e-4) return;

    if (!attached() || coupling?.isTethered != true || maxLen == null) {
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
      return;
    }

    final slack = (maxLen - chordLen).clamp(0.0, maxLen);
    if (slack < 0.008) {
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
      return;
    }

    final dir = chord / chordLen;
    var perp = Vector2(-dir.y, dir.x);
    if (perp.y < 0) {
      perp = -perp;
    }
    final dip = slack * _slackDipScale;
    final mid = (a + b) * 0.5;
    final c = mid + perp * dip;

    final path = ui.Path()
      ..moveTo(a.x, a.y)
      ..quadraticBezierTo(c.x, c.y, b.x, b.y);
    canvas.drawPath(path, paint);
  }
}
