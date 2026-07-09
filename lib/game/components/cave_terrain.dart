import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/tags.dart';

/// Organic cave terrain: one static body with a ChainShape loop per contour
/// (ghost vertices via createLoop avoid seam collisions), rendered as an
/// even-odd filled path — rock everywhere, cave interior transparent to the
/// backdrop and parallax.
class CaveTerrain extends BodyComponent {
  CaveTerrain({
    required this.loops,
    required this.worldSize,
    required this.theme,
    this.friction = 0.35,
  }) : super(priority: -1700, renderBody: false);

  final List<List<Pt>> loops;
  final Vector2 worldSize;
  final ThemeSpec theme;
  final double friction;

  late final ui.Path _rockPath;
  late final List<ui.Path> _edgePaths;

  @override
  Future<void> onLoad() async {
    _rockPath = ui.Path()..fillType = ui.PathFillType.evenOdd;
    // Rock extends slightly past the world so the border never shows gaps.
    _rockPath.addRect(Rect.fromLTWH(-1, -1, worldSize.x + 2, worldSize.y + 2));
    _edgePaths = <ui.Path>[];
    for (final loop in loops) {
      final p = ui.Path()
        ..addPolygon([for (final pt in loop) Offset(pt.x, pt.y)], true);
      _rockPath.addPath(p, Offset.zero);
      _edgePaths.add(p);
    }
    await super.onLoad();
  }

  @override
  Body createBody() {
    final def = BodyDef()
      ..position = Vector2.zero()
      ..type = BodyType.static;
    final body = world.createBody(def);
    for (final loop in loops) {
      final vertices = [for (final pt in loop) Vector2(pt.x, pt.y)];
      body.createFixture(
        FixtureDef(
          ChainShape()..createLoop(vertices),
          friction: friction,
          userData: const WallTag(),
          filter: filterWall(),
        ),
      );
    }
    return body;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawPath(_rockPath, Paint()..color = theme.rockFill);

    final edgePaint = Paint()
      ..color = theme.rockEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.14;
    final highlightPaint = Paint()
      ..color = theme.rockHighlight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05;
    for (final p in _edgePaths) {
      canvas.drawPath(p, edgePaint);
      canvas.drawPath(p, highlightPaint);
    }

    // Sparse seeded mineral speckles inside the rock for texture.
    final rng = math.Random(loops.length * 7919);
    final speckPaint = Paint()..color = theme.rockHighlight;
    for (int i = 0; i < 60; i++) {
      final x = rng.nextDouble() * worldSize.x;
      final y = rng.nextDouble() * worldSize.y;
      if (_rockPath.contains(Offset(x, y))) {
        canvas.drawCircle(Offset(x, y), 0.03 + rng.nextDouble() * 0.04, speckPaint);
      }
    }
  }
}
