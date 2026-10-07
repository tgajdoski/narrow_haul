import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
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
    canvas.drawCircle(c, _size / 2, Paint()..color = const Color(0x661B263B));
    canvas.drawCircle(
      c,
      _size / 2,
      Paint()
        ..color = const Color(0x8800B4D8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final bar = Paint()..color = const Color(0xDDFFFFFF);
    for (final dx in [-5.0, 5.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c + Offset(dx, 0), width: 4.5, height: 15),
          const Radius.circular(1.5),
        ),
        bar,
      );
    }
  }
}

/// World + level name card that fades in and out at level start.
class LevelIntroHud extends PositionComponent {
  LevelIntroHud() : super(priority: 4920);

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

    final sub = TextPainter(
      text: TextSpan(
        text: _subtitle.toUpperCase(),
        style: TextStyle(
          color: _accent.withValues(alpha: a * 0.9),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final title = TextPainter(
      text: TextSpan(
        text: _title,
        style: TextStyle(
          color: Colors.white.withValues(alpha: a),
          fontFamily: kDisplayFont,
          fontSize: 30,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: a * 0.7),
              blurRadius: 8,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

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
      final note = TextPainter(
        text: TextSpan(
          text: _note,
          style: TextStyle(
            color: Colors.white.withValues(alpha: a * 0.75),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      note.paint(canvas, Offset((size.x - note.width) / 2, lineY + 8));
    }
  }
}

/// Crash explosion in world space (meters): a flash, a shock ring and hull
/// debris under gravity. Removes itself when finished.
class ExplosionBurst extends Component {
  ExplosionBurst({required this.center, required this.accent, int seed = 0})
    : _rng = math.Random(seed),
      super(priority: 1100);

  final Offset center;
  final Color accent;
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
        0.3 + k * 2.4,
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

/// Short contextual hint pill (tutorial steps, landing status). Set [message]
/// every frame; changes cross-fade, null fades out.
class HintHud extends PositionComponent {
  HintHud() : super(priority: 4910);

  String? message;
  String _shown = '';
  double _alpha = 0;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final target = message;
    if (target != null && target == _shown) {
      _alpha = math.min(1, _alpha + dt * 4);
    } else {
      // Fade out the old text before swapping in the new one.
      _alpha = math.max(0, _alpha - dt * 5);
      if (_alpha == 0 && target != null) _shown = target;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_alpha <= 0 || _shown.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: _shown,
        style: TextStyle(
          color: Colors.white.withValues(alpha: _alpha),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.min(420, size.x - 280));
    final w = tp.width + 32;
    final h = tp.height + 16;
    // Top-center below the HUD text lines, clear of both thumbs.
    const top = 92.0;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH((size.x - w) / 2, top, w, h),
      Radius.circular(h / 2),
    );
    canvas.drawRRect(
      r,
      Paint()..color = const Color(0xCC0D1B2A).withValues(alpha: 0.8 * _alpha),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = const Color(0xFF4ADE80).withValues(alpha: 0.6 * _alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    tp.paint(canvas, Offset((size.x - tp.width) / 2, top + 8));
  }
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
