import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/physics_constants.dart';

/// Thin dynamic bar: local +X runs ship → cargo; ship end at (−halfLength, 0), cargo at (+halfLength, 0).
class RopeSegmentBody extends BodyComponent {
  RopeSegmentBody({
    required Vector2 center,
    required double angle,
    required this.halfLength,
    this.halfThickness = 0.045,
  }) : _center = center,
       _angle = angle,
       super(
         renderBody: false,
         priority: -450,
       );

  final Vector2 _center;
  final double _angle;
  final double halfLength;
  final double halfThickness;

  Vector2 get endShipWorld => body.worldPoint(Vector2(-halfLength, 0));
  Vector2 get endCargoWorld => body.worldPoint(Vector2(halfLength, 0));

  @override
  Body createBody() {
    final def = BodyDef()
      ..position = _center
      ..angle = _angle
      ..type = BodyType.dynamic
      ..angularDamping = 0.35
      ..linearDamping = 0.12;

    final b = world.createBody(def);
    final shape = PolygonShape()..setAsBoxXY(halfLength, halfThickness);
    b.createFixture(
      FixtureDef(
        shape,
        density: 0.4,
        friction: 0.35,
        restitution: 0.02,
        filter: filterRope(),
      ),
    );
    return b;
  }
}
