import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/fleet.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// How a ship joined the fleet (or that it hasn't).
enum ShipSource { stock, rated, coins, iap, locked }

/// Ship ownership and choice (rules in `ship/fleet.dart`). Every ship is
/// earned by play (its type rating), or bought early with coins or an IAP.
class FleetService {
  FleetService._();

  static ProgressService get _p => ProgressService.instance;

  static ShipSource sourceOf(String id) {
    if (id == kKestrel.id) return ShipSource.stock;
    if (LevelRegistry.hasTypeRating(id)) return ShipSource.rated;
    final product = ProductIds.forShip(id);
    if (_p.isProductGranted(ProductIds.fleetPass) ||
        (product != null && _p.isProductGranted(product))) {
      return ShipSource.iap;
    }
    if (_p.isShipBought(id)) return ShipSource.coins;
    return ShipSource.locked;
  }

  static bool owns(String id) => sourceOf(id) != ShipSource.locked;

  static List<ShipSpec> get fleet => [for (final id in kFleetOrder) kShips[id]!];

  static List<ShipSpec> get owned => [for (final s in fleet) if (owns(s.id)) s];

  static bool get ownsAll => fleet.every((s) => owns(s.id));

  static int? coinPrice(String id) => kShipCoinPrice[id];

  /// Buys [id] with coins. False if owned already, unpriced or too dear.
  static Future<bool> buyWithCoins(String id) async {
    final price = kShipCoinPrice[id];
    if (price == null || owns(id)) return false;
    if (_p.getCosmeticCurrency() < price) return false;
    await _p.spendCosmeticCurrency(price);
    await _p.setShipBought(id);
    Analytics.spendCoins(price, 'ship_$id');
    Analytics.shipUnlock(id, 'coins');
    return true;
  }

  /// The Garage's "Fly by default" ship (null: each level's own).
  static String? get preferred {
    final id = _p.preferredShip;
    return id != null && owns(id) ? id : null;
  }

  static Future<void> setPreferred(String? id) async {
    await _p.setPreferredShip(id);
    if (id != null) Analytics.shipSelected(id, 'garage');
  }

  static Future<void> setChoice(int flatIndex, String id) async {
    await _p.setShipChoice(LevelRegistry.defAt(flatIndex).saveId, id);
    Analytics.shipSelected(id, 'briefing');
  }

  /// Can [ship] fly the level at [flatIndex]?
  static ShipFit fitOn(int flatIndex, ShipSpec ship) => shipFitOn(
        LevelRegistry.defAt(flatIndex),
        LevelRegistry.shipFor(flatIndex),
        ship,
      );

  /// The ship flown on [flatIndex] outside dailies and demos.
  static ShipSpec flownShipFor(int flatIndex) {
    final def = LevelRegistry.defAt(flatIndex);
    return resolveFlownShip(
      def: def,
      par: LevelRegistry.shipFor(flatIndex),
      owns: owns,
      choice: _p.shipChoiceFor(def.saveId),
      preferred: _p.preferredShip,
    );
  }

  // ── Notices (keys share the Garage's `garage_seen`) ─────────────────────

  /// `ship_<id>:rated` once type-rated, `ship_<id>:afford` while locked and
  /// the coins cover it; null when there's nothing to tell.
  static String? noticeKey(String id) => switch (sourceOf(id)) {
        ShipSource.rated => 'ship_$id:rated',
        ShipSource.locked
            when _p.getCosmeticCurrency() >= (kShipCoinPrice[id] ?? 1 << 30) =>
          'ship_$id:afford',
        _ => null,
      };

  /// Ships with news the player hasn't looked at (Ships tab, hangar badge).
  static List<String> get fresh {
    final seen = _p.getGarageSeen();
    return [
      for (final id in kFleetOrder)
        if (noticeKey(id) case final k? when !seen.contains(k)) id,
    ];
  }

  static Future<void> markSeen() async {
    final keys = [for (final id in kFleetOrder) ?noticeKey(id)];
    if (keys.isNotEmpty) await _p.addGarageSeen(keys);
  }

  /// Missions [ship] can fly (its own and every one it passes).
  static int missionsFor(ShipSpec ship) {
    var n = 0;
    for (var i = 0; i < LevelRegistry.totalLevels; i++) {
      if (fitOn(i, ship).flies) n++;
    }
    return n;
  }
}
