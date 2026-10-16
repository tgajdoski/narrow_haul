part of '../level_select_overlay.dart';

/// One mission beacon: a hexagon with the number, stars, modifier glyphs
/// and best time. Locked beacons shake and buzz when tapped.
class _MapNode extends StatefulWidget {
  const _MapNode({
    required this.def,
    required this.label,
    required this.unlocked,
    required this.stars,
    required this.bestTime,
    required this.onTap,
    this.isNext = false,
    this.fullGame = false,
    this.flawless = false,
  });

  final bool isNext;

  /// Delivered flawless (3★, no scrape): a gold outer ring.
  final bool flawless;

  /// Part of the Full Game, not owned: a gold lock that opens the briefing.
  final bool fullGame;
  final LevelDef def;
  final String label;
  final bool unlocked;
  final int stars;
  final double? bestTime;
  final VoidCallback onTap;

  @override
  State<_MapNode> createState() => _MapNodeState();
}

class _MapNodeState extends State<_MapNode>
    with TickerProviderStateMixin, DeniedShake {
  AnimationController? _pulse;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.isNext && _pulse == null && spaceAnimationsOn(context)) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  /// Compact glyphs for the level's physics modifiers.
  String get _badges {
    final m = widget.def.modifiers;
    final b = StringBuffer();
    if (m.gravityMul > 1) b.write('▼');
    if (m.gravityMul < 1) b.write('▲');
    if (m.fuelDrainMul > 1) b.write('⛽');
    if (m.cargoDensityMul > 1) b.write('⚓');
    if (m.wallFriction != null) b.write('❄');
    final d = widget.def;
    if (d is CaveLevelDef) {
      if (d.spec.obstacles.any((o) => o is TurretSpec)) b.write('✛');
      if (d.spec.obstacles.any((o) => o is ReactorSpec)) b.write('☢');
    }
    return b.toString();
  }

  void _tap() {
    if (widget.unlocked || widget.fullGame) {
      widget.onTap();
    } else {
      deny();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = (gameThemes[widget.def.themeId] ?? tutorialTheme).uiAccent;
    final unlocked = widget.unlocked;
    final stars = widget.stars;
    final badges = _badges;

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!unlocked && widget.fullGame) ...[
          const Icon(Icons.lock_outline, size: 20, color: SpaceColors.gold),
          const SizedBox(height: 2),
          Text('FULL GAME', style: hudLabel(8, color: SpaceColors.gold, spacing: 1)),
        ] else if (!unlocked)
          const Icon(Icons.lock_outline, size: 22, color: Colors.white30)
        else ...[
          Text(widget.label, style: hudLabel(19, color: accent, spacing: 0)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              3,
              (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: StarIcon(filled: i < stars, size: 9),
              ),
            ),
          ),
          if (badges.isNotEmpty)
            Text(
              badges,
              style: TextStyle(
                color: accent.withValues(alpha: 0.8),
                fontSize: 9,
              ),
            ),
          if (widget.bestTime case final t?)
            Text(
              formatFlightTime(t),
              style: const TextStyle(color: Colors.white38, fontSize: 9),
            ),
        ],
      ],
    );

    Widget hex(double pulse) => CustomPaint(
      painter: _HexPainter(
        accent: unlocked ? accent : Colors.white24,
        strength: !unlocked
            ? 0
            : widget.isNext
            ? 0.7 + 0.3 * pulse
            : stars > 0
            ? 0.45
            : 0.2,
        thick: stars == 3 || widget.isNext,
        flawless: unlocked && widget.flawless,
      ),
      child: content,
    );

    final pulse = _pulse;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      child: shaking(
        Opacity(
          opacity: unlocked ? 1 : 0.55,
          child: pulse == null
              ? hex(0)
              // Own layer, so the pulse doesn't repaint the whole map.
              : RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: pulse,
                    builder: (context, _) => hex(pulse.value),
                  ),
                ),
        ),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  _HexPainter({
    required this.accent,
    required this.strength,
    required this.thick,
    this.flawless = false,
  });

  final Color accent;
  final bool flawless;

  /// 0–1: how strongly the beacon glows.
  final double strength;
  final bool thick;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final hex = hexPath(c, r);
    if (strength > 0) {
      canvas.drawPath(
        hex,
        GlowPaint.of(accent.withValues(alpha: 0.55 * strength), 8, 10 * strength),
      );
    }
    canvas.drawPath(
      hex,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.alphaBlend(
              accent.withValues(alpha: 0.18 * (0.4 + strength)),
              SpaceColors.panel,
            ),
            const Color(0xF0081222),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawPath(
      hex,
      Paint()
        ..color = accent.withValues(alpha: 0.35 + 0.65 * strength)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick ? 2.6 : 1.6,
    );
    // Inner ring of ticks.
    final tick = Paint()
      ..color = accent.withValues(alpha: 0.25 + 0.4 * strength)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r * 0.78), c + dir * (r * 0.86), tick);
    }
    if (flawless) {
      canvas.drawPath(
        hexPath(c, r + 3),
        Paint()
          ..color = SpaceColors.gold.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(_HexPainter o) =>
      o.accent != accent ||
      o.strength != strength ||
      o.thick != thick ||
      o.flawless != flawless;
}
