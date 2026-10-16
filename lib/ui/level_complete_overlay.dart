import 'dart:async';

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/games_service.dart';
import 'package:narrow_haul/game/services/garage_notices.dart';
import 'package:narrow_haul/game/services/haptics.dart';
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
    with TickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  /// The coin chip counting up (from [_coinFrom] to the payout).
  late final AnimationController _coins = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  int _coinFrom = 0;
  int _coinShown = -1;
  int _lastTickMs = 0;

  /// Result-screen beats on [_anim]'s 0–1 timeline: each earned star pops
  /// at [starAt], the jingle follows the last one, then coins and the best
  /// badge.
  static double starAt(int i) => 0.05 + i * 0.1;
  static double flourishAt(int stars) => starAt(stars.clamp(1, 3) - 1) + 0.12;
  static const double coinsAt = 0.42;
  static const double badgeAt = 0.5;
  double _lastT = 0;

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

  void _onBeat() {
    final t = _anim.value;
    final prev = _lastT;
    _lastT = t;
    bool crossed(double at) => prev < at && t >= at;
    final stars = widget.game.lastLevelStars;
    for (var i = 0; i < stars && i < 3; i++) {
      if (crossed(starAt(i))) {
        AudioService.playStarPop(i);
        Haptics.light();
      }
    }
    if (stars > 0 && crossed(flourishAt(stars))) {
      AudioService.playStar(volume: stars >= 2 ? 0.8 : 0.45);
    }
    final reward = widget.game.lastRunReward;
    if (crossed(coinsAt) && (reward?.currency ?? 0) > 0) {
      unawaited(_coins.forward(from: 0));
    }
    if (crossed(badgeAt) && _badge(reward) != null) {
      AudioService.playAchievement();
      Haptics.medium();
    }
  }

  void _onCoinTick() {
    final shown = _coinValue;
    if (shown == _coinShown) return;
    _coinShown = shown;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTickMs >= 45 || _coins.isCompleted) {
      _lastTickMs = now;
      AudioService.playCoinTick();
    }
  }

  int get _coinValue {
    final to = widget.game.lastRunReward?.currency ?? 0;
    final k = Curves.easeOut.transform(_coins.value);
    return (_coinFrom + (to - _coinFrom) * k).round();
  }

  /// One gold line for what this run beat: FLAWLESS (3★, no scrape), a new
  /// best time with the seconds saved, else a new best fuel.
  String? _badge(RunReward? r) {
    if (r == null) return null;
    final prev = r.previousBestTime;
    final saved = prev == null ? 0.0 : prev - widget.game.lastLevelTimeSeconds;
    final parts = <String>[
      if (r.newFlawless) 'FLAWLESS',
      if (r.personalBest && prev != null)
        'NEW BEST −${saved.toStringAsFixed(1)} s',
      if (!r.personalBest && r.newBestFuel) 'BEST FUEL',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  void initState() {
    super.initState();
    _anim.addListener(_onBeat);
    _coins.addListener(_onCoinTick);
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
    _coins.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final stars = game.lastLevelStars;
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
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _stars(stars),
            // What this run beat, popping in under the stars.
            if (_badge(reward) case final badge?)
              AnimatedBuilder(
                animation: _anim,
                builder: (context, child) {
                  final t = ((_anim.value - badgeAt) / 0.18).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: t > 0 ? 1 : 0,
                    child: Transform.scale(
                      scale: t > 0 ? Curves.elasticOut.transform(t) : 1,
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 1, right: 4),
                  child: Text(
                    badge,
                    style: hudLabel(10, color: SpaceColors.gold, spacing: 1.5)
                        .copyWith(
                          shadows: const [
                            Shadow(color: Color(0x88FFD166), blurRadius: 10),
                          ],
                        ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    return _buildBody(context, header);
  }

  Widget _stars(int stars) {
    // Stars pop in one after another (earned ones only).
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final start = starAt(i);
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
    );
  }

  Widget _buildBody(BuildContext context, Widget header) {
    final game = widget.game;
    final stars = game.lastLevelStars;
    final time = game.lastLevelTimeSeconds;
    final isLastLevel = game.levelIndex >= LevelRegistry.totalLevels - 1;
    final isChallengeMode = game.isChallengeMode;
    final reward = game.lastRunReward;

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
            for (final a in reward?.newAchievements ?? const [])
              HoloChip(
                leading: Text(a.icon, style: const TextStyle(fontSize: 12)),
                label: a.title,
                color: SpaceColors.gold,
              ),
            if (reward != null && reward.currency > 0)
              AnimatedBuilder(
                animation: _coins,
                builder: (context, _) => HoloChip(
                  leading: const Text('💰', style: TextStyle(fontSize: 12)),
                  // Counts up from 0 (last in the row, so growing never
                  // pushes the other chips about).
                  label: '+$_coinValue',
                  color: SpaceColors.green,
                  highlight: true,
                ),
              ),
          ],
        ),
        for (final n in notes) ...[
          const SizedBox(height: 6),
          Text(
            n,
            style: TextStyle(
              color:
                  n.startsWith('★') ||
                      n.startsWith('Enjoying') ||
                      n.startsWith(_garageNotePrefix)
                  ? const Color(0xCCFFD166)
                  : Colors.white38,
              fontSize: 12,
            ),
          ),
        ],
        if (isChallengeMode &&
            GamesService.dailyBoardAvailable(NarrowHaulGame.dispatchTier())) ...[
          const SizedBox(height: 8),
          HoloButton(
            key: const ValueKey('daily-board'),
            label: "Today's board · ${NarrowHaulGame.dispatchTier().title} pilots",
            icon: Icons.leaderboard_rounded,
            variant: HoloVariant.ghost,
            height: 34,
            fontSize: 10.5,
            onPressed: () => GamesService.showDailyLeaderboard(NarrowHaulGame.dispatchTier()),
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
              final before = game.lastRunReward?.currency ?? 0;
              await game.doubleRunCurrency();
              if (!mounted) return;
              setState(() => _coinFrom = before);
              unawaited(_coins.forward(from: 0));
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
