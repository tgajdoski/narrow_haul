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
      ),
    );
    return body;
  }
}
