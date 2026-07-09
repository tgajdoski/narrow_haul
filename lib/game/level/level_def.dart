import 'package:narrow_haul/game/level/cave/level_spec.dart';

/// One playable level in the registry — either a rectangle-based TMX tutorial
/// map or an organic cave spec.
sealed class LevelDef {
  const LevelDef({
    required this.saveId,
    required this.name,
    required this.themeId,
    this.stars = const StarSpec(),
  });

  /// Stable progress key — survives reordering/insertion of levels.
  final String saveId;
  final String name;
  final String themeId;
  final StarSpec stars;

  LevelModifiers get modifiers;
}

class TmxLevelDef extends LevelDef {
  const TmxLevelDef({
    required super.saveId,
    required super.name,
    required this.assetPath,
    super.themeId = 'tutorial',
    super.stars,
  });

  final String assetPath;

  @override
  LevelModifiers get modifiers => const LevelModifiers();
}

class CaveLevelDef extends LevelDef {
  CaveLevelDef({required this.spec, super.stars})
      : super(saveId: spec.id, name: spec.name, themeId: spec.themeId);

  final LevelSpec spec;

  @override
  LevelModifiers get modifiers => spec.modifiers;
}

/// A themed pack of levels, gated by total stars earned.
class WorldDef {
  const WorldDef({
    required this.id,
    required this.name,
    required this.themeId,
    required this.starsRequired,
    required this.rewardPerStar,
    required this.levels,
  });

  final String id;
  final String name;
  final String themeId;

  /// Total stars needed to unlock this world's first level.
  final int starsRequired;

  /// Cosmetic currency granted per newly earned star in this world.
  final int rewardPerStar;
  final List<LevelDef> levels;
}
