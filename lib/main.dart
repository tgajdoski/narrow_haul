import 'dart:math' as math;

import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Point the global Flame image cache at assets/ (not the default assets/images/).
  Flame.images.prefix = 'assets/';
  await ProgressService.init();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final game = NarrowHaulGame();
  runApp(_NarrowHaulApp(game: game));
}

class _NarrowHaulApp extends StatelessWidget {
  const _NarrowHaulApp({required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B4D8),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF050816),
        body: ClipRect(
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
                );
              },
              'levelComplete': (context, game) {
                final g = game as NarrowHaulGame;
                return _LevelCompleteOverlay(game: g);
              },
            },
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

    return ColoredBox(
      color: const Color(0xDD050816),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
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
                // Star total
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StarIcon(filled: totalStars > 0, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '$totalStars / $maxStars stars',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
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
                        onPressed: challengeComplete ? null : () => game.beginChallenge(),
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
                              challengeComplete ? 'Daily ✓' : 'Daily Challenge',
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
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Left side: joystick (rotate)  ·  Right side: thrust',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white24,
                  ),
                ),
              ],
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
            Expanded(
              child: _WorldMap(game: game),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldMap extends StatelessWidget {
  const _WorldMap({required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.instance;
    final totalStars = LevelRegistry.totalStars();

    return LayoutBuilder(builder: (context, constraints) {
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

      return SingleChildScrollView(
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
                    unlocked: totalStars >= LevelRegistry.worlds[wi].starsRequired,
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
                      onTap: LevelRegistry.isLevelUnlocked(i)
                          ? () => game.startLevel(i)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
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
                color: unlocked ? accent.withValues(alpha: 0.6) : const Color(0x331B263B),
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
                if (unlocked)
                  Text(
                    '${world.levels.length} missions',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  )
                else ...[
                  const Icon(Icons.lock_outline, size: 16, color: Colors.white24),
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
  });

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
                  ? accent.withValues(alpha: stars > 0 ? 0.8 : 0.3)
                  : const Color(0x331B263B),
              width: stars == 3 ? 3 : 2,
            ),
            boxShadow: unlocked && stars > 0
                ? [BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 10)]
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
                  children: List.generate(3, (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: _StarIcon(filled: i < stars, size: 8),
                  )),
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
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                    ),
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
                  Builder(builder: (ctx) => IconButton(
                    onPressed: () {
                      final game = ctx
                          .findAncestorWidgetOfExactType<GameWidget>()
                          ?.game as NarrowHaulGame?;
                      game?.overlays.remove('achievements');
                      game?.overlays.add('menu');
                    },
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    color: Colors.white70,
                  )),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      color: unlocked ? const Color(0xFFFFD166) : Colors.white54,
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
            if (unlocked) const Icon(Icons.check_circle, color: Color(0xFF4ADE80), size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Level Complete
// ─────────────────────────────────────────────────────────────────────────────

class _LevelCompleteOverlay extends StatelessWidget {
  const _LevelCompleteOverlay({required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final stars = game.lastLevelStars;
    final time = game.lastLevelTimeSeconds;
    final isLastLevel = game.levelIndex >= LevelRegistry.totalLevels - 1;
    final isChallengeMode = game.isChallengeMode;

    return ColoredBox(
      color: const Color(0xCC000000),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: const Color(0xFF0D1B2A),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
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
                  const SizedBox(height: 20),
                  // Stars
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _StarIcon(filled: i < stars, size: 28),
                    )),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$stars / 3 stars  ·  ${_formatTime(time)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: game.backToMenu,
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
                          onPressed: game.nextLevel,
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
    if (seconds.isInfinite || seconds.isNaN) return '--';
    if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = (seconds % 60).toStringAsFixed(1);
      return '${m}m ${s}s';
    }
    return '${seconds.toStringAsFixed(1)}s';
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
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xCC000000),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Material(
            color: const Color(0xFF0D1B2A),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(24),
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
                  const SizedBox(height: 24),
                  Row(
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

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
    final items = CosmeticsService.all.where((e) => e.category == _selectedCategory).toList();

    return ColoredBox(
      color: const Color(0xEE050816),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Builder(builder: (ctx) => IconButton(
                    onPressed: () {
                      final game = ctx
                          .findAncestorWidgetOfExactType<GameWidget>()
                          ?.game as NarrowHaulGame?;
                      game?.overlays.remove('cosmetics');
                      game?.overlays.add('menu');
                    },
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    color: Colors.white70,
                  )),
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
                    style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 14, fontWeight: FontWeight.bold),
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
                  onTap: () => setState(() => _selectedCategory = CosmeticsService.catShip),
                ),
                _Tab(
                  label: 'Ropes',
                  selected: _selectedCategory == CosmeticsService.catRope,
                  onTap: () => setState(() => _selectedCategory = CosmeticsService.catRope),
                ),
                _Tab(
                  label: 'Plumes',
                  selected: _selectedCategory == CosmeticsService.catPlume,
                  onTap: () => setState(() => _selectedCategory = CosmeticsService.catPlume),
                ),
              ],
            ),
            const Divider(color: Color(0x22FFFFFF), height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final unlocked = CosmeticsService.isUnlocked(item);
                  final equipped = CosmeticsService.getEquippedId(item.category) == item.id;
                  return _CosmeticTile(
                    item: item,
                    unlocked: unlocked,
                    equipped: equipped,
                    onTap: () async {
                      if (equipped) return;
                      if (unlocked) {
                        await CosmeticsService.equip(item);
                        setState(() {});
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
  const _Tab({required this.label, required this.selected, required this.onTap});
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

class _CosmeticTile extends StatelessWidget {
  const _CosmeticTile({required this.item, required this.unlocked, required this.equipped, required this.onTap});
  final CosmeticItem item;
  final bool unlocked;
  final bool equipped;
  final VoidCallback onTap;

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
            if (equipped)
              const Text('EQUIPPED', style: TextStyle(color: Color(0xFFE07A5F), fontSize: 11, fontWeight: FontWeight.bold))
            else if (unlocked)
              const Text('EQUIP', style: TextStyle(color: Colors.white54, fontSize: 11))
            else
              Text('💰 ${item.cost}', style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
