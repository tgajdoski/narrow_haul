import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/tags.dart';

class CargoBody extends BodyComponent {
  CargoBody({required Vector2 initialPosition})
    : _initialPosition = initialPosition,
      super(
        paint: Paint()..color = const Color(0xFFE07A5F),
      );

  final Vector2 _initialPosition;

  /// Smaller than ship hull (~0.68 m tall).
  static const double radius = 0.14;

  ui.Image? _cargoImage;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _cargoImage = await Flame.images.load('cargo.png');
      renderBody = false;
    } catch (_) {}
  }

  // Sprite drawn slightly larger than the physics circle so the art
  // fills the collision boundary comfortably.
  static const double _spriteHalf = radius + 0.06; // ≈ 0.20 m half-size

  @override
  void render(Canvas canvas) {
    super.render(canvas); // no-op when renderBody = false
    final img = _cargoImage;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: _spriteHalf * 2, height: _spriteHalf * 2),
        Paint(),
      );
    }
  }

  @override
  Body createBody() {
    final def = BodyDef()
      ..position = _initialPosition
      ..type = BodyType.dynamic
      ..angularDamping = 0.6
      ..linearDamping = 0.05;
    final body = world.createBody(def);
    body.userData = const CargoTag();
    body.createFixture(
      FixtureDef(
        CircleShape()..radius = radius,
        density: 2.0,
        friction: 0.45,
        restitution: 0.08,
        filter: filterCargo(),
        userData: const CargoTag(),
      ),
    );
    return body;
  }

  @override
  void renderCircle(Canvas canvas, Offset center, double radius) {
    // Only reached when renderBody = true (sprite failed to load — fallback).
    super.renderCircle(canvas, center, radius);
    canvas.drawCircle(
      center,
      radius + 0.018,
      Paint()
        ..color = const Color(0xFF5C3D2E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.035,
    );
  }
}
