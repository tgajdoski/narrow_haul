import 'dart:math' as math;

import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
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
    final totalStars = progress.getTotalStars(NarrowHaulGame.levelPaths.length);
    final maxStars = NarrowHaulGame.levelPaths.length * 3;
    final challengeComplete = progress.isDailyChallengeComplete();

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
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(
                            color: challengeComplete
                                ? const Color(0x334ADE80)
                                : const Color(0x55FFD166),
                          ),
                        ),
                        child: Text(
                          challengeComplete ? 'Daily ✓' : 'Daily Challenge',
                          style: TextStyle(
                            color: challengeComplete
                                ? const Color(0xFF4ADE80)
                                : const Color(0xFFFFD166),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Level Select
// ─────────────────────────────────────────────────────────────────────────────

class _LevelSelectOverlay extends StatelessWidget {
  const _LevelSelectOverlay({required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.instance;
    final total = NarrowHaulGame.levelPaths.length;

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
                    '${progress.getTotalStars(total)} / ${total * 3} ★',
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
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: total,
                itemBuilder: (context, index) {
                  final unlocked = progress.isUnlocked(index);
                  final stars = progress.getStars(index);
                  final bestTime = progress.getBestTime(index);
                  return _LevelCell(
                    levelIndex: index,
                    unlocked: unlocked,
                    stars: stars,
                    bestTime: bestTime,
                    onTap: unlocked
                        ? () => game.startLevel(index)
                        : null,
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

class _LevelCell extends StatelessWidget {
  const _LevelCell({
    required this.levelIndex,
    required this.unlocked,
    required this.stars,
    required this.bestTime,
    required this.onTap,
  });

  final int levelIndex;
  final bool unlocked;
  final int stars;
  final double? bestTime;
  final VoidCallback? onTap;

  static const _zones = [
    ('Tutorial', Color(0xFF00B4D8)),
    ('Beginner', Color(0xFF4ADE80)),
    ('Intermediate', Color(0xFFFFD166)),
    ('Advanced', Color(0xFFFF6B35)),
    ('Expert', Color(0xFFE07A5F)),
  ];

  Color get _zoneColor {
    if (levelIndex < 3) return _zones[0].$2;
    if (levelIndex < 7) return _zones[1].$2;
    if (levelIndex < 12) return _zones[2].$2;
    if (levelIndex < 16) return _zones[3].$2;
    return _zones[4].$2;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: unlocked ? 1.0 : 0.38,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: unlocked
                  ? _zoneColor.withValues(alpha: stars > 0 ? 0.6 : 0.25)
                  : const Color(0x221B263B),
              width: stars == 3 ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!unlocked)
                const Icon(Icons.lock_outline, size: 18, color: Colors.white24)
              else ...[
                Text(
                  '${levelIndex + 1}',
                  style: TextStyle(
                    color: _zoneColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: _StarIcon(filled: i < stars, size: 8),
                  )),
                ),
                if (bestTime != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(bestTime!),
                    style: const TextStyle(
                      color: Colors.white24,
                      fontSize: 8,
                    ),
                  ),
                ],
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
    final isLastLevel = game.levelIndex >= NarrowHaulGame.levelPaths.length - 1;
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
                        : 'Mission ${game.levelIndex + 1} cleared.',
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
