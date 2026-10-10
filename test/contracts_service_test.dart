import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/contracts_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

DeliveryEvent _event({
  int world = 0,
  bool challenge = false,
  bool clean = true,
  double fuel = 0.5,
  double seconds = 90,
  int newStars = 0,
  bool pb = false,
}) =>
    DeliveryEvent(
      worldIndex: world,
      challenge: challenge,
      clean: clean,
      fuelFraction: fuel,
      seconds: seconds,
      newStars: newStars,
      personalBest: pb,
    );

void main() {
  group('generateContracts', () {
    test('is deterministic per date and picks 3 distinct kinds', () {
      final a = generateContracts(DateTime(2026, 10, 7),
          unlockedWorlds: [0, 1], starsRemaining: 50, dailyDone: false);
      final b = generateContracts(DateTime(2026, 10, 7),
          unlockedWorlds: [0, 1], starsRemaining: 50, dailyDone: false);
      expect(a.map((c) => c.encode()), b.map((c) => c.encode()));
      expect(a.length, 3);
      expect(a.map((c) => c.kind).toSet().length, 3);
    });

    test('never offers impossible contracts', () {
      for (int d = 1; d <= 60; d++) {
        final list = generateContracts(DateTime(2026, 1, d),
            unlockedWorlds: [0], starsRemaining: 0, dailyDone: true);
        for (final c in list) {
          expect(c.kind, isNot(ContractKind.earnStars));
          expect(c.kind, isNot(ContractKind.dailyChallenge));
          if (c.kind == ContractKind.deliverInWorld) expect(c.param, 0);
        }
      }
    });

    test('encode/decode round-trips', () {
      const c = Contract(ContractKind.deliverInWorld, target: 3, param: 2);
      final d = Contract.decode(c.encode())!;
      expect((d.kind, d.target, d.param), (c.kind, c.target, c.param));
      expect(Contract.decode('garbage'), isNull);
    });
  });

  test('contractProgress rules', () {
    const fuel = Contract(ContractKind.fuelFinish, target: 1, param: 70);
    expect(contractProgress(fuel, _event(fuel: 0.69)), 0);
    expect(contractProgress(fuel, _event(fuel: 0.70)), 1);

    const world = Contract(ContractKind.deliverInWorld, target: 2, param: 1);
    expect(contractProgress(world, _event(world: 0)), 0);
    expect(contractProgress(world, _event(world: 1)), 1);

    const stars = Contract(ContractKind.earnStars, target: 2);
    expect(contractProgress(stars, _event(newStars: 3)), 3);

    const quick = Contract(ContractKind.quickDelivery, target: 1, param: 45);
    expect(contractProgress(quick, _event(seconds: 44.9)), 1);

    const clean = Contract(ContractKind.cleanFlights, target: 2);
    expect(contractProgress(clean, _event(clean: false)), 0);
  });

  group('ContractsService', () {
    test('locked below Commercial Pilot', () async {
      SharedPreferences.setMockInitialValues({'save_v3': true, 'xp_total': 0});
      await ProgressService.init();
      expect(ContractsService.isUnlocked, isFalse);
      expect(ContractsService.today(), isEmpty);
    });

    test('completing all contracts pays each plus the bonus once', () async {
      SharedPreferences.setMockInitialValues({'save_v3': true, 'xp_total': 1200});
      await ProgressService.init();
      await ProgressService.instance.setTodayContracts([
        const Contract(ContractKind.cleanFlights, target: 2).encode(),
        const Contract(ContractKind.personalBest, target: 1).encode(),
        const Contract(ContractKind.fuelFinish, target: 1, param: 60).encode(),
      ]);

      var (lines, allDone) =
          await ContractsService.recordDelivery(_event(pb: true, fuel: 0.9));
      expect(lines.map((l) => l.xp), [100, 100]); // PB + fuel
      expect(allDone, isFalse);

      (lines, allDone) = await ContractsService.recordDelivery(_event());
      expect(lines.map((l) => l.xp), [75, kAllContractsBonusXp]);
      expect(allDone, isTrue);

      (lines, allDone) = await ContractsService.recordDelivery(_event(pb: true));
      expect(lines, isEmpty);
      expect(allDone, isFalse);
    });
  });

  group('turret contracts', () {
    test('turret contract counts kills and is gated on armed worlds', () {
      const c = Contract(ContractKind.destroyTurrets, target: 4);
      const e = DeliveryEvent(
        worldIndex: 6,
        challenge: false,
        clean: true,
        fuelFraction: 0.5,
        seconds: 60,
        newStars: 0,
        personalBest: false,
        turretsDestroyed: 3,
      );
      expect(contractProgress(c, e), 3);
      for (int d = 1; d <= 60; d++) {
        final list = generateContracts(DateTime(2026, 2, d),
            unlockedWorlds: [0], starsRemaining: 10, dailyDone: false);
        expect(list.map((c) => c.kind), isNot(contains(ContractKind.destroyTurrets)));
      }
      final offered = [
        for (int d = 1; d <= 60; d++)
          ...generateContracts(DateTime(2026, 2, d),
              unlockedWorlds: [0], starsRemaining: 10, dailyDone: false, armedUnlocked: true),
      ];
      expect(offered.map((c) => c.kind), contains(ContractKind.destroyTurrets));
    });
  });
}
