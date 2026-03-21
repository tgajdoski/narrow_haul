import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final game = NarrowHaulGame();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B4D8),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: GameWidget(
          game: game,
          overlayBuilderMap: {
            'menu': (context, game) {
              final g = game as NarrowHaulGame;
              return _MenuOverlay(
                onPlay: () => g.beginPlay(),
              );
            },
            'gameOver': (context, game) {
              final g = game as NarrowHaulGame;
              return _EndOverlay(
                title: 'Hull breach',
                subtitle: 'The ship touched the terrain.',
                primaryLabel: 'Retry',
                onPrimary: g.restartLevel,
                secondaryLabel: 'Menu',
                onSecondary: g.backToMenu,
              );
            },
            'levelComplete': (context, game) {
              final g = game as NarrowHaulGame;
              return _EndOverlay(
                title: 'Mission complete',
                subtitle: 'Cargo and ship on the landing pad. Level ${g.levelIndex + 1} cleared.',
                primaryLabel: g.levelIndex < NarrowHaulGame.levelPaths.length - 1
                    ? 'Next level'
                    : 'Replay',
                onPrimary: g.nextLevel,
                secondaryLabel: 'Menu',
                onSecondary: g.backToMenu,
              );
            },
          },
        ),
      ),
    ),
  );
}

class _MenuOverlay extends StatelessWidget {
  const _MenuOverlay({required this.onPlay});

  final Future<void> Function() onPlay;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xDD050816),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Narrow Haul',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Landscape mode. Left: ⟲ ⟳ rotate. Right: THRUST. '
                  'Pick up cargo (orange zone), then land both the cargo and the ship on the green pad.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => onPlay(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text('Play'),
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
            color: const Color(0xFF1B263B),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onSecondary,
                          child: Text(secondaryLabel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: onPrimary,
                          child: Text(primaryLabel),
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
