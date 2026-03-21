import 'package:forge2d/forge2d.dart';

/// Parsed level: static walls, spawns, landing pad, optional cargo zone (meters).
class LevelData {
  const LevelData({
    required this.walls,
    required this.shipSpawn,
    required this.cargoSpawn,
    required this.goalCenter,
    required this.goalHalfWidth,
    required this.goalHalfHeight,
    required this.worldSize,
    required this.ropeMaxLength,
    required this.cargoZoneCenter,
    required this.cargoZoneSize,
  });

  final List<WallRect> walls;
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
