import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/components/tractor_beam_coupling.dart';

/// Tractor beam visual: a widening cone of light from the winch to the pod
/// with energy rings running up it and a halo on the pod. Before lock-on a
/// faint targeting line; when the beam breaks, a short fizzle at the pod.
class TractorBeamLine extends Component {
  TractorBeamLine({
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
  final TractorBeamCoupling? Function() getCoupling;

  static const _core = Color(0xFF7DF9FF);
  static const _edge = Color(0xFF3A7BFF);

  double _t = 0;
  double _fizzle = 0;
  bool _wasAttached = false;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final now = attached();
    if (_wasAttached && !now) _fizzle = 0.35;
    _wasAttached = now;
    if (_fizzle > 0) _fizzle = math.max(0, _fizzle - dt);
  }

  @override
  void render(Canvas canvas) {
    final a = ship.body.worldPoint(Vector2(0, ship.rearLocalY));
    final b = cargo.body.worldCenter;
    if (_fizzle > 0) _renderFizzle(canvas, b);

    final p = progress();
    if (p <= 0.01) return;
    final chord = b - a;
    final len = chord.length;
    if (len < 1e-3) return;
    final dir = chord / len;
    final perp = Vector2(-dir.y, dir.x);

    if (!attached()) {
      // Targeting: a thin flickering line while in range.
      final flick = 0.5 + 0.5 * math.sin(_t * 30);
      canvas.drawLine(
        Offset(a.x, a.y),
        Offset(b.x, b.y),
        Paint()
          ..color = _core.withValues(alpha: p * (0.15 + 0.2 * flick))
          ..strokeWidth = 0.025,
      );
      return;
    }

    final strain = getCoupling()?.strain ?? 0;
    // Near the force cap the beam stutters.
    final flicker = strain > 0.85 ? 0.55 + 0.45 * math.sin(_t * 55).abs() : 1.0;
    final alpha = p * flicker;

    const w0 = 0.07;
    const w1 = 0.24;
    final cone = ui.Path()
      ..moveTo(a.x + perp.x * w0, a.y + perp.y * w0)
      ..lineTo(b.x + perp.x * w1, b.y + perp.y * w1)
      ..lineTo(b.x - perp.x * w1, b.y - perp.y * w1)
      ..lineTo(a.x - perp.x * w0, a.y - perp.y * w0)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(a.x, a.y),
          Offset(b.x, b.y),
          [_core.withValues(alpha: 0.55 * alpha), _edge.withValues(alpha: 0.18 * alpha)],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.04),
    );
    canvas.drawLine(
      Offset(a.x, a.y),
      Offset(b.x, b.y),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5 * alpha)
        ..strokeWidth = 0.018,
    );

    // Energy rings travelling from the pod up to the ship.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.022;
    const rings = 4;
    for (int i = 0; i < rings; i++) {
      final f = 1 - ((_t * 1.4 + i / rings) % 1.0);
      final at = a + chord * f;
      final half = w0 + (w1 - w0) * f;
      ring.color = _core.withValues(alpha: alpha * 0.8 * math.sin(f * math.pi));
      final l = at + perp * half;
      final r = at - perp * half;
      canvas.drawLine(Offset(l.x, l.y), Offset(r.x, r.y), ring);
    }

    // Halo on the pod.
    final pulse = 0.85 + 0.15 * math.sin(_t * 8);
    canvas.drawCircle(
      Offset(b.x, b.y),
      CargoBody.radius * 2.6 * pulse,
      Paint()
        ..color = _core.withValues(alpha: 0.28 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.08),
    );
  }

  void _renderFizzle(Canvas canvas, Vector2 at) {
    final k = _fizzle / 0.35;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8 * k)
      ..strokeWidth = 0.02;
    final rnd = math.Random((_t * 60).floor());
    for (int i = 0; i < 6; i++) {
      final ang = rnd.nextDouble() * 2 * math.pi;
      final r = 0.1 + 0.25 * (1 - k) + rnd.nextDouble() * 0.08;
      canvas.drawLine(
        Offset(at.x, at.y),
        Offset(at.x + math.cos(ang) * r, at.y + math.sin(ang) * r),
        paint,
      );
    }
  }
}
