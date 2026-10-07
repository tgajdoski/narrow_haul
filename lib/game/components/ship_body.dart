import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/thrust_plume.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/game/tags.dart';

/// Rocket with rear thrust along local −Y (nose at −Y). [onWallHit] from contacts.
class ShipBody extends BodyComponent with ContactCallbacks {
  ShipBody({
    required Vector2 initialPosition,
    required this.onWallHit,
    this.onHookTouchesCargo,
    this.fuelDrainMultiplier = 1.0,
    this.spec = kKestrel,
  }) : _initialPosition = initialPosition,
       fuel = spec.maxFuel,
       super(
         paint: Paint()..color = const Color(0xFF00B4D8),
       );

  /// Multiplier applied to fuel drain rate (daily challenge modifier).
  final double fuelDrainMultiplier;

  /// Flight characteristics (hull, engine, tank). Chosen by the level.
  final ShipSpec spec;

  final Vector2 _initialPosition;

  ui.Image? _shipImage;
  bool _usingFallbackArt = false;
  final void Function() onWallHit;
  final void Function()? onHookTouchesCargo;

  /// Local +Y anchor at engine bell (rope + plume).
  double get rearLocalY => spec.rearLocalY;

  /// Nose hook sensor (same as [CircleShape] in [createBody]).
  Vector2 get hookLocal => Vector2(0, spec.hookLocalY);
  double get hookRadius => spec.hookRadius;

  /// Extra spin decay per second when no rotate input (release feels like “stop”).
  static const double releaseSpinDecay = 22;

  double get maxFuel => spec.maxFuel;

  /// Local acceleration at the ship (m/s²), fed by the game each frame — the
  /// "down" that passive assists level against.
  final Vector2 localAccel = Vector2(0, 1);

  /// Auto-level gain (1/s) and max correction as a fraction of turn rate.
  static const double _levelGain = 2.5;
  static const double _levelMaxRate = 0.7;

  /// Fraction of the local pull the hover assist cancels while thrusting.
  static const double hoverAssistFraction = 0.75;
  double fuel;

  double _rotateInput = 0;
  bool _thrustInput = false;

  void setInput({required double rotate, required bool thrust}) {
    _rotateInput = rotate.clamp(-1.0, 1.0);
    _thrustInput = thrust;
    if (!_launched && (thrust || rotate.abs() > 0.05)) {
      _launched = true;
      body.gravityScale = null; // gravity on from the first input
    }
  }

  /// The ship hovers on its start pad (no gravity) until the first input, so
  /// reading the intro card or a tutorial hint never ends in a crash.
  bool get launched => _launched;
  bool _launched = false;

  bool get isThrusting => _thrustInput && fuel > 0 && !_wrecked;

  bool _wrecked = false;

  /// Crash: hide the hull and kill input; the body keeps simulating so the
  /// rope/cargo react naturally while the explosion plays.
  void wreck() {
    _wrecked = true;
    setInput(rotate: 0, thrust: false);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    body.userData = this;
    await add(ThrustPlume(
      isThrusting: () => isThrusting,
      flameStartY: rearLocalY,
    ));
    // Bespoke art if present, else the Kestrel sprite + the spec's tint.
    for (final path in {spec.sprite, kKestrel.sprite}) {
      try {
        _shipImage = await Flame.images.load(path);
        _usingFallbackArt = path != spec.sprite;
        renderBody = false;
        break;
      } catch (_) {}
    }
  }

  // Sprite is drawn at 3× the physics hull dimensions so the ship is clearly
  // visible on-screen. The hitbox remains at the original physics size.
  static const double _visualScale = 4.5;
  late final Rect _spriteRect = Rect.fromLTRB(
    -0.23 * _visualScale * spec.hullScale, // left
    -0.37 * _visualScale * spec.hullScale, // top  (nose)
     0.23 * _visualScale * spec.hullScale, // right
     0.29 * _visualScale * spec.hullScale, // bottom (rear)
  );

  @override
  void render(Canvas canvas) {
    if (_wrecked) return;
    super.render(canvas); // no-op when renderBody = false
    final img = _shipImage;
    if (img != null) {
      final skinId = CosmeticsService.getEquippedId(CosmeticsService.catShip);
      final paint = Paint();
      if (skinId == 'ship_neon') {
        paint.colorFilter = const ColorFilter.mode(Color(0x88FF00FF), BlendMode.srcATop);
      } else if (skinId == 'ship_stealth') {
        paint.colorFilter = const ColorFilter.mode(Color(0xCC000000), BlendMode.srcATop);
      } else if (skinId == 'ship_gold') {
        paint.colorFilter = const ColorFilter.mode(Color(0xAAFFD700), BlendMode.srcATop);
      } else if (skinId == 'ship_carbon') {
        paint.colorFilter = const ColorFilter.mode(Color(0x99404855), BlendMode.srcATop);
      } else if (skinId == 'ship_gold_trim') {
        paint.colorFilter = const ColorFilter.mode(Color(0x55FFD166), BlendMode.srcATop);
      } else if (_usingFallbackArt && spec.tint != null) {
        // Placeholder livery until the ship's own sprite exists.
        paint.colorFilter = ColorFilter.mode(Color(spec.tint!), BlendMode.srcATop);
      }
      
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        _spriteRect,
        paint,
      );
    }
  }

  @override
  Body createBody() {
    final vertices = [
      Vector2(0, spec.noseLocalY),
      Vector2(-spec.rearHalfWidth, rearLocalY),
      Vector2(spec.rearHalfWidth, rearLocalY),
    ];
    final shape = PolygonShape()..set(vertices);

    final def = BodyDef()
      ..position = _initialPosition
      ..type = BodyType.dynamic
      // Rotation rate is set directly in [update]; keep 0 so we hit exactly
      // [ShipSpec.secondsPerFullRotation] per turn without fighting damping.
      ..angularDamping = 0
      ..linearDamping = spec.linearDamping
      ..gravityScale = Vector2.zero();

    final b = world.createBody(def);
    b.createFixture(
      FixtureDef(
        shape,
        density: spec.density,
        friction: 0.2,
        restitution: 0.05,
        filter: filterShip(),
        userData: const ShipTag(),
      ),
    );

    b.createFixture(
      FixtureDef(
        CircleShape(
          radius: hookRadius,
          position: hookLocal,
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
    final idle = _rotateInput.abs() < rotateDeadzone;
    if (idle && spec.autoLevel && _launched && !_thrustInput && localAccel.length2 > 1e-4) {
      // Ease the nose to point against local gravity (θ where the nose
      // (sin θ, −cos θ) = −â).
      final target = math.atan2(-localAccel.x, localAccel.y);
      var diff = (target - body.angle) % (2 * math.pi);
      if (diff > math.pi) diff -= 2 * math.pi;
      final maxRate = spec.rotationSpeedRadPerSec * _levelMaxRate;
      body.angularVelocity = (diff * _levelGain).clamp(-maxRate, maxRate);
    } else if (idle) {
      final t = (releaseSpinDecay * dt).clamp(0.0, 1.0);
      body.angularVelocity *= 1.0 - t;
    } else {
      // Constant turn rate: 360° in [secondsPerFullRotation] at |input| == 1.
      body.angularVelocity = _rotateInput * spec.rotationSpeedRadPerSec;
    }

    if (_thrustInput && fuel > 0) {
      fuel -= spec.fuelDrainPerSecond * fuelDrainMultiplier * dt;
      if (fuel < 0) fuel = 0;
      final dir = body.worldVector(Vector2(0, -1))..scale(spec.thrustForce);
      body.applyForce(dir);
      if (spec.hoverAssist) {
        // Fly-by-wire: cancel most of the local pull while the engine burns.
        body.applyForce(localAccel * (-hoverAssistFraction * body.mass));
      }
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
