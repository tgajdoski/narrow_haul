import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/theme_assets.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';

class _Prop {
  const _Prop(this.base, this.angle, this.height, this.frame);

  /// Root point, sunk into the rock (meters).
  final Offset base;

  /// Rotation that maps local "up" onto the wall's outward normal.
  final double angle;
  final double height;
  final int frame;
}

/// Visual-only stalactites / stalagmites / props along cave walls. No physics
/// — so placement is conservative: props sit on floors and ceilings only,
/// mostly sunk into the rock (drawn *below* the rock so the root is hidden),
/// never near anchors, and only where the passage beyond stays wide open so
/// a prop never visually blocks a route the ship can actually fly.
class CaveDecor extends Component {
  CaveDecor({
    required this.loops,
    required this.rockPath,
    required this.theme,
    required this.anchors,
    this.assets = ThemeAssets.empty,
  }) : super(priority: -1750);

  final List<List<Pt>> loops;
  final ui.Path rockPath;
  final ThemeSpec theme;
  final List<Offset> anchors;
  final ThemeAssets assets;

  static const _sink = 0.4; // fraction of the prop buried in rock
  static const _maxProtrusion = 0.85; // meters visible into the cave
  static const _clearance = 2.0; // free meters required beyond the tip
  static const _anchorRadius = 3.0;

  final List<_Prop> _props = [];

  /// Visible tip of every placed prop (meters) — for tests.
  @visibleForTesting
  List<Offset> get propTips => [
    for (final p in _props)
      p.base + Offset(math.sin(p.angle), -math.cos(p.angle)) * p.height,
  ];
  late final Paint _spritePaint = Paint()..filterQuality = FilterQuality.medium;

  @override
  Future<void> onLoad() async {
    if (theme.decorDensity <= 0) return;
    // Seed from geometry: levels are fixed, so decor must be too.
    final first = loops.isEmpty || loops.first.isEmpty ? null : loops.first.first;
    final rng = math.Random(
      loops.length * 92821 + ((first?.x ?? 0) * 1000).round() * 31 + ((first?.y ?? 0) * 1000).round(),
    );
    final meanGap = 2.6 / theme.decorDensity;

    for (final loop in loops) {
      var untilNext = meanGap * (0.3 + rng.nextDouble());
      for (int i = 0; i < loop.length; i++) {
        final a = loop[i];
        final b = loop[(i + 1) % loop.length];
        final dx = b.x - a.x, dy = b.y - a.y;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 1e-6) continue;
        untilNext -= len;
        if (untilNext > 0) continue;
        untilNext = meanGap * (0.5 + rng.nextDouble());
        _tryPlace(rng, Offset((a.x + b.x) / 2, (a.y + b.y) / 2), Offset(-dy / len, dx / len));
      }
    }
  }

  void _tryPlace(math.Random rng, Offset mid, Offset normal) {
    // Orient the normal outward (into open cave), independent of winding.
    if (rockPath.contains(mid + normal * 0.25)) normal = -normal;
    if (rockPath.contains(mid + normal * 0.25)) return; // thin sliver
    // Floors (outward points up) and ceilings only; walls look odd.
    if (normal.dy.abs() < 0.6) return;
    for (final anchor in anchors) {
      if ((anchor - mid).distance < _anchorRadius) return;
    }
    final height = (_maxProtrusion / (1 - _sink)) * (0.6 + rng.nextDouble() * 0.4);
    final tip = mid + normal * (height * (1 - _sink));
    for (double d = 0.5; d <= _clearance; d += 0.5) {
      if (rockPath.contains(tip + normal * d)) return;
    }
    _props.add(_Prop(
      mid - normal * (height * _sink),
      math.atan2(normal.dx, -normal.dy),
      height,
      rng.nextInt(ThemeAssets.decorFrames),
    ));
  }

  @override
  void render(Canvas canvas) {
    final sheet = assets.decor;
    for (final p in _props) {
      canvas
        ..save()
        ..translate(p.base.dx, p.base.dy)
        ..rotate(p.angle);
      if (sheet != null) {
        final cell = sheet.width / ThemeAssets.decorFrames;
        canvas.drawImageRect(
          sheet,
          Rect.fromLTWH(p.frame * cell, 0, cell, sheet.height.toDouble()),
          Rect.fromLTWH(-p.height / 2, -p.height, p.height, p.height),
          _spritePaint,
        );
      } else {
        _drawSpike(canvas, p);
      }
      canvas.restore();
    }
  }

  /// Procedural fallback: a slightly crooked tapered spike (plus a small
  /// sibling) shaded from rock color at the root to [ThemeSpec.decorTip].
  /// Drawn in unit space (height 1) and scaled, so paints are shared.
  late final Paint _spikeFill = Paint()
    ..shader = ui.Gradient.linear(
      Offset.zero,
      const Offset(0, -1),
      [theme.rockFill, theme.decorTip],
    );
  late final Paint _spikeEdge = Paint()
    ..color = theme.rockEdge.withValues(alpha: 0.6)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.04;

  void _drawSpike(Canvas canvas, _Prop p) {
    canvas.scale(p.height);
    final lean = (p.frame - 1.5) * 0.05;
    // A cluster: one main spike flanked by shorter siblings (varies by frame).
    final spikes = <(double x, double w, double h)>[
      (0, 0.30 + 0.04 * p.frame, 1),
      ((p.frame.isEven ? 1 : -1) * 0.24, 0.20, 0.55 + 0.08 * p.frame),
      if (p.frame >= 2) ((p.frame.isEven ? -1 : 1) * 0.2, 0.16, 0.4),
    ];
    for (final (x, w, h) in spikes) {
      final path = Path()
        ..moveTo(x - w / 2, 0.05)
        ..quadraticBezierTo(x - w * 0.18, -h * 0.55, x + lean * h, -h)
        ..quadraticBezierTo(x + w * 0.18, -h * 0.55, x + w / 2, 0.05)
        ..close();
      canvas
        ..drawPath(path, _spikeFill)
        ..drawPath(path, _spikeEdge);
    }
  }
}
