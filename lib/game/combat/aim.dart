import 'dart:math' as math;

/// Pure turret aiming math (no Flame imports) so it is unit-testable.

/// Angle (radians, atan2 convention, +Y down) a shell fired at [speed] from
/// ([fx], [fy]) must take to meet a target at ([tx], [ty]) moving with
/// ([vx], [vy]). Falls back to aiming straight at the target when no
/// intercept exists (target outrunning the shell).
double leadAngle(
  double fx,
  double fy,
  double tx,
  double ty,
  double vx,
  double vy,
  double speed,
) {
  final dx = tx - fx;
  final dy = ty - fy;
  // |d + v·t| = s·t  →  (v·v − s²)t² + 2(d·v)t + d·d = 0
  final a = vx * vx + vy * vy - speed * speed;
  final b = 2 * (dx * vx + dy * vy);
  final c = dx * dx + dy * dy;
  double? t;
  if (a.abs() < 1e-9) {
    if (b.abs() > 1e-9) t = -c / b;
  } else {
    final disc = b * b - 4 * a * c;
    if (disc >= 0) {
      final r = math.sqrt(disc);
      final t1 = (-b - r) / (2 * a);
      final t2 = (-b + r) / (2 * a);
      final lo = math.min(t1, t2);
      final hi = math.max(t1, t2);
      t = lo > 0 ? lo : (hi > 0 ? hi : null);
    }
  }
  if (t == null || t <= 0) return math.atan2(dy, dx);
  return math.atan2(dy + vy * t, dx + vx * t);
}

/// Signed smallest difference `to − from`, wrapped into (−π, π].
double angleDelta(double from, double to) {
  var d = (to - from) % (2 * math.pi);
  if (d > math.pi) d -= 2 * math.pi;
  return d;
}
