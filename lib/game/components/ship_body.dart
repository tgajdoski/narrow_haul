import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/thrust_plume.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/tags.dart';

/// Rocket with rear thrust along local −Y (nose at −Y). [onWallHit] from contacts.
class ShipBody extends BodyComponent with ContactCallbacks {
  ShipBody({
    required Vector2 initialPosition,
    required this.onWallHit,
    this.onHookTouchesCargo,
  }) : _initialPosition = initialPosition,
       super(
         paint: Paint()..color = const Color(0xFF00B4D8),
       );

  final Vector2 _initialPosition;
  final void Function() onWallHit;
  final void Function()? onHookTouchesCargo;

  /// Local +Y anchor at engine bell (rope + plume).
  static const double rearLocalY = 0.26;

  /// Seconds to complete one full 360° while holding ⟲ or ⟳ at full input.
  static const double secondsPerFullRotation = 4.0;

  /// rad/s = 2π / secondsPerFullRotation (e.g. 4s → π/2 rad/s).
  static double get rotationSpeedRadPerSec =>
      (math.pi * 2) / secondsPerFullRotation;

  /// Main engine strength (N). ~30% of prior 17 for lighter thrust.
  static const double thrustForce = 5.1;

  /// Extra spin decay per second when no rotate input (release feels like “stop”).
  static const double releaseSpinDecay = 22;

  static const double maxFuel = 100;
  double fuel = maxFuel;
  static const double fuelDrainPerSecond = 12;

  double _rotateInput = 0;
  bool _thrustInput = false;

  void setInput({required double rotate, required bool thrust}) {
    _rotateInput = rotate.clamp(-1.0, 1.0);
    _thrustInput = thrust;
  }

  bool get isThrusting => _thrustInput && fuel > 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    body.userData = this;
    await add(ThrustPlume(isThrusting: () => isThrusting));
  }

  @override
  Body createBody() {
    final vertices = [
      Vector2(0, -0.34),
      Vector2(-0.21, rearLocalY),
      Vector2(0.21, rearLocalY),
    ];
    final shape = PolygonShape()..set(vertices);

    final def = BodyDef()
      ..position = _initialPosition
      ..type = BodyType.dynamic
      // Rotation rate is set directly in [update]; keep 0 so we hit exactly
      // [secondsPerFullRotation] per turn without fighting damping.
      ..angularDamping = 0
      ..linearDamping = 0.22;

    final b = world.createBody(def);
    b.createFixture(
      FixtureDef(
        shape,
        density: 1.15,
        friction: 0.2,
        restitution: 0.05,
        filter: filterShip(),
        userData: const ShipTag(),
      ),
    );

    b.createFixture(
      FixtureDef(
        CircleShape(
          radius: 0.14,
          position: Vector2(0, -0.24),
        ),
        isSensor: true,
        userData: const HookTag(),
        filter: filterHook(),
      ),
    );
    return b;
  }

  @override
  void update(double dt) {
    super.update(dt);

    const rotateDeadzone = 0.01;
    if (_rotateInput.abs() < rotateDeadzone) {
      final t = (releaseSpinDecay * dt).clamp(0.0, 1.0);
      body.angularVelocity *= 1.0 - t;
    } else {
      // Constant turn rate: 360° in [secondsPerFullRotation] at |input| == 1.
      body.angularVelocity = _rotateInput * rotationSpeedRadPerSec;
    }

    if (_thrustInput && fuel > 0) {
      fuel -= fuelDrainPerSecond * dt;
      if (fuel < 0) fuel = 0;
      final dir = body.worldVector(Vector2(0, -1))..scale(thrustForce);
      body.applyForce(dir);
    }
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (other is WallTag) {
      onWallHit();
    }
    if (other is CargoTag) {
      final hookHit = contact.fixtureA.userData is HookTag ||
          contact.fixtureB.userData is HookTag;
      if (hookHit) {
        onHookTouchesCargo?.call();
      }
    }
  }
}
