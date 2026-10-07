import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/theme_assets.dart';
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
    this.assets = ThemeAssets.empty,
    this.friction = 0.35,
  }) : super(priority: -1700, renderBody: false);

  final List<List<Pt>> loops;
  final Vector2 worldSize;
  final ThemeSpec theme;
  final ThemeAssets assets;
  final double friction;

  late final ui.Path _rockPath;
  late final List<ui.Path> _edgePaths;
  late final Paint _rockPaint;
  late final Paint _edgePaint;
  late final Paint _highlightPaint;
  Paint? _glowPaint;
  final List<(Offset, double)> _specks = [];

  @override
  Future<void> onLoad() async {
    _edgePaths = [
      for (final loop in loops)
        ui.Path()..addPolygon([for (final pt in loop) Offset(pt.x, pt.y)], true),
    ];
    _rockPath = buildRockPath(_edgePaths, worldSize);

    _rockPaint = Paint()..color = theme.rockFill;
    final rockImg = assets.rock;
    if (rockImg != null) {
      final s = theme.rockTextureMeters / rockImg.width;
      _rockPaint
        ..shader = ui.ImageShader(
          rockImg,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Matrix4.diagonal3Values(s, s, 1).storage,
        )
        ..filterQuality = FilterQuality.medium;
    }
    _edgePaint = Paint()
      ..color = theme.rockEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.14;
    _highlightPaint = Paint()
      ..color = theme.rockHighlight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05;
    final glow = theme.edgeGlow;
    if (glow != null) {
      _glowPaint = Paint()
        ..color = glow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.35
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.25);
    }

    // Sparse seeded mineral speckles — only for the flat look; a texture
    // carries its own detail. Computed once (Path.contains is not cheap).
    if (rockImg == null) {
      final rng = math.Random(loops.length * 7919);
      for (int i = 0; i < 60; i++) {
        final x = rng.nextDouble() * worldSize.x;
        final y = rng.nextDouble() * worldSize.y;
        final r = 0.03 + rng.nextDouble() * 0.04;
        if (_rockPath.contains(Offset(x, y))) _specks.add((Offset(x, y), r));
      }
    }
    await super.onLoad();
  }

  /// The even-odd rock region (solid where true); shared with decor placement.
  ui.Path get rockPath => _rockPath;

  /// Rock = world rect (padded 1 m so the border never shows gaps) minus the
  /// cave interiors, via even-odd fill.
  static ui.Path buildRockPath(List<ui.Path> edgePaths, Vector2 worldSize) {
    final path = ui.Path()
      ..fillType = ui.PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(-1, -1, worldSize.x + 2, worldSize.y + 2));
    for (final p in edgePaths) {
      path.addPath(p, Offset.zero);
    }
    return path;
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
    canvas.drawPath(_rockPath, _rockPaint);

    final glow = _glowPaint;
    for (final p in _edgePaths) {
      if (glow != null) canvas.drawPath(p, glow);
      canvas.drawPath(p, _edgePaint);
      canvas.drawPath(p, _highlightPaint);
    }

    if (_specks.isNotEmpty) {
      final speckPaint = Paint()..color = theme.rockHighlight;
      for (final (c, r) in _specks) {
        canvas.drawCircle(c, r, speckPaint);
      }
    }
  }
}
