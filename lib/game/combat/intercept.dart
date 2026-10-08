import 'package:narrow_haul/game/ship/weapons.dart';

/// Pure shot-interception rules (no Flame imports) so they are unit-testable.
///
/// Player fire can stop turret fire. A turret shell has strength
/// [kEnemyShellStrength]; a player round's strength is its weapon's damage
/// (the cannon counts as 1). Equal strength trades both rounds; a stronger
/// round knocks the shell out and flies on. Blasts (charge, bomb, seeker)
/// and the mining laser beam clear shells without being spent.

/// Strength of one turret shell.
const int kEnemyShellStrength = 1;

/// Centre distance at which two rounds meet (m): both shells' radius
/// (0.1 m each) plus a little forgiveness, as rounds are hard to line up.
const double kInterceptRadius = 0.25;

/// How close a shell must pass the mining laser beam to burn (m).
const double kLaserInterceptRadius = 0.15;

/// Strength of a player round fired from [weapon] (null = the cannon).
int interceptStrength(WeaponSpec? weapon) =>
    weapon == null || weapon.kind == WeaponKind.cannon ? 1 : weapon.damage;

enum InterceptOutcome {
  /// Both rounds are spent.
  trade,

  /// The enemy shell is destroyed; the player round flies on.
  pierce,

  /// The enemy shell survives and the player round is spent.
  blocked,
}

/// What happens when a player round of [attacker] strength meets an enemy
/// shell of [enemy] strength.
InterceptOutcome resolveIntercept(int attacker, {int enemy = kEnemyShellStrength}) {
  if (attacker > enemy) return InterceptOutcome.pierce;
  if (attacker == enemy) return InterceptOutcome.trade;
  return InterceptOutcome.blocked;
}

/// Whether two points moving in straight lines over one step — A from
/// ([ax0], [ay0]) to ([ax1], [ay1]), B from ([bx0], [by0]) to ([bx1],
/// [by1]) — come within [r] of each other at any moment of it. Rounds close
/// at ~13 m/s (0.22 m per 1/60 s step), so an end-of-step distance check
/// would let them slip past each other.
bool sweptCircleHit(
  double ax0,
  double ay0,
  double ax1,
  double ay1,
  double bx0,
  double by0,
  double bx1,
  double by1,
  double r,
) {
  // Relative motion: d(t) = d0 + (dv)·t, t ∈ [0, 1].
  final dx = ax0 - bx0;
  final dy = ay0 - by0;
  final vx = (ax1 - ax0) - (bx1 - bx0);
  final vy = (ay1 - ay0) - (by1 - by0);
  final vv = vx * vx + vy * vy;
  var t = vv < 1e-12 ? 0.0 : -(dx * vx + dy * vy) / vv;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final cx = dx + vx * t;
  final cy = dy + vy * t;
  return cx * cx + cy * cy <= r * r;
}

/// Whether point P moving from ([px0], [py0]) to ([px1], [py1]) passes
/// within [r] of the segment ([sx0], [sy0])–([sx1], [sy1]) (a beam).
bool sweptSegmentHit(
  double px0,
  double py0,
  double px1,
  double py1,
  double sx0,
  double sy0,
  double sx1,
  double sy1,
  double r,
) {
  if (_pointSegment2(px0, py0, sx0, sy0, sx1, sy1) <= r * r) return true;
  if (_pointSegment2(px1, py1, sx0, sy0, sx1, sy1) <= r * r) return true;
  return _segmentsCross(px0, py0, px1, py1, sx0, sy0, sx1, sy1);
}

double _pointSegment2(double px, double py, double ax, double ay, double bx, double by) {
  final abx = bx - ax;
  final aby = by - ay;
  final l2 = abx * abx + aby * aby;
  var t = l2 < 1e-12 ? 0.0 : ((px - ax) * abx + (py - ay) * aby) / l2;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final dx = ax + abx * t - px;
  final dy = ay + aby * t - py;
  return dx * dx + dy * dy;
}

bool _segmentsCross(
  double ax,
  double ay,
  double bx,
  double by,
  double cx,
  double cy,
  double dx,
  double dy,
) {
  double cross(double ox, double oy, double px, double py, double qx, double qy) =>
      (px - ox) * (qy - oy) - (py - oy) * (qx - ox);
  final d1 = cross(cx, cy, dx, dy, ax, ay);
  final d2 = cross(cx, cy, dx, dy, bx, by);
  final d3 = cross(ax, ay, bx, by, cx, cy);
  final d4 = cross(ax, ay, bx, by, dx, dy);
  return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
}
