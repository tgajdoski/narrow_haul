import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';

/// Cheap world-space atmosphere: snow, embers, spores or dust drifting through
/// the level. Rendered below the rock, so particles only appear in open cave.
/// Purely cosmetic and deliberately sparse/faint so it never reads as hazard.
class AmbientParticles extends Component {
  AmbientParticles({required this.kind, required this.worldSize, int seed = 0})
    : _rng = math.Random(seed),
      super(priority: -1800);

  final AmbientKind kind;
  final Vector2 worldSize;
  final math.Random _rng;

  late final List<_Mote> _motes;
  late final Paint _paint;
  double _time = 0;

  @override
  Future<void> onLoad() async {
    final count = (worldSize.x * worldSize.y / 5).clamp(40, 260).round();
    _motes = List.generate(count, (_) => _spawn(randomY: true));
    final color = switch (kind) {
      AmbientKind.snow => const Color(0xFFE6F7FF),
      AmbientKind.embers => const Color(0xFFFF9A3D),
      AmbientKind.spores => const Color(0xFF7EF9D2),
      AmbientKind.dust => const Color(0xFFE0C9A0),
      AmbientKind.none => Colors.transparent,
    };
    _paint = Paint()..color = color;
  }

  _Mote _spawn({required bool randomY}) {
    final (vy, size) = switch (kind) {
      AmbientKind.snow => (0.25 + _rng.nextDouble() * 0.35, 0.03 + _rng.nextDouble() * 0.04),
      AmbientKind.embers => (-(0.3 + _rng.nextDouble() * 0.6), 0.02 + _rng.nextDouble() * 0.035),
      AmbientKind.spores => (-(0.03 + _rng.nextDouble() * 0.08), 0.03 + _rng.nextDouble() * 0.04),
      _ => (0.02 + _rng.nextDouble() * 0.05, 0.015 + _rng.nextDouble() * 0.025),
    };
    final y = randomY
        ? _rng.nextDouble() * worldSize.y
        : (vy > 0 ? -0.2 : worldSize.y + 0.2);
    return _Mote(
      x: _rng.nextDouble() * worldSize.x,
      y: y,
      vy: vy,
      size: size,
      phase: _rng.nextDouble() * math.pi * 2,
      alpha: 0.25 + _rng.nextDouble() * 0.45,
    );
  }

  @override
  void update(double dt) {
    if (kind == AmbientKind.none) return;
    _time += dt;
    final sway = kind == AmbientKind.snow ? 0.35 : 0.18;
    for (int i = 0; i < _motes.length; i++) {
      final m = _motes[i];
      m.y += m.vy * dt;
      m.x += math.sin(_time * 0.8 + m.phase) * sway * dt;
      if (m.y < -0.5 || m.y > worldSize.y + 0.5) _motes[i] = _spawn(randomY: false);
    }
  }

  @override
  void render(Canvas canvas) {
    if (kind == AmbientKind.none) return;
    final base = _paint.color;
    final flicker = kind == AmbientKind.embers || kind == AmbientKind.spores;
    for (final m in _motes) {
      var a = m.alpha;
      if (flicker) a *= 0.6 + 0.4 * math.sin(_time * 3 + m.phase * 5);
      _paint.color = base.withValues(alpha: a.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(m.x, m.y), m.size, _paint);
    }
    _paint.color = base;
  }
}

class _Mote {
  _Mote({
    required this.x,
    required this.y,
    required this.vy,
    required this.size,
    required this.phase,
    required this.alpha,
  });

  double x;
  double y;
  final double vy;
  final double size;
  final double phase;
  final double alpha;
}
