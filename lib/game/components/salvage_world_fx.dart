import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/combat.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/components/salvage_glyphs.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/salvage/salvage.dart';

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
    drawQuestionGlyph(canvas, Offset.zero, 0.26, Colors.white);
    canvas.restore();
  }
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
        drawBeeGlyph(canvas, Offset.zero, 0.42, _t * 14, Colors.black);
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
