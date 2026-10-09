import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/components/hud_text.dart';
import 'package:narrow_haul/ui/fonts.dart';

/// Top-center pause button (top-right belongs to the minimap).
class PauseButtonHud extends PositionComponent with TapCallbacks {
  PauseButtonHud({required this.onPressed})
    : super(priority: 4950, size: Vector2.all(_size), anchor: Anchor.topCenter);

  final VoidCallback onPressed;

  /// Hidden (and untappable) outside of active flight.
  bool visible = false;

  static const double _size = 40;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    position = Vector2(size.x / 2, 8);
  }

  @override
  bool containsLocalPoint(Vector2 point) =>
      visible && super.containsLocalPoint(point);

  @override
  void onTapUp(TapUpEvent event) => onPressed();

  @override
  void render(Canvas canvas) {
    if (!visible) return;
    const c = Offset(_size / 2, _size / 2);
    final plate = chamferRect(Offset.zero & const Size(_size, _size), 11);
    drawGlow(canvas, plate, HudColors.cyan, 0.25);
    canvas.drawPath(plate, Paint()..color = HudColors.plate);
    drawStroke(canvas, plate, HudColors.cyan.withValues(alpha: 0.7), 1.4);
    final bar = Paint()..color = const Color(0xE6FFFFFF);
    for (final dx in [-5.0, 5.0]) {
      canvas.drawRect(
        Rect.fromCenter(center: c + Offset(dx, 0), width: 4.5, height: 15),
        bar,
      );
    }
  }
}

/// "3 · 2 · 1 · GO" before the ship launches by itself. Each step pops in
/// big and shrinks; GO fades out after the launch.
class CountdownHud extends PositionComponent {
  CountdownHud() : super(priority: 4930);

  final _label = HudText();
  String? _text;
  double _age = 0;
  Color accent = Colors.white;

  static const double _goSeconds = 0.6;

  /// Shows [text] (restarting the pop when it changes); null hides it.
  set text(String? value) {
    if (value == _text) return;
    _text = value;
    _age = 0;
  }

  /// Shows GO, then fades it out on its own.
  void go() => text = 'GO';

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_text == 'GO' && _age > _goSeconds) _text = null;
  }

  @override
  void render(Canvas canvas) {
    final text = _text;
    if (text == null) return;
    final pop = (1 - _age / 0.25).clamp(0.0, 1.0);
    final scale = 1 + 0.5 * pop * pop;
    final alpha = text == 'GO'
        ? (1 - _age / _goSeconds).clamp(0.0, 1.0)
        : (1 - math.max(0, _age - 0.7) / 0.3).clamp(0.0, 1.0);
    final q = quantizeAlpha(alpha);
    final tp = _label.layout(
      TextSpan(
        text: text,
        style: TextStyle(
          color: (text == 'GO' ? accent : Colors.white).withValues(alpha: q),
          fontFamily: kDisplayFont,
          fontSize: 64,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(color: Colors.black.withValues(alpha: q * 0.7), blurRadius: 12),
          ],
        ),
      ),
    );
    canvas.save();
    canvas.translate(size.x / 2, size.y * 0.5);
    canvas.scale(scale);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }
}

/// World + level name card that fades in and out at level start.
class LevelIntroHud extends PositionComponent {
  LevelIntroHud() : super(priority: 4920);

  final _sub = HudText();
  final _titleText = HudText();
  final _noteText = HudText();

  String _title = '';
  String _subtitle = '';
  String _note = '';
  Color _accent = Colors.white;
  double _t = _duration;

  static const double _duration = 2.4;
  static const double _fade = 0.45;

  void show({
    required String title,
    required String subtitle,
    required Color accent,
    String note = '',
  }) {
    _title = title;
    _subtitle = subtitle;
    _note = note;
    _accent = accent;
    _t = 0;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_t < _duration) _t += dt;
  }

  @override
  void render(Canvas canvas) {
    if (_t >= _duration || _title.isEmpty) return;
    final a = _t < _fade
        ? _t / _fade
        : _t > _duration - _fade
        ? (_duration - _t) / _fade
        : 1.0;
    final rise = (1 - a) * 10;
    final q = quantizeAlpha(a);

    final sub = _sub.layout(
      TextSpan(
        text: _subtitle.toUpperCase(),
        style: TextStyle(
          color: _accent.withValues(alpha: q * 0.9),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 4,
        ),
      ),
    );
    final title = _titleText.layout(
      TextSpan(
        text: _title,
        style: TextStyle(
          color: Colors.white.withValues(alpha: q),
          fontFamily: kDisplayFont,
          fontSize: 30,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: q * 0.7),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );

    final cy = size.y * 0.28 + rise;
    sub.paint(canvas, Offset((size.x - sub.width) / 2, cy));
    title.paint(
      canvas,
      Offset((size.x - title.width) / 2, cy + sub.height + 2),
    );
    final lineW = math.max(title.width, sub.width) * 0.6;
    final lineY = cy + sub.height + title.height + 8;
    canvas.drawLine(
      Offset((size.x - lineW) / 2, lineY),
      Offset((size.x + lineW) / 2, lineY),
      Paint()
        ..color = _accent.withValues(alpha: a * 0.6)
        ..strokeWidth = 2,
    );
    if (_note.isNotEmpty) {
      final note = _noteText.layout(
        TextSpan(
          text: _note,
          style: TextStyle(
            color: Colors.white.withValues(alpha: q * 0.75),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
      );
      note.paint(canvas, Offset((size.x - note.width) / 2, lineY + 8));
    }
  }
}

/// Dust kicked up where the ship touched down on rock (world space,
/// meters), thrown off the surface along [normal].
class DustPuff extends Component {
  DustPuff({required this.center, required Offset normal, int seed = 0})
    : super(priority: 1100) {
    final rng = math.Random(seed);
    final base = math.atan2(normal.dy, normal.dx);
    _grains = List.generate(10, (_) {
      final ang = base + (rng.nextDouble() - 0.5) * 2.6;
      final speed = 0.6 + rng.nextDouble() * 0.8;
      return _Debris(
        pos: center,
        vel: Offset(math.cos(ang), math.sin(ang)) * speed,
        size: 0.05 + rng.nextDouble() * 0.06,
        hot: false,
        life: 0.35 + rng.nextDouble() * 0.2,
      );
    });
  }

  final Offset center;
  late final List<_Debris> _grains;
  double _t = 0;

  @override
  void update(double dt) {
    _t += dt;
    for (final d in _grains) {
      d.vel = d.vel * math.pow(0.05, dt).toDouble() + Offset(0, 1.5 * dt);
      d.pos += d.vel * dt;
    }
    if (_t >= 0.6) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint();
    for (final d in _grains) {
      final k = 1 - (_t / d.life).clamp(0.0, 1.0);
      if (k <= 0) continue;
      paint.color = const Color(0xFFB8B0A0).withValues(alpha: 0.45 * k);
      canvas.drawCircle(d.pos, d.size * (1.6 - k * 0.6), paint);
    }
  }
}

/// Crash explosion in world space (meters): a flash, a shock ring and hull
/// debris under gravity. Removes itself when finished.
class ExplosionBurst extends Component {
  ExplosionBurst({
    required this.center,
    required this.accent,
    int seed = 0,
    this.ringRadius = 2.7,
  }) : _rng = math.Random(seed),
       super(priority: 1100);

  final Offset center;
  final Color accent;

  /// Where the shock ring ends (m): a weapon's blast radius shows its reach.
  final double ringRadius;
  final math.Random _rng;

  static const double _life = 1.1;
  double _t = 0;
  late final List<_Debris> _debris;

  @override
  Future<void> onLoad() async {
    _debris = List.generate(46, (i) {
      final ang = _rng.nextDouble() * math.pi * 2;
      final speed = 1.5 + _rng.nextDouble() * 5.5;
      return _Debris(
        pos: center,
        vel: Offset(math.cos(ang), math.sin(ang)) * speed,
        size: 0.04 + _rng.nextDouble() * 0.09,
        hot: i.isEven,
        life: 0.5 + _rng.nextDouble() * 0.6,
      );
    });
  }

  @override
  void update(double dt) {
    _t += dt;
    for (final d in _debris) {
      d.vel = d.vel * math.pow(0.12, dt).toDouble() + Offset(0, 2.5 * dt);
      d.pos += d.vel * dt;
    }
    if (_t >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    // Flash + expanding shock ring.
    final k = (_t / 0.35).clamp(0.0, 1.0);
    if (k < 1) {
      canvas.drawCircle(
        center,
        0.4 + k * 1.4,
        Paint()
          ..color = const Color(0xFFFFE8B0).withValues(alpha: (1 - k) * 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.3),
      );
      canvas.drawCircle(
        center,
        0.3 + k * (ringRadius - 0.3),
        Paint()
          ..color = accent.withValues(alpha: (1 - k) * 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.08,
      );
    }
    final paint = Paint();
    for (final d in _debris) {
      final a = (1 - _t / d.life).clamp(0.0, 1.0);
      if (a <= 0) continue;
      paint.color = d.hot
          ? Color.lerp(
              const Color(0xFFFFD166),
              const Color(0xFFFF4D1A),
              1 - a,
            )!.withValues(alpha: a)
          : const Color(0xFF9AA5B1).withValues(alpha: a);
      canvas.drawCircle(d.pos, d.size * (d.hot ? a : 1), paint);
    }
  }
}

/// Mining laser beam (world space): drawn while [active], from [from] to
/// [to] (where it meets rock or machinery), with sparks at the cut.
class MiningLaserBeam extends Component {
  MiningLaserBeam({required this.color}) : super(priority: 1060);

  final Color color;
  bool active = false;
  bool hitting = false;
  Offset from = Offset.zero;
  Offset to = Offset.zero;
  final math.Random _rng = math.Random(7);
  double _t = 0;

  @override
  void update(double dt) => _t += dt;

  @override
  void render(Canvas canvas) {
    if (!active) return;
    final flicker = 0.8 + 0.2 * math.sin(_t * 70);
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = color.withValues(alpha: 0.35 * flicker)
        ..strokeWidth = 0.22
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.08),
    );
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 0.05
        ..strokeCap = StrokeCap.round,
    );
    if (!hitting) return;
    canvas.drawCircle(
      to,
      0.18 + 0.06 * math.sin(_t * 50),
      Paint()
        ..color = const Color(0xFFFFE8B0).withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.08),
    );
    final spark = Paint()
      ..color = const Color(0xFFFFB347)
      ..strokeWidth = 0.03
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final l = 0.15 + _rng.nextDouble() * 0.35;
      canvas.drawLine(to, to + Offset(math.cos(a), math.sin(a)) * l, spark);
    }
  }
}

class _Debris {
  _Debris({
    required this.pos,
    required this.vel,
    required this.size,
    required this.hot,
    required this.life,
  });

  Offset pos;
  Offset vel;
  final double size;
  final bool hot;
  final double life;
}

/// Delivery celebration in world space (meters): confetti fountaining up
/// from the pad. Removes itself when finished.
class CelebrationBurst extends Component {
  CelebrationBurst({required this.center, required this.accent, int seed = 0})
    : _rng = math.Random(seed),
      super(priority: 1100);

  final Offset center;
  final Color accent;
  final math.Random _rng;

  static const double _life = 1.6;
  double _t = 0;
  late final List<_Confetti> _bits;

  @override
  Future<void> onLoad() async {
    final colors = [
      accent,
      const Color(0xFF4ADE80),
      const Color(0xFFFFD166),
      Colors.white,
    ];
    _bits = List.generate(60, (i) {
      final ang = -math.pi / 2 + (_rng.nextDouble() - 0.5) * 1.6;
      final speed = 3 + _rng.nextDouble() * 4;
      return _Confetti(
        pos: center + Offset((_rng.nextDouble() - 0.5) * 2, 0),
        vel: Offset(math.cos(ang), math.sin(ang)) * speed,
        spin: (_rng.nextDouble() - 0.5) * 14,
        color: colors[i % colors.length],
      );
    });
  }

  @override
  void update(double dt) {
    _t += dt;
    for (final b in _bits) {
      b.vel = b.vel * math.pow(0.35, dt).toDouble() + Offset(0, 4.0 * dt);
      b.pos += b.vel * dt;
      b.angle += b.spin * dt;
    }
    if (_t >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final a = (1 - (_t - _life * 0.6) / (_life * 0.4)).clamp(0.0, 1.0);
    final paint = Paint();
    for (final b in _bits) {
      paint.color = b.color.withValues(alpha: a);
      canvas
        ..save()
        ..translate(b.pos.dx, b.pos.dy)
        ..rotate(b.angle)
        ..drawRect(const Rect.fromLTWH(-0.07, -0.035, 0.14, 0.07), paint)
        ..restore();
    }
  }
}

class _Confetti {
  _Confetti({
    required this.pos,
    required this.vel,
    required this.spin,
    required this.color,
  });

  Offset pos;
  Offset vel;
  double angle = 0;
  final double spin;
  final Color color;
}

/// Combat banner, top-center: the meltdown escape countdown (Thrust's
/// reactor) or how long the turrets stay offline after reactor hits.
class CombatStatusHud extends PositionComponent {
  CombatStatusHud() : super(priority: 4920);

  final _text = HudText();
  final _bang = HudText();

  /// Safe-area insets: the banner sits under the top one.
  EdgeInsets insets = EdgeInsets.zero;

  /// Seconds left to deliver before the reactor blows; null = no meltdown.
  double? meltdownLeft;

  /// Seconds the turrets stay offline; 0 = online.
  double turretsOfflineLeft = 0;

  bool get showing => meltdownLeft != null || turretsOfflineLeft > 0;

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
    final melt = meltdownLeft;
    final String text;
    final Color color;
    if (melt != null) {
      final s = melt.ceil().clamp(0, 999);
      text = 'REACTOR CRITICAL — ESCAPE  ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
      // Blink faster in the last ten seconds.
      final rate = melt < 10 ? 10.0 : 4.0;
      color = Color.lerp(
        const Color(0xFFFF3D00),
        const Color(0xFFFFD180),
        // Snapped so the pulsing label re-lays out ~32 times per beat.
        quantizeAlpha(0.5 + 0.5 * math.sin(_t * rate)),
      )!;
    } else if (turretsOfflineLeft > 0) {
      text = 'TURRETS OFFLINE  ${turretsOfflineLeft.ceil()}s';
      color = const Color(0xFF4FC3F7);
    } else {
      return;
    }
    final tp = _text.layout(
      TextSpan(
        text: text,
        style: hudFont(melt != null ? 14 : 12, color, spacing: 1.4),
      ),
    );
    // A chamfered alert plate under the pause button: hex warning glyph on
    // the left, hazard stripes on both ends.
    final top = 54.0 + insets.top;
    const stripeW = 16.0;
    const glyphW = 22.0;
    final w = tp.width + glyphW + stripeW * 2 + 22;
    final h = tp.height + 12;
    final rect = Rect.fromLTWH((size.x - w) / 2, top, w, h);
    final plate = chamferRect(rect, 8);
    drawGlow(canvas, plate, color, melt != null ? 0.7 : 0.4);
    canvas.drawPath(plate, Paint()..color = HudColors.plateDark);
    canvas.save();
    canvas.clipPath(plate);
    final stripe = Paint()..color = color.withValues(alpha: 0.55);
    for (final x0 in [rect.left, rect.right - stripeW]) {
      for (var x = x0 - h; x < x0 + stripeW; x += 7) {
        canvas.drawPath(
          Path()
            ..moveTo(x, rect.bottom)
            ..lineTo(x + 3.5, rect.bottom)
            ..lineTo(x + 3.5 + h, rect.top)
            ..lineTo(x + h, rect.top)
            ..close(),
          stripe,
        );
      }
    }
    canvas.restore();
    // Keep the stripes out of the text area.
    canvas.drawRect(
      Rect.fromLTRB(rect.left + stripeW, rect.top + 1, rect.right - stripeW, rect.bottom - 1),
      Paint()..color = HudColors.plateDark,
    );
    drawStroke(canvas, plate, color.withValues(alpha: 0.85), 1.4);
    final gc = Offset(rect.left + stripeW + 6 + glyphW / 2 - 4, rect.center.dy);
    final hex = hexPath(gc, 8);
    drawStroke(canvas, hex, color, 1.5);
    final bang = _bang.layout(TextSpan(text: '!', style: hudFont(10, color, spacing: 0)));
    bang.paint(canvas, gc - Offset(bang.width / 2, bang.height / 2));
    tp.paint(canvas, Offset(gc.dx + glyphW / 2 + 4, rect.top + 6));
  }
}
