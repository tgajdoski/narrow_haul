import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/tags.dart';

/// Axis-aligned static wall from [wallCenter] (meters) and half-extents.
class WallBox extends BodyComponent {
  WallBox({
    required this.wallCenter,
    required this.halfWidth,
    required this.halfHeight,
  }) : super(
         paint: Paint()..color = const Color(0xFF3D5A80),
       );

  final Vector2 wallCenter;
  final double halfWidth;
  final double halfHeight;

  @override
  Body createBody() {
    final def = BodyDef()
      ..position = wallCenter
      ..type = BodyType.static;
    final body = world.createBody(def);
    body.createFixture(
      FixtureDef(
        PolygonShape()..setAsBoxXY(halfWidth, halfHeight),
        friction: 0.35,
        userData: const WallTag(),
        filter: filterWall(),
      ),
    );
    return body;
  }
}
