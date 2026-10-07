import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/level_data.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

/// Whole-level overview in the top-right corner: terrain, landing pad, cargo,
/// ship and the camera's view. Tap toggles between the map and a small map
/// icon; the choice persists via [ProgressService.minimapEnabled].
///
/// Terrain is recorded once per level into a [ui.Picture]; per frame only the
/// markers are drawn.
class MinimapHud extends PositionComponent
    with TapCallbacks, HasGameReference<NarrowHaulGame> {
  MinimapHud() : super(priority: 4900, anchor: Anchor.topRight);

  static const double _maxW = 150;
  static const double _maxH = 90;
  static const double _margin = 12;
  static const double _iconSize = 28;
  static const double _radius = 6;

  static const _padColor = Color(0xFF4ADE80);
  static const _cargoColor = Color(0xFFFFB347);

  LevelData? _level;
  ui.Picture? _terrain;
  double _scale = 1; // minimap px per meter
  Vector2 _mapSize = Vector2.zero();
  double _t = 0;

  bool get _expanded => ProgressService.instance.minimapEnabled;

  /// Rebuilds the cached terrain for [data]; null hides the minimap.
  void setLevel(LevelData? data) {
    _terrain?.dispose();
    _terrain = null;
    _level = data;
    if (data == null) return;

    final w = data.worldSize;
    _scale = math.min(_maxW / w.x, _maxH / w.y);
    _mapSize = Vector2(w.x * _scale, w.y * _scale);

    final rock = Paint()
      ..color = Color.lerp(data.theme.rockFill, Colors.white, 0.3)!
          .withValues(alpha: 0.85);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_scale);
    if (data.caveLoops.isNotEmpty) {
      // Even-odd: rock everywhere, cave interiors cut out (as in CaveTerrain).
      final path = ui.Path()
        ..fillType = ui.PathFillType.evenOdd
        ..addRect(Rect.fromLTWH(0, 0, w.x, w.y));
      for (final loop in data.caveLoops) {
        path.addPolygon([for (final p in loop) Offset(p.x, p.y)], true);
      }
      canvas.drawPath(path, rock);
    }
    for (final r in data.walls) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(r.center.x, r.center.y),
          width: r.halfWidth * 2,
          height: r.halfHeight * 2,
        ),
        rock,
      );
    }
    _terrain = recorder.endRecording();
    _relayout();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _relayout();
  }

  /// Re-reads the expanded/collapsed setting (e.g. after the Settings screen).
  void refreshLayout() {
    if (isMounted) _relayout();
  }

  void _relayout() {
    final vp = game.camera.viewport.size;
    final safe = game.safeInsets;
    position = Vector2(vp.x - safe.right - _margin, safe.top + _margin);
    size = _expanded ? _mapSize : Vector2.all(_iconSize);
  }

  @override
  bool containsLocalPoint(Vector2 point) =>
      _level != null && super.containsLocalPoint(point);

  @override
  void onTapUp(TapUpEvent event) {
    ProgressService.instance.setMinimapEnabled(!_expanded);
    _relayout();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    final level = _level;
    if (level == null) return;
    final accent = level.theme.uiAccent;

    final panel = RRect.fromRectAndRadius(
      size.toRect(),
      const Radius.circular(_radius),
    );
    canvas.drawRRect(
      panel,
      Paint()..color = level.theme.backdropColor.withValues(alpha: 0.6),
    );

    if (_expanded) {
      canvas.save();
      canvas.clipRRect(panel);
      final terrain = _terrain;
      if (terrain != null) canvas.drawPicture(terrain);
      _renderMarkers(canvas, level);
      canvas.restore();
    } else {
      _renderIcon(canvas, accent);
    }

    canvas.drawRRect(
      panel,
      Paint()
        ..color = accent.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  Offset _toMap(Vector2 world) => Offset(world.x * _scale, world.y * _scale);

  void _renderMarkers(Canvas canvas, LevelData level) {
    // Camera view.
    final view = game.camera.visibleWorldRect;
    canvas.drawRect(
      Rect.fromLTRB(
        view.left * _scale,
        view.top * _scale,
        view.right * _scale,
        view.bottom * _scale,
      ),
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Landing pad — a minimum size so it stays visible on big levels.
    canvas.drawRect(
      Rect.fromCenter(
        center: _toMap(level.goalCenter),
        width: math.max(level.goalHalfWidth * 2 * _scale, 8),
        height: math.max(level.goalHalfHeight * 2 * _scale, 3),
      ),
      Paint()..color = _padColor,
    );

    // Cargo — pulses until it's hooked.
    final cargo = game.cargo;
    if (cargo != null && cargo.isMounted) {
      final c = _toMap(cargo.body.position);
      final attached = game.cargoAttachment?.attached ?? false;
      if (!attached) {
        final pulse = (math.sin(_t * 4) + 1) / 2;
        canvas.drawCircle(
          c,
          3 + 3 * pulse,
          Paint()..color = _cargoColor.withValues(alpha: 0.35 * (1 - pulse)),
        );
      }
      canvas.drawCircle(c, 2.5, Paint()..color = _cargoColor);
    }

    // Ship — triangle with its nose along local −Y.
    final ship = game.ship;
    if (ship != null && ship.isMounted) {
      final p = _toMap(ship.body.position);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(ship.body.angle);
      canvas.drawPath(
        ui.Path()
          ..moveTo(0, -4.5)
          ..lineTo(3, 3)
          ..lineTo(-3, 3)
          ..close(),
        Paint()..color = Colors.white,
      );
      canvas.restore();
    }
  }

  /// Folded-map glyph shown while collapsed.
  void _renderIcon(Canvas canvas, Color accent) {
    const s = _iconSize;
    final paint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    final path = ui.Path()
      ..moveTo(s * 0.2, s * 0.3)
      ..lineTo(s * 0.4, s * 0.22)
      ..lineTo(s * 0.6, s * 0.3)
      ..lineTo(s * 0.8, s * 0.22)
      ..lineTo(s * 0.8, s * 0.7)
      ..lineTo(s * 0.6, s * 0.78)
      ..lineTo(s * 0.4, s * 0.7)
      ..lineTo(s * 0.2, s * 0.78)
      ..close()
      ..moveTo(s * 0.4, s * 0.22)
      ..lineTo(s * 0.4, s * 0.7)
      ..moveTo(s * 0.6, s * 0.3)
      ..lineTo(s * 0.6, s * 0.78);
    canvas.drawPath(path, paint);
  }
}
