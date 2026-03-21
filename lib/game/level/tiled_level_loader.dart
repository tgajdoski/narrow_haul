import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:forge2d/forge2d.dart';
import 'package:narrow_haul/game/level/level_data.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:tiled/tiled.dart';

/// Loads [LevelData] from a Tiled `.tmx` with `walls`, `markers` (ship, goal, cargo_zone).
/// Cargo position is randomized inside `cargo_zone` each load.
Future<LevelData> loadLevelFromTmx(String assetPath, {required int levelIndex}) async {
  final xml = await rootBundle.loadString(assetPath);
  final map = await TiledMap.fromString(xml, TsxProvider.parse);

  const ppm = pixelsPerMeter;
  final walls = <WallRect>[];
  Vector2? ship;
  double? goalX;
  double? goalY;
  double? goalW;
  double? goalH;

  double? czLeft;
  double? czTop;
  double? czW;
  double? czH;

  for (final group in map.layers.whereType<ObjectGroup>()) {
    if (group.name == 'walls') {
      for (final obj in group.objects) {
        if (obj.width > 0 && obj.height > 0) {
          final cx = (obj.x + obj.width / 2) / ppm;
          final cy = (obj.y + obj.height / 2) / ppm;
          walls.add(
            WallRect(
              center: Vector2(cx, cy),
              halfWidth: obj.width / 2 / ppm,
              halfHeight: obj.height / 2 / ppm,
            ),
          );
        }
      }
    } else if (group.name == 'markers') {
      for (final obj in group.objects) {
        final name = obj.name.toLowerCase();
        final cx = (obj.x + obj.width / 2) / ppm;
        final cy = (obj.y + obj.height / 2) / ppm;
        if (name == 'ship') {
          ship = Vector2(cx, cy);
        } else if (name == 'goal' && obj.width > 0 && obj.height > 0) {
          goalX = (obj.x + obj.width / 2) / ppm;
          goalY = (obj.y + obj.height / 2) / ppm;
          goalW = obj.width / 2 / ppm;
          goalH = obj.height / 2 / ppm;
        } else if (name == 'cargo_zone' && obj.width > 0 && obj.height > 0) {
          czLeft = obj.x / ppm;
          czTop = obj.y / ppm;
          czW = obj.width / ppm;
          czH = obj.height / ppm;
        }
      }
    }
  }

  if (ship == null || goalX == null || goalY == null) {
    throw StateError('TMX $assetPath must define markers: ship, goal');
  }
  if (czLeft == null || czTop == null || czW == null || czH == null) {
    throw StateError('TMX $assetPath must define cargo_zone rectangle');
  }

  final worldSize = Vector2(
    map.width * map.tileWidth / ppm,
    map.height * map.tileHeight / ppm,
  );

  final zl = czLeft;
  final zt = czTop;
  final zw = czW;
  final zh = czH;

  final cargoZoneCenter = Vector2(
    zl + zw / 2,
    zt + zh / 2,
  );
  final cargoZoneSize = Vector2(zw, zh);

  const margin = 0.55;
  final rng = Random(levelIndex * 10007 + assetPath.hashCode);
  final innerW = (zw - 2 * margin).clamp(0.1, double.infinity);
  final innerH = (zh - 2 * margin).clamp(0.1, double.infinity);
  final cargoSpawn = Vector2(
    zl + margin + rng.nextDouble() * innerW,
    zt + margin + rng.nextDouble() * innerH,
  );

  final dist = (ship - cargoSpawn).length;
  final ropeMaxLength = dist + 6;

  return LevelData(
    walls: walls,
    shipSpawn: ship,
    cargoSpawn: cargoSpawn,
    goalCenter: Vector2(goalX, goalY),
    goalHalfWidth: goalW ?? 1,
    goalHalfHeight: goalH ?? 1,
    worldSize: worldSize,
    ropeMaxLength: ropeMaxLength,
    cargoZoneCenter: cargoZoneCenter,
    cargoZoneSize: cargoZoneSize,
  );
}
