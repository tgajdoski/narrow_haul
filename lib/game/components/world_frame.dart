import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/camera/camera_director.dart';
import 'package:narrow_haul/game/components/wall_box.dart';
import 'package:narrow_haul/game/level/theme_assets.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';

/// Visual-only rock around a tutorial (TMX) level, as far out as the camera
/// may look past the edge ([kCameraOverscroll]) to keep the ship clear of
/// the controls. Cave levels draw this in their own rock path.
class WorldFrame extends Component {
  WorldFrame({
    required Vector2 worldSize,
    required ThemeSpec theme,
    required ThemeAssets assets,
  })  : _paint = WallBox.rockPaint(theme, assets),
        _path = framePath(worldSize);

  final Paint _paint;
  final ui.Path _path;

  /// The world rect's surround, [kCameraOverscroll] + 1 m deep.
  static ui.Path framePath(Vector2 worldSize) {
    const pad = kCameraOverscroll + 1;
    return ui.Path()
      ..fillType = ui.PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(-pad, -pad, worldSize.x + 2 * pad, worldSize.y + 2 * pad))
      ..addRect(Rect.fromLTWH(0, 0, worldSize.x, worldSize.y));
  }

  @override
  void render(Canvas canvas) => canvas.drawPath(_path, _paint);
}
