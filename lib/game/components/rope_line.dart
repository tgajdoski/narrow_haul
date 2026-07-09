import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/rope_physics_coupling.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';

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
    final alphaInt = (baseAlpha * 230).round().clamp(0, 255);
    final ropeId = CosmeticsService.getEquippedId(CosmeticsService.catRope);

    final paint = Paint()
      ..style = PaintingStyle.stroke;

    if (ropeId == 'rope_energy') {
      paint.color = Color.fromARGB(alphaInt, 50, 255, 255);
      paint.strokeWidth = attached() ? 0.08 : 0.05;
      paint.maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.05);
    } else if (ropeId == 'rope_chain') {
      paint.color = Color.fromARGB(alphaInt, 180, 180, 180);
      paint.strokeWidth = attached() ? 0.09 : 0.06;
    } else {
      paint.color = Color.fromARGB(alphaInt, 148, 210, 189);
      paint.strokeWidth = attached() ? 0.06 : 0.045;
    }

    final coupling = getCoupling();
    final maxLen = coupling?.tetherLengthMeters;
    final chord = b - a;
    final chordLen = chord.length;
    if (chordLen < 1e-4) return;

    void drawRope(Canvas c, ui.Path p) {
      if (ropeId == 'rope_energy') {
        final corePaint = Paint()
          ..color = Colors.white.withValues(alpha: baseAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = paint.strokeWidth * 0.4;
        c.drawPath(p, paint);
        c.drawPath(p, corePaint);
      } else if (ropeId == 'rope_chain') {
        c.drawPath(p, paint);
        final chainPaint = Paint()
          ..color = Color.fromARGB(alphaInt, 60, 60, 60)
          ..style = PaintingStyle.stroke
          ..strokeWidth = paint.strokeWidth * 0.4;
        c.drawPath(p, chainPaint);
      } else {
        c.drawPath(p, paint);
      }
    }

    if (!attached() || coupling?.isTethered != true || maxLen == null) {
      final p = ui.Path()..moveTo(a.x, a.y)..lineTo(b.x, b.y);
      drawRope(canvas, p);
      return;
    }

    final slack = (maxLen - chordLen).clamp(0.0, maxLen);
    if (slack < 0.008) {
      final p = ui.Path()..moveTo(a.x, a.y)..lineTo(b.x, b.y);
      drawRope(canvas, p);
      return;
    }

    final dir = chord / chordLen;
    var perp = Vector2(-dir.y, dir.x);
    if (perp.y < 0) {
      perp = -perp;
    }
    final dip = slack * _slackDipScale;
    final mid = (a + b) * 0.5;
    final cNode = mid + perp * dip;

    final path = ui.Path()
      ..moveTo(a.x, a.y)
      ..quadraticBezierTo(cNode.x, cNode.y, b.x, b.y);
    drawRope(canvas, path);
  }
}
