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
import 'package:narrow_haul/game/overlay_ids.dart';

part 'level_select/world_tabs.dart';
part 'level_select/map_node.dart';

/// 'levelSelect' overlay: a horizontally scrolling star chart, one route per
/// world, missions as hexagonal beacons.
class LevelSelectOverlay extends StatelessWidget {
  const LevelSelectOverlay({super.key, required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final total = LevelRegistry.careerLevels;
    return SpaceScreen(
      title: 'Missions',
      onBack: () => game.closeScreen(OverlayIds.levelSelect),
      trailing: [
        HoloChip(
          leading: const StarIcon(filled: true, size: 13),
          label: '${LevelRegistry.totalStars()}/${total * 3}',
          color: SpaceColors.gold,
        ),
      ],
      child: _WorldMap(game: game),
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
  static const _nodeSpacing = 150.0;
  static const _headerW = 140.0;

  final _scroll = ScrollController();
  bool _scrolled = false;

  /// Left edge of each world's header on the map.
  late final List<double> _headerXs = _layoutHeaderXs();

  /// The world under the middle of the screen (its tab is lit).
  late int _activeWorld = LevelRegistry.worlds.indexOf(
    LevelRegistry.worldOf(LevelRegistry.nextLevelIndex()).$1,
  );

  /// Set while a tab tap scrolls the map, so the tabs don't flicker
  /// through every world on the way.
  bool _jumping = false;

  NarrowHaulGame get game => widget.game;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static List<double> _layoutHeaderXs() {
    final xs = <double>[];
    double x = 30;
    for (final world in LevelRegistry.worlds) {
      xs.add(x);
      x += _headerW + world.levels.length * _nodeSpacing;
    }
    return xs;
  }

  void _onScroll() {
    if (_jumping || !_scroll.hasClients) return;
    final p = _scroll.position;
    final centre = p.pixels + p.viewportDimension / 2;
    var wi = 0;
    for (var i = 0; i < _headerXs.length; i++) {
      if (_headerXs[i] <= centre) wi = i;
    }
    if (wi != _activeWorld) setState(() => _activeWorld = wi);
  }

  /// Scrolls the map so world [wi]'s header sits at the left edge.
  Future<void> _jumpToWorld(int wi) async {
    if (!_scroll.hasClients) return;
    setState(() => _activeWorld = wi);
    _jumping = true;
    try {
      await _scroll.animateTo(
        (_headerXs[wi] - 16).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _jumping = false;
    }
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

    final map = LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;

        // Layout: [world header][node node ...][world header][...]
        final worldPaths = <List<Offset>>[];
        final headerXs = _headerXs;
        final nodePositions = <Offset>[];
        double x = 30;
        int flat = 0;
        for (final world in LevelRegistry.worlds) {
          x += _headerW;
          final points = <Offset>[];
          for (int i = 0; i < world.levels.length; i++) {
            final y = (h / 2) + (h * 0.26) * math.sin(flat * 1.3) - 6;
            points.add(Offset(x + 45, y));
            nodePositions.add(Offset(x + 45, y));
            x += _nodeSpacing;
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
                        // A paid Expedition opens its briefing, which offers
                        // the Full Game.
                        fullGame: LevelRegistry.offersFullGame(i),
                        stars: progress.getStarsById(flatDefs[i].saveId),
                        bestTime: progress.getBestTimeById(flatDefs[i].saveId),
                        flawless: progress.isFlawless(flatDefs[i].saveId),
                        isNext: i == next,
                        onTap: () => game.openBriefing(i),
                      ),
                    ),
                  ),
                for (int i = 0; i < flatDefs.length; i++)
                  if (LevelRegistry.isLevelUnlocked(i) || LevelRegistry.offersFullGame(i))
                    Positioned(
                      left: nodePositions[i].dx - 70,
                      top: nodePositions[i].dy + 47,
                      width: 140,
                      child: IgnorePointer(
                        child: MarqueeText(
                          flatDefs[i].name,
                          textAlign: TextAlign.center,
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

    return Column(
      children: [
        Expanded(child: map),
        _WorldTabs(
          active: _activeWorld,
          totalStars: totalStars,
          onSelect: _jumpToWorld,
        ),
      ],
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
