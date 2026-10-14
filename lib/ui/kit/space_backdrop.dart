import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'holo_buttons.dart';
import 'marquee_text.dart';
import 'tokens.dart';


class _Star {
  const _Star(this.x, this.y, this.r, this.layer, this.phase, this.tint);
  final double x, y, r;
  final int layer;
  final double phase;
  final Color tint;
}

final List<_Star> _stars = () {
  final rnd = math.Random(7);
  const tints = [Colors.white, Color(0xFFBDE9FF), Color(0xFFFFE7B8)];
  return [
    for (var i = 0; i < 160; i++)
      _Star(
        rnd.nextDouble(),
        rnd.nextDouble(),
        0.5 + rnd.nextDouble() * (i % 3 == 0 ? 1.4 : 0.8),
        i % 3,
        rnd.nextDouble() * math.pi * 2,
        tints[rnd.nextInt(tints.length)],
      ),
  ];
}();

/// Drifting three-layer parallax starfield over a deep-space nebula. Runs on
/// its own ticker, so it moves while the game engine is paused behind it.
class SpaceBackdrop extends StatefulWidget {
  const SpaceBackdrop({super.key, this.nebula = SpaceColors.cyan});

  /// Tint of the main nebula glow.
  final Color nebula;

  @override
  State<SpaceBackdrop> createState() => _SpaceBackdropState();
}

class _SpaceBackdropState extends State<SpaceBackdrop>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  final _time = ValueNotifier<double>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = spaceAnimationsOn(context);
    if (animate && _ticker == null) {
      _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)
        ..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _SpacePainter(_time, widget.nebula),
        size: Size.infinite,
      ),
    );
  }
}

class _SpacePainter extends CustomPainter {
  _SpacePainter(this.time, this.nebula) : super(repaint: time);
  final ValueListenable<double> time;
  final Color nebula;

  static const _speeds = [4.0, 9.0, 18.0]; // px/s per layer

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF070B1F), SpaceColors.bg, Color(0xFF03050D)],
        ).createShader(r),
    );
    // Nebula clouds breathing slowly.
    void cloud(Offset c, double radius, Color color, double alpha) {
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: radius)),
      );
    }

    final breathe = 0.85 + 0.15 * math.sin(t * 0.3);
    cloud(
      Offset(size.width * 0.78, size.height * 0.25),
      size.height * 0.9,
      nebula,
      0.13 * breathe,
    );
    cloud(
      Offset(size.width * 0.12, size.height * 0.95),
      size.height * 0.75,
      SpaceColors.violet,
      0.10 * (2 - breathe),
    );
    cloud(
      Offset(size.width * 0.45, size.height * 0.05),
      size.height * 0.5,
      const Color(0xFFE07A5F),
      0.04,
    );

    final paint = Paint();
    for (final s in _stars) {
      final w = size.width + 20;
      final x = (s.x * w - t * _speeds[s.layer]) % w - 10;
      final y = s.y * size.height;
      final twinkle = 0.55 + 0.45 * math.sin(t * (1.2 + s.layer) + s.phase);
      final a = (0.18 + 0.27 * s.layer) * twinkle;
      paint.color = s.tint.withValues(alpha: a.clamp(0, 1));
      canvas.drawCircle(Offset(x, y), s.r * (0.8 + 0.25 * s.layer), paint);
    }
  }

  @override
  bool shouldRepaint(_SpacePainter old) => old.nebula != nebula;
}

/// Full-screen cockpit screen: starfield, header bar (back button, title,
/// trailing chips) and a body.
class SpaceScreen extends StatelessWidget {
  const SpaceScreen({
    super.key,
    required this.title,
    required this.onBack,
    required this.child,
    this.accent = SpaceColors.cyan,
    this.trailing = const [],
    this.backLabel = 'Hangar',
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;
  final Color accent;
  final List<Widget> trailing;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: SpaceBackdrop(nebula: accent)),
        Positioned.fill(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: Row(
                    children: [
                      HoloBackButton(onPressed: onBack, label: backLabel),
                      const SizedBox(width: 14),
                      Flexible(
                        child: MarqueeText(
                          title.toUpperCase(),
                          style: hudLabel(18, color: accent, spacing: 3.5)
                              .copyWith(
                                shadows: [
                                  Shadow(
                                    color: accent.withValues(alpha: 0.6),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                        ),
                      ),
                      const Spacer(),
                      for (final w in trailing) ...[
                        const SizedBox(width: 8),
                        w,
                      ],
                    ],
                  ),
                ),
                _HeaderRule(color: accent),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderRule extends StatelessWidget {
  const _HeaderRule({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.6),
          color.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared bits
// ─────────────────────────────────────────────────────────────────────────────
