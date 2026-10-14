import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';


/// Segmented bar with [value] in 0–1 (cockpit gauge look).
class HoloGauge extends StatelessWidget {
  const HoloGauge({
    super.key,
    required this.value,
    this.color = SpaceColors.cyan,
    this.height = 6,
    this.segments = 20,
  });

  final double value;
  final Color color;
  final double height;
  final int segments;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(
      painter: _GaugePainter(value.clamp(0.0, 1.0), color, segments),
      size: Size.infinite,
    ),
  );
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.value, this.color, this.segments);
  final double value;
  final Color color;
  final int segments;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.0;
    final w = (size.width - gap * (segments - 1)) / segments;
    final lit = value * segments;
    final on = Paint()..color = color;
    final off = Paint()..color = const Color(0x22FFFFFF);
    for (var i = 0; i < segments; i++) {
      final rect = Rect.fromLTWH(i * (w + gap), 0, w, size.height);
      if (i + 1 <= lit) {
        canvas.drawRect(rect, on);
      } else if (i < lit) {
        canvas.drawRect(rect, off);
        canvas.drawRect(
          Rect.fromLTWH(rect.left, 0, w * (lit - i), size.height),
          on,
        );
      } else {
        canvas.drawRect(rect, off);
      }
    }
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.value != value || o.color != color || o.segments != segments;
}

/// Progress ring with [value] in 0–1 and a [child] (label/icon) inside.
class HoloRing extends StatelessWidget {
  const HoloRing({
    super.key,
    required this.value,
    this.color = SpaceColors.cyan,
    this.size = 44,
    this.stroke = 3.5,
    this.child,
  });

  final double value;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _RingPainter(value.clamp(0.0, 1.0), color, stroke),
      child: Center(child: child),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.stroke);
  final double value;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = SpaceColors.track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (value <= 0) return;
    final sweep = math.pi * 2 * value;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.value != value || o.color != color || o.stroke != stroke;
}
