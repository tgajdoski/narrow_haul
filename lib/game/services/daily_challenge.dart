import 'dart:math';

import 'package:narrow_haul/game/ship/ship_spec.dart';

/// Deterministic daily challenge generated from the current date.
class DailyChallengeConfig {
  const DailyChallengeConfig({
    required this.levelIndex,
    required this.gravityMultiplier,
    required this.fuelDrainMultiplier,
    required this.modifierName,
    required this.modifierDesc,
    this.shipId,
    this.chaos = false,
  });

  final int levelIndex;
  final double gravityMultiplier;
  final double fuelDrainMultiplier;
  final String modifierName;
  final String modifierDesc;

  /// "Test Flight" days fly this ship instead of the level's own.
  final String? shipId;

  /// "Salvage Chaos" days: three mystery caches, 50/50 boon or curse.
  final bool chaos;

  static const _modifiers = [
    ('Standard Run', 'Normal physics.', 1.0, 1.0),
    ('Low Gravity', 'Half gravity — floatier flight.', 0.5, 1.0),
    ('Heavy Haul', 'Extra gravity — heavier control.', 1.8, 1.0),
    ('Fuel Crisis', 'Twice the fuel burn rate.', 1.0, 2.0),
    ('Fuel Rich', 'Half the fuel burn rate.', 1.0, 0.5),
    (testFlightName, '', 1.0, 1.0),
    (chaosName, 'Three mystery caches. Boon or curse: 50/50.', 1.0, 1.0),
  ];

  static const testFlightName = 'Test Flight';
  static const chaosName = 'Salvage Chaos';

  /// [levels] are the flat level indices the player may be sent to (the
  /// unlocked ones, so a new pilot never lands in a late world); empty means
  /// level 0. [shipOptions] lists ship ids that may replace the level's own
  /// ship (see `testFlightShips`); with none, a Test Flight day falls back to
  /// a standard run.
  /// [chaosOk] says whether a level can hold mystery caches (cave levels);
  /// a chaos day on any other level is a standard run.
  static DailyChallengeConfig forToday(
    List<int> levels, {
    List<String> Function(int levelIndex)? shipOptions,
    bool Function(int levelIndex)? chaosOk,
  }) {
    final rng = _todayRng();
    final levelIndex = levels.isEmpty ? 0 : levels[rng.nextInt(levels.length)];
    var mod = _modifiers[rng.nextInt(_modifiers.length)];
    if (mod.$1 == chaosName && !(chaosOk?.call(levelIndex) ?? true)) {
      mod = _modifiers.first;
    }

    if (mod.$1 == testFlightName) {
      final options = shipOptions?.call(levelIndex) ?? const <String>[];
      if (options.isEmpty) {
        mod = _modifiers.first;
      } else {
        final ship = shipById(options[rng.nextInt(options.length)]);
        return DailyChallengeConfig(
          levelIndex: levelIndex,
          modifierName: testFlightName,
          modifierDesc: 'Fly the ${ship.name} today. ${ship.blurb}',
          gravityMultiplier: 1.0,
          fuelDrainMultiplier: 1.0,
          shipId: ship.id,
        );
      }
    }

    return DailyChallengeConfig(
      levelIndex: levelIndex,
      modifierName: mod.$1,
      modifierDesc: mod.$2,
      gravityMultiplier: mod.$3,
      fuelDrainMultiplier: mod.$4,
      chaos: mod.$1 == chaosName,
    );
  }

  static Random _todayRng() {
    final now = DateTime.now();
    return Random(now.year * 10000 + now.month * 100 + now.day);
  }

  /// Today's level and whether it's a Test Flight day — same draw as
  /// [forToday], so the (slow, validator-backed) ship options can be worked
  /// out first, off the UI thread, and only on the days that need them.
  static (int levelIndex, bool testFlight) peekToday(List<int> levels) {
    final rng = _todayRng();
    final levelIndex = levels.isEmpty ? 0 : levels[rng.nextInt(levels.length)];
    final mod = _modifiers[rng.nextInt(_modifiers.length)];
    return (levelIndex, mod.$1 == testFlightName);
  }
}
