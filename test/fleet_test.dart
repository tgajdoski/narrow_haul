import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/fleet_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/fleet.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

import 'autopilot/harness.dart';
import 'helpers/levels.dart';
import 'helpers/pump.dart';

void main() {
  group('fleet rules (pure)', () {
    test('validator issues sort into one reason', () {
      expect(classifyFitIssues([]), ShipFit.ok);
      expect(classifyFitIssues(['TURRET: (3,4) but Kestrel is unarmed']), ShipFit.needsCannon);
      expect(classifyFitIssues(['LIFT: thrust/pull ratio 1.80 < 2.0']), ShipFit.lowLift);
      expect(classifyFitIssues(['FUEL: estimated burn 70% > 60%']), ShipFit.lowFuel);
      expect(classifyFitIssues(['UNREACHABLE: goal cannot be reached']), ShipFit.tooBig);
    });

    test('normalised fuel: the par ship is unchanged, range scales the burn', () {
      expect(normalisedFuelLeft(0.7, kKestrel, kKestrel), 0.7);
      // The Mule burns a smaller share of its bigger range: charged more.
      final mule = normalisedFuelLeft(0.8, kMule, kKestrel);
      expect(mule, closeTo(1 - 0.2 * kMule.deltaV / kKestrel.deltaV, 1e-9));
      expect(mule, lessThan(0.8));
      // The Hopper's small tank empties fast: charged less.
      expect(normalisedFuelLeft(0.4, kHopper, kKestrel), greaterThan(0.4));
    });

    test('ship stats stay in 0..1 and tell the ships apart', () {
      for (final s in kShips.values) {
        final st = ShipStats.of(s);
        for (final v in [st.lift, st.turn, st.range, st.steady, st.compact]) {
          expect(v, inInclusiveRange(0.0, 1.0), reason: s.id);
        }
      }
      expect(ShipStats.of(kMule).range, greaterThan(ShipStats.of(kHopper).range));
      expect(ShipStats.of(kHopper).turn, greaterThan(ShipStats.of(kMule).turn));
      expect(ShipStats.of(kHopper).compact, greaterThan(ShipStats.of(kKestrel).compact));
    });

    test('every ship but the Kestrel has a coin price and a world', () {
      for (final id in kFleetOrder) {
        expect(kShipEarnedIn[id], isNotNull, reason: id);
        if (id == kKestrel.id) continue;
        expect(kShipCoinPrice[id], greaterThan(0), reason: id);
      }
      expect(kFleetOrder.toSet(), kShips.keys.toSet());
    });
  });

  group('resolving the flown ship', () {
    final i = levelIndexOf('alien_02');
    final def = LevelRegistry.defAt(i);
    final par = LevelRegistry.shipFor(i);

    test('choice, then preferred, then par; only owned ships that fit', () {
      bool all(String _) => true;
      bool none(String _) => false;
      expect(resolveFlownShip(def: def, par: par, owns: all, choice: 'mule').id, 'mule');
      expect(
        resolveFlownShip(def: def, par: par, owns: all, choice: null, preferred: 'skate').id,
        'skate',
      );
      expect(resolveFlownShip(def: def, par: par, owns: none, choice: 'mule'), par);
      expect(resolveFlownShip(def: def, par: par, owns: all, choice: 'nope'), par);
    });

    test('an unarmed ship never flies a defended level', () {
      final r = levelIndexOf('redoubt_02');
      expect(shipFitOn(LevelRegistry.defAt(r), LevelRegistry.shipFor(r), kKestrel), ShipFit.needsCannon);
      expect(
        resolveFlownShip(
          def: LevelRegistry.defAt(r),
          par: LevelRegistry.shipFor(r),
          owns: (_) => true,
          choice: 'kestrel',
        ).id,
        'talon',
      );
    });

    test('type ratings fly the rated ship', () {
      for (var j = 0; j < LevelRegistry.totalLevels; j++) {
        final d = LevelRegistry.defAt(j);
        if (!isParOnly(d)) continue;
        expect(
          resolveFlownShip(def: d, par: LevelRegistry.shipFor(j), owns: (_) => true, choice: 'kestrel'),
          LevelRegistry.shipFor(j),
          reason: d.saveId,
        );
      }
    });

    test('tutorial maps take ships that fit with enough range', () {
      final t = LevelRegistry.defAt(levelIndexOf('tut_05'));
      expect(shipFitOn(t, kKestrel, kHopper), ShipFit.lowFuel);
      expect(shipFitOn(t, kKestrel, kTalon), ShipFit.ok);
    });
  });

  group('FleetService', () {
    setUp(freshSave);

    test('a new pilot owns the Kestrel only', () {
      expect(FleetService.owned.map((s) => s.id), ['kestrel']);
      expect(FleetService.sourceOf('kestrel'), ShipSource.stock);
      expect(FleetService.sourceOf('mule'), ShipSource.locked);
    });

    test('a type rating earns the ship', () async {
      await ProgressService.instance.saveStarsById('rating_hopper', 1);
      expect(FleetService.sourceOf('hopper'), ShipSource.rated);
    });

    test('coins buy a ship once, only when they cover it', () async {
      final p = ProgressService.instance;
      expect(await FleetService.buyWithCoins('mule'), isFalse);
      await p.addCosmeticCurrency(1000);
      expect(await FleetService.buyWithCoins('mule'), isTrue);
      expect(p.getCosmeticCurrency(), 1000 - kShipCoinPrice['mule']!);
      expect(FleetService.sourceOf('mule'), ShipSource.coins);
      expect(await FleetService.buyWithCoins('mule'), isFalse);
    });

    test('a bought ship flies where it fits, as chosen or by default', () async {
      final p = ProgressService.instance;
      await p.addCosmeticCurrency(1000);
      await FleetService.buyWithCoins('mule');
      final alien = levelIndexOf('alien_02');
      expect(FleetService.flownShipFor(alien).id, 'hopper');
      await FleetService.setPreferred('mule');
      expect(FleetService.flownShipFor(alien).id, 'mule');
      await FleetService.setChoice(alien, 'kestrel');
      expect(FleetService.flownShipFor(alien).id, 'kestrel');
      // The default never overrides a type rating.
      expect(FleetService.flownShipFor(levelIndexOf('rating_hopper')).id, 'hopper');
    });

    test('the Fleet Pass grants every ship and never removes ads', () async {
      final p = ProgressService.instance;
      await MonetizationService.instance.grant(ProductIds.fleetPass);
      expect(FleetService.ownsAll, isTrue);
      expect(FleetService.sourceOf('vector'), ShipSource.iap);
      expect(p.adsRemoved, isFalse);
      expect(p.hasPurchased, isTrue);
    });

    test('reset drops coin ships, keeps the Fleet Pass', () async {
      final p = ProgressService.instance;
      await p.addCosmeticCurrency(1000);
      await FleetService.buyWithCoins('skate');
      await p.resetProgress();
      expect(FleetService.owns('skate'), isFalse);
      await MonetizationService.instance.grant(ProductIds.fleetPass);
      await p.resetProgress();
      expect(FleetService.ownsAll, isTrue);
    });

    test('affordable and newly rated ships are news until seen', () async {
      final p = ProgressService.instance;
      expect(FleetService.fresh, isEmpty);
      await p.addCosmeticCurrency(kShipCoinPrice['hopper']!);
      expect(FleetService.fresh, ['hopper']);
      await FleetService.markSeen();
      expect(FleetService.fresh, isEmpty);
      await p.saveStarsById('rating_hopper', 2);
      expect(FleetService.fresh, ['hopper']);
    });
  });

  group('in the game', () {
    late GameHarness h;
    setUpAll(() async {
      h = GameHarness();
      await h.boot();
    });

    test('the default ship flies, stars scale by range, routes stay par', () async {
      final p = ProgressService.instance;
      await p.addCosmeticCurrency(2000);
      await FleetService.buyWithCoins('mule');
      await FleetService.setPreferred('mule');
      final alien = levelIndexOf('alien_02');
      await h.loadLevel(alien);
      final g = h.game;
      expect(g.ship!.spec.id, 'mule');
      expect(g.flyingParShip, isFalse);
      // 80% of the Mule's tank left is a much smaller share of the
      // Hopper's range: not a 3★ on fuel.
      final left = normalisedFuelLeft(0.8, kMule, kHopper);
      expect(left, lessThan(g.currentLevelDef.stars.star3Fuel));
      expect(g.debugStars(0.8, 1), lessThan(3));
      // A type rating flies its own ship whatever the default.
      await h.loadLevel(levelIndexOf('rating_hopper'));
      expect(g.ship!.spec.id, 'hopper');
      expect(g.flyingParShip, isTrue);
      expect(g.debugStars(1, 1), 3);
    });
  });
}
