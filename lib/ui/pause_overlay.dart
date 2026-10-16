
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/ui/route_guide_overlays.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// Mid-flight pause menu ('pause' overlay): one wide cockpit panel, every
/// action in a single row so it fits a landscape phone.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    return HoloDialog(
      maxWidth: 620,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PAUSED',
                      style:
                          hudLabel(
                            24,
                            color: SpaceColors.cyanBright,
                            spacing: 5,
                          ).copyWith(
                            shadows: const [
                              Shadow(color: SpaceColors.cyan, blurRadius: 14),
                            ],
                          ),
                    ),
                    const SizedBox(height: 2),
                    MarqueeText(
                      game.currentLevelDef.name,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (game.routeGuideAvailable)
                SizedBox(width: 250, child: RouteGuideToggle(game: game))
              else if (game.raceGhostAvailable)
                SizedBox(width: 250, child: RaceGhostToggle(game: game)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 68,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: HoloButton.primary(
                    label: 'Resume',
                    icon: Icons.play_arrow_rounded,
                    sound: UiSound.close,
                    height: 68,
                    fontSize: 18,
                    onPressed: game.resumeGame,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HoloTile(
                    icon: Icons.replay_rounded,
                    label: 'Restart',
                    accent: SpaceColors.coral,
                    sound: UiSound.launch,
                    onTap: game.restartLevel,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HoloTile(
                    icon: Icons.tune_rounded,
                    label: 'Settings',
                    accent: Colors.white70,
                    onTap: () {
                      game.openSettingsFromPause();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HoloTile(
                    icon: Icons.home_rounded,
                    label: 'Hangar',
                    sound: UiSound.back,
                    onTap: game.backToMenu,
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
