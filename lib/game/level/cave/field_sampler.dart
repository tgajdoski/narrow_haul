import 'dart:math' as math;

import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';

/// Local acceleration (m/s², +Y down) anywhere in a level: base gravity,
/// gravity zones, wind and wells. Pure Dart — the runtime force system and
/// the headless validator share it, so they can never disagree.
class FieldSampler {
  const FieldSampler({
    required this.fields,
    required this.g0,
    this.gravityMul = 1.0,
  });

  /// Level fields, applied in order.
  final List<FieldSpec> fields;

  /// Base gravity magnitude (m/s²) that "1 g" maps to.
  final double g0;

  /// Level base gravity in g ([LevelModifiers.gravityMul]).
  final double gravityMul;

  bool get isEmpty => fields.isEmpty;

  /// Uniform level gravity, before any field.
  Pt get baseAccel => Pt(0, g0 * gravityMul);

  /// Acceleration at ([x], [y]) at time [t] seconds. [cargo] applies each
  /// wind zone's `cargoFactor`.
  Pt accelAt(double x, double y, {double t = 0, bool cargo = false}) {
    var ax = 0.0;
    var ay = g0 * gravityMul;
    for (final f in fields) {
      switch (f) {
        case GravityZoneSpec():
          final w = _weight(f.shape, f.center, f.halfW, f.halfH, f.feather, x, y);
          if (w > 0) {
            ax += (f.gx * g0 - ax) * w;
            ay += (f.gy * g0 - ay) * w;
          }
        case WindZoneSpec():
          var w = _weight(f.shape, f.center, f.halfW, f.halfH, f.feather, x, y);
          if (w > 0) {
            if (f.gustAmp != 0 && f.gustPeriod > 0) {
              w *= 1 + f.gustAmp * math.sin(2 * math.pi * t / f.gustPeriod);
            }
            if (cargo) w *= f.cargoFactor;
            ax += f.ax * g0 * w;
            ay += f.ay * g0 * w;
          }
        case GravityWellSpec():
          final dx = f.center.x - x;
          final dy = f.center.y - y;
          final r = math.sqrt(dx * dx + dy * dy);
          if (r > 1e-6) {
            final eps2 = f.softening * f.softening;
            final g = math.min(f.strength / (r * r + eps2), f.maxG) * g0;
            ax += dx / r * g;
            ay += dy / r * g;
          }
      }
    }
    return Pt(ax, ay);
  }

  /// 0 outside the shape, ramping linearly to 1 at [feather] meters inside.
  static double _weight(
    FieldShape shape,
    Pt c,
    double halfW,
    double halfH,
    double feather,
    double x,
    double y,
  ) {
    final dx = (x - c.x).abs();
    final dy = (y - c.y).abs();
    final double depth; // meters inside the edge (negative = outside)
    switch (shape) {
      case FieldShape.rect:
        depth = math.min(halfW - dx, halfH - dy);
      case FieldShape.ellipse:
        final nx = dx / halfW;
        final ny = dy / halfH;
        // Approximate distance to the ellipse edge along the radial line.
        depth = (1 - math.sqrt(nx * nx + ny * ny)) * math.min(halfW, halfH);
    }
    if (depth <= 0) return 0;
    if (feather <= 0 || depth >= feather) return 1;
    return depth / feather;
  }
}
