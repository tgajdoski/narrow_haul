import 'dart:async';

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/garage_notices.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/ui/career_widgets.dart';
import 'package:narrow_haul/ui/rewarded_button.dart';
import 'package:narrow_haul/ui/space_ui.dart';
import 'package:narrow_haul/ui/store_feedback.dart';
import 'package:narrow_haul/game/story/story.dart';

const _garageNotePrefix = 'New in the Garage';

/// "New in the Garage: Tow Chain (80 💰)" when this payout made something
/// affordable (gear first).
String? _garageNote(RunReward? reward) {
  if (reward == null || reward.currency <= 0) return null;
  final snap = GarageNotices.current();
  final items = newlyAffordable(
    CosmeticsService.all,
    before: reward.coinsBefore,
    after: reward.coinsBefore + reward.currency,
    owned: snap.owned,
    rankIndex: snap.rankIndex,
  );
  if (items.isEmpty) return null;
  final first = items.first;
  final more = items.length > 1 ? ' and ${items.length - 1} more' : '';
  return '$_garageNotePrefix: ${first.name} (${first.cost} 💰)$more';
}

/// 'levelComplete' overlay: stars, flight stats, coins and the XP breakdown,
/// laid out side by side so it fits a landscape phone.
class LevelCompleteOverlay extends StatefulWidget {
  const LevelCompleteOverlay({super.key, required this.game});
  final NarrowHaulGame game;

  @override
  State<LevelCompleteOverlay> createState() => _LevelCompleteOverlayState();
}

class _LevelCompleteOverlayState extends State<LevelCompleteOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  /// True while leaving (an interstitial may be showing) — blocks double taps.
  bool _leaving = false;
  late final bool _showFullGameOffer = _shouldOfferFullGame();

  /// Soft Full Game offer: once the tutorial world is done (or after the
  /// first interstitial), at most every 3 days, never to Full Game owners.
  bool _shouldOfferFullGame() {
    final p = ProgressService.instance;
    final m = MonetizationService.instance;
    if (p.hasFullGame || !m.canBuy(ProductIds.fullGame)) {
      return false;
    }
    final tutorialDone = LevelRegistry.trainingComplete;
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
      if (!mounted || widget.game.showStoryOutroIfDue()) return;
      final reward = widget.game.lastRunReward;
      if (reward != null && reward.rankedUp) {
        widget.game.showRankUp();
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

    final header = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MarqueeText(
                isChallengeMode ? 'CHALLENGE COMPLETE' : 'MISSION COMPLETE',
                style: hudLabel(20, color: SpaceColors.green, spacing: 3)
                    .copyWith(
                      shadows: const [
                        Shadow(color: Color(0x884ADE80), blurRadius: 14),
                      ],
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                isChallengeMode
                    ? game.activeChallengeConfig?.modifierDesc ?? ''
                    : storyFor(game.currentLevelDef.saveId)?.debrief ??
                          '"${game.currentLevelDef.name}" delivered.',
                // The story's debrief gets a second line where there's room.
                maxLines: MediaQuery.sizeOf(context).height < 400 ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Stars pop in one after another (earned ones only).
        AnimatedBuilder(
          animation: _anim,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final start = 0.05 + i * 0.1;
              final t = ((_anim.value - start) / 0.18).clamp(0.0, 1.0);
              final scale = i < stars ? Curves.elasticOut.transform(t) : 1.0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const StarIcon(filled: false, size: 30),
                    if (i < stars)
                      Transform.scale(
                        scale: scale,
                        child: const StarIcon(filled: true, size: 30),
                      ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );

    final notes = <String>[
      ?_missedStarHint(game, stars, time),
      if (game.continuedThisRun) 'Continued flight · max 2★',
      if (game.carriedWeaponUsedThisRun)
        'Carried weapons used · max 2★ (crate finds are free)',
      for (final id in CosmeticsService.activeTrials)
        if (CosmeticsService.byId(id) case final item?
            when !CosmeticsService.isUnlocked(item))
          'Enjoying the ${item.name}? Own it in the Garage for ${item.cost} 💰',
      ?_garageNote(reward),
    ];

    final result = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            HoloChip(icon: Icons.timer_outlined, label: formatFlightTime(time)),
            HoloChip(
              icon: Icons.local_gas_station_outlined,
              label: '${(game.lastLevelFuelFraction * 100).round()}% FUEL',
            ),
            if (reward != null && reward.currency > 0)
              HoloChip(
                leading: const Text('💰', style: TextStyle(fontSize: 12)),
                label: '+${reward.currency}',
                color: SpaceColors.green,
                highlight: true,
              ),
            for (final a in reward?.newAchievements ?? const [])
              HoloChip(
                leading: Text(a.icon, style: const TextStyle(fontSize: 12)),
                label: a.title,
                color: SpaceColors.gold,
              ),
          ],
        ),
        for (final n in notes) ...[
          const SizedBox(height: 6),
          Text(
            n,
            style: TextStyle(
              color: n.startsWith('★') ||
                      n.startsWith('Enjoying') ||
                      n.startsWith(_garageNotePrefix)
                  ? const Color(0xCCFFD166)
                  : Colors.white38,
              fontSize: 12,
            ),
          ),
        ],
        if (game.canDoubleCurrency) ...[
          const SizedBox(height: 10),
          RewardedButton(
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
        if (_showFullGameOffer) ...[
          const SizedBox(height: 8),
          HoloButton(
            label:
                'Full Game · Expeditions, no ads · '
                '${MonetizationService.instance.priceOf(ProductIds.fullGame)}',
            icon: Icons.all_inclusive_rounded,
            variant: HoloVariant.ghost,
            height: 34,
            fontSize: 10.5,
            onPressed: () async {
              await buyWithFeedback(context, ProductIds.fullGame);
              if (mounted) setState(() {});
            },
          ),
        ],
      ],
    );

    final buttons = Row(
      children: [
        Expanded(
          child: HoloButton(
            label: 'Hangar',
            icon: Icons.home_rounded,
            sound: UiSound.back,
            onPressed: _leaving
                ? null
                : () => _leave(() async => game.backToMenu()),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: HoloButton.primary(
            label: isChallengeMode
                ? 'Done'
                : isLastLevel
                ? 'Replay'
                : 'Next mission',
            icon: isChallengeMode
                ? Icons.check_rounded
                : isLastLevel
                ? Icons.replay_rounded
                : Icons.arrow_forward_rounded,
            sound: UiSound.launch,
            height: 46,
            onPressed: _leaving ? null : () => _leave(game.nextLevel),
          ),
        ),
      ],
    );

    return HoloDialog(
      accent: SpaceColors.green,
      maxWidth: reward == null ? 480 : 720,
      sound: false,
      footer: buttons,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 10),
          const Divider(color: Color(0x224ADE80), height: 1),
          const SizedBox(height: 10),
          if (reward == null)
            result
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: result),
                const SizedBox(width: 20),
                Expanded(
                  child: XpSummary(reward: reward, anim: _anim),
                ),
              ],
            ),
        ],
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
      // Fuel and time were enough: a cap (continue, guide, carried weapons)
      // took the third star, and its own note says so.
      if (time <= spec.star3Time) return null;
      return '★★★ needs a time under ${spec.star3Time.round()}s';
    }
    return '★★ needs ${(spec.star2Fuel * 100).round()}% fuel left (you had $fuelPct%)';
  }
}

/// XP lines ticking in one by one, then the career gauge filling (and
/// rolling over on rank-up). Long breakdowns fold their tail into one line.
class XpSummary extends StatelessWidget {
  const XpSummary({super.key, required this.reward, required this.anim});
  final RunReward reward;
  final Animation<double> anim;

  static const _maxLines = 5;

  @override
  Widget build(BuildContext context) {
    final lines = foldXpLines(reward.xp.lines);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final t = anim.value;
        // First 45%: reveal lines. Remainder: fill the gauge.
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
            Row(
              children: [
                const Expanded(child: PanelTitle('Pilot XP')),
                Text(
                  '+${reward.xp.total} XP',
                  style: hudLabel(13, color: SpaceColors.cyan),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (int i = 0; i < lines.length; i++)
              AnimatedOpacity(
                opacity: i < shown ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(
                    children: [
                      Expanded(
                        child: MarqueeText(
                          lines[i].label,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        '+${lines[i].xp}',
                        style: const TextStyle(
                          color: SpaceColors.cyan,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            CareerProgress(xp: xpNow, badgeSize: 32),
          ],
        );
      },
    );
  }

  /// Folds the per-achievement lines into one "Achievements ×N" line (the
  /// chips below name each of them), then folds anything past [_maxLines]
  /// into a single "+N more" line.
  @visibleForTesting
  static List<XpLine> foldXpLines(List<XpLine> lines) {
    const prefix = 'Achievement: ';
    final achievements = lines.where((l) => l.label.startsWith(prefix));
    var out = lines;
    if (achievements.length >= 2) {
      final total = achievements.fold<int>(0, (sum, l) => sum + l.xp);
      out = <XpLine>[];
      var added = false;
      for (final l in lines) {
        if (!l.label.startsWith(prefix)) {
          out.add(l);
        } else if (!added) {
          out.add(XpLine('Achievements ×${achievements.length}', total));
          added = true;
        }
      }
    }
    if (out.length <= _maxLines) return out;
    final rest = out.sublist(_maxLines - 1);
    return [
      ...out.take(_maxLines - 1),
      XpLine(
        '${rest.length} more bonuses',
        rest.fold<int>(0, (sum, l) => sum + l.xp),
      ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crash
// ─────────────────────────────────────────────────────────────────────────────
