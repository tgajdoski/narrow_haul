import 'package:forge2d/forge2d.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';

/// Parsed level: static geometry, spawns, landing pad, theme and modifiers
/// (meters). Rectangle walls come from TMX tutorial levels; [caveLoops] come
/// from organic cave specs — exactly one of the two is non-empty.
class LevelData {
  const LevelData({
    required this.walls,
    this.caveLoops = const <List<Pt>>[],
    required this.shipSpawn,
    required this.cargoSpawn,
    required this.goalCenter,
    required this.goalHalfWidth,
    required this.goalHalfHeight,
    required this.worldSize,
    required this.ropeMaxLength,
    required this.cargoZoneCenter,
    required this.cargoZoneSize,
    this.theme = tutorialTheme,
    this.modifiers = const LevelModifiers(),
    this.obstacles = const <ObstacleSpec>[],
    this.fields = const <FieldSpec>[],
    this.pickups = const <PickupSpec>[],
    this.cargoClamped = false,
    List<LegData>? legs,
  }) : _legs = legs;

  final List<WallRect> walls;

  /// Closed cave contour loops (meters) for organic levels.
  final List<List<Pt>> caveLoops;

  final Vector2 shipSpawn;
  final Vector2 cargoSpawn;
  final Vector2 goalCenter;
  final double goalHalfWidth;
  final double goalHalfHeight;

  /// Used for camera bounds (meters).
  final Vector2 worldSize;

  /// Rope [RopeJointDef.maxLength] in meters.
  final double ropeMaxLength;

  /// Cargo pickup zone (for dashed outline).
  final Vector2 cargoZoneCenter;
  final Vector2 cargoZoneSize;

  final ThemeSpec theme;
  final LevelModifiers modifiers;
  final List<ObstacleSpec> obstacles;
  final List<FieldSpec> fields;
  final List<PickupSpec> pickups;
  final bool cargoClamped;

  final List<LegData>? _legs;

  /// Every haul in order: an Expedition's legs, or the one from
  /// [cargoSpawn] / [goalCenter].
  List<LegData> get legs =>
      _legs ??
      [
        LegData(
          cargoSpawn: cargoSpawn,
          goalCenter: goalCenter,
          goalHalfWidth: goalHalfWidth,
          goalHalfHeight: goalHalfHeight,
          cargoClamped: cargoClamped,
          startSpawn: shipSpawn,
          parkedPod: Vector2(goalCenter.x - goalHalfWidth + 0.45, goalCenter.y + goalHalfHeight),
        ),
      ];

  /// Turrets or a reactor present — drives combat HUD and stats.
  bool get hasCombat =>
      obstacles.any((o) => o is TurretSpec || o is ReactorSpec);
}

/// One haul of a level (see `LegSpec`): its pod, its pad, where the ship
/// starts it (the previous pad on a checkpoint resume) and where its pod is
/// parked once delivered.
class LegData {
  const LegData({
    required this.cargoSpawn,
    required this.goalCenter,
    required this.goalHalfWidth,
    required this.goalHalfHeight,
    required this.cargoClamped,
    required this.startSpawn,
    required this.parkedPod,
  });

  final Vector2 cargoSpawn;
  final Vector2 goalCenter;
  final double goalHalfWidth;
  final double goalHalfHeight;
  final bool cargoClamped;
  final Vector2 startSpawn;
  final Vector2 parkedPod;
}

class WallRect {
  const WallRect({
    required this.center,
    required this.halfWidth,
    required this.halfHeight,
  });

  final Vector2 center;
  final double halfWidth;
  final double halfHeight;
}
