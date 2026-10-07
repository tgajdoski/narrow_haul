import 'dart:math' as math;

import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/game/components/rank_insignia.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/contracts_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/ui/fonts.dart';
import 'package:narrow_haul/ui/pause_settings_overlays.dart';
import 'package:narrow_haul/ui/route_guide_overlays.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Point the global Flame image cache at assets/ (not the default assets/images/).
  Flame.images.prefix = 'assets/';
  await ProgressService.init();
  await CareerService.migrateIfNeeded();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final game = NarrowHaulGame();
  runApp(_NarrowHaulApp(game: game));
  // After runApp: the UMP consent form needs a live UI. Never blocks play.
  MonetizationService.instance.init();
}

/// Dark theme; display/headline/title styles use the bundled RussoOne face
/// (titles only — body text stays on the platform font for legibility).
ThemeData _theme() {
  final base = ThemeData.dark().copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF00B4D8),
      brightness: Brightness.dark,
    ),
  );
  TextStyle? display(TextStyle? s) => s?.copyWith(fontFamily: kDisplayFont);
  final t = base.textTheme;
  return base.copyWith(
    textTheme: t.copyWith(
      displayLarge: display(t.displayLarge),
      displayMedium: display(t.displayMedium),
      displaySmall: display(t.displaySmall),
      headlineLarge: display(t.headlineLarge),
      headlineMedium: display(t.headlineMedium),
      headlineSmall: display(t.headlineSmall),
      titleLarge: display(t.titleLarge),
      titleMedium: display(t.titleMedium),
    ),
  );
}

class _NarrowHaulApp extends StatelessWidget {
  const _NarrowHaulApp({required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: Scaffold(
        backgroundColor: const Color(0xFF050816),
        body: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: GameWidget(
                  game: game,
                  overlayBuilderMap: {
                    'menu': (context, game) {
                      final g = game as NarrowHaulGame;
                      return _MenuOverlay(game: g);
                    },
                    'levelSelect': (context, game) {
                      final g = game as NarrowHaulGame;
                      return _LevelSelectOverlay(game: g);
                    },
                    'achievements': (context, game) {
                      return const _AchievementsOverlay();
                    },
                    'cosmetics': (context, game) {
                      return const _CosmeticsOverlay();
                    },
                    'gameOver': (context, game) {
                      final g = game as NarrowHaulGame;
                      return _EndOverlay(
                        title: 'Hull Breach',
                        subtitle: 'The ship touched the terrain.',
                        primaryLabel: 'Retry',
                        onPrimary: g.restartLevel,
                        secondaryLabel: 'Menu',
                        onSecondary: g.backToMenu,
                        extra: g.canContinue || g.canShowRoute
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (g.canContinue)
                                    _RewardedButton(
                                      label: 'Continue from before the crash',
                                      note: 'Watch an ad · this run can earn up to 2★',
                                      icon: Icons.play_circle_outline_rounded,
                                      placement: AdPlacement.continueAfterCrash,
                                      onReward: g.continueAfterCrash,
                                    ),
                                  if (g.canContinue && g.canShowRoute)
                                    const SizedBox(height: 12),
                                  RouteHelpButtons(game: g),
                                ],
                              )
                            : null,
                      );
                    },
                    'demo': (context, game) {
                      return DemoFlightOverlay(game: game as NarrowHaulGame);
                    },
                    'levelComplete': (context, game) {
                      final g = game as NarrowHaulGame;
                      return _LevelCompleteOverlay(game: g);
                    },
                    'rankUp': (context, game) {
                      final g = game as NarrowHaulGame;
                      return _RankUpOverlay(game: g);
                    },
                    'pause': (context, game) {
                      return PauseOverlay(game: game as NarrowHaulGame);
                    },
                    'settings': (context, game) {
                      return SettingsOverlay(game: game as NarrowHaulGame);
                    },
                    'pilotProfile': (context, game) {
                      final g = game as NarrowHaulGame;
                      return _PilotLogbookOverlay(game: g);
                    },
                  },
                ),
              ),
              const _AchievementToastHost(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Menu
// ─────────────────────────────────────────────────────────────────────────────

class _MenuOverlay extends StatelessWidget {
  const _MenuOverlay({required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.instance;
    final totalStars = LevelRegistry.totalStars();
    final maxStars = LevelRegistry.totalLevels * 3;
    final challengeComplete = progress.isDailyChallengeComplete();
    final dailyBestTime = progress.getDailyBestTime();
    final dailyStreak = progress.getDailyStreak();

    return ColoredBox(
      color: const Color(0xDD050816),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'NARROW HAUL',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: const Color(0xFF00B4D8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cargo tow · Space physics · Precision landing',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white38,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _RankCard(
                    xp: progress.getXp(),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StarIcon(filled: totalStars > 0, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '$totalStars / $maxStars',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      game.overlays.remove('menu');
                      game.overlays.add('pilotProfile');
                    },
                  ),
                  const SizedBox(height: 20),
                  // Play button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => game.beginPlay(),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF00B4D8),
                      ),
                      child: const Text(
                        'PLAY',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Level select + daily challenge row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            game.overlays.remove('menu');
                            game.overlays.add('levelSelect');
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Color(0x5500B4D8)),
                          ),
                          child: const Text('Missions'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: challengeComplete
                              ? null
                              : () => game.beginChallenge(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            side: BorderSide(
                              color: challengeComplete
                                  ? const Color(0x334ADE80)
                                  : const Color(0x55FFD166),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                (challengeComplete
                                        ? 'Daily ✓'
                                        : 'Daily Challenge') +
                                    (dailyStreak > 0 ? '  🔥$dailyStreak' : ''),
                                style: TextStyle(
                                  color: challengeComplete
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFFFFD166),
                                ),
                              ),
                              if (challengeComplete && dailyBestTime != null)
                                Text(
                                  _formatTime(dailyBestTime),
                                  style: const TextStyle(
                                    color: Color(0xAA4ADE80),
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const _ContractsPanel(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          game.overlays.remove('menu');
                          game.overlays.add('achievements');
                        },
                        child: const Text(
                          'Achievements',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ),
                      const Text('·', style: TextStyle(color: Colors.white24)),
                      TextButton(
                        onPressed: () {
                          game.overlays.remove('menu');
                          game.overlays.add('cosmetics');
                        },
                        child: const Text(
                          'Garage (Skins)',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ),
                      const Text('·', style: TextStyle(color: Colors.white24)),
                      TextButton(
                        onPressed: () {
                          game.overlays.remove('menu');
                          game.overlays.add('settings');
                        },
                        child: const Text(
                          'Settings',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ProgressService.instance.leftHanded
                        ? 'Left side: thrust  ·  Right side: joystick (rotate)'
                        : 'Left side: joystick (rotate)  ·  Right side: thrust',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white24),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(double seconds) {
    if (seconds >= 60) {
      final m = (seconds ~/ 60);
      final s = (seconds % 60).toStringAsFixed(0).padLeft(2, '0');
      return '${m}m${s}s';
    }
    return '${seconds.toStringAsFixed(1)}s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Level Select
// ─────────────────────────────────────────────────────────────────────────────

class _LevelSelectOverlay extends StatelessWidget {
  const _LevelSelectOverlay({required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final total = LevelRegistry.totalLevels;

    return ColoredBox(
      color: const Color(0xEE050816),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      game.overlays.remove('levelSelect');
                      game.overlays.add('menu');
                    },
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'MISSION SELECT',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: const Color(0xFF00B4D8),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${LevelRegistry.totalStars()} / ${total * 3} ★',
                    style: const TextStyle(
                      color: Color(0xFFFFD166),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0x2200B4D8), height: 1),
            Expanded(child: _WorldMap(game: game)),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '▼ heavy gravity   ▲ light gravity   ⛽ fast fuel burn   '
                '⚓ heavy cargo   ❄ icy walls   ✛ turrets   ☢ reactor',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
        ),
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

  /// First unlocked level without a star, else the last unlocked one.
  static int nextLevelIndex() {
    int lastUnlocked = 0;
    for (int i = 0; i < LevelRegistry.totalLevels; i++) {
      if (!LevelRegistry.isLevelUnlocked(i)) continue;
      lastUnlocked = i;
      final def = LevelRegistry.defAt(i);
      if (ProgressService.instance.getStarsById(def.saveId) == 0) return i;
    }
    return lastUnlocked;
  }

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
      final target = (x - viewportW / 2).clamp(0.0, _scroll.position.maxScrollExtent);
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
        const headerW = 130.0;

        // Layout: [world header][node node ...][world header][...]
        final worldPaths = <List<Offset>>[];
        final headerXs = <double>[];
        final nodePositions = <Offset>[];
        double x = 40;
        int flat = 0;
        for (final world in LevelRegistry.worlds) {
          headerXs.add(x);
          x += headerW;
          final points = <Offset>[];
          for (int i = 0; i < world.levels.length; i++) {
            final y = (h / 2) + (h * 0.28) * math.sin(flat * 1.3);
            points.add(Offset(x + 45, y));
            nodePositions.add(Offset(x + 45, y));
            x += nodeSpacing;
            flat++;
          }
          worldPaths.add(points);
        }
        final w = x + 60;

        final flatDefs = LevelRegistry.flat;
        final next = nextLevelIndex();
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
                        onTap: LevelRegistry.isLevelUnlocked(i)
                            ? () => game.startLevel(i)
                            : null,
                      ),
                    ),
                  ),
                for (int i = 0; i < flatDefs.length; i++)
                  if (LevelRegistry.isLevelUnlocked(i))
                    Positioned(
                      left: nodePositions[i].dx - 70,
                      top: nodePositions[i].dy + 49,
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
                            fontWeight: i == next ? FontWeight.w700 : FontWeight.w500,
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
      width: 120,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1B2A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: unlocked
                    ? accent.withValues(alpha: 0.6)
                    : const Color(0x331B263B),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  world.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: unlocked ? accent : Colors.white24,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                if (unlocked) ...[
                  Text(
                    '${world.levels.length} missions',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  Text(
                    '✈ ${shipById(world.defaultShipId).name}',
                    style: TextStyle(
                      color: accent.withValues(alpha: 0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else ...[
                  const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: Colors.white24,
                  ),
                  Text(
                    '$totalStars / ${world.starsRequired} ★',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPathPainter extends CustomPainter {
  _MapPathPainter({required this.worldPaths, required this.colors});
  final List<List<Offset>> worldPaths;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    for (int wi = 0; wi < worldPaths.length; wi++) {
      final points = worldPaths[wi];
      if (points.isEmpty) continue;
      final paint = Paint()
        ..color = colors[wi].withValues(alpha: 0.35)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path();
      path.moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_MapPathPainter old) => false;
}

class _MapNode extends StatelessWidget {
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
  final VoidCallback? onTap;

  /// Compact glyphs for the level's physics modifiers.
  String get _badges {
    final m = def.modifiers;
    final b = StringBuffer();
    if (m.gravityMul > 1) b.write('▼');
    if (m.gravityMul < 1) b.write('▲');
    if (m.fuelDrainMul > 1) b.write('⛽');
    if (m.cargoDensityMul > 1) b.write('⚓');
    if (m.wallFriction != null) b.write('❄');
    final d = def;
    if (d is CaveLevelDef) {
      if (d.spec.obstacles.any((o) => o is TurretSpec)) b.write('✛');
      if (d.spec.obstacles.any((o) => o is ReactorSpec)) b.write('☢');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final accent = (gameThemes[def.themeId] ?? tutorialTheme).uiAccent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: unlocked ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0D1B2A),
            border: Border.all(
              color: unlocked
                  ? accent.withValues(alpha: isNext ? 1 : (stars > 0 ? 0.8 : 0.3))
                  : const Color(0x331B263B),
              width: stars == 3 || isNext ? 3 : 2,
            ),
            boxShadow: isNext
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.6),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : unlocked && stars > 0
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.25),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!unlocked)
                const Icon(Icons.lock_outline, size: 22, color: Colors.white24)
              else ...[
                Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                    (i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: _StarIcon(filled: i < stars, size: 8),
                    ),
                  ),
                ),
                if (_badges.isNotEmpty)
                  Text(
                    _badges,
                    style: TextStyle(
                      color: accent.withValues(alpha: 0.8),
                      fontSize: 9,
                    ),
                  ),
                if (bestTime != null)
                  Text(
                    _formatTime(bestTime!),
                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(double seconds) {
    if (seconds >= 60) {
      final m = (seconds ~/ 60);
      final s = (seconds % 60).toStringAsFixed(0).padLeft(2, '0');
      return '${m}m${s}s';
    }
    return '${seconds.toStringAsFixed(1)}s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Achievements
// ─────────────────────────────────────────────────────────────────────────────

class _AchievementsOverlay extends StatelessWidget {
  const _AchievementsOverlay();

  @override
  Widget build(BuildContext context) {
    final unlocked = AchievementService.unlocked;

    return ColoredBox(
      color: const Color(0xEE050816),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      onPressed: () {
                        final game =
                            ctx
                                    .findAncestorWidgetOfExactType<GameWidget>()
                                    ?.game
                                as NarrowHaulGame?;
                        game?.overlays.remove('achievements');
                        game?.overlays.add('menu');
                      },
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ACHIEVEMENTS',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: const Color(0xFFFFD166),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${unlocked.length} / ${AchievementService.all.length}',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0x22FFD166), height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: AchievementService.all.length,
                itemBuilder: (context, i) {
                  final a = AchievementService.all[i];
                  final done = unlocked.contains(a.id);
                  return _AchievementTile(meta: a, unlocked: done);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.meta, required this.unlocked});
  final AchievementMeta meta;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: unlocked ? 1.0 : 0.35,
      duration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: unlocked ? const Color(0x55FFD166) : const Color(0x151B263B),
          ),
        ),
        child: Row(
          children: [
            Text(meta.icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.title,
                    style: TextStyle(
                      color: unlocked
                          ? const Color(0xFFFFD166)
                          : Colors.white54,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    meta.description,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (unlocked)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF4ADE80),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Level Complete
// ─────────────────────────────────────────────────────────────────────────────

class _LevelCompleteOverlay extends StatefulWidget {
  const _LevelCompleteOverlay({required this.game});
  final NarrowHaulGame game;

  @override
  State<_LevelCompleteOverlay> createState() => _LevelCompleteOverlayState();
}

class _LevelCompleteOverlayState extends State<_LevelCompleteOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  /// True while leaving (an interstitial may be showing) — blocks double taps.
  bool _leaving = false;
  late final bool _showRemoveAdsOffer = _shouldOfferRemoveAds();

  /// Soft remove-ads offer: once the tutorial world is done (or after the
  /// first interstitial), at most every 3 days, never to payers.
  bool _shouldOfferRemoveAds() {
    final p = ProgressService.instance;
    final m = MonetizationService.instance;
    if (m.adsRemoved || p.hasPurchased || !m.canBuy(ProductIds.removeAds)) {
      return false;
    }
    final tutorialDone = p.getStarsById('tut_10') > 0;
    if (!tutorialDone && p.lastInterstitialMs == 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - p.removeAdsOfferMs < const Duration(days: 3).inMilliseconds) {
      return false;
    }
    p.setRemoveAdsOfferMs(now);
    return true;
  }

  Future<void> _leave(Future<void> Function() then) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await widget.game.leaveResults(then);
  }

  @override
  void initState() {
    super.initState();
    _anim.forward().whenComplete(() {
      final reward = widget.game.lastRunReward;
      if (mounted && reward != null && reward.rankedUp) {
        widget.game.overlays.add('rankUp');
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final stars = game.lastLevelStars;
    final time = game.lastLevelTimeSeconds;
    final isLastLevel = game.levelIndex >= LevelRegistry.totalLevels - 1;
    final isChallengeMode = game.isChallengeMode;
    final reward = game.lastRunReward;

    final result = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isChallengeMode ? 'Challenge Complete!' : 'Mission Complete',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF4ADE80),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isChallengeMode
              ? game.activeChallengeConfig?.modifierDesc ?? ''
              : '"${game.currentLevelDef.name}" cleared.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 16),
        // Stars pop in one after another (earned ones only).
        AnimatedBuilder(
          animation: _anim,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final start = 0.05 + i * 0.1;
              final t = ((_anim.value - start) / 0.18).clamp(0.0, 1.0);
              final scale = i < stars ? Curves.elasticOut.transform(t) : 1.0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const _StarIcon(filled: false, size: 26),
                    if (i < stars)
                      Transform.scale(
                        scale: scale,
                        child: const _StarIcon(filled: true, size: 26),
                      ),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$stars / 3 stars  ·  ${_formatTime(time)}  ·  '
          '${(game.lastLevelFuelFraction * 100).round()}% fuel left',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        if (_missedStarHint(game, stars, time) case final hint?) ...[
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xCCFFD166), fontSize: 12),
          ),
        ],
        if (game.continuedThisRun) ...[
          const SizedBox(height: 6),
          const Text(
            'Continued flight · max 2★',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
        if (reward != null && reward.currency > 0) ...[
          const SizedBox(height: 8),
          Text(
            '+${reward.currency} 💰',
            style: const TextStyle(
              color: Color(0xFF4ADE80),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
        if (game.canDoubleCurrency) ...[
          const SizedBox(height: 8),
          _RewardedButton(
            label: 'Double coins',
            note: 'Watch an ad',
            icon: Icons.ondemand_video_rounded,
            placement: AdPlacement.doubleCoins,
            onReward: () async {
              await game.doubleRunCurrency();
              if (mounted) setState(() {});
            },
          ),
        ],
        for (final id in CosmeticsService.activeTrials)
          if (CosmeticsService.byId(id) case final item?
              when !CosmeticsService.isUnlocked(item)) ...[
            const SizedBox(height: 8),
            Text(
              'Enjoying the ${item.name}? Own it in the Garage for ${item.cost} 💰',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xCCFFD166), fontSize: 12),
            ),
          ],
        if (_showRemoveAdsOffer) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: () async {
              await MonetizationService.instance.buy(ProductIds.removeAds);
              if (mounted) setState(() {});
            },
            child: Text(
              'Remove ads · ${MonetizationService.instance.priceOf(ProductIds.removeAds)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ],
    );

    final buttons = Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _leaving
                ? null
                : () => _leave(() async => game.backToMenu()),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: Color(0x5500B4D8)),
            ),
            child: const Text('Menu'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _leaving ? null : () => _leave(game.nextLevel),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: const Color(0xFF00B4D8),
            ),
            child: Text(
              isChallengeMode
                  ? 'Done'
                  : isLastLevel
                  ? 'Replay'
                  : 'Next Mission',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );

    return ColoredBox(
      color: const Color(0xCC000000),
      child: _PopupFrame(
        maxWidth: reward == null ? 420 : 640,
        radius: 20,
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
        footer: buttons,
        child: reward == null
            ? result
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Center(child: result)),
                    const VerticalDivider(color: Color(0x22FFFFFF), width: 32),
                    Expanded(
                      child: _XpSummary(reward: reward, anim: _anim),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// What the next star would have taken — the actionable "why".
  String? _missedStarHint(NarrowHaulGame game, int stars, double time) {
    if (stars >= 3) return null;
    final spec = game.currentLevelDef.stars;
    final fuelPct = (game.lastLevelFuelFraction * 100).round();
    if (stars == 2) {
      if (game.lastLevelFuelFraction < spec.star3Fuel) {
        return '★★★ needs ${(spec.star3Fuel * 100).round()}% fuel left (you had $fuelPct%)';
      }
      return '★★★ needs a time under ${spec.star3Time.round()}s';
    }
    return '★★ needs ${(spec.star2Fuel * 100).round()}% fuel left (you had $fuelPct%)';
  }

  String _formatTime(double seconds) {
    if (seconds.isInfinite || seconds.isNaN) return '--';
    if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = (seconds % 60).toStringAsFixed(1);
      return '${m}m ${s}s';
    }
    return '${seconds.toStringAsFixed(1)}s';
  }
}

/// XP lines ticking in one by one, then the career bar filling (and rolling
/// over on rank-up).
class _XpSummary extends StatelessWidget {
  const _XpSummary({required this.reward, required this.anim});
  final RunReward reward;
  final Animation<double> anim;

  @override
  Widget build(BuildContext context) {
    final lines = _groupAchievements(reward.xp.lines);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final t = anim.value;
        // First 45%: reveal lines. Remainder: fill the bar.
        final shown = (t / 0.45 * lines.length).ceil().clamp(0, lines.length);
        final barT = Curves.easeOut.transform(
          ((t - 0.45) / 0.55).clamp(0.0, 1.0),
        );
        final xpNow =
            reward.xpBefore +
            ((reward.xpAfter - reward.xpBefore) * barT).round();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PILOT XP',
              style: TextStyle(
                color: Color(0xFF00B4D8),
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < lines.length; i++)
              AnimatedOpacity(
                opacity: i < shown ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          lines[i].label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        '+${lines[i].xp}',
                        style: const TextStyle(
                          color: Color(0xFF00B4D8),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(color: Color(0x22FFFFFF), height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                Text(
                  '+${reward.xp.total} XP',
                  style: const TextStyle(
                    color: Color(0xFF00B4D8),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CareerProgress(xp: xpNow, badgeSize: 34),
            if (reward.newAchievements.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in reward.newAchievements)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x22FFD166),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0x55FFD166)),
                      ),
                      child: Text(
                        '${a.icon} ${a.title}',
                        style: const TextStyle(
                          color: Color(0xFFFFD166),
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  /// Folds the per-achievement lines into one "Achievements ×N" line (at the
  /// first one's position) — the chips below already name each of them.
  static List<XpLine> _groupAchievements(List<XpLine> lines) {
    const prefix = 'Achievement: ';
    final achievements = lines.where((l) => l.label.startsWith(prefix));
    if (achievements.length < 2) return lines;
    final total = achievements.fold<int>(0, (sum, l) => sum + l.xp);
    final out = <XpLine>[];
    var added = false;
    for (final l in lines) {
      if (!l.label.startsWith(prefix)) {
        out.add(l);
      } else if (!added) {
        out.add(XpLine('Achievements ×${achievements.length}', total));
        added = true;
      }
    }
    return out;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Game Over
// ─────────────────────────────────────────────────────────────────────────────

class _EndOverlay extends StatelessWidget {
  const _EndOverlay({
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    this.extra,
  });

  /// Optional row above the buttons (e.g. the rewarded "continue").
  final Widget? extra;

  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final buttons = Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onSecondary,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: Color(0x3300B4D8)),
            ),
            child: Text(secondaryLabel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: onPrimary,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE07A5F),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              primaryLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );

    return ColoredBox(
      color: const Color(0xCC000000),
      child: _PopupFrame(
        maxWidth: 400,
        radius: 16,
        padding: const EdgeInsets.all(24),
        footer: buttons,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFFE07A5F),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            if (extra case final extra?) ...[const SizedBox(height: 24), extra],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Centered popup card that always fits the screen: kept clear of notches and
/// edges, [child] scrolls inside the card when it's too tall, and [footer]
/// (the buttons) stays pinned at the bottom so it never scrolls off-screen.
class _PopupFrame extends StatelessWidget {
  const _PopupFrame({
    required this.maxWidth,
    required this.child,
    required this.footer,
    this.padding = const EdgeInsets.all(24),
    this.radius = 16,
  });

  final double maxWidth;
  final Widget child;
  final Widget footer;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Material(
              color: const Color(0xFF0D1B2A),
              borderRadius: BorderRadius.circular(radius),
              child: Padding(
                padding: padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: SingleChildScrollView(child: child)),
                    const SizedBox(height: 16),
                    footer,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opt-in rewarded-ad button. Hidden until an ad is actually loaded, so a tap
/// always pays out; runs [onReward] only when the reward was earned.
class _RewardedButton extends StatefulWidget {
  const _RewardedButton({
    required this.label,
    required this.note,
    required this.icon,
    required this.placement,
    required this.onReward,
  });

  final String label;
  final String note;
  final IconData icon;
  final String placement;
  final VoidCallback onReward;

  @override
  State<_RewardedButton> createState() => _RewardedButtonState();
}

class _RewardedButtonState extends State<_RewardedButton> {
  bool _busy = false;

  Future<void> _watch() async {
    setState(() => _busy = true);
    await MonetizationService.instance.showRewarded(
      widget.placement,
      onReward: widget.onReward,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MonetizationService.instance.rewardedReady,
      builder: (context, ready, _) {
        if (!ready && !_busy) return const SizedBox.shrink();
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busy ? null : _watch,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              side: const BorderSide(color: Color(0x88FFD166)),
              foregroundColor: const Color(0xFFFFD166),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                Text(
                  widget.note,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StarIcon extends StatelessWidget {
  const _StarIcon({required this.filled, required this.size});
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _StarPainter(filled: filled),
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter({required this.filled});
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = filled ? const Color(0xFFFFD166) : const Color(0x3300B4D8);

    if (!filled) {
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 1.2;
      paint.color = const Color(0x4400B4D8);
    }

    final cx = size.width / 2;
    final cy = size.height / 2;
    final outer = size.width / 2;
    final inner = outer * 0.4;

    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -math.pi / 2 + (i * 2 * math.pi / 5);
      final innerAngle = outerAngle + math.pi / 5;
      final ox = cx + outer * math.cos(outerAngle);
      final oy = cy + outer * math.sin(outerAngle);
      final ix = cx + inner * math.cos(innerAngle);
      final iy = cy + inner * math.sin(innerAngle);
      i == 0 ? path.moveTo(ox, oy) : path.lineTo(ox, oy);
      path.lineTo(ix, iy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.filled != filled;
}

// ─────────────────────────────────────────────────────────────────────────────
// Cosmetics
// ─────────────────────────────────────────────────────────────────────────────

class _CosmeticsOverlay extends StatefulWidget {
  const _CosmeticsOverlay();

  @override
  State<_CosmeticsOverlay> createState() => _CosmeticsOverlayState();
}

class _CosmeticsOverlayState extends State<_CosmeticsOverlay> {
  String _selectedCategory = CosmeticsService.catShip;

  @override
  Widget build(BuildContext context) {
    final currency = ProgressService.instance.getCosmeticCurrency();
    final items = CosmeticsService.all
        .where((e) => e.category == _selectedCategory)
        .toList();

    return ColoredBox(
      color: const Color(0xEE050816),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      onPressed: () {
                        final game =
                            ctx
                                    .findAncestorWidgetOfExactType<GameWidget>()
                                    ?.game
                                as NarrowHaulGame?;
                        game?.overlays.remove('cosmetics');
                        game?.overlays.add('menu');
                      },
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'GARAGE',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: const Color(0xFFE07A5F),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '💰 $currency',
                    style: const TextStyle(
                      color: Color(0xFF4ADE80),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0x22E07A5F), height: 1),
            // Category Tabs
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Tab(
                  label: 'Ships',
                  selected: _selectedCategory == CosmeticsService.catShip,
                  onTap: () => setState(
                    () => _selectedCategory = CosmeticsService.catShip,
                  ),
                ),
                _Tab(
                  label: 'Ropes',
                  selected: _selectedCategory == CosmeticsService.catRope,
                  onTap: () => setState(
                    () => _selectedCategory = CosmeticsService.catRope,
                  ),
                ),
                _Tab(
                  label: 'Plumes',
                  selected: _selectedCategory == CosmeticsService.catPlume,
                  onTap: () => setState(
                    () => _selectedCategory = CosmeticsService.catPlume,
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0x22FFFFFF), height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final unlocked = CosmeticsService.isUnlocked(item);
                  final equipped =
                      CosmeticsService.getSavedEquippedId(item.category) ==
                      item.id;
                  final trying = CosmeticsService.trialOverride[item.category] ==
                      item.id;
                  // Coin items can be test-flown for one level via an ad.
                  final canTry = !unlocked &&
                      !trying &&
                      !item.supporterOnly &&
                      !CosmeticsService.isRankLocked(item);
                  return _CosmeticTile(
                    item: item,
                    unlocked: unlocked,
                    equipped: equipped,
                    trying: trying,
                    tryButton: canTry
                        ? _TryButton(
                            onReward: () =>
                                setState(() => CosmeticsService.startTrial(item)),
                          )
                        : null,
                    onTap: () async {
                      if (equipped) return;
                      if (unlocked) {
                        await CosmeticsService.equip(item);
                        setState(() {});
                      } else if (item.supporterOnly) {
                        final bought = await MonetizationService.instance.buy(
                          ProductIds.supporterPack,
                        );
                        if (bought) {
                          await CosmeticsService.equip(item);
                          if (mounted) setState(() {});
                        }
                      } else {
                        final success = await CosmeticsService.unlock(item);
                        if (success) {
                          await CosmeticsService.equip(item);
                          setState(() {});
                        }
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? const Color(0xFFE07A5F) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Garage "Try" chip: a rewarded ad lends the item for the next level.
class _TryButton extends StatelessWidget {
  const _TryButton({required this.onReward});
  final VoidCallback onReward;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MonetizationService.instance.rewardedReady,
      builder: (context, ready, _) => !ready
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TextButton.icon(
                onPressed: () => MonetizationService.instance.showRewarded(
                  AdPlacement.cosmeticTrial,
                  onReward: onReward,
                ),
                icon: const Icon(Icons.ondemand_video_rounded, size: 16),
                label: const Text('Try', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFD166),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
    );
  }
}

class _CosmeticTile extends StatelessWidget {
  const _CosmeticTile({
    required this.item,
    required this.unlocked,
    required this.equipped,
    required this.onTap,
    this.trying = false,
    this.tryButton,
  });
  final CosmeticItem item;
  final bool unlocked;
  final bool equipped;
  final VoidCallback onTap;

  /// On loan for the next level (rewarded trial).
  final bool trying;
  final Widget? tryButton;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: equipped ? const Color(0xFF1B263B) : const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: equipped ? const Color(0xFFE07A5F) : const Color(0x151B263B),
            width: equipped ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(item.icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.name,
                style: TextStyle(
                  color: unlocked ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            ?tryButton,
            if (trying)
              const Text(
                'ON TRIAL · NEXT LEVEL',
                style: TextStyle(
                  color: Color(0xFFFFD166),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              )
            else if (equipped)
              const Text(
                'EQUIPPED',
                style: TextStyle(
                  color: Color(0xFFE07A5F),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              )
            else if (unlocked)
              const Text(
                'EQUIP',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              )
            else if (item.supporterOnly)
              const Text(
                '💎 Supporter Pack',
                style: TextStyle(
                  color: Color(0xFF33D6C9),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              )
            else if (CosmeticsService.isRankLocked(item))
              Text(
                '🔒 ${item.requiredRank.title}',
                style: const TextStyle(
                  color: Color(0xFFFFD166),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              )
            else
              Text(
                '💰 ${item.cost}',
                style: const TextStyle(
                  color: Color(0xFF4ADE80),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pilot career (rank badge, XP bar, rank-up, logbook)
// ─────────────────────────────────────────────────────────────────────────────

class _RankBadge extends StatelessWidget {
  const _RankBadge({
    required this.kind,
    required this.size,
    this.dimmed = false,
  });
  final InsigniaKind kind;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.3 : 1,
      child: CustomPaint(
        size: Size(size, size),
        painter: _InsigniaPainter(kind),
      ),
    );
  }
}

class _InsigniaPainter extends CustomPainter {
  _InsigniaPainter(this.kind);
  final InsigniaKind kind;

  @override
  void paint(Canvas canvas, Size size) =>
      paintInsignia(canvas, Offset.zero & size, kind);

  @override
  bool shouldRepaint(_InsigniaPainter old) => old.kind != kind;
}

/// Badge + rank title + XP bar toward the next rank.
class _CareerProgress extends StatelessWidget {
  const _CareerProgress({required this.xp, this.badgeSize = 40});
  final int xp;
  final double badgeSize;

  @override
  Widget build(BuildContext context) {
    final rank = rankFor(xp);
    final next = nextRank(rank);
    final (into, step) = stepProgress(xp);
    return Row(
      children: [
        _RankBadge(kind: rank.insignia, size: badgeSize),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rankTitle(xp).toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFFFFD166),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressToNext(xp),
                  minHeight: 6,
                  backgroundColor: const Color(0xFF1B263B),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF00B4D8)),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                next != null
                    ? '$into / $step XP  ·  next: ${next.title}'
                    : '$into / $step XP  ·  next: ★${prestigeStars(xp) + 1}',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Menu card: tap to open the Pilot Logbook.
class _RankCard extends StatelessWidget {
  const _RankCard({required this.xp, required this.onTap, this.trailing});
  final int xp;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0D1B2A),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x33FFD166)),
          ),
          child: Row(
            children: [
              Expanded(child: _CareerProgress(xp: xp, badgeSize: 38)),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankUpOverlay extends StatefulWidget {
  const _RankUpOverlay({required this.game});
  final NarrowHaulGame game;

  @override
  State<_RankUpOverlay> createState() => _RankUpOverlayState();
}

class _RankUpOverlayState extends State<_RankUpOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reward = widget.game.lastRunReward;
    if (reward == null) return const SizedBox.shrink();
    final rank = reward.rankAfter;
    final scale = CurvedAnimation(parent: _anim, curve: Curves.elasticOut);

    return GestureDetector(
      onTap: () => widget.game.overlays.remove('rankUp'),
      child: ColoredBox(
        color: const Color(0xEE050816),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'PROMOTED',
                    style: TextStyle(
                      color: Color(0xFF00B4D8),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ScaleTransition(
                    scale: scale,
                    child: _RankBadge(kind: rank.insignia, size: 110),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    rank.title.toUpperCase(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFFFFD166),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    rank.perk,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  if (rankUpBonus(rank) > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Promotion bonus +${rankUpBonus(rank)} 💰',
                      style: const TextStyle(
                        color: Color(0xFF4ADE80),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => widget.game.overlays.remove('rankUp'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD166),
                      foregroundColor: const Color(0xFF050816),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 36,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Career overview: current rank, the full ladder, and lifetime stats.
class _PilotLogbookOverlay extends StatefulWidget {
  const _PilotLogbookOverlay({required this.game});
  final NarrowHaulGame game;

  @override
  State<_PilotLogbookOverlay> createState() => _PilotLogbookOverlayState();
}

class _PilotLogbookOverlayState extends State<_PilotLogbookOverlay> {
  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.instance;
    final xp = progress.getXp();
    final current = rankFor(xp);
    final playtime = progress.getStat(ProgressService.statPlaytimeSeconds);
    final stats = <(String, String)>[
      ('Flight hours', '${(playtime / 3600).toStringAsFixed(1)} h'),
      ('Flights', '${progress.getStat(ProgressService.statFlights)}'),
      ('Deliveries', '${progress.getStat(ProgressService.statDeliveries)}'),
      ('Crashes', '${progress.getStat(ProgressService.statCrashes)}'),
      ('Fuel burned', '${progress.getTotalFuelSpent().round()} u'),
      (
        'Stars',
        '${LevelRegistry.totalStars()} / ${LevelRegistry.totalLevels * 3}',
      ),
      ('Total XP', '$xp'),
      ('Daily streak', '🔥 ${progress.getDailyStreak()}'),
    ];

    return ColoredBox(
      color: const Color(0xEE050816),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      widget.game.overlays.remove('pilotProfile');
                      widget.game.overlays.add('menu');
                    },
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'PILOT LOGBOOK',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: const Color(0xFFFFD166),
                    ),
                  ),
                  const Spacer(),
                  if (kDebugMode && !kStoreCapture)
                    TextButton(
                      onPressed: () async {
                        await progress.addXp(1000);
                        setState(() {});
                      },
                      child: const Text(
                        '+1000 XP (debug)',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: Color(0x22FFD166), height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: current rank + stats
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _CareerProgress(xp: xp, badgeSize: 56),
                        const SizedBox(height: 16),
                        for (final (label, value) in stats)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Text(
                                  value,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                        const Text(
                          'TYPE RATINGS',
                          style: TextStyle(
                            color: Color(0xFFFFD166),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final ship in kShips.values)
                          _TypeRatingRow(
                            ship: ship,
                            rated: LevelRegistry.hasTypeRating(ship.id),
                          ),
                      ],
                    ),
                  ),
                  const VerticalDivider(color: Color(0x22FFFFFF), width: 1),
                  // Right: rank ladder
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: kRanks.length,
                      itemBuilder: (context, i) {
                        final r = kRanks[i];
                        final reached = r.index <= current.index;
                        final isCurrent = r.index == current.index;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? const Color(0xFF1B263B)
                                : const Color(0xFF0D1B2A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCurrent
                                  ? const Color(0xFFFFD166)
                                  : const Color(0x151B263B),
                            ),
                          ),
                          child: Row(
                            children: [
                              _RankBadge(
                                kind: r.insignia,
                                size: 30,
                                dimmed: !reached,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.title,
                                      style: TextStyle(
                                        color: reached
                                            ? const Color(0xFFFFD166)
                                            : Colors.white38,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      r.perk,
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                reached ? '✓' : '${r.minXp} XP',
                                style: TextStyle(
                                  color: reached
                                      ? const Color(0xFF4ADE80)
                                      : Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contracts & achievement toast
// ─────────────────────────────────────────────────────────────────────────────

/// Today's 3 contracts on the menu (or a teaser until Commercial Pilot).
class _ContractsPanel extends StatelessWidget {
  const _ContractsPanel();

  @override
  Widget build(BuildContext context) {
    if (!ContractsService.isUnlocked) {
      return Text(
        '📋 Contracts unlock at ${kRanks[kContractsRankIndex].title}',
        style: const TextStyle(color: Colors.white30, fontSize: 11),
      );
    }
    final contracts = ContractsService.today();
    final done = contracts.where((c) => c.done).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x3300B4D8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                "TODAY'S CONTRACTS",
                style: TextStyle(
                  color: Color(0xFF00B4D8),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                '$done / ${contracts.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final c in contracts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    c.done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 14,
                    color: c.done ? const Color(0xFF4ADE80) : Colors.white30,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.contract.description,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.done ? Colors.white38 : Colors.white70,
                        fontSize: 12,
                        decoration: c.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  Text(
                    c.done
                        ? '+${c.contract.xp} XP'
                        : '${c.progress}/${c.contract.target} · ${c.contract.xp} XP',
                    style: TextStyle(
                      color: c.done ? const Color(0xFF4ADE80) : Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Slides a banner in from the top when an achievement is announced
/// mid-flight.
class _AchievementToastHost extends StatefulWidget {
  const _AchievementToastHost();

  @override
  State<_AchievementToastHost> createState() => _AchievementToastHostState();
}

class _AchievementToastHostState extends State<_AchievementToastHost> {
  AchievementMeta? _shown;
  bool _visible = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    AchievementService.announced.addListener(_onAnnounced);
  }

  @override
  void dispose() {
    AchievementService.announced.removeListener(_onAnnounced);
    super.dispose();
  }

  void _onAnnounced() {
    final a = AchievementService.announced.value;
    if (a == null) return;
    final token = ++_token;
    setState(() {
      _shown = a;
      _visible = true;
    });
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted && token == _token) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _shown;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: SafeArea(
          child: AnimatedSlide(
            offset: _visible ? Offset.zero : const Offset(0, -1.5),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            child: Center(
              child: a == null
                  ? const SizedBox.shrink()
                  : Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xEE0D1B2A),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0x88FFD166)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(a.icon, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'ACHIEVEMENT UNLOCKED',
                                style: TextStyle(
                                  color: Color(0xFFFFD166),
                                  fontSize: 9,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${a.title}  ·  +100 XP',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One licence endorsement in the logbook: ship name, role and status.
class _TypeRatingRow extends StatelessWidget {
  const _TypeRatingRow({required this.ship, required this.rated});

  final ShipSpec ship;
  final bool rated;

  @override
  Widget build(BuildContext context) {
    final tint = ship.tint != null ? Color(ship.tint!).withValues(alpha: 1) : const Color(0xFF00B4D8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.flight,
            size: 18,
            color: rated ? tint : Colors.white24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ship.name,
                  style: TextStyle(
                    color: rated ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  ship.blurb,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            rated ? '✓ Rated' : 'Not rated',
            style: TextStyle(
              color: rated ? const Color(0xFF4ADE80) : Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
