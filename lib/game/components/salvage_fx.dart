import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/post_process.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/combat.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/components/hud_text.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/salvage/salvage.dart';

/// Boon gold and curse purple: every salvage visual is colour coded.
const Color kSalvageGood = Color(0xFFFFC857);
const Color kSalvageBad = Color(0xFFB388FF);

Color salvageColor(SalvageSpec s) => s.good ? kSalvageGood : kSalvageBad;

/// Mystery salvage cache: a bobbing "?" capsule. Fly through it like a fuel
/// canister; what's inside is rolled on pickup.
class SalvageCache extends Component {
  SalvageCache({required this.pos, required this.host, required this.onCollected})
      : super(priority: 6);

  final Offset pos;
  final CombatHost host;
  final void Function(SalvageCache cache) onCollected;

  static const double pickupRadius = 0.9;

  double _t = 0;
  bool collected = false;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (collected) return;
    final ship = host.combatShip;
    if (ship == null || !ship.isMounted || !host.combatLive) return;
    final p = ship.body.position;
    final dx = p.x - pos.dx;
    final dy = p.y - pos.dy;
    final r = pickupRadius * ship.sizeMul;
    if (dx * dx + dy * dy <= r * r) {
      collected = true;
      onCollected(this);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final bob = math.sin(_t * 1.8) * 0.1;
    canvas.save();
    canvas.translate(pos.dx, pos.dy + bob);
    canvas.scale(1.6);
    // Gold ↔ purple: you can't tell which it'll be.
    final mix = 0.5 + 0.5 * math.sin(_t * 2.4);
    final tint = Color.lerp(kSalvageGood, kSalvageBad, mix)!;
    canvas.drawCircle(
      Offset.zero,
      0.5,
      Paint()
        ..color = tint.withValues(alpha: 0.22 + 0.1 * math.sin(_t * 4))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.22),
    );
    // Orbiting sparks.
    for (var i = 0; i < 3; i++) {
      final a = _t * 2.2 + i * 2 * math.pi / 3;
      canvas.drawCircle(
        Offset(math.cos(a) * 0.4, math.sin(a) * 0.4 * 0.55),
        0.03,
        Paint()..color = Color.lerp(kSalvageGood, kSalvageBad, i / 2)!,
      );
    }
    canvas.rotate(math.sin(_t * 1.1) * 0.15);
    final shell = hexPath(Offset.zero, 0.27);
    canvas.drawPath(shell, Paint()..color = const Color(0xFF241A38));
    canvas.drawPath(
      shell,
      Paint()
        ..color = tint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.035,
    );
    _drawQuestion(canvas, Offset.zero, 0.26, Colors.white);
    canvas.restore();
  }
}

void _drawQuestion(Canvas canvas, Offset c, double h, Color color) {
  final w = h * 0.36;
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = h * 0.16
    ..strokeCap = StrokeCap.round;
  final top = c.dy - h * 0.5;
  final path = Path()
    ..moveTo(c.dx - w, top + w * 0.9)
    ..arcTo(Rect.fromCircle(center: Offset(c.dx, top + w), radius: w), math.pi, math.pi * 1.45, false)
    ..lineTo(c.dx, c.dy + h * 0.12);
  canvas.drawPath(path, stroke);
  canvas.drawCircle(Offset(c.dx, c.dy + h * 0.42), h * 0.09, Paint()..color = color);
}

Path _dropPath(Offset c, double s) {
  final top = Offset(c.dx, c.dy - s * 0.5);
  final r = s * 0.3;
  final ctr = Offset(c.dx, c.dy + s * 0.18);
  return Path()
    ..moveTo(top.dx, top.dy)
    ..quadraticBezierTo(c.dx + r * 1.1, c.dy - s * 0.05, ctr.dx + r, ctr.dy)
    ..arcTo(Rect.fromCircle(center: ctr, radius: r), 0, math.pi, false)
    ..quadraticBezierTo(c.dx - r * 1.1, c.dy - s * 0.05, top.dx, top.dy)
    ..close();
}

/// HUD glyph for a salvage effect ([effect] null = "?"), [s] tall.
void drawSalvageGlyph(Canvas canvas, Offset c, double s, SalvageEffect? effect, Color color) {
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.1
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final fill = Paint()..color = color;
  switch (effect) {
    case null:
      _drawQuestion(canvas, c, s * 0.9, color);
    case SalvageEffect.overshield:
      canvas.drawPath(hexPath(c, s * 0.48), stroke);
      canvas.drawPath(hexPath(c, s * 0.24), fill);
    case SalvageEffect.topOff:
      canvas.drawPath(_dropPath(c.translate(-s * 0.1, 0), s * 0.85), stroke);
      final p = c.translate(s * 0.28, -s * 0.22);
      canvas.drawLine(p.translate(-s * 0.14, 0), p.translate(s * 0.14, 0), stroke);
      canvas.drawLine(p.translate(0, -s * 0.14), p.translate(0, s * 0.14), stroke);
    case SalvageEffect.afterburner:
      drawFlameGlyph(canvas, c, s * 0.95, hot: true);
    case SalvageEffect.fuelSaver:
      canvas.drawPath(_dropPath(c, s * 0.9), stroke);
      canvas.drawCircle(c.translate(0, s * 0.12), s * 0.12, stroke..strokeWidth = s * 0.07);
    case SalvageEffect.stealth:
      final eye = Path()
        ..moveTo(c.dx - s * 0.48, c.dy)
        ..quadraticBezierTo(c.dx, c.dy - s * 0.42, c.dx + s * 0.48, c.dy)
        ..quadraticBezierTo(c.dx, c.dy + s * 0.42, c.dx - s * 0.48, c.dy)
        ..close();
      canvas.drawPath(eye, stroke);
      canvas.drawCircle(c, s * 0.11, fill);
      canvas.drawLine(c.translate(-s * 0.42, s * 0.38), c.translate(s * 0.42, -s * 0.38), stroke);
    case SalvageEffect.swarmSting:
      _drawBee(canvas, c, s * 0.9, 0, color);
    case SalvageEffect.fuelLeak:
      canvas.drawPath(_dropPath(c.translate(0, -s * 0.06), s * 0.8), stroke);
      final crack = Path()
        ..moveTo(c.dx - s * 0.05, c.dy - s * 0.2)
        ..lineTo(c.dx + s * 0.06, c.dy - s * 0.02)
        ..lineTo(c.dx - s * 0.04, c.dy + s * 0.12);
      canvas.drawPath(crack, stroke..strokeWidth = s * 0.07);
      canvas.drawCircle(c.translate(s * 0.02, s * 0.45), s * 0.06, fill);
    case SalvageEffect.compactor:
      // Four arrows pointing in.
      for (var i = 0; i < 4; i++) {
        final d = Offset(math.cos(i * math.pi / 2 + math.pi / 4), math.sin(i * math.pi / 2 + math.pi / 4));
        final tip = c + d * s * 0.12;
        canvas.drawLine(c + d * s * 0.46, tip, stroke);
        final n = Offset(-d.dy, d.dx) * s * 0.1;
        canvas.drawLine(tip, tip + d * s * 0.13 + n, stroke);
        canvas.drawLine(tip, tip + d * s * 0.13 - n, stroke);
      }
    case SalvageEffect.chrono:
      canvas.drawCircle(c, s * 0.44, stroke);
      canvas.drawLine(c, c.translate(0, -s * 0.28), stroke);
      canvas.drawLine(c, c.translate(s * 0.2, s * 0.08), stroke);
    case SalvageEffect.antiGrav:
      canvas.drawLine(c.translate(0, s * 0.42), c.translate(0, -s * 0.4), stroke);
      canvas.drawLine(c.translate(0, -s * 0.4), c.translate(-s * 0.18, -s * 0.2), stroke);
      canvas.drawLine(c.translate(0, -s * 0.4), c.translate(s * 0.18, -s * 0.2), stroke);
      canvas.drawOval(Rect.fromCenter(center: c.translate(0, s * 0.18), width: s * 0.8, height: s * 0.24), stroke..strokeWidth = s * 0.06);
    case SalvageEffect.lucky:
      canvas.drawCircle(c, s * 0.42, fill);
      canvas.drawCircle(c, s * 0.3, Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.06);
      canvas.drawCircle(c, s * 0.1, Paint()..color = Colors.black.withValues(alpha: 0.35));
    case SalvageEffect.ammoCache:
      final box = Rect.fromCenter(center: c, width: s * 0.86, height: s * 0.6);
      canvas.drawRect(box, stroke);
      canvas.drawLine(box.centerLeft.translate(0, -s * 0.08), box.centerRight.translate(0, -s * 0.08), stroke);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - s * 0.12, c.dy + s * 0.2)
          ..lineTo(c.dx, c.dy + s * 0.06)
          ..lineTo(c.dx + s * 0.12, c.dy + s * 0.2),
        stroke,
      );
    case SalvageEffect.sporeTrip:
      // A mushroom: spotted cap on a stalk.
      final cap = Path()
        ..moveTo(c.dx - s * 0.48, c.dy)
        ..quadraticBezierTo(c.dx, c.dy - s * 0.7, c.dx + s * 0.48, c.dy)
        ..close();
      canvas.drawPath(cap, fill);
      canvas.drawRect(Rect.fromLTRB(c.dx - s * 0.12, c.dy, c.dx + s * 0.12, c.dy + s * 0.42), stroke);
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.85);
      canvas.drawCircle(c.translate(-s * 0.18, -s * 0.14), s * 0.07, dot);
      canvas.drawCircle(c.translate(s * 0.14, -s * 0.2), s * 0.06, dot);
    case SalvageEffect.crossedWires:
      for (final dir in [-1.0, 1.0]) {
        final y = c.dy + dir * s * 0.18;
        final from = c.dx - dir * s * 0.42, to = c.dx + dir * s * 0.42;
        canvas.drawLine(Offset(from, y), Offset(to, y), stroke);
        canvas.drawLine(Offset(to, y), Offset(to - dir * s * 0.16, y - s * 0.12), stroke);
        canvas.drawLine(Offset(to, y), Offset(to - dir * s * 0.16, y + s * 0.12), stroke);
      }
    case SalvageEffect.sputter:
      for (final (dx, dy, r) in [(-0.2, 0.1, 0.18), (0.08, -0.1, 0.22), (0.26, 0.16, 0.14)]) {
        canvas.drawCircle(c.translate(s * dx, s * dy), s * r, stroke..strokeWidth = s * 0.07);
      }
    case SalvageEffect.blackout:
      canvas.drawCircle(c, s * 0.42, fill);
      canvas.drawCircle(c.translate(s * 0.16, -s * 0.1), s * 0.36, Paint()..color = const Color(0xFF050B18));
    case SalvageEffect.hiccups:
      final z = Path()..moveTo(c.dx - s * 0.45, c.dy);
      for (var i = 1; i <= 4; i++) {
        z.lineTo(c.dx - s * 0.45 + i * s * 0.225, c.dy + (i.isOdd ? -s * 0.28 : s * 0.28));
      }
      canvas.drawPath(z, stroke);
    case SalvageEffect.heavyHeart:
      // A weight: trapezoid with a handle.
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - s * 0.26, c.dy - s * 0.12)
          ..lineTo(c.dx + s * 0.26, c.dy - s * 0.12)
          ..lineTo(c.dx + s * 0.42, c.dy + s * 0.42)
          ..lineTo(c.dx - s * 0.42, c.dy + s * 0.42)
          ..close(),
        fill,
      );
      canvas.drawCircle(c.translate(0, -s * 0.28), s * 0.14, stroke..strokeWidth = s * 0.07);
    case SalvageEffect.flareBeacon:
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + d * s * 0.2, c + d * s * (i.isEven ? 0.48 : 0.36), stroke);
      }
      canvas.drawCircle(c, s * 0.13, fill);
  }
}

/// A cartoon bee facing +x, [s] long; [wing] 0…1 flaps the wings.
void _drawBee(Canvas canvas, Offset c, double s, double wing, Color outline) {
  final body = Rect.fromCenter(center: c, width: s * 0.8, height: s * 0.52);
  final wingPaint = Paint()..color = const Color(0xCCE3F2FD);
  final flap = 0.6 + 0.4 * math.sin(wing * 2 * math.pi);
  canvas.drawOval(
    Rect.fromCenter(
      center: c.translate(-s * 0.05, -s * 0.3),
      width: s * 0.38,
      height: s * 0.3 * flap,
    ),
    wingPaint,
  );
  canvas.drawOval(body, Paint()..color = const Color(0xFFFFC107));
  canvas.save();
  canvas.clipPath(Path()..addOval(body));
  final stripe = Paint()..color = const Color(0xFF212121);
  for (final x in [-0.12, 0.08]) {
    canvas.drawRect(
      Rect.fromCenter(center: c.translate(s * x, 0), width: s * 0.1, height: s),
      stripe,
    );
  }
  canvas.restore();
  // Stinger and eye.
  canvas.drawPath(
    Path()
      ..moveTo(c.dx - s * 0.38, c.dy - s * 0.06)
      ..lineTo(c.dx - s * 0.52, c.dy)
      ..lineTo(c.dx - s * 0.38, c.dy + s * 0.06)
      ..close(),
    Paint()..color = const Color(0xFF212121),
  );
  canvas.drawCircle(c.translate(s * 0.26, -s * 0.06), s * 0.05, Paint()..color = const Color(0xFF212121));
  canvas.drawOval(
    body,
    Paint()
      ..color = outline.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.04,
  );
}

/// World-space effects around the ship: the Overshield bubble, the stealth
/// shimmer, the bee of a Swarm Sting, Fuel Leak drips, and the pop where a
/// cache was opened.
class SalvageAura extends Component {
  SalvageAura({required this.ship, required this.state, this.pod}) : super(priority: 1045);

  final ShipBody ship;
  final ActiveSalvage state;

  /// The pod's centre (Anti-grav and Heavy Heart mark it too).
  final Vector2? Function()? pod;
  final math.Random _rng = math.Random(7);

  double _t = 0;
  double _dripTimer = 0;
  final List<_Drip> _drips = [];
  final List<_Pop> _pops = [];

  /// Gravity for the drips (world, m/s²); set by the game.
  final Vector2 gravity = Vector2(0, 1.4);

  void pop(Offset at, Color color) => _pops.add(_Pop(at, color));

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    for (final p in _pops) {
      p.t += dt;
    }
    _pops.removeWhere((p) => p.t > 0.7);
    for (final d in _drips) {
      d.t += dt;
      d.vel.add(gravity * dt);
      d.pos.add(d.vel * dt);
    }
    _drips.removeWhere((d) => d.t > 1.2);
    if (state.effect == SalvageEffect.sputter && ship.sputtering && ship.isMounted) {
      // The engine coughs out a puff of smoke.
      _dripTimer -= dt;
      if (_dripTimer <= 0) {
        _dripTimer = 0.05;
        final at = ship.body.worldPoint(Vector2(0, ship.rearLocalY * ship.sizeMul + 0.1));
        _drips.add(_Drip(at, ship.body.worldVector(Vector2((_rng.nextDouble() - 0.5) * 0.8, 1.2)), smoke: true));
      }
    }
    if (state.effect == SalvageEffect.fuelLeak && ship.isMounted && ship.launched) {
      _dripTimer -= dt;
      if (_dripTimer <= 0) {
        _dripTimer = 0.06;
        final at = ship.body.worldPoint(Vector2((_rng.nextDouble() - 0.5) * 0.3, ship.rearLocalY * ship.sizeMul));
        _drips.add(_Drip(
          at,
          ship.body.linearVelocity * 0.6 + Vector2((_rng.nextDouble() - 0.5) * 0.6, 0.2),
        ));
      }
    }
  }

  @override
  void render(Canvas canvas) {
    for (final p in _pops) {
      final k = p.t / 0.7;
      final r = 0.3 + 1.6 * Curves.easeOut.transform(k);
      canvas.drawCircle(
        p.at,
        r,
        Paint()
          ..color = p.color.withValues(alpha: 0.8 * (1 - k))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.08 * (1 - k) + 0.02,
      );
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4 + 0.3;
        canvas.drawCircle(
          p.at + Offset(math.cos(a), math.sin(a)) * r * 0.8,
          0.05 * (1 - k),
          Paint()..color = p.color,
        );
      }
    }
    final drip = Paint();
    for (final d in _drips) {
      final fade = (1 - d.t / 1.2).clamp(0.0, 1.0);
      if (d.smoke) {
        drip.color = const Color(0xFF8D8D8D).withValues(alpha: 0.5 * fade);
        canvas.drawCircle(Offset(d.pos.x, d.pos.y), 0.08 + 0.2 * d.t, drip);
      } else {
        drip.color = const Color(0xFF9CCC65).withValues(alpha: fade);
        canvas.drawCircle(Offset(d.pos.x, d.pos.y), 0.045, drip);
      }
    }
    if (!ship.isMounted) return;
    final effect = state.effect;
    if (effect == null) return;
    final c = Offset(ship.body.position.x, ship.body.position.y);
    final r = ship.spec.circumradius * ship.sizeMul * 0.85;
    // Last 2 s: blink so the end never surprises.
    final ending = state.left < 2 && (state.left * 6).floor().isEven;
    switch (effect) {
      case SalvageEffect.overshield:
        final a = ending ? 0.25 : 0.55;
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = kSalvageGood.withValues(alpha: 0.12)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.15),
        );
        canvas.drawPath(
          hexPath(c, r, rotation: _t * 0.6),
          Paint()
            ..color = kSalvageGood.withValues(alpha: a)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.05,
        );
        canvas.drawCircle(
          c,
          r * 1.04,
          Paint()
            ..color = kSalvageGood.withValues(alpha: a * 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.025,
        );
      case SalvageEffect.stealth:
        final sparkle = Paint()..color = const Color(0xFF7DF9FF).withValues(alpha: ending ? 0.3 : 0.7);
        for (var i = 0; i < 6; i++) {
          final a = _t * 1.7 + i * math.pi / 3;
          final rr = r * (0.8 + 0.25 * math.sin(_t * 3 + i));
          canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * rr, 0.035, sparkle);
        }
      case SalvageEffect.swarmSting:
        final a = _t * 3.1;
        final orbit = r * 1.15;
        final at = c + Offset(math.cos(a) * orbit, math.sin(a * 1.3) * orbit * 0.6);
        canvas.save();
        canvas.translate(at.dx, at.dy);
        // Faces where it's flying.
        canvas.rotate(math.atan2(math.cos(a * 1.3) * 1.3 * 0.6, -math.sin(a)));
        _drawBee(canvas, Offset.zero, 0.42, _t * 14, Colors.black);
        canvas.restore();
      case SalvageEffect.afterburner || SalvageEffect.fuelSaver:
        // A soft ring round the bell: the engine kit is on.
        final bell = ship.body.worldPoint(Vector2(0, ship.rearLocalY * ship.sizeMul));
        canvas.drawCircle(
          Offset(bell.x, bell.y),
          0.28 + 0.04 * math.sin(_t * 12),
          Paint()
            ..color = (effect == SalvageEffect.afterburner ? const Color(0xFF64B5F6) : const Color(0xFF9CCC65))
                .withValues(alpha: ending ? 0.2 : 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.1),
        );
      case SalvageEffect.flareBeacon:
        // A red strobe stuck to the hull.
        final on = (_t * 5).floor().isEven;
        canvas.drawCircle(
          c,
          r * (on ? 1.1 : 0.7),
          Paint()
            ..color = const Color(0xFFFF1744).withValues(alpha: on ? 0.3 : 0.12)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.3),
        );
        canvas.drawCircle(c, 0.07, Paint()..color = on ? Colors.white : const Color(0xFFFF1744));
      case SalvageEffect.antiGrav || SalvageEffect.heavyHeart:
        final anti = effect == SalvageEffect.antiGrav;
        final color = anti ? const Color(0xFF80DEEA) : kSalvageBad;
        final paint = Paint()
          ..color = color.withValues(alpha: ending ? 0.25 : 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.04;
        void rings(Offset at, double size) {
          for (var i = 0; i < 2; i++) {
            final k = (_t * 0.8 + i * 0.5) % 1;
            // Anti-grav rings rise; Heavy Heart's sink.
            final y = at.dy + (anti ? -1 : 1) * (k - 0.5) * size;
            canvas.drawOval(
              Rect.fromCenter(center: Offset(at.dx, y), width: size * (1.2 - 0.4 * k), height: size * 0.3),
              paint..color = color.withValues(alpha: (ending ? 0.25 : 0.55) * (1 - k)),
            );
          }
        }
        if (anti) rings(c, r * 1.4);
        final p = pod?.call();
        if (p != null) rings(Offset(p.x, p.y), 0.8);
      case SalvageEffect.compactor || SalvageEffect.chrono:
        // A ticking ring: the clock is on.
        final sweep = 2 * math.pi * state.fraction;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r * 1.08),
          -math.pi / 2,
          sweep,
          false,
          Paint()
            ..color = kSalvageGood.withValues(alpha: ending ? 0.25 : 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.035,
        );
      case SalvageEffect.fuelLeak ||
            SalvageEffect.topOff ||
            SalvageEffect.lucky ||
            SalvageEffect.ammoCache ||
            SalvageEffect.sporeTrip ||
            SalvageEffect.crossedWires ||
            SalvageEffect.sputter ||
            SalvageEffect.blackout ||
            SalvageEffect.hiccups:
        break;
    }
  }
}

class _Drip {
  _Drip(this.pos, this.vel, {this.smoke = false});
  final Vector2 pos;
  final Vector2 vel;
  final bool smoke;
  double t = 0;
}

class _Pop {
  _Pop(this.at, this.color);
  final Offset at;
  final Color color;
  double t = 0;
}

/// The salvage badge (top left, under the fuel gauge): a slot-machine
/// roulette while a cache is being opened, then the effect's icon, name and
/// a draining countdown bar.
class SalvageHud extends PositionComponent {
  SalvageHud({required this.state, this.onTick}) : super(priority: 4910);

  final ActiveSalvage state;

  /// One roulette click (a tick sound).
  final void Function()? onTick;

  /// Safe-area insets (the badge keeps clear of the notch).
  EdgeInsets insets = EdgeInsets.zero;

  static const double rouletteSeconds = 0.9;

  /// Plate rect (left, top) relative to the safe area; below the fuel gauge
  /// and level info (`HudButtonLayout.topClear`).
  static const Offset origin = Offset(12, 110);
  static const Size plateSize = Size(196, 38);

  SalvageSpec? _shown;
  double _roulette = 0;
  int _face = -1;
  double _pop = 1;
  double _hold = 0;
  double _fade = 0;
  double _t = 0;

  final _name = HudText();
  final _sub = HudText();

  /// A cache opened: spin, then land on [result] (the game applies it).
  void spin(SalvageSpec result) {
    _shown = result;
    _roulette = rouletteSeconds;
    _face = -1;
    _pop = 0;
    _hold = 0;
  }

  bool get spinning => _roulette > 0;

  /// Clears the badge (new level).
  void clear() {
    _shown = null;
    _roulette = 0;
    _fade = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_roulette > 0) {
      _roulette = math.max(0, _roulette - dt);
      // Faces flick by fast, then slow down (ease-out).
      final k = 1 - _roulette / rouletteSeconds;
      final face = (Curves.easeOut.transform(k) * 9).floor();
      if (face != _face) {
        _face = face;
        if (_roulette > 0) onTick?.call();
      }
      if (_roulette == 0) _hold = 1.6;
    } else {
      _pop = math.min(1, _pop + dt / 0.3);
      if (_hold > 0) _hold -= dt;
    }
    final visible = _shown != null && (_roulette > 0 || state.active || _hold > 0);
    _fade = (_fade + (visible ? dt : -dt) * 5).clamp(0.0, 1.0);
    if (_fade == 0 && !visible) _shown = null;
  }

  @override
  void render(Canvas canvas) {
    final spec = _shown;
    if (spec == null || _fade <= 0) return;
    final spinning = _roulette > 0;
    final color = spinning
        ? Color.lerp(kSalvageGood, kSalvageBad, 0.5 + 0.5 * math.sin(_t * 18))!
        : salvageColor(spec);
    final left = insets.left + origin.dx;
    final top = insets.top + origin.dy;
    final scale = spinning ? 1.0 : 1 + 0.15 * (1 - Curves.easeOutBack.transform(_pop));
    canvas.save();
    canvas.translate(left, top);
    canvas.scale(scale);
    if (_fade < 1) {
      canvas.saveLayer(
        Offset.zero & plateSize,
        Paint()..color = Color.fromRGBO(255, 255, 255, _fade),
      );
    }
    final plate = chamferRect(Offset.zero & plateSize, 9);
    drawGlow(canvas, plate, color, spinning ? 0.7 : 0.45);
    canvas.drawPath(plate, Paint()..color = HudColors.plateDark);
    drawStroke(canvas, plate, color.withValues(alpha: 0.85), 1.4);

    const hexC = Offset(21, 19);
    final hex = hexPath(hexC, 14);
    canvas.drawPath(hex, Paint()..color = color.withValues(alpha: 0.18));
    drawStroke(canvas, hex, color, 1.2);
    final face = spinning
        ? (_face <= 0 ? null : kSalvage[(_face * 3) % kSalvage.length].effect)
        : spec.effect;
    drawSalvageGlyph(canvas, hexC, 16, face, spinning ? Colors.white : color);

    final title = spinning ? 'SALVAGE  ? ? ?' : spec.name;
    final name = _name.layout(TextSpan(text: title, style: hudFont(11, Colors.white)));
    name.paint(canvas, const Offset(42, 6));
    final subText = spinning
        ? 'OPENING…'
        : spec.timed
            ? (spec.good ? 'BOON' : 'CURSE')
            : (spec.good ? 'BOON · INSTANT' : 'CURSE');
    final sub = _sub.layout(
      TextSpan(text: subText, style: hudFont(8, color.withValues(alpha: 0.9), spacing: 1.2)),
    );
    sub.paint(canvas, Offset(plateSize.width - 10 - sub.width, 8));

    // Countdown bar.
    final bar = Rect.fromLTWH(42, 25, plateSize.width - 42 - 12, 5);
    canvas.drawRect(bar, Paint()..color = Colors.white.withValues(alpha: 0.12));
    final frac = spinning ? (1 - _roulette / rouletteSeconds) : (spec.timed ? state.fraction : (_hold / 1.6).clamp(0.0, 1.0));
    final blink = !spinning && spec.timed && state.left < 2 && (state.left * 6).floor().isEven;
    canvas.drawRect(
      Rect.fromLTWH(bar.left, bar.top, bar.width * frac, bar.height),
      Paint()..color = color.withValues(alpha: blink ? 0.35 : 0.95),
    );
    if (_fade < 1) canvas.restore();
    canvas.restore();
  }
}

/// Full-screen salvage effects over the world, under the HUD: Blackout's
/// headlamp, Spore Trip's colour drift (on top of its shader, or alone
/// where shaders aren't available) and Chrono's blue vignette.
class SalvageScreenFx extends PositionComponent {
  SalvageScreenFx() : super(priority: 4700);

  /// Ship centre on screen, zoom (px per metre) and heading; set each frame.
  Offset shipScreen = Offset.zero;
  double pxPerMeter = 28;
  double noseAngle = 0;

  /// 0…1 each, eased by the effect.
  double darkness = 0;
  double hallucination = 0;
  double chrono = 0;

  double _t = 0;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    final screen = Offset.zero & size.toSize();
    if (chrono > 0) {
      canvas.drawRect(
        screen,
        Paint()
          ..shader = ui.Gradient.radial(
            screen.center,
            screen.longestSide * 0.62,
            [const Color(0x00000000), const Color(0xFF2962FF).withValues(alpha: 0.32 * chrono)],
            [0.55, 1.0],
          ),
      );
    }
    if (hallucination > 0) {
      // Slow bands of shifting colour.
      for (var i = 0; i < 3; i++) {
        final hue = (_t * 40 + i * 120) % 360;
        final color = HSVColor.fromAHSV(0.12 * hallucination, hue, 0.8, 1).toColor();
        final y = screen.height * (0.5 + 0.45 * math.sin(_t * 0.7 + i * 2.1));
        canvas.drawRect(
          screen,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.linear(
              Offset(0, y - screen.height * 0.35),
              Offset(0, y + screen.height * 0.35),
              [color.withValues(alpha: 0), color, color.withValues(alpha: 0)],
              [0, 0.5, 1],
            ),
        );
      }
    }
    if (darkness > 0) {
      canvas.saveLayer(screen, Paint());
      canvas.drawRect(screen, Paint()..color = Colors.black.withValues(alpha: 0.94 * darkness));
      final cut = Paint()..blendMode = BlendMode.dstOut;
      // A small glow round the ship…
      final glowR = 2.4 * pxPerMeter;
      canvas.drawCircle(
        shipScreen,
        glowR,
        cut
          ..shader = ui.Gradient.radial(
            shipScreen,
            glowR,
            [Colors.white, Colors.white.withValues(alpha: 0)],
          ),
      );
      // …and a headlamp cone out of the nose.
      final reach = 8.5 * pxPerMeter;
      const half = 0.42;
      final dir = noseAngle - math.pi / 2;
      final cone = Path()
        ..moveTo(shipScreen.dx, shipScreen.dy)
        ..arcTo(Rect.fromCircle(center: shipScreen, radius: reach), dir - half, half * 2, false)
        ..close();
      canvas.drawPath(
        cone,
        cut
          ..shader = ui.Gradient.radial(
            shipScreen,
            reach,
            [Colors.white, Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0)],
            [0, 0.55, 1],
          ),
      );
      canvas.restore();
    }
  }
}

/// Spore Trip's warp: the world is rendered to an image and redrawn through
/// `shaders/spore.frag` (waves, colour split, hue drift).
class SporePostProcess extends PostProcess {
  SporePostProcess(ui.FragmentProgram program, this.amount) : _shader = program.fragmentShader();

  final ui.FragmentShader _shader;
  final double Function() amount;
  double _t = 0;

  @override
  void update(double dt) => _t += dt;

  @override
  void postProcess(Vector2 size, Canvas canvas) {
    final a = amount();
    if (a <= 0.001) {
      renderSubtree(canvas);
      return;
    }
    final recorder = ui.PictureRecorder();
    final inner = Canvas(recorder)..scale(pixelRatio);
    renderSubtree(inner);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (size.x * pixelRatio).ceil(),
      (size.y * pixelRatio).ceil(),
    );
    picture.dispose();
    _shader
      ..setFloat(0, size.x)
      ..setFloat(1, size.y)
      ..setFloat(2, _t)
      ..setFloat(3, a)
      ..setImageSampler(0, image);
    canvas.drawRect(Offset.zero & size.toSize(), Paint()..shader = _shader);
    image.dispose();
  }
}
