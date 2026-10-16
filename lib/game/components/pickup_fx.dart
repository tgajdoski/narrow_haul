import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// A ring that grows and fades round a moving point (world metres): the
/// hook-up "clamp" at the winch and at the pod. Removes itself.
class PulseRing extends Component {
  PulseRing({
    required this.at,
    required this.color,
    this.delay = 0,
    this.startRadius = 0.15,
    this.endRadius = 0.75,
    this.life = 0.45,
  }) : super(priority: 1100);

  /// Where the ring is centred, read every frame (follows the body).
  final Offset Function() at;
  final Color color;
  final double delay;
  final double startRadius;
  final double endRadius;
  final double life;

  double _t = 0;
  final Paint _paint = Paint()..style = PaintingStyle.stroke;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= delay + life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final k = (_t - delay) / life;
    if (k <= 0 || k >= 1) return;
    final ease = 1 - math.pow(1 - k, 3).toDouble();
    final r = startRadius + (endRadius - startRadius) * ease;
    _paint
      ..color = color.withValues(alpha: 0.85 * (1 - k))
      ..strokeWidth = 0.07 * (1 - 0.6 * k);
    canvas.drawCircle(at(), r, _paint);
  }
}

/// A fuel canister picked up: a quick ring and a handful of sparks flying
/// out from where it was. Removes itself.
class PickupSparkle extends Component {
  PickupSparkle({required this.center, required this.color, int seed = 0})
    : _rng = math.Random(seed),
      super(priority: 1100);

  final Offset center;
  final Color color;
  final math.Random _rng;

  static const double _life = 0.55;
  static const int _count = 12;
  double _t = 0;
  late final List<(Offset dir, double speed)> _sparks = [
    for (var i = 0; i < _count; i++)
      () {
        final a = i / _count * 2 * math.pi + _rng.nextDouble() * 0.4;
        return (Offset(math.cos(a), math.sin(a)), 2.2 + _rng.nextDouble() * 1.6);
      }(),
  ];
  final Paint _ring = Paint()..style = PaintingStyle.stroke;
  final Paint _spark = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final k = (_t / _life).clamp(0.0, 1.0);
    final fade = 1 - k;
    _ring
      ..color = color.withValues(alpha: 0.8 * fade)
      ..strokeWidth = 0.06;
    canvas.drawCircle(center, 0.2 + 0.7 * math.sqrt(k), _ring);
    _spark
      ..color = Color.lerp(color, Colors.white, 0.4)!.withValues(alpha: fade)
      ..strokeWidth = 0.05;
    for (final (dir, speed) in _sparks) {
      // Decelerating sparks: distance = v·t·(1 − t/2·life).
      final d = speed * _t * (1 - 0.5 * k);
      final head = center + dir * d;
      final tail = center + dir * math.max(0.0, d - 0.25 * fade);
      canvas.drawLine(tail, head, _spark);
    }
  }
}
