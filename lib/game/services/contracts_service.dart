import 'dart:math';

import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// Contracts ("flying for hire") unlock with the Commercial Pilot licence.
const int kContractsRankIndex = 2;

/// Bonus for finishing all of a day's contracts.
const int kAllContractsBonusXp = 100;

enum ContractKind {
  deliverInWorld,
  fuelFinish,
  cleanFlights,
  personalBest,
  earnStars,
  quickDelivery,
  dailyChallenge,
  destroyTurrets,
}

/// One daily task. [param] meaning depends on [kind]: world index, fuel %, or
/// a time limit in seconds.
class Contract {
  const Contract(this.kind, {required this.target, this.param = 0});

  final ContractKind kind;
  final int target;
  final int param;

  int get xp => switch (kind) {
        ContractKind.deliverInWorld => 100,
        ContractKind.fuelFinish => 100,
        ContractKind.cleanFlights => 75,
        ContractKind.personalBest => 100,
        ContractKind.earnStars => 150,
        ContractKind.quickDelivery => 100,
        ContractKind.dailyChallenge => 75,
        ContractKind.destroyTurrets => 100,
      };

  String get description => switch (kind) {
        ContractKind.deliverInWorld =>
          'Deliver $target cargos in ${LevelRegistry.worlds[param].name}',
        ContractKind.fuelFinish =>
          target == 1 ? 'Land with ≥ $param% fuel' : 'Land $target times with ≥ $param% fuel',
        ContractKind.cleanFlights => '$target deliveries without crashing',
        ContractKind.personalBest => 'Beat a personal best time',
        ContractKind.earnStars => 'Earn $target new stars',
        ContractKind.quickDelivery => 'Deliver in under ${param}s',
        ContractKind.dailyChallenge => "Complete today's daily challenge",
        ContractKind.destroyTurrets => 'Destroy $target turrets and deliver',
      };

  String encode() => '${kind.name}|$target|$param';

  static Contract? decode(String raw) {
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    final kind = ContractKind.values.where((k) => k.name == parts[0]).firstOrNull;
    final target = int.tryParse(parts[1]);
    final param = int.tryParse(parts[2]);
    if (kind == null || target == null || param == null) return null;
    if (kind == ContractKind.deliverInWorld &&
        (param < 0 || param >= LevelRegistry.worlds.length)) {
      return null;
    }
    return Contract(kind, target: target, param: param);
  }
}

/// What happened in one successful delivery, for contract progress.
class DeliveryEvent {
  const DeliveryEvent({
    required this.worldIndex,
    required this.challenge,
    required this.clean,
    required this.fuelFraction,
    required this.seconds,
    required this.newStars,
    required this.personalBest,
    this.turretsDestroyed = 0,
  });

  final int worldIndex;
  final bool challenge;
  final bool clean;
  final double fuelFraction;
  final double seconds;
  final int newStars;
  final bool personalBest;
  final int turretsDestroyed;
}

/// Progress a single delivery adds to [c] (pure).
int contractProgress(Contract c, DeliveryEvent e) => switch (c.kind) {
      ContractKind.deliverInWorld => e.worldIndex == c.param ? 1 : 0,
      ContractKind.fuelFinish => e.fuelFraction * 100 >= c.param ? 1 : 0,
      ContractKind.cleanFlights => e.clean ? 1 : 0,
      ContractKind.personalBest => e.personalBest ? 1 : 0,
      ContractKind.earnStars => e.newStars,
      ContractKind.quickDelivery => e.seconds < c.param ? 1 : 0,
      ContractKind.dailyChallenge => e.challenge ? 1 : 0,
      ContractKind.destroyTurrets => e.turretsDestroyed,
    };

/// Deterministic pick of 3 contracts for [date] (pure). Only offers what the
/// player can actually do: unlocked worlds, stars still left to earn, and a
/// daily challenge not yet completed.
List<Contract> generateContracts(
  DateTime date, {
  required List<int> unlockedWorlds,
  required int starsRemaining,
  required bool dailyDone,
  bool armedUnlocked = false,
}) {
  final rng = Random(date.year * 10000 + date.month * 100 + date.day + 7919);
  final pool = <Contract>[
    if (unlockedWorlds.isNotEmpty)
      Contract(
        ContractKind.deliverInWorld,
        target: 2 + rng.nextInt(2),
        param: unlockedWorlds[rng.nextInt(unlockedWorlds.length)],
      ),
    Contract(ContractKind.fuelFinish, target: 1, param: [60, 70, 80][rng.nextInt(3)]),
    Contract(ContractKind.cleanFlights, target: 2 + rng.nextInt(2)),
    const Contract(ContractKind.personalBest, target: 1),
    if (starsRemaining >= 2) const Contract(ContractKind.earnStars, target: 2),
    Contract(ContractKind.quickDelivery, target: 1, param: [40, 45, 50][rng.nextInt(3)]),
    if (!dailyDone) const Contract(ContractKind.dailyChallenge, target: 1),
    if (armedUnlocked) Contract(ContractKind.destroyTurrets, target: 4 + rng.nextInt(3)),
  ]..shuffle(rng);
  return pool.take(3).toList();
}

class ContractStatus {
  const ContractStatus(this.contract, this.progress);
  final Contract contract;
  final int progress;
  bool get done => progress >= contract.target;
}

/// Persistence glue: today's contracts are generated once and stored, so they
/// don't reshuffle when the player unlocks a world mid-day.
abstract final class ContractsService {
  static bool get isUnlocked => CareerService.rank.index >= kContractsRankIndex;

  static List<ContractStatus> today() {
    if (!isUnlocked) return const [];
    final progress = ProgressService.instance;
    var raw = progress.getTodayContracts();
    if (raw == null) {
      final unlocked = [
        for (int i = 0; i < LevelRegistry.worlds.length; i++)
          if (LevelRegistry.isWorldUnlocked(LevelRegistry.worlds[i])) i,
      ];
      raw = generateContracts(
        DateTime.now(),
        unlockedWorlds: unlocked,
        starsRemaining: LevelRegistry.totalLevels * 3 - LevelRegistry.totalStars(),
        dailyDone: progress.isDailyChallengeComplete(),
        armedUnlocked: LevelRegistry.worlds.any((w) =>
            shipById(w.defaultShipId).armed && LevelRegistry.isWorldUnlocked(w)),
      ).map((c) => c.encode()).toList();
      progress.setTodayContracts(raw);
    }
    final result = <ContractStatus>[];
    for (int i = 0; i < raw.length; i++) {
      final c = Contract.decode(raw[i]);
      if (c != null) result.add(ContractStatus(c, progress.getContractProgress(i)));
    }
    return result;
  }

  /// Applies a delivery to today's contracts. Returns XP lines for contracts
  /// it completed (plus the bonus), and whether it finished the day's set.
  static Future<(List<XpLine>, bool allDone)> recordDelivery(
    DeliveryEvent event,
  ) async {
    final statuses = today();
    if (statuses.isEmpty) return (const <XpLine>[], false);
    final progress = ProgressService.instance;
    final lines = <XpLine>[];
    for (int i = 0; i < statuses.length; i++) {
      final s = statuses[i];
      if (s.done) continue;
      final add = contractProgress(s.contract, event);
      if (add <= 0) continue;
      final next = min(s.progress + add, s.contract.target);
      await progress.setContractProgress(i, next);
      if (next >= s.contract.target) {
        lines.add(XpLine('Contract: ${s.contract.description}', s.contract.xp));
      }
    }
    final allDone = lines.isNotEmpty && today().every((s) => s.done);
    if (allDone) {
      lines.add(const XpLine('All contracts done', kAllContractsBonusXp));
    }
    return (lines, allDone);
  }
}
