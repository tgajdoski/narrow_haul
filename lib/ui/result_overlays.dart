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
import 'package:narrow_haul/ui/route_guide_overlays.dart';
import 'package:narrow_haul/ui/space_ui.dart';
import 'package:narrow_haul/ui/store_feedback.dart';
import 'package:narrow_haul/game/story/story.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mission complete
// ─────────────────────────────────────────────────────────────────────────────

/// 'levelComplete' overlay: stars, flight stats, coins and the XP breakdown,
/// laid out side by side so it fits a landscape phone.
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
  late final bool _showRemoveAdsOffer = _shouldOfferRemoveAds();

  /// Soft remove-ads offer: once the tutorial world is done (or after the
  /// first interstitial), at most every 3 days, never to payers.
  bool _shouldOfferRemoveAds() {
    final p = ProgressService.instance;
    final m = MonetizationService.instance;
    if (m.adsRemoved || p.hasPurchased || !m.canBuy(ProductIds.removeAds)) {
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
              Text(
                isChallengeMode ? 'CHALLENGE COMPLETE' : 'MISSION COMPLETE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
        if (_showRemoveAdsOffer) ...[
          const SizedBox(height: 8),
          HoloButton(
            label:
                'Remove ads · '
                '${MonetizationService.instance.priceOf(ProductIds.removeAds)}',
            icon: Icons.block_rounded,
            variant: HoloVariant.ghost,
            height: 34,
            fontSize: 10.5,
            onPressed: () async {
              await buyWithFeedback(context, ProductIds.removeAds);
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
                        child: Text(
                          lines[i].label,
                          maxLines: 1,
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
              'The ship touched the terrain.',
              textAlign: hasHelp ? TextAlign.start : TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              g.currentLevelDef.name,
              style: hudLabel(11, color: Colors.white38, spacing: 2),
            ),
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
              if (g.canResumeFromPad) ...[
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

/// Opt-in rewarded-ad button. Hidden until an ad is actually loaded, so a tap
/// always pays out; runs [onReward] only when the reward was earned.
class RewardedButton extends StatefulWidget {
  const RewardedButton({
    super.key,
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
  State<RewardedButton> createState() => _RewardedButtonState();
}

class _RewardedButtonState extends State<RewardedButton> {
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
        return HoloButton(
          label: widget.label,
          subtitle: widget.note,
          icon: widget.icon,
          accent: SpaceColors.gold,
          height: 48,
          fontSize: 13,
          onPressed: _busy ? null : _watch,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rank up
// ─────────────────────────────────────────────────────────────────────────────

/// 'rankUp' overlay, pushed over the results when a run crossed a rank.
class RankUpOverlay extends StatefulWidget {
  const RankUpOverlay({super.key, required this.game});
  final NarrowHaulGame game;

  @override
  State<RankUpOverlay> createState() => _RankUpOverlayState();
}

class _RankUpOverlayState extends State<RankUpOverlay>
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

  void _close() => widget.game.closeRankUp();

  /// Garage items handed out by every rank this run crossed.
  late final List<CosmeticItem> _unlocks = () {
    final reward = widget.game.lastRunReward;
    if (reward == null) return <CosmeticItem>[];
    return [
      for (var i = reward.rankBefore.index + 1; i <= reward.rankAfter.index; i++)
        ...unlocksAtRank(CosmeticsService.all, i),
    ];
  }();

  @override
  void initState() {
    super.initState();
    // Shown here, so the Garage doesn't flag them NEW again (unfitted gear
    // still says FIT).
    unawaited(GarageNotices.markSeen(_unlocks));
  }

  Future<void> _fit(CosmeticItem item) async {
    await CosmeticsService.equip(item);
    if (mounted) setState(() {});
  }

  Widget _unlockRow(CosmeticItem item) {
    final fitted = CosmeticsService.getSavedEquippedId(item.category) == item.id;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text(item.icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  isGear(item)
                      ? 'Free · new tow gear in your Garage'
                      : 'Free · in your Garage',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          if (fitted)
            HoloChip(
              icon: Icons.check_rounded,
              label: isGear(item) ? 'FITTED' : 'EQUIPPED',
              color: SpaceColors.gold,
            )
          else
            HoloButton(
              label: isGear(item) ? 'Fit now' : 'Use now',
              accent: SpaceColors.gold,
              height: 32,
              fontSize: 11,
              expand: false,
              onPressed: () => _fit(item),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reward = widget.game.lastRunReward;
    if (reward == null) return const SizedBox.shrink();
    final rank = reward.rankAfter;
    final scale = CurvedAnimation(parent: _anim, curve: Curves.elasticOut);
    final next = nextRank(rank);
    final nextItems =
        next == null ? const <CosmeticItem>[] : unlocksAtRank(CosmeticsService.all, next.index);

    return GestureDetector(
      onTap: () {
        AudioService.playUi(UiSound.select);
        _close();
      },
      child: HoloDialog(
        accent: SpaceColors.gold,
        maxWidth: 560,
        scrim: const Color(0xE6050816),
        child: Row(
          children: [
            ScaleTransition(
              scale: scale,
              child: RankBadge(kind: rank.insignia, size: 110),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PROMOTED',
                    style: hudLabel(13, color: SpaceColors.cyan, spacing: 6),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    rank.title.toUpperCase(),
                    style: hudLabel(24, color: SpaceColors.gold, spacing: 3)
                        .copyWith(
                          shadows: const [
                            Shadow(color: Color(0x88FFD166), blurRadius: 16),
                          ],
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
                        color: SpaceColors.green,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  for (final item in _unlocks) _unlockRow(item),
                  if (next != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Next: ${next.title} at ${next.minXp} XP'
                      '${nextItems.isEmpty ? '' : ' · ${nextItems.map((i) => i.name).join(', ')}'}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                    ),
                  ],
                  const SizedBox(height: 14),
                  HoloButton.primary(
                    label: 'Continue',
                    accent: SpaceColors.gold,
                    height: 44,
                    fontSize: 14,
                    expand: false,
                    onPressed: _close,
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
