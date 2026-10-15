import 'package:flame/game.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/ui/career_overlays.dart';
import 'package:narrow_haul/ui/delivered_by_screen.dart';
import 'package:narrow_haul/ui/garage_overlay.dart';
import 'package:narrow_haul/ui/launch_intro.dart';
import 'package:narrow_haul/ui/level_select_overlay.dart';
import 'package:narrow_haul/ui/menu_overlay.dart';
import 'package:narrow_haul/ui/mission_briefing.dart';
import 'package:narrow_haul/ui/pause_settings_overlays.dart';
import 'package:narrow_haul/ui/result_overlays.dart';
import 'package:narrow_haul/ui/route_guide_overlays.dart';
import 'package:narrow_haul/ui/space_ui.dart';
import 'package:narrow_haul/ui/story_card.dart';
import 'package:narrow_haul/game/overlay_ids.dart';
import 'package:narrow_haul/ui/theme.dart';
import 'package:narrow_haul/ui/achievement_toast.dart';

class NarrowHaulApp extends StatelessWidget {
  const NarrowHaulApp({super.key, required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // The HUD (drawn by Flame) keeps clear of the notch / home indicator.
        game.setSafeInsets(mq.viewPadding);
        game.reducedMotion = mq.disableAnimations;
        // Large system font sizes would overflow buttons on short landscape
        // phones; allow some scaling, not unlimited.
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
          ),
          child: child!,
        );
      },
      // Android back steps back through screens (pause mid-flight) instead of
      // closing the app; only the main menu lets it exit.
      home: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !game.handleBack()) SystemNavigator.pop();
        },
        child: Scaffold(
          backgroundColor: SpaceColors.bg,
          body: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  // Raw pointers for the pinch zoom: a Listener never takes
                  // part in the gesture arena, so the controls keep theirs.
                  child: Listener(
                    onPointerDown: (e) =>
                        game.zoomPointerDown(e.pointer, e.localPosition),
                    onPointerMove: (e) =>
                        game.zoomPointerMove(e.pointer, e.localPosition),
                    onPointerUp: (e) => game.zoomPointerUp(e.pointer),
                    onPointerCancel: (e) => game.zoomPointerUp(e.pointer),
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
                        game.zoomBy(e.scrollDelta.dy < 0 ? 1 : -1);
                      }
                    },
                    child: GameWidget<NarrowHaulGame>(
                      game: game,
                      overlayBuilderMap: {
                        OverlayIds.menu: (context, game) =>
                            MenuOverlay(game: game),
                        OverlayIds.levelSelect: (context, game) =>
                            LevelSelectOverlay(game: game),
                        OverlayIds.achievements: (context, game) =>
                            AchievementsOverlay(game: game),
                        OverlayIds.cosmetics: (context, game) => GarageOverlay(
                          game: game,
                          initialTab: game.takeGarageTab(),
                        ),
                        OverlayIds.gameOver: (context, game) =>
                            GameOverOverlay(game: game),
                        OverlayIds.demo: (context, game) =>
                            DemoFlightOverlay(game: game),
                        OverlayIds.levelComplete: (context, game) =>
                            LevelCompleteOverlay(game: game),
                        OverlayIds.rankUp: (context, game) =>
                            RankUpOverlay(game: game),
                        OverlayIds.story: (context, game) =>
                            StoryChapterOverlay(game: game),
                        OverlayIds.pause: (context, game) =>
                            PauseOverlay(game: game),
                        OverlayIds.settings: (context, game) =>
                            SettingsOverlay(game: game),
                        OverlayIds.pilotProfile: (context, game) =>
                            PilotLogbookOverlay(game: game),
                        OverlayIds.briefing: (context, game) =>
                            MissionBriefingOverlay(game: game),
                      },
                    ),
                  ),
                ),
                const AchievementToastHost(),
                // Launch intro (every start without the credits): takes over
                // from the native splash and covers loading. Positioned, for
                // the same reason as the credits below.
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: game.introVisible,
                    builder: (context, visible, _) => visible
                        ? LaunchIntro(
                            ready: game.loaded,
                            onDone: () => game.introVisible.value = false,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                // "Delivered by" credits: above everything, so on the first
                // launch they also cover the game while it loads. Always
                // positioned: a non-positioned child would size the Stack to
                // itself and collapse the GameWidget to 0×0.
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: game.creditsVisible,
                    builder: (context, visible, _) => visible
                        ? DeliveredByScreen(
                            ready: game.loaded,
                            onDone: () {
                              game.creditsVisible.value = false;
                              ProgressService.instance.markCreditsSeen();
                            },
                          )
                        : const SizedBox.shrink(),
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
// Achievement toast
// ─────────────────────────────────────────────────────────────────────────────
