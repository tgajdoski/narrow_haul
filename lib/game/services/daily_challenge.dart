import 'dart:math';

/// Deterministic daily challenge generated from the current date.
class DailyChallengeConfig {
  const DailyChallengeConfig({
    required this.levelIndex,
    required this.gravityMultiplier,
    required this.fuelDrainMultiplier,
    required this.modifierName,
    required this.modifierDesc,
  });

  final int levelIndex;
  final double gravityMultiplier;
  final double fuelDrainMultiplier;
  final String modifierName;
  final String modifierDesc;

  static const _modifiers = [
    ('Standard Run', 'Normal physics.', 1.0, 1.0),
    ('Low Gravity', 'Half gravity — floatier flight.', 0.5, 1.0),
    ('Heavy Haul', 'Extra gravity — heavier control.', 1.8, 1.0),
    ('Fuel Crisis', 'Twice the fuel burn rate.', 1.0, 2.0),
    ('Fuel Rich', 'Half the fuel burn rate.', 1.0, 0.5),
  ];

  static DailyChallengeConfig forToday(int totalLevels) {
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final rng = Random(seed);

    // Level cycles through available levels, weighted toward later ones for challenge
    final levelIndex = rng.nextInt(totalLevels);
    final mod = _modifiers[rng.nextInt(_modifiers.length)];

    return DailyChallengeConfig(
      levelIndex: levelIndex,
      modifierName: mod.$1,
      modifierDesc: mod.$2,
      gravityMultiplier: mod.$3,
      fuelDrainMultiplier: mod.$4,
    );
  }

  String get levelDisplay => 'Mission ${levelIndex + 1}';
}
