
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/ui/rewarded_button.dart';
import 'package:narrow_haul/ui/route_guide_overlays.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// 'gameOver' overlay: the crash on the left, ways to carry on (rewarded
/// continue / charge, route help) on the right, Retry pinned below.
class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({super.key, required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    final g = game;
    return ValueListenableBuilder<bool>(
      valueListenable: MonetizationService.instance.rewardedReady,
      builder: (context, adReady, _) {
        final rewarded = adReady && (g.canContinue || g.canOfferAmmo);
        final hasHelp = rewarded || g.canShowRoute;
        final advice = g.crashAdvice;

        final crash = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: hasHelp
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 38,
              color: SpaceColors.coral,
              shadows: [Shadow(color: SpaceColors.coral, blurRadius: 16)],
            ),
            const SizedBox(height: 6),
            Text(
              'HULL BREACH',
              style: hudLabel(24, color: SpaceColors.coral, spacing: 4)
                  .copyWith(
                    shadows: const [
                      Shadow(color: Color(0x88E07A5F), blurRadius: 14),
                    ],
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              g.currentLevelDef.name,
              style: hudLabel(11, color: Colors.white38, spacing: 2),
            ),
            if (advice != null) ...[
              const SizedBox(height: 8),
              _CrashAdvice(text: advice, center: !hasHelp),
            ],
          ],
        );

        final help = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (g.canContinue) ...[
              RewardedButton(
                label: 'Continue',
                note: 'Ad · from before the crash · max 2★',
                icon: Icons.play_circle_outline_rounded,
                placement: AdPlacement.continueAfterCrash,
                onReward: g.continueAfterCrash,
              ),
              const SizedBox(height: 8),
            ],
            if (g.canOfferAmmo) ...[
              RewardedButton(
                label: 'Demolition Charge',
                note: 'Ad · blast a way through · max 2★',
                icon: Icons.local_fire_department_rounded,
                placement: AdPlacement.ammo,
                onReward: g.grantRewardedCharge,
              ),
              const SizedBox(height: 8),
            ],
            RouteHelpButtons(game: g),
          ],
        );

        return HoloDialog(
          accent: SpaceColors.coral,
          maxWidth: hasHelp ? 640 : 420,
          sound: false,
          footer: Row(
            children: [
              Expanded(
                child: HoloButton(
                  label: 'Hangar',
                  icon: Icons.home_rounded,
                  sound: UiSound.back,
                  onPressed: g.backToMenu,
                ),
              ),
              const SizedBox(width: 12),
              if (g.canFreeContinue) ...[
                // Training: rewind for free, as often as needed.
                Expanded(
                  child: HoloButton(
                    label: 'Restart',
                    icon: Icons.replay_rounded,
                    sound: UiSound.launch,
                    onPressed: g.restartLevel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: HoloButton.primary(
                    key: const ValueKey('free-continue'),
                    label: 'Try again',
                    subtitle: 'from just before the crash',
                    icon: Icons.fast_rewind_rounded,
                    accent: SpaceColors.coral,
                    sound: UiSound.launch,
                    height: 46,
                    onPressed: g.freeContinue,
                  ),
                ),
              ] else if (g.canResumeFromPad) ...[
                // An Expedition flies on from its last staging pad.
                Expanded(
                  child: HoloButton(
                    label: 'Restart',
                    icon: Icons.replay_rounded,
                    sound: UiSound.launch,
                    onPressed: g.restartLevel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: HoloButton.primary(
                    key: const ValueKey('resume-pad'),
                    label: 'Resume · pad ${g.checkpointPad}',
                    subtitle: 'max 2★',
                    icon: Icons.flag_rounded,
                    accent: SpaceColors.coral,
                    sound: UiSound.launch,
                    height: 46,
                    onPressed: g.resumeFromPad,
                  ),
                ),
              ] else
                Expanded(
                  flex: 2,
                  child: HoloButton.primary(
                    label: 'Retry',
                    icon: Icons.replay_rounded,
                    accent: SpaceColors.coral,
                    sound: UiSound.launch,
                    height: 46,
                    onPressed: g.restartLevel,
                  ),
                ),
            ],
          ),
          child: hasHelp
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 5, child: crash),
                    const SizedBox(width: 20),
                    Expanded(flex: 6, child: help),
                  ],
                )
              : crash,
        );
      },
    );
  }
}

/// The crash screen's advice: what went wrong, in one line.
class _CrashAdvice extends StatelessWidget {
  const _CrashAdvice({required this.text, required this.center});
  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: SpaceColors.gold.withValues(alpha: 0.08),
        border: Border(
          left: BorderSide(color: SpaceColors.gold.withValues(alpha: 0.8), width: 3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.lightbulb_outline_rounded, size: 15, color: SpaceColors.gold),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              text,
              textAlign: center ? TextAlign.center : TextAlign.start,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rank up
// ─────────────────────────────────────────────────────────────────────────────
