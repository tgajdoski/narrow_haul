import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/cave/level_validator.dart';
import 'package:narrow_haul/game/level/level_data.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/specs/world_alien.dart';
import 'package:narrow_haul/game/level/specs/world_ice.dart';
import 'package:narrow_haul/game/level/specs/world_lava.dart';
import 'package:narrow_haul/game/level/specs/world_mine.dart';
import 'package:narrow_haul/game/level/specs/world_orbit.dart';
import 'package:narrow_haul/game/level/specs/world_redoubt.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// Authoritative list of worlds and levels. Ordering is stable; progress is
/// keyed by [LevelDef.saveId] so future insertions never corrupt saves.
abstract final class LevelRegistry {
  static final List<WorldDef> worlds = [
    const WorldDef(
      id: 'tutorial',
      name: 'Training Grounds',
      themeId: 'tutorial',
      starsRequired: 0,
      rewardPerStar: 5,
      levels: [
        TmxLevelDef(saveId: 'tut_01', name: 'First Flight', assetPath: 'assets/tiles/level_01.tmx', stars: StarSpec(star3Time: 30)),
        TmxLevelDef(saveId: 'tut_02', name: 'Steady Hands', assetPath: 'assets/tiles/level_02.tmx', stars: StarSpec(star3Time: 30)),
        TmxLevelDef(saveId: 'tut_03', name: 'Tow Basics', assetPath: 'assets/tiles/level_03.tmx', stars: StarSpec(star3Time: 30)),
        TmxLevelDef(saveId: 'tut_04', name: 'The Pillar', assetPath: 'assets/tiles/level_04.tmx', stars: StarSpec(star3Time: 35)),
        TmxLevelDef(saveId: 'tut_05', name: 'Twin Gates', assetPath: 'assets/tiles/level_05.tmx', stars: StarSpec(star3Time: 35)),
        TmxLevelDef(saveId: 'tut_06', name: 'Down Under', assetPath: 'assets/tiles/level_06.tmx', stars: StarSpec(star3Time: 35)),
        TmxLevelDef(saveId: 'tut_07', name: 'Zigzag Run', assetPath: 'assets/tiles/level_07.tmx', stars: StarSpec(star3Fuel: 0.65, star3Time: 40)),
        TmxLevelDef(saveId: 'tut_08', name: 'The Shaft', assetPath: 'assets/tiles/level_08.tmx', stars: StarSpec(star3Time: 45)),
        TmxLevelDef(saveId: 'tut_09', name: 'Long Haul', assetPath: 'assets/tiles/level_09.tmx', stars: StarSpec(star3Time: 45)),
        TmxLevelDef(saveId: 'tut_10', name: 'Graduation', assetPath: 'assets/tiles/level_10.tmx', stars: StarSpec(star3Time: 50)),
      ],
    ),
    WorldDef(
      id: 'alien',
      name: 'Xenar Caverns',
      themeId: 'alien',
      starsRequired: 8,
      rewardPerStar: 10,
      levels: alienLevels,
      defaultShipId: alienShipId,
    ),
    WorldDef(
      id: 'mine',
      name: 'Rustshaft Mines',
      themeId: 'mine',
      starsRequired: 22,
      rewardPerStar: 12,
      levels: mineLevels,
      defaultShipId: mineShipId,
    ),
    WorldDef(
      id: 'ice',
      name: 'Glacier Deep',
      themeId: 'ice',
      starsRequired: 40,
      rewardPerStar: 15,
      levels: iceLevels,
      defaultShipId: iceShipId,
    ),
    WorldDef(
      id: 'lava',
      name: 'Ember Core',
      themeId: 'lava',
      starsRequired: 60,
      rewardPerStar: 20,
      levels: lavaLevels,
      defaultShipId: lavaShipId,
    ),
    WorldDef(
      id: 'orbit',
      name: 'Outer Ring',
      themeId: 'orbit',
      starsRequired: 80,
      rewardPerStar: 25,
      levels: orbitLevels,
      defaultShipId: orbitShipId,
    ),
    WorldDef(
      id: 'redoubt',
      name: 'The Redoubt',
      themeId: 'redoubt',
      starsRequired: 100,
      rewardPerStar: 25,
      levels: redoubtLevels,
      defaultShipId: redoubtShipId,
    ),
  ];

  static final List<LevelDef> flat = [
    for (final w in worlds) ...w.levels,
  ];

  static int get totalLevels => flat.length;

  static LevelDef defAt(int flatIndex) => flat[flatIndex];

  /// The world containing [flatIndex] plus the level's index within it.
  /// A pilot holds a ship's type rating once its `rating_<id>` mission is
  /// flown; the Kestrel's comes from completing Training Grounds.
  static bool hasTypeRating(String shipId) {
    final progress = ProgressService.instance;
    if (shipId == kKestrel.id) {
      return progress.getStarsById(worlds.first.levels.last.saveId) > 0;
    }
    return progress.getStarsById('rating_$shipId') > 0;
  }

  /// Ships the daily "Test Flight" may fly on a level instead of its own.
  /// Cave levels: every candidate must pass the full validator (clearance,
  /// lift, fuel, fields) — at most a few runs, once per challenge start.
  /// TMX levels have no validator, so they require ≥ 90% of the native range.
  static List<ShipSpec> testFlightOptions(int flatIndex) {
    final native = shipFor(flatIndex);
    final def = defAt(flatIndex);
    return switch (def) {
      CaveLevelDef() => [
          for (final s in testFlightShips(native))
            if (validateCaveSpec(def.spec, ship: s).isEmpty) s,
        ],
      TmxLevelDef() => testFlightShips(native, minDeltaVRatio: 0.9),
    };
  }

  /// Ship flown on a level: its own override, else its world's default.
  static ShipSpec shipFor(int flatIndex) {
    final (world, indexInWorld) = worldOf(flatIndex);
    return shipById(world.levels[indexInWorld].shipId ?? world.defaultShipId);
  }

  static (WorldDef, int) worldOf(int flatIndex) {
    int offset = 0;
    for (final w in worlds) {
      if (flatIndex < offset + w.levels.length) return (w, flatIndex - offset);
      offset += w.levels.length;
    }
    return (worlds.last, worlds.last.levels.length - 1);
  }

  static int totalStars() {
    final progress = ProgressService.instance;
    int total = 0;
    for (final def in flat) {
      total += progress.getStarsById(def.saveId);
    }
    return total;
  }

  static bool isWorldUnlocked(WorldDef world) =>
      totalStars() >= world.starsRequired;

  /// A level is playable when its world's star gate is met and it's either
  /// the world's first level or the previous level has been completed.
  static bool isLevelUnlocked(int flatIndex) {
    final (world, indexInWorld) = worldOf(flatIndex);
    if (!isWorldUnlocked(world)) return false;
    if (indexInWorld == 0) return true;
    // Already flown → stays open even if a level was inserted before it
    // (e.g. a new type-rating mission at the start of a world).
    final self = world.levels[indexInWorld];
    if (ProgressService.instance.getStarsById(self.saveId) > 0) return true;
    final previous = world.levels[indexInWorld - 1];
    return ProgressService.instance.getStarsById(previous.saveId) > 0;
  }

  /// The career's next mission: the first unlocked level without a star,
  /// else the last unlocked one.
  static int nextLevelIndex() {
    var lastUnlocked = 0;
    for (var i = 0; i < totalLevels; i++) {
      if (!isLevelUnlocked(i)) continue;
      lastUnlocked = i;
      if (ProgressService.instance.getStarsById(flat[i].saveId) == 0) return i;
    }
    return lastUnlocked;
  }
}

/// Carves a cave level into spawnable [LevelData].
LevelData buildCaveLevelData(CaveLevelDef def) {
  final spec = def.spec;
  final cave = buildCave(spec);

  final shipSpawn = Vector2(spec.shipSpawn.x, spec.shipSpawn.y);
  final cargoSpawn = Vector2(spec.cargoSpawn.x, spec.cargoSpawn.y);
  final dist = shipSpawn.distanceTo(cargoSpawn);

  return LevelData(
    walls: const [],
    caveLoops: cave.loops,
    shipSpawn: shipSpawn,
    cargoSpawn: cargoSpawn,
    goalCenter: Vector2(spec.goal.center.x, spec.goal.center.y),
    goalHalfWidth: spec.goal.halfW,
    goalHalfHeight: spec.goal.halfH,
    worldSize: Vector2(spec.worldW, spec.worldH),
    ropeMaxLength: (dist + 6) * 2,
    cargoZoneCenter: cargoSpawn,
    cargoZoneSize: Vector2.zero(),
    theme: gameThemes[spec.themeId] ?? tutorialTheme,
    modifiers: spec.modifiers,
    obstacles: spec.obstacles,
    fields: spec.fields,
    pickups: spec.pickups,
    cargoClamped: spec.cargoClamped,
  );
}
