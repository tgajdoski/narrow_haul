import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/ship_body.dart';

/// Engine plume in the ship's local space (rear along +Y).
class ThrustPlume extends Component {
  ThrustPlume({required this.isThrusting});

  final bool Function() isThrusting;

  final math.Random _rng = math.Random();

  @override
  void render(Canvas canvas) {
    if (!isThrusting()) return;
    final base = ShipBody.rearLocalY - 0.06;
    for (var i = 0; i < 7; i++) {
      final t = _rng.nextDouble();
      final ox = (_rng.nextDouble() - 0.5) * 0.12;
      final oy = base + t * 0.28;
      final r = 0.04 + t * 0.06;
      final paint = Paint()
        ..color = Color.lerp(
          const Color(0xFFFFD166),
          const Color(0xFFFF6B35),
          t,
        )!
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(ox, oy), r, paint);
    }
  }
}
