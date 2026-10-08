import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/ui/career_widgets.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// 'levelSelect' overlay: a horizontally scrolling star chart, one route per
/// world, missions as hexagonal beacons.
class LevelSelectOverlay extends StatelessWidget {
  const LevelSelectOverlay({super.key, required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final total = LevelRegistry.totalLevels;
    return SpaceScreen(
      title: 'Missions',
      onBack: () => game.closeScreen('levelSelect'),
      trailing: [
        HoloChip(
          leading: const StarIcon(filled: true, size: 13),
          label: '${LevelRegistry.totalStars()}/${total * 3}',
          color: SpaceColors.gold,
        ),
      ],
      child: Column(
        children: [
          Expanded(child: _WorldMap(game: game)),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              '▼ heavy gravity   ▲ light gravity   ⛽ fast fuel burn   '
              '⚓ heavy cargo   ❄ icy walls   ✛ turrets   ☢ reactor',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldMap extends StatefulWidget {
  const _WorldMap({required this.game});
  final NarrowHaulGame game;

  @override
  State<_WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<_WorldMap> {
  final _scroll = ScrollController();
  bool _scrolled = false;

  NarrowHaulGame get game => widget.game;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Centers the map on [x] once, right after the first layout.
  void _scrollToOnce(double x, double viewportW) {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = (x - viewportW / 2).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.instance;
    final totalStars = LevelRegistry.totalStars();

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        const nodeSpacing = 150.0;
        const headerW = 140.0;

        // Layout: [world header][node node ...][world header][...]
        final worldPaths = <List<Offset>>[];
        final headerXs = <double>[];
        final nodePositions = <Offset>[];
        double x = 30;
        int flat = 0;
        for (final world in LevelRegistry.worlds) {
          headerXs.add(x);
          x += headerW;
          final points = <Offset>[];
          for (int i = 0; i < world.levels.length; i++) {
            final y = (h / 2) + (h * 0.26) * math.sin(flat * 1.3) - 6;
            points.add(Offset(x + 45, y));
            nodePositions.add(Offset(x + 45, y));
            x += nodeSpacing;
            flat++;
          }
          worldPaths.add(points);
        }
        final w = x + 60;

        final flatDefs = LevelRegistry.flat;
        final next = LevelRegistry.nextLevelIndex();
        _scrollToOnce(nodePositions[next].dx, constraints.maxWidth);

        return SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: Size(w, h),
                  painter: _MapPathPainter(
                    worldPaths: worldPaths,
                    colors: [
                      for (final world in LevelRegistry.worlds)
                        (gameThemes[world.themeId] ?? tutorialTheme).uiAccent,
                    ],
                  ),
                ),
                for (int wi = 0; wi < LevelRegistry.worlds.length; wi++)
                  Positioned(
                    left: headerXs[wi],
                    top: 0,
                    bottom: 0,
                    child: _WorldHeader(
                      world: LevelRegistry.worlds[wi],
                      unlocked:
                          totalStars >= LevelRegistry.worlds[wi].starsRequired,
                      totalStars: totalStars,
                    ),
                  ),
                for (int i = 0; i < flatDefs.length; i++)
                  Positioned(
                    left: nodePositions[i].dx - 45,
                    top: nodePositions[i].dy - 45,
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: _MapNode(
                        def: flatDefs[i],
                        label: '${LevelRegistry.worldOf(i).$2 + 1}',
                        unlocked: LevelRegistry.isLevelUnlocked(i),
                        stars: progress.getStarsById(flatDefs[i].saveId),
                        bestTime: progress.getBestTimeById(flatDefs[i].saveId),
                        isNext: i == next,
                        onTap: () => game.startLevel(i),
                      ),
                    ),
                  ),
                for (int i = 0; i < flatDefs.length; i++)
                  if (LevelRegistry.isLevelUnlocked(i))
                    Positioned(
                      left: nodePositions[i].dx - 70,
                      top: nodePositions[i].dy + 47,
                      width: 140,
                      child: IgnorePointer(
                        child: Text(
                          flatDefs[i].name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: i == next ? Colors.white : Colors.white54,
                            fontSize: 11,
                            fontWeight: i == next
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WorldHeader extends StatelessWidget {
  const _WorldHeader({
    required this.world,
    required this.unlocked,
    required this.totalStars,
  });

  final WorldDef world;
  final bool unlocked;
  final int totalStars;

  @override
  Widget build(BuildContext context) {
    final accent = (gameThemes[world.themeId] ?? tutorialTheme).uiAccent;
    return SizedBox(
      width: 126,
      child: Center(
        child: HoloPanel(
          accent: unlocked ? accent : Colors.white24,
          glow: unlocked ? 0.6 : 0,
          cut: 12,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                world.name.toUpperCase(),
                textAlign: TextAlign.center,
                style: hudLabel(
                  12,
                  color: unlocked ? accent : Colors.white30,
                  spacing: 1.4,
                ),
              ),
              const SizedBox(height: 5),
              if (unlocked) ...[
                Text(
                  '${world.levels.length} missions',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.rocket_rounded,
                      size: 11,
                      color: accent.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        shipById(world.defaultShipId).name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accent.withValues(alpha: 0.9),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const Icon(Icons.lock_outline, size: 16, color: Colors.white30),
                const SizedBox(height: 2),
                Text(
                  '$totalStars / ${world.starsRequired} ★',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed glowing flight route through a world's missions.
class _MapPathPainter extends CustomPainter {
  _MapPathPainter({required this.worldPaths, required this.colors});
  final List<List<Offset>> worldPaths;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    for (int wi = 0; wi < worldPaths.length; wi++) {
      final points = worldPaths[wi];
      if (points.length < 2) continue;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        final a = points[i - 1];
        final b = points[i];
        final mx = (a.dx + b.dx) / 2;
        path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[wi].withValues(alpha: 0.18)
          ..strokeWidth = 8
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      final dash = Paint()
        ..color = colors[wi].withValues(alpha: 0.6)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (final metric in path.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 14) {
          canvas.drawPath(metric.extractPath(d, d + 7), dash);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_MapPathPainter old) => false;
}

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
  });

  final bool isNext;
  final LevelDef def;
  final String label;
  final bool unlocked;
  final int stars;
  final double? bestTime;
  final VoidCallback onTap;

  @override
  State<_MapNode> createState() => _MapNodeState();
}

class _MapNodeState extends State<_MapNode> with TickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
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
    _shake.dispose();
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
    if (widget.unlocked) {
      AudioService.playUi(UiSound.launch);
      widget.onTap();
    } else {
      AudioService.playUi(UiSound.denied);
      _shake.forward(from: 0);
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
        if (!unlocked)
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
      ),
      child: content,
    );

    final pulse = _pulse;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final t = _shake.value;
          final dx = _shake.isAnimating
              ? math.sin(t * math.pi * 6) * 6 * (1 - t)
              : 0.0;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: Opacity(
          opacity: unlocked ? 1 : 0.55,
          child: pulse == null
              ? hex(0)
              : AnimatedBuilder(
                  animation: pulse,
                  builder: (context, _) => hex(pulse.value),
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
  });

  final Color accent;

  /// 0–1: how strongly the beacon glows.
  final double strength;
  final bool thick;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final hex = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 6 + i * math.pi / 3;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? hex.moveTo(p.dx, p.dy) : hex.lineTo(p.dx, p.dy);
    }
    hex.close();
    if (strength > 0) {
      canvas.drawPath(
        hex,
        Paint()
          ..color = accent.withValues(alpha: 0.55 * strength)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = MaskFilter.blur(BlurStyle.outer, 10 * strength),
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
  }

  @override
  bool shouldRepaint(_HexPainter o) =>
      o.accent != accent || o.strength != strength || o.thick != thick;
}
