import 'dart:math' as math;

import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

/// Epaulette / wings badge drawn for each rank (see `rank_insignia.dart`).
enum InsigniaKind {
  wingsOutline,
  wingsSilver,
  wingsGold,
  stripes1,
  stripes2,
  stripes3,
  stripes4,
  stripes4Star,
  stripes4Laurel,
  stripes4LaurelStar,
}

/// One step of the pilot career. Titles follow real civil aviation:
/// FAA certificate levels, then airline cockpit seniority.
class PilotRank {
  const PilotRank({
    required this.index,
    required this.title,
    required this.minXp,
    required this.insignia,
    required this.perk,
    this.currencyBonus = 0,
  });

  final int index;
  final String title;
  final int minXp;
  final InsigniaKind insignia;

  /// Human-readable reward shown on rank-up and in the logbook.
  final String perk;

  /// Extra cosmetic currency on star payouts (0.05 = +5%).
  final double currencyBonus;
}

/// The 10-rank ladder. XP past [kRanks.last] earns prestige stars.
const List<PilotRank> kRanks = [
  PilotRank(index: 0, title: 'Student Pilot', minXp: 0, insignia: InsigniaKind.wingsOutline, perk: 'Welcome aboard'),
  PilotRank(index: 1, title: 'Private Pilot', minXp: 400, insignia: InsigniaKind.wingsSilver, perk: 'Silver wings'),
  PilotRank(index: 2, title: 'Commercial Pilot', minXp: 1200, insignia: InsigniaKind.wingsGold, perk: '+5% currency · Daily contracts', currencyBonus: 0.05),
  PilotRank(index: 3, title: 'Second Officer', minXp: 2500, insignia: InsigniaKind.stripes1, perk: 'Braided rope', currencyBonus: 0.05),
  PilotRank(index: 4, title: 'First Officer', minXp: 4000, insignia: InsigniaKind.stripes2, perk: '+10% currency · Carbon ship', currencyBonus: 0.10),
  PilotRank(index: 5, title: 'Senior First Officer', minXp: 6000, insignia: InsigniaKind.stripes3, perk: 'Afterburner plume', currencyBonus: 0.10),
  PilotRank(index: 6, title: 'Captain', minXp: 8500, insignia: InsigniaKind.stripes4, perk: '+15% currency · Gold Trim ship', currencyBonus: 0.15),
  PilotRank(index: 7, title: 'Senior Captain', minXp: 11500, insignia: InsigniaKind.stripes4Star, perk: 'Command star', currencyBonus: 0.15),
  PilotRank(index: 8, title: 'Training Captain', minXp: 15000, insignia: InsigniaKind.stripes4Laurel, perk: 'Instructor laurels', currencyBonus: 0.15),
  PilotRank(index: 9, title: 'Chief Pilot', minXp: 20000, insignia: InsigniaKind.stripes4LaurelStar, perk: '+20% currency · Aurora plume', currencyBonus: 0.20),
];

/// XP per prestige star once the top rank is reached.
const int kPrestigeStepXp = 3000;

/// Cap on XP from runs that earn nothing new (replays), per calendar day.
const int kReplayXpDailyCap = 300;

PilotRank rankFor(int xp) {
  for (int i = kRanks.length - 1; i >= 0; i--) {
    if (xp >= kRanks[i].minXp) return kRanks[i];
  }
  return kRanks.first;
}

PilotRank? nextRank(PilotRank rank) =>
    rank.index + 1 < kRanks.length ? kRanks[rank.index + 1] : null;

int prestigeStars(int xp) {
  final top = kRanks.last.minXp;
  return xp < top ? 0 : (xp - top) ~/ kPrestigeStepXp;
}

/// (xp into current step, xp size of current step). At the top rank the step
/// is the next prestige star.
(int, int) stepProgress(int xp) {
  final rank = rankFor(xp);
  final next = nextRank(rank);
  if (next != null) return (xp - rank.minXp, next.minXp - rank.minXp);
  return ((xp - rank.minXp) % kPrestigeStepXp, kPrestigeStepXp);
}

/// 0..1 progress toward the next rank (or next prestige star).
double progressToNext(int xp) {
  final (into, size) = stepProgress(xp);
  return (into / size).clamp(0.0, 1.0);
}

/// Display title including prestige stars, e.g. "Chief Pilot ★2".
String rankTitle(int xp) {
  final stars = prestigeStars(xp);
  final title = rankFor(xp).title;
  return stars > 0 ? '$title ★$stars' : title;
}

/// One-off currency paid when reaching [rank].
int rankUpBonus(PilotRank rank) => 25 * rank.index;

/// Difficulty multiplier for XP: Training 1.0, then +0.5 per world.
double worldTier(int worldIndex) => 1.0 + 0.5 * worldIndex;

// ── Run XP ──────────────────────────────────────────────────────────────────

class XpLine {
  const XpLine(this.label, this.xp);
  final String label;
  final int xp;
}

class XpBreakdown {
  const XpBreakdown(this.lines);
  final List<XpLine> lines;
  int get total => lines.fold(0, (sum, l) => sum + l.xp);
}

/// Pure XP calculation for one successful delivery.
///
/// Runs that earn nothing new (replays, repeat dailies) draw from a shared
/// daily budget of [kReplayXpDailyCap] so easy levels can't be farmed.
XpBreakdown computeRunXp({
  required bool challenge,
  required bool firstClear,
  required int newStars,
  required double tier,
  required bool cleanFlight,
  required bool personalBest,
  bool dailyFirstToday = false,
  int dailyStreak = 0,
  int replayXpUsedToday = 0,
}) {
  final lines = <XpLine>[];
  bool progressRun;

  if (challenge) {
    progressRun = dailyFirstToday;
    if (dailyFirstToday) {
      lines.add(const XpLine('Daily challenge', 150));
      final streakDays = math.min(dailyStreak, 7);
      if (streakDays > 1) {
        lines.add(XpLine('Streak ×$streakDays', 25 * streakDays));
      }
    }
  } else {
    progressRun = firstClear || newStars > 0;
    if (firstClear) lines.add(XpLine('First delivery', (60 * tier).round()));
    if (newStars > 0) {
      lines.add(XpLine('New stars ×$newStars', (30 * tier * newStars).round()));
    }
    if (!progressRun) lines.add(XpLine('Repeat delivery', (10 * tier).round()));
    if (personalBest && !firstClear) lines.add(const XpLine('Personal best', 20));
  }
  if (cleanFlight) lines.add(const XpLine('Clean flight', 15));

  if (progressRun) return XpBreakdown(lines);

  // Replay: clip lines to what's left of today's budget.
  int budget = math.max(0, kReplayXpDailyCap - replayXpUsedToday);
  final clipped = <XpLine>[];
  for (final l in lines) {
    final xp = math.min(l.xp, budget);
    budget -= xp;
    if (xp > 0) clipped.add(XpLine(l.label, xp));
  }
  if (clipped.isEmpty) clipped.add(const XpLine('Daily replay XP limit reached', 0));
  return XpBreakdown(clipped);
}

// ── Career persistence ──────────────────────────────────────────────────────

/// Glue between XP math and [ProgressService].
abstract final class CareerService {
  static int get xp => ProgressService.instance.getXp();
  static PilotRank get rank => rankFor(xp);

  static double get currencyMultiplier => 1.0 + rank.currencyBonus;

  /// XP an existing save has already "earned", so players upgrading from a
  /// pre-rank build start at a fair rank instead of Student Pilot.
  static int backfillXp() {
    final progress = ProgressService.instance;
    double total = 0;
    for (int w = 0; w < LevelRegistry.worlds.length; w++) {
      final tier = worldTier(w);
      for (final def in LevelRegistry.worlds[w].levels) {
        final stars = progress.getStarsById(def.saveId);
        if (stars > 0) total += 60 * tier + 30 * tier * stars;
      }
    }
    final achievements = progress
        .getUnlockedAchievements()
        .where((id) => AchievementService.all.any((a) => a.id == id))
        .length;
    return total.round() + 100 * achievements;
  }

  /// One-time `save_v3` migration: seed XP from existing progress.
  static Future<void> migrateIfNeeded() async {
    final progress = ProgressService.instance;
    if (progress.isXpMigrated) return;
    if (progress.getXp() == 0) await progress.setXp(backfillXp());
    await progress.markXpMigrated();
  }
}
