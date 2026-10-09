import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';

/// What a Garage tile is flagged with.
enum GarageMark {
  none,

  /// Rank reached: free and owned, not looked at yet.
  newUnlock,

  /// Enough coins to buy it, not looked at since it became affordable.
  affordable,

  /// Tow gear or a handling kit the player owns but has never flown with.
  notFitted,
}

/// The nearest thing in the Garage to work towards.
class GarageGoal {
  const GarageGoal(this.item, {this.coinsToGo = 0, this.xpToGo = 0});
  final CosmeticItem item;
  final int coinsToGo;
  final int xpToGo;

  bool get byRank => xpToGo > 0;

  /// e.g. "Tow Chain · 30 💰 to go" or "Long Line · free at Second Officer".
  String get label => byRank
      ? '${item.name} · free at ${item.requiredRank.title}'
      : '${item.name} · $coinsToGo 💰 to go';
}

/// Gameplay gear (changes how the ship flies) as opposed to looks.
bool isGear(CosmeticItem i) =>
    i.category == CosmeticsService.catRope || i.category == CosmeticsService.catKit;

/// Pure view of the Garage for notices: what's new, affordable, owned but
/// never fitted, and what to save for next. Built from plain values so
/// tests don't need prefs ([GarageNotices.current] builds the live one).
class GarageSnapshot {
  GarageSnapshot({
    required this.items,
    required this.owned,
    required this.rankIndex,
    required this.xp,
    required this.coins,
    required this.seen,
    required this.fitted,
    required this.equipped,
  });

  final List<CosmeticItem> items;

  /// Ids the player can equip (bought, granted, default, rank reached).
  final Set<String> owned;
  final int rankIndex;
  final int xp;
  final int coins;

  /// State keys already shown to the player ([stateKey]).
  final Set<String> seen;

  /// Gear ids the player has equipped at some point.
  final Set<String> fitted;

  /// Category → the player's own equipped id (trials excluded).
  final Map<String, String> equipped;

  bool _isDefault(CosmeticItem i) => i.cost == 0 && i.rankRequired == 0;

  /// The notice-worthy state an item is in, or null when there's nothing
  /// to tell. A new state (affordable → rank-unlocked, ...) is a new key,
  /// so the item is flagged again.
  String? stateKey(CosmeticItem i) {
    if (i.supporterOnly || _isDefault(i)) return null;
    if (i.rankRequired > 0 && rankIndex >= i.rankRequired) return '${i.id}:rank';
    if (owned.contains(i.id)) return null;
    if (i.rankRequired > rankIndex) return null;
    if (i.cost > 0 && i.cost <= coins) return '${i.id}:afford';
    return null;
  }

  bool isFresh(CosmeticItem i) {
    final k = stateKey(i);
    return k != null && !seen.contains(k);
  }

  bool isUnusedGear(CosmeticItem i) =>
      isGear(i) &&
      !_isDefault(i) &&
      owned.contains(i.id) &&
      equipped[i.category] != i.id &&
      !fitted.contains(i.id);

  GarageMark markFor(CosmeticItem i) {
    if (isFresh(i)) {
      return stateKey(i)!.endsWith(':rank') ? GarageMark.newUnlock : GarageMark.affordable;
    }
    if (isUnusedGear(i)) return GarageMark.notFitted;
    return GarageMark.none;
  }

  List<CosmeticItem> get fresh => [for (final i in items) if (isFresh(i)) i];

  List<CosmeticItem> get unusedGear => [for (final i in items) if (isUnusedGear(i)) i];

  /// Fresh items in one Garage tab.
  bool tabHasNews(String category) =>
      items.any((i) => i.category == category && (isFresh(i) || isUnusedGear(i)));

  /// Gear first (it changes the game), then the nearest rank unlock, then
  /// the cheapest look still out of reach.
  GarageGoal? get nextGoal {
    CosmeticItem? cheapest(bool Function(CosmeticItem) where) {
      CosmeticItem? best;
      for (final i in items) {
        if (i.supporterOnly || owned.contains(i.id) || i.rankRequired > rankIndex) continue;
        if (i.cost <= coins || !where(i)) continue;
        if (best == null || i.cost < best.cost) best = i;
      }
      return best;
    }

    final gear = cheapest(isGear);
    if (gear != null) return GarageGoal(gear, coinsToGo: gear.cost - coins);

    CosmeticItem? rankItem;
    for (final i in items) {
      if (i.rankRequired <= rankIndex) continue;
      if (rankItem == null || i.rankRequired < rankItem.rankRequired) rankItem = i;
    }
    if (rankItem != null) {
      return GarageGoal(rankItem, xpToGo: (rankItem.requiredRank.minXp - xp).clamp(1, 1 << 30));
    }

    final look = cheapest((_) => true);
    if (look != null) return GarageGoal(look, coinsToGo: look.cost - coins);
    return null;
  }
}

/// Items a payout made affordable: cost in (before, after], not owned yet.
/// Gear first, then by price.
List<CosmeticItem> newlyAffordable(
  List<CosmeticItem> items, {
  required int before,
  required int after,
  required Set<String> owned,
  required int rankIndex,
}) {
  final out = [
    for (final i in items)
      if (!i.supporterOnly &&
          !owned.contains(i.id) &&
          i.rankRequired <= rankIndex &&
          i.cost > before &&
          i.cost <= after)
        i,
  ];
  out.sort((a, b) {
    final g = (isGear(a) ? 0 : 1) - (isGear(b) ? 0 : 1);
    return g != 0 ? g : a.cost.compareTo(b.cost);
  });
  return out;
}

/// Garage items a rank hands out (free once reached). None for the first
/// rank: its items are the stock fit everyone starts with.
List<CosmeticItem> unlocksAtRank(List<CosmeticItem> items, int rankIndex) => [
      if (rankIndex > 0)
        for (final i in items) if (i.rankRequired == rankIndex) i,
    ];

/// Live glue: builds a [GarageSnapshot] from the services and records what
/// the player has looked at.
abstract final class GarageNotices {
  static GarageSnapshot current() {
    final p = ProgressService.instance;
    const items = CosmeticsService.all;
    return GarageSnapshot(
      items: items,
      owned: {for (final i in items) if (CosmeticsService.isUnlocked(i)) i.id},
      rankIndex: CareerService.rank.index,
      xp: CareerService.xp,
      coins: p.getCosmeticCurrency(),
      seen: p.getGarageSeen(),
      fitted: {for (final i in items) if (isGear(i) && p.isGearFitted(i.id)) i.id},
      equipped: {
        for (final c in const [
          CosmeticsService.catShip,
          CosmeticsService.catRope,
          CosmeticsService.catKit,
          CosmeticsService.catPlume,
        ])
          c: CosmeticsService.getSavedEquippedId(c),
      },
    );
  }

  /// The player has looked at [items] (a Garage tab, a rank-up card).
  static Future<void> markSeen(Iterable<CosmeticItem> items) async {
    final snap = current();
    final keys = [for (final i in items) ?snap.stateKey(i)];
    if (keys.isEmpty) return;
    await ProgressService.instance.addGarageSeen(keys);
  }
}
