import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/level/cave/field_sampler.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/ui/fonts.dart';

/// Applies a level's force fields (gravity zones, wind, wells) to the ship and
/// cargo, and draws them. Forge2D world gravity stays the uniform base; this
/// adds only the *difference* `mass × (local − base)`, so a level without
/// fields is untouched. Kinematic obstacles are unaffected by design.
///
/// Visuals are driven by the same [sampler] as the forces, so what the player
/// sees (streak speed, gusts, feathered edges) is exactly what they feel.
/// Rendered below the rock so effects only show in open cave.
class ForceFieldSystem extends Component {
  ForceFieldSystem({
    required this.sampler,
    required this.ship,
    required this.cargo,
    required this.accent,
    int seed = 0,
  }) : _rng = math.Random(seed),
       super(priority: -1700);

  final FieldSampler sampler;
  final ShipBody ship;
  /// The pod in play (an Expedition moves on to the next leg's).
  CargoBody cargo;

  /// Theme accent for gravity-zone tint and wells.
  final Color accent;
  final math.Random _rng;

  double _time = 0;

  /// Seconds since the level spawned (drives wind gusts).
  double get time => _time;

  /// Last sampled acceleration at the ship (m/s²) — for HUD / assists.
  final Vector2 shipAccel = Vector2.zero();

  /// Gravity alone at the ship (base and zones, no wind or wells).
  final Vector2 shipGravity = Vector2(0, 1);

  final List<_Streak> _streaks = [];
  final List<_Mote> _motes = [];

  /// How deep the ship is in a zero-g pocket (0 outside, 1 in its core):
  /// the pocket's edge lights up while it's inside.
  double _shipInZeroG = 0;

  final Map<GravityZoneSpec, TextPainter> _zeroGTags = {};

  @override
  Future<void> onLoad() async {
    for (final f in sampler.fields) {
      switch (f) {
        case WindZoneSpec():
          final n = (f.halfW * f.halfH * 1.6).clamp(12, 140).round();
          for (int i = 0; i < n; i++) {
            _streaks.add(_Streak(f, _randomIn(f.center, f.halfW, f.halfH), _rng.nextDouble()));
          }
        case GravityZoneSpec():
          if (math.sqrt(f.gx * f.gx + f.gy * f.gy) < 0.05) {
            final n = (f.halfW * f.halfH * 1.8).clamp(14, 160).round();
            for (int i = 0; i < n; i++) {
              _motes.add(_Mote(f, _randomIn(f.center, f.halfW, f.halfH), _rng.nextDouble() * math.pi * 2));
            }
          }
        case GravityWellSpec():
          break;
      }
    }
  }

  Offset _randomIn(Pt c, double hw, double hh) => Offset(
    c.x + (_rng.nextDouble() * 2 - 1) * hw,
    c.y + (_rng.nextDouble() * 2 - 1) * hh,
  );

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    final base = sampler.baseAccel;

    if (ship.isMounted) {
      final p = ship.body.worldCenter;
      final a = sampler.accelAt(p.x, p.y, t: _time);
      shipAccel.setValues(a.x, a.y);
      final g = sampler.gravityAt(p.x, p.y);
      shipGravity.setValues(g.x, g.y);
      var inside = 0.0;
      for (final f in sampler.fields) {
        if (f is GravityZoneSpec && math.sqrt(f.gx * f.gx + f.gy * f.gy) < 0.05) {
          inside = math.max(inside, _depthIn(f, p.x, p.y));
        }
      }
      // Ease, so the glow swells and fades instead of snapping.
      _shipInZeroG += (inside - _shipInZeroG) * math.min(1, dt * 6);
      // The ship floats on its pad until first input (gravityScale = 0).
      if (ship.launched) _applyDelta(ship.body, a.x - base.x, a.y - base.y);
    }

    if (cargo.isMounted && cargo.body.bodyType == BodyType.dynamic) {
      final p = cargo.body.worldCenter;
      final a = sampler.accelAt(p.x, p.y, t: _time, cargo: true);
      _applyDelta(cargo.body, a.x - base.x, a.y - base.y);
    }

    _updateStreaks(dt, base);
    for (final m in _motes) {
      m.phase += dt * 0.6;
    }
  }

  /// 0 outside [z], rising to 1 a feather's width inside its edge.
  static double _depthIn(GravityZoneSpec z, double x, double y) {
    final dx = (x - z.center.x).abs(), dy = (y - z.center.y).abs();
    final double depth;
    if (z.shape == FieldShape.ellipse) {
      final r = math.sqrt(math.pow(dx / z.halfW, 2) + math.pow(dy / z.halfH, 2));
      depth = (1 - r) * math.min(z.halfW, z.halfH);
    } else {
      depth = math.min(z.halfW - dx, z.halfH - dy);
    }
    return z.feather <= 0 ? (depth > 0 ? 1 : 0) : (depth / z.feather).clamp(0.0, 1.0);
  }

  static void _applyDelta(Body body, double dx, double dy) {
    if (dx.abs() < 1e-9 && dy.abs() < 1e-9) return;
    body.applyForce(Vector2(dx * body.mass, dy * body.mass));
  }

  /// Streaks travel with the *local wind* (sampled minus base gravity), so
  /// gusts and feathered edges show up as speed and fade.
  void _updateStreaks(double dt, Pt base) {
    final g0 = sampler.g0;
    for (final s in _streaks) {
      final a = sampler.accelAt(s.pos.dx, s.pos.dy, t: _time);
      final wx = (a.x - base.x) / g0;
      final wy = (a.y - base.y) / g0;
      final w = math.sqrt(wx * wx + wy * wy);
      s.life += dt * 0.5;
      if (w < 0.02 || s.life >= 1) {
        s.pos = _randomIn(s.zone.center, s.zone.halfW, s.zone.halfH);
        s.life = 0;
        continue;
      }
      // ~5 m/s per g of wind: fast enough to read, slow enough to track.
      s.pos += Offset(wx, wy) * (5.0 * dt);
      s.dir = Offset(wx / w, wy / w);
      s.strength = w;
    }
  }

  @override
  void render(Canvas canvas) {
    for (final f in sampler.fields) {
      switch (f) {
        case GravityZoneSpec():
          _renderGravityZone(canvas, f);
        case WindZoneSpec():
          _renderWindZone(canvas, f);
        case GravityWellSpec():
          _renderWell(canvas, f);
      }
    }
    _renderStreaks(canvas);
    _renderMotes(canvas);
  }

  void _renderGravityZone(Canvas canvas, GravityZoneSpec z) {
    final rect = Rect.fromCenter(
      center: Offset(z.center.x, z.center.y),
      width: z.halfW * 2,
      height: z.halfH * 2,
    );
    final zeroG = math.sqrt(z.gx * z.gx + z.gy * z.gy) < 0.05;
    // A slow breath on the edge, brighter while the ship floats inside.
    final pulse = 0.5 + 0.5 * math.sin(_time * 2.4);
    final lit = zeroG ? _shipInZeroG : 0.0;
    final fill = Paint()..color = accent.withValues(alpha: zeroG ? 0.06 + 0.06 * lit : 0.07);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = zeroG ? 0.07 + 0.04 * lit : 0.05
      ..color = accent.withValues(alpha: zeroG ? 0.38 + 0.17 * pulse + 0.3 * lit : 0.28);
    // The fully weightless core (inside the feather), a shade stronger.
    final core = rect.deflate(math.min(z.feather, math.min(z.halfW, z.halfH) * 0.8));
    final coreFill = Paint()..color = accent.withValues(alpha: 0.05 + 0.05 * lit);
    if (z.shape == FieldShape.ellipse) {
      canvas.drawOval(rect, fill);
      if (zeroG) canvas.drawOval(core, coreFill);
      canvas.drawOval(rect, edge);
    } else {
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(0.4));
      canvas.drawRRect(rr, fill);
      if (zeroG) canvas.drawRRect(RRect.fromRectAndRadius(core, const Radius.circular(0.3)), coreFill);
      canvas.drawRRect(rr, edge);
    }
    if (zeroG) _renderZeroGTag(canvas, z, rect, 0.45 + 0.25 * pulse + 0.3 * lit);

    final g = math.sqrt(z.gx * z.gx + z.gy * z.gy);
    if (g < 0.05) return; // zero-g pockets show floating motes instead

    // Chevrons marching in the pull direction; faster for stronger pull.
    final dir = Offset(z.gx / g, z.gy / g);
    final side = Offset(-dir.dy, dir.dx);
    const spacing = 1.6;
    final scroll = (_time * (0.4 + 0.5 * g)) % spacing;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.07
      ..strokeCap = StrokeCap.round;
    for (var y = rect.top + spacing / 2; y < rect.bottom; y += spacing) {
      for (var x = rect.left + spacing / 2; x < rect.right; x += spacing) {
        final p = Offset(x, y) + dir * (scroll - spacing / 2);
        final a = sampler.accelAt(p.dx, p.dy, t: _time);
        final w = _zoneWeightHint(a, z);
        if (w < 0.15) continue;
        paint.color = accent.withValues(alpha: 0.32 * w);
        final tip = p + dir * 0.22;
        canvas.drawLine(tip, p - dir * 0.08 + side * 0.25, paint);
        canvas.drawLine(tip, p - dir * 0.08 - side * 0.25, paint);
      }
    }
  }

  @override
  void onRemove() {
    for (final tp in _zeroGTags.values) {
      tp.dispose();
    }
    _zeroGTags.clear();
    super.onRemove();
  }

  /// "0 g" inside the pocket's top edge.
  void _renderZeroGTag(Canvas canvas, GravityZoneSpec z, Rect rect, double alpha) {
    final tp = _zeroGTags[z] ??= TextPainter(
      text: TextSpan(
        text: '0 g',
        style: TextStyle(fontFamily: kDisplayFont, fontSize: 0.55, color: accent, letterSpacing: 0.04),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = Offset(rect.center.dx - tp.width / 2, rect.top + 0.25);
    // Bounded to the label: an unbounded layer is a full-screen offscreen
    // pass every frame.
    canvas.saveLayer(
      (at & tp.size).inflate(0.1),
      Paint()..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0)),
    );
    tp.paint(canvas, at);
    canvas.restore();
  }

  /// A faint tint and chevrons scrolling with the wind: where it blows, which
  /// way and how hard (faster and brighter in a gust).
  void _renderWindZone(Canvas canvas, WindZoneSpec z) {
    final steady = math.sqrt(z.ax * z.ax + z.ay * z.ay);
    if (steady < 1e-6) return;
    final rect = Rect.fromCenter(
      center: Offset(z.center.x, z.center.y),
      width: z.halfW * 2,
      height: z.halfH * 2,
    );
    const tint = Color(0xFFE6F7FF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(0.6)),
      Paint()..color = tint.withValues(alpha: 0.035),
    );
    final dir = Offset(z.ax / steady, z.ay / steady);
    final side = Offset(-dir.dy, dir.dx);
    const spacing = 1.8;
    final base = sampler.baseAccel;
    final g0 = sampler.g0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.07
      ..strokeCap = StrokeCap.round;
    // Scroll at the gusting strength at the zone's centre.
    final c = sampler.accelAt(z.center.x, z.center.y, t: _time);
    final now = math.sqrt(math.pow(c.x - base.x, 2) + math.pow(c.y - base.y, 2)) / g0;
    final scroll = (_time * (0.6 + 2.0 * now)) % spacing;
    for (var y = rect.top + spacing / 2; y < rect.bottom; y += spacing) {
      for (var x = rect.left + spacing / 2; x < rect.right; x += spacing) {
        final p = Offset(x, y) + dir * (scroll - spacing / 2);
        final a = sampler.accelAt(p.dx, p.dy, t: _time);
        final w = math.sqrt(math.pow(a.x - base.x, 2) + math.pow(a.y - base.y, 2)) / g0;
        final k = (w / steady).clamp(0.0, 1.5);
        if (k < 0.15) continue;
        paint.color = tint.withValues(alpha: (0.22 * k).clamp(0.0, 0.33));
        final tip = p + dir * 0.25;
        canvas.drawLine(tip, p - dir * 0.1 + side * 0.28, paint);
        canvas.drawLine(tip, p - dir * 0.1 - side * 0.28, paint);
      }
    }
  }

  /// How strongly [z] dominates at a point (0..1), inferred from the sampled
  /// field so feathered edges fade the chevrons.
  double _zoneWeightHint(Pt a, GravityZoneSpec z) {
    final base = sampler.baseAccel;
    final tx = z.gx * sampler.g0 - base.x;
    final ty = z.gy * sampler.g0 - base.y;
    final denom = tx * tx + ty * ty;
    if (denom < 1e-9) return 1;
    return (((a.x - base.x) * tx + (a.y - base.y) * ty) / denom).clamp(0.0, 1.0);
  }

  void _renderWell(Canvas canvas, GravityWellSpec w) {
    // Influence radius: where the pull drops to ~0.15 g.
    final reach = math.sqrt(math.max(w.strength / 0.15 - w.softening * w.softening, 1));
    final c = Offset(w.center.x, w.center.y);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.06;
    for (int k = 0; k < 4; k++) {
      final f = ((k / 4) - _time * 0.22) % 1.0; // rings contract inward
      final r = w.coreRadius + (reach - w.coreRadius) * f;
      paint.color = accent.withValues(alpha: 0.35 * (1 - f) * f * 4 * 0.5);
      canvas.drawCircle(c, r, paint);
    }
    canvas.drawCircle(
      c,
      w.coreRadius * 1.6,
      Paint()
        ..shader = RadialGradient(
          colors: [accent.withValues(alpha: 0.35), accent.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: w.coreRadius * 1.6)),
    );
  }

  void _renderStreaks(Canvas canvas) {
    if (_streaks.isEmpty) return;
    final paint = Paint()
      ..strokeWidth = 0.06
      ..strokeCap = StrokeCap.round;
    for (final s in _streaks) {
      if (s.strength < 0.02) continue;
      // Fade in/out over each streak's life so respawns never pop.
      final life = math.sin(s.life * math.pi);
      paint.color = const Color(0xFFE6F7FF)
          .withValues(alpha: (0.28 + 0.6 * s.strength).clamp(0.0, 0.7) * life);
      final len = 0.4 + 1.3 * s.strength.clamp(0.0, 1.0);
      canvas.drawLine(s.pos, s.pos - s.dir * len, paint);
    }
  }

  void _renderMotes(Canvas canvas) {
    if (_motes.isEmpty) return;
    final paint = Paint();
    for (final m in _motes) {
      final p = m.home + Offset(math.cos(m.phase), math.sin(m.phase * 0.8)) * 0.6;
      final a = sampler.accelAt(p.dx, p.dy, t: _time);
      final w = _zoneWeightHint(a, m.zone);
      if (w < 0.1) continue;
      paint.color = accent.withValues(alpha: (0.5 + 0.2 * _shipInZeroG) * w * (0.6 + 0.4 * math.sin(m.phase * 3)));
      canvas.drawCircle(p, 0.07, paint);
    }
  }
}

class _Streak {
  _Streak(this.zone, this.pos, this.life);
  final WindZoneSpec zone;
  Offset pos;
  double life;
  Offset dir = const Offset(1, 0);
  double strength = 0;
}

class _Mote {
  _Mote(this.zone, this.home, this.phase);
  final GravityZoneSpec zone;
  final Offset home;
  double phase;
}
