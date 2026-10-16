import 'dart:async';
import 'dart:math' as math;

import 'package:narrow_haul/game/guidance/flight_guidance.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/salvage/salvage.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/contracts_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// First reactor escape on a level pays this XP and currency (once).
const int kReactorEscapeXp = 150;
const int kReactorEscapeCurrency = 40;

/// Everything a successful delivery paid out, for the level-complete screen.
class RunReward {
  const RunReward({
    required this.xp,
    required this.xpBefore,
    required this.xpAfter,
    required this.currency,
    required this.newAchievements,
    this.coinsBefore = 0,
    this.firstClear = false,
    this.personalBest = false,
    this.previousBestTime,
    this.newBestFuel = false,
    this.newFlawless = false,
  });

  final XpBreakdown xp;
  final int xpBefore;
  final int xpAfter;
  final int currency;
  final List<AchievementMeta> newAchievements;

  /// Coin balance before this payout (what it made affordable).
  final int coinsBefore;

  /// The level's first delivery (career levels only).
  final bool firstClear;

  /// Faster than the previous best, which was [previousBestTime].
  final bool personalBest;
  final double? previousBestTime;

  /// More fuel left than ever before on this level (not on a first clear).
  final bool newBestFuel;

  /// The level's first flawless delivery (3★, no scrape).
  final bool newFlawless;

  RunReward withCurrency(int value) => RunReward(
    xp: xp,
    xpBefore: xpBefore,
    xpAfter: xpAfter,
    currency: value,
    newAchievements: newAchievements,
    coinsBefore: coinsBefore,
    firstClear: firstClear,
    personalBest: personalBest,
    previousBestTime: previousBestTime,
    newBestFuel: newBestFuel,
    newFlawless: newFlawless,
  );

  PilotRank get rankBefore => rankFor(xpBefore);
  PilotRank get rankAfter => rankFor(xpAfter);
  bool get rankedUp => rankAfter.index > rankBefore.index;
}

/// The facts of one delivery the booking needs, read off the game when
/// ship and pod land.
class DeliveryFacts {
  const DeliveryFacts({
    required this.level,
    required this.levelIndex,
    required this.challenge,
    required this.challengeShipId,
    required this.stars,
    required this.seconds,
    required this.fuelLeft,
    required this.maxFuel,
    required this.attempt,
    required this.guided,
    required this.continued,
    required this.carriedAmmo,
    required this.mode,
    required this.shipId,
    required this.noseDownWarnings,
    required this.steer,
    required this.retried,
    required this.turretsDestroyed,
    required this.salvageOpened,
    required this.curses,
    required this.luckyCoins,
    required this.reactorEscape,
    required this.inFlightAchievements,
    required this.heldFire,
    required this.fields,
    required this.gravityG,
    required this.flyingParShip,
    required this.salvageEffect,
    required this.shipSizeMul,
    this.scrapes = 0,
    this.ratedFuel,
  });

  final LevelDef level;
  final int levelIndex;
  final bool challenge;

  /// The daily's Test Flight ship, if it is one.
  final String? challengeShipId;
  final int stars;
  final double seconds;

  /// Fuel left (units; an Expedition's mean over its pads) and the tank.
  final double fuelLeft;
  final double maxFuel;

  // Analytics.
  final int attempt;
  final bool guided;
  final bool continued;
  final bool carriedAmmo;
  final String mode;
  final String shipId;
  final int noseDownWarnings;
  final String steer;

  /// The level was retried this session (no clean-flight bonus).
  final bool retried;
  final int turretsDestroyed;
  final int salvageOpened;

  /// Curses flown this run (the last one names the Grit bonus).
  final List<SalvageSpec> curses;
  final int luckyCoins;
  final bool reactorEscape;

  /// Achievements unlocked mid-flight; their XP is paid with the delivery.
  final List<AchievementMeta> inFlightAchievements;

  /// An armed ship delivered a level with defences without firing.
  final bool heldFire;
  final List<FieldSpec> fields;
  final double gravityG;
  final bool flyingParShip;

  /// The salvage effect running at touchdown, and the hull size it left.
  final SalvageEffect? salvageEffect;
  final double shipSizeMul;

  /// Rock scrapes and touchdowns that weren't on the pad (flawless needs 0).
  final int scrapes;

  /// The fuel fraction the stars were rated on (normalised for an off-par
  /// ship); null means [fuelFraction].
  final double? ratedFuel;

  double get fuelFraction => fuelLeft / maxFuel;
}

/// What booking a delivery produced.
typedef DeliveryBooking = ({RunReward reward, bool dailyFirst});

/// Books a delivery: stars, best time, streaks, contracts, achievements,
/// XP and coins, and the analytics that go with them. No game state: the
/// game turns what it has into [DeliveryFacts] and shows the [RunReward].
abstract final class DeliveryBooker {
  static Future<DeliveryBooking> book(DeliveryFacts f) async {
    final progress = ProgressService.instance;
    final def = f.level;
    final stars = f.stars;
    final elapsed = f.seconds;
    final xpBefore = progress.getXp();
    final prevStars = f.challenge ? stars : progress.getStarsById(def.saveId);
    final worldsBefore = {
      for (final w in LevelRegistry.worlds)
        if (LevelRegistry.isWorldUnlocked(w)) w.id,
    };
    Analytics.levelEnd(
      levelId: def.saveId,
      stars: stars,
      prevStars: prevStars,
      attempt: f.attempt,
      seconds: elapsed,
      fuelLeft: f.fuelFraction,
      guided: f.guided,
      continued: f.continued,
      carriedAmmo: f.carriedAmmo,
      mode: f.mode,
      ship: f.shipId,
      noseDownWarnings: f.noseDownWarnings,
      steer: f.steer,
    );
    if (f.noseDownWarnings == 0) {
      final clean = progress.noseDownCleanFlights;
      if (clean < kNoseDownCleanFlights) {
        unawaited(progress.setNoseDownCleanFlights(clean + 1));
      }
    }
    final saveId = def.saveId;
    if (prevStars == 0 && saveId.startsWith('rating_')) {
      Analytics.shipUnlock(saveId.substring('rating_'.length), 'rating');
    }
    final currencyMul = CareerService.currencyMultiplier;
    int currency = 0;
    final XpBreakdown runXp;

    unawaited(progress.incrementStat(ProgressService.statDeliveries));
    unawaited(MonetizationService.instance.recordLevelClear());
    var dailyFirst = false;
    final (levelWorld, _) = LevelRegistry.worldOf(f.levelIndex);
    final worldIndex = LevelRegistry.worlds.indexOf(levelWorld);
    int earnedStars = 0;
    bool personalBest = false;
    bool firstClear = false;
    double? previousBestTime;
    bool newBestFuel = false;
    bool newFlawless = false;

    if (f.challenge) {
      final firstToday = !progress.isDailyChallengeComplete();
      dailyFirst = firstToday;
      int streak = progress.getDailyStreak();
      if (firstToday) {
        currency += (50 * currencyMul).round(); // Daily reward
        streak = await progress.advanceDailyStreak();
      }
      unawaited(progress.markDailyChallengeComplete());
      unawaited(progress.saveDailyBestTime(elapsed));
      runXp = computeRunXp(
        challenge: true,
        firstClear: false,
        newStars: 0,
        tier: 1,
        cleanFlight: !f.retried,
        personalBest: false,
        dailyFirstToday: firstToday,
        dailyStreak: streak,
        replayXpUsedToday: progress.getReplayXpToday(),
      );
      if (!firstToday) unawaited(progress.addReplayXpToday(runXp.total));
    } else {
      final prevStars = progress.getStarsById(def.saveId);
      final prevBest = progress.getBestTimeById(def.saveId);

      // Newly earned stars pay out cosmetic currency, scaled by world + rank.
      final newStars = stars - prevStars;
      earnedStars = math.max(0, newStars);
      personalBest = prevBest != null && elapsed < prevBest;
      previousBestTime = prevBest;
      firstClear = prevStars == 0;
      final rated = f.ratedFuel ?? f.fuelFraction;
      final prevFuel = progress.getBestFuelById(saveId);
      newBestFuel = prevFuel != null && !firstClear && rated > prevFuel + 0.005;
      unawaited(progress.saveBestFuelById(saveId, rated));
      if (stars >= 3 && f.scrapes == 0 && !progress.isFlawless(saveId)) {
        newFlawless = true;
        unawaited(progress.markFlawless(saveId));
      }
      if (newStars > 0) {
        currency += (newStars * levelWorld.rewardPerStar * currencyMul).round();
      }

      unawaited(progress.saveStarsById(def.saveId, stars));
      unawaited(progress.saveBestTimeById(def.saveId, elapsed));

      // No-retry streak
      if (!f.retried) {
        final streak = progress.getNoRetryStreak() + 1;
        unawaited(progress.setNoRetryStreak(streak));
      }

      runXp = computeRunXp(
        challenge: false,
        firstClear: prevStars == 0,
        newStars: earnedStars,
        tier: worldTier(worldIndex),
        cleanFlight: !f.retried,
        personalBest: personalBest,
        replayXpUsedToday: progress.getReplayXpToday(),
      );
      if (prevStars > 0 && newStars <= 0) {
        unawaited(progress.addReplayXpToday(runXp.total));
      }
    }

    final (
      contractLines,
      allContractsDone,
      contractCoins,
    ) = await ContractsService.recordDelivery(
      DeliveryEvent(
        worldIndex: worldIndex,
        challenge: f.challenge,
        clean: !f.retried,
        fuelFraction: f.fuelFraction,
        seconds: elapsed,
        newStars: earnedStars,
        personalBest: personalBest,
        turretsDestroyed: f.turretsDestroyed,
        salvageOpened: f.salvageOpened,
        cursed: f.curses.isNotEmpty,
      ),
    );
    currency += (contractCoins * currencyMul).round();

    // Reactor escape (Thrust's big finish): bonus the first time per level.
    final combatLines = <XpLine>[];
    if (f.reactorEscape) {
      unawaited(progress.incrementStat(ProgressService.statReactorEscapes));
      if (await progress.markOnce('reactor_${def.saveId}')) {
        combatLines.add(const XpLine('Reactor escape', kReactorEscapeXp));
        currency += (kReactorEscapeCurrency * currencyMul).round();
      }
    }

    // Mystery salvage: flying a curse home pays a little grit bonus.
    if (f.curses.isNotEmpty) {
      final curse = f.curses.last;
      combatLines.add(XpLine('Grit: ${_titleCase(curse.name)}', kSalvageGritXp));
      currency += (kSalvageGritCoins * currencyMul).round();
      unawaited(progress.incrementStat(ProgressService.statSalvageGrit));
    }
    if (f.luckyCoins > 0) currency += (f.luckyCoins * currencyMul).round();

    final unlocked = [
      ...f.inFlightAchievements,
      ...await _checkAchievements(f, allContractsDone: allContractsDone),
    ];
    var xp = XpBreakdown([
      ...runXp.lines,
      ...combatLines,
      ...contractLines,
      for (final a in unlocked) XpLine('Achievement: ${a.title}', 100),
    ]);

    // Rank achievements depend on the XP just earned (and pay XP themselves).
    final rankUnlocks = await _checkRankAchievements(
      rankFor(xpBefore + xp.total),
    );
    if (rankUnlocks.isNotEmpty) {
      unlocked.addAll(rankUnlocks);
      xp = XpBreakdown([
        ...xp.lines,
        for (final a in rankUnlocks) XpLine('Achievement: ${a.title}', 100),
      ]);
    }
    final xpAfter = xpBefore + xp.total;
    await progress.setXp(xpAfter);

    // Each rank crossed pays its one-off bonus.
    for (
      int i = rankFor(xpBefore).index + 1;
      i <= rankFor(xpAfter).index;
      i++
    ) {
      currency += rankUpBonus(kRanks[i]);
    }
    final coinsBefore = progress.getCosmeticCurrency();
    if (currency > 0) unawaited(progress.addCosmeticCurrency(currency));

    if (currency > 0) Analytics.earnCoins(currency, 'delivery');
    final rankAfter = rankFor(xpAfter);
    if (rankAfter.index > rankFor(xpBefore).index) {
      Analytics.rankUp(rankAfter.index, rankAfter.title);
    }
    for (final a in unlocked) {
      Analytics.achievement(a.id);
    }
    if (def == LevelRegistry.trainingFinale && prevStars == 0) {
      Analytics.tutorialComplete();
    }
    for (final w in LevelRegistry.worlds) {
      if (!worldsBefore.contains(w.id) && LevelRegistry.isWorldUnlocked(w)) {
        Analytics.worldUnlocked(w.id);
      }
    }

    return (
      reward: RunReward(
        xp: xp,
        xpBefore: xpBefore,
        xpAfter: xpAfter,
        currency: currency,
        newAchievements: unlocked,
        coinsBefore: coinsBefore,
        firstClear: firstClear,
        personalBest: personalBest,
        previousBestTime: previousBestTime,
        newBestFuel: newBestFuel,
        newFlawless: newFlawless,
      ),
      dailyFirst: dailyFirst,
    );
  }

  /// Runs the post-win achievement checks; returns the newly unlocked ones.
  static Future<List<AchievementMeta>> _checkAchievements(
    DeliveryFacts f, {
    required bool allContractsDone,
  }) async {
    final progress = ProgressService.instance;
    final candidates = <String>[AchievementIds.firstHaul];
    final stars = f.stars;

    if (f.reactorEscape) candidates.add(AchievementIds.meltdownEscape);
    if (f.heldFire) candidates.add(AchievementIds.holdFire);

    if (f.fuelLeft >= 0.85 * f.maxFuel) candidates.add(AchievementIds.fuelMiser);
    if (f.seconds < 30) candidates.add(AchievementIds.speedHauler);

    final streak = progress.getNoRetryStreak();
    if (!f.retried && streak >= 5) {
      candidates.add(AchievementIds.noScratch);
    }

    int completed = 0;
    bool allPerfect = true;
    for (final def in LevelRegistry.career) {
      final s = progress.getStarsById(def.saveId);
      if (s > 0) completed++;
      if (s < 3) allPerfect = false;
    }
    if (completed >= 10) candidates.add(AchievementIds.level10);
    if (completed >= LevelRegistry.careerLevels) {
      candidates.add(AchievementIds.level20);
    }

    if (f.challenge) candidates.add(AchievementIds.dailyPilot);
    if (f.challenge && f.challengeShipId != null) {
      candidates.add(AchievementIds.testPilot);
    }

    // Flight-condition achievements.
    if (stars >= 3 && f.fields.any((x) => x is WindZoneSpec)) {
      candidates.add(AchievementIds.stormRider);
    }
    if (stars >= 3 && f.fields.any((x) => x is GravityWellSpec)) {
      candidates.add(AchievementIds.orbitalMechanic);
    }
    if (f.gravityG >= 1.5) candidates.add(AchievementIds.heavyLifter);
    if (stars >= 3 && !f.challenge && !f.flyingParShip) {
      candidates.add(AchievementIds.offType);
    }
    if (kShips.keys.every(LevelRegistry.hasTypeRating)) {
      candidates.add(AchievementIds.fleetQualified);
    }

    if (allPerfect) candidates.add(AchievementIds.perfectPilot);
    if (stars >= 3 && !f.challenge) {
      final (world, _) = LevelRegistry.worldOf(f.levelIndex);
      if (world.levels.every((d) => progress.isFlawless(d.saveId))) {
        candidates.add(AchievementIds.flawlessWorld);
      }
    }

    if (allContractsDone) candidates.add(AchievementIds.fullManifest);
    // Mystery salvage: delivered mid-curse.
    if (f.salvageEffect == SalvageEffect.swarmSting && f.shipSizeMul > 1.05) {
      candidates.add(AchievementIds.beeLieveIt);
    }
    if (f.salvageEffect == SalvageEffect.sporeTrip) {
      candidates.add(AchievementIds.badTrip);
    }
    if (progress.getDailyStreak() >= 7) {
      candidates.add(AchievementIds.weekOnDuty);
    }
    if (progress.getStat(ProgressService.statDeliveries) >= 100) {
      candidates.add(AchievementIds.centuryHauler);
    }

    final unlocked = <AchievementMeta>[];
    for (final id in candidates) {
      if (await AchievementService.unlock(id)) {
        unlocked.add(AchievementService.all.firstWhere((a) => a.id == id));
      }
    }
    return unlocked;
  }

  static Future<List<AchievementMeta>> _checkRankAchievements(
    PilotRank rank,
  ) async {
    final unlocked = <AchievementMeta>[];
    for (final (id, minRank) in [
      (AchievementIds.rankCommercial, 2),
      (AchievementIds.rankCaptain, 6),
      (AchievementIds.rankChief, 9),
    ]) {
      if (rank.index >= minRank && await AchievementService.unlock(id)) {
        unlocked.add(AchievementService.byId(id));
      }
    }
    return unlocked;
  }
}

String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');
