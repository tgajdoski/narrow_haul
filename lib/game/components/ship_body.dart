import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/thrust_plume.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/hull_contact.dart';
import 'package:narrow_haul/game/ship/loadout.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/game/ship/weapons.dart';
import 'package:narrow_haul/game/tags.dart';

/// Rocket with rear thrust along local −Y (nose at −Y). [onWallHit] from contacts.
class ShipBody extends BodyComponent with ContactCallbacks {
  ShipBody({
    required Vector2 initialPosition,
    required this.onWallHit,
    this.onRockTouch,
    this.onHookTouchesCargo,
    this.onFire,
    this.onWeapon,
    this.rack,
    this.fuelDrainMultiplier = 1.0,
    this.spec = kKestrel,
    this.kit = kStockKit,
  }) : _initialPosition = initialPosition,
       fuel = spec.maxFuel * kit.tankMul,
       super(
         paint: Paint()..color = const Color(0xFF00B4D8),
       );

  /// Multiplier applied to fuel drain rate (daily challenge modifier).
  final double fuelDrainMultiplier;

  /// Flight characteristics (hull, engine, tank). Chosen by the level.
  final ShipSpec spec;

  /// Handling kit fitted in the Garage ([kStockKit] = none).
  final KitSpec kit;

  final Vector2 _initialPosition;

  ui.Image? _shipImage;
  bool _usingFallbackArt = false;
  final void Function() onWallHit;

  /// A slow rock touch that didn't crash: world point, rock normal, kind.
  final void Function(Vector2 point, Vector2 normal, HullContact kind)?
  onRockTouch;
  final void Function()? onHookTouchesCargo;

  /// Armed ships: spawn a shell at [muzzle] with [velocity] (world, m, m/s).
  final void Function(Vector2 muzzle, Vector2 velocity)? onFire;

  /// A special weapon fired (ammo already taken). Continuous weapons call
  /// this every frame the trigger is held, with that frame's [dt].
  final void Function(WeaponSpec weapon, double dt)? onWeapon;

  /// This flight's weapons (cannon + special ammo); null = none.
  final WeaponRack? rack;

  /// The mining laser is cutting this frame.
  bool get laserFiring => _laserFiring;
  bool _laserFiring = false;

  /// Unit vector along the nose (world).
  Vector2 get noseDir => body.worldVector(Vector2(0, -1));

  /// Where shells leave the nose (world).
  Vector2 get muzzleWorld => body.worldPoint(Vector2(0, spec.noseLocalY - 0.1));

  /// Where bombs drop from (world, just behind the engine bell).
  Vector2 get bellyWorld => body.worldPoint(Vector2(0, rearLocalY + 0.25));

  /// Local +Y anchor at engine bell (rope + plume).
  double get rearLocalY => spec.rearLocalY;

  /// Nose hook sensor (same as [CircleShape] in [createBody]).
  Vector2 get hookLocal => Vector2(0, spec.hookLocalY);
  double get hookRadius => spec.hookRadius;

  double get maxFuel => spec.maxFuel * kit.tankMul;

  /// Turn rate at rotate input 1 (rad/s).
  double get turnRate => spec.rotationSpeedRadPerSec * kit.turnMul;

  /// Set by the game each frame: towing trims the turn boost.
  bool towing = false;

  /// Largest rotate input right now (the stick's boost zone).
  double get maxRotateInput =>
      FlightTuning.effectiveBoost(spec.turnBoost, towing: towing);

  /// Local acceleration at the ship (m/s²), fed by the game each frame — the
  /// "down" that passive assists level against.
  final Vector2 localAccel = Vector2(0, 1);

  /// Auto-level gain (1/s) and max correction as a fraction of turn rate.
  static const double _levelGain = 2.5;
  static const double _levelMaxRate = 0.7;

  /// The Gyro Stabiliser kit: a gentler version of the Skate's.
  static const double _kitLevelGain = 1.6;
  static const double _kitLevelMaxRate = 0.5;

  /// Fraction of the local pull the hover assist cancels while thrusting.
  static const double hoverAssistFraction = 0.75;
  double fuel;

  double _rotateInput = 0;
  bool _thrustInput = false;
  bool _fireInput = false;
  double _fireCooldown = 0;

  /// Shells fired this flight (for the "pacifist" check).
  int shotsFired = 0;

  void setInput({required double rotate, required bool thrust, bool fire = false}) {
    _rotateInput = rotate.clamp(-maxRotateInput, maxRotateInput);
    _thrustInput = thrust;
    _fireInput = fire && (spec.armed || (rack?.canFire ?? false));
    if (!_launched && (thrust || _fireInput || rotate.abs() > 0.05)) {
      _launched = true;
      body.gravityScale = null; // gravity on from the first input
    }
  }

  /// The ship hovers on its start pad (no gravity) until the first input or
  /// the start countdown ([launch]), so reading the intro card or a tutorial
  /// hint never ends in a crash.
  bool get launched => _launched;

  /// Ends the hover without input (the level-start countdown ran out).
  void launch() {
    if (_launched) return;
    _launched = true;
    // Wake it too: a ship hovering still on its pad has fallen asleep, and
    // turning gravity on alone wouldn't move it (input forces wake it).
    body
      ..gravityScale = null
      ..setAwake(true);
  }
  bool _launched = false;

  bool get isThrusting => (_thrustInput || _scriptedThrust) && fuel > 0 && !_wrecked;

  /// Demo flight: the ship is placed along a recorded route each frame
  /// (kinematic, so it can neither crash nor drift); [thrust] lights the plume.
  /// [velocity] keeps the body's motion real for anything reading it
  /// (turret lead aim); the next pose overrides any drift.
  void drivePose(Vector2 position, double angle, {required bool thrust, Vector2? velocity}) {
    if (body.bodyType != BodyType.kinematic) {
      body.setType(BodyType.kinematic);
      body.gravityScale = Vector2.zero();
    }
    _scriptedThrust = thrust;
    body
      ..setTransform(position, angle)
      ..linearVelocity.setFrom(velocity ?? Vector2.zero())
      ..angularVelocity = 0;
  }

  bool _scriptedThrust = false;

  bool _wrecked = false;

  /// Crash: hide the hull and kill input; the body keeps simulating so the
  /// rope/cargo react naturally while the explosion plays.
  void wreck() {
    _wrecked = true;
    setInput(rotate: 0, thrust: false);
    throttle = 0;
  }

  /// Undo [wreck] for "continue after crash": back at [position] at rest,
  /// still launched (gravity on, clock running).
  void revive({
    required Vector2 position,
    required double angle,
    required double fuel,
  }) {
    _wrecked = false;
    setInput(rotate: 0, thrust: false);
    throttle = 0;
    _fireCooldown = 0;
    this.fuel = fuel;
    body
      ..setTransform(position, angle)
      ..linearVelocity.setZero()
      ..angularVelocity = 0
      ..setAwake(true);
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

  /// Garage liveries: a tint over the ship's own art (srcATop).
  static const Map<String, Color> _skinTints = {
    'ship_neon': Color(0x88FF00FF),
    'ship_stealth': Color(0xCC000000),
    'ship_gold': Color(0xAAFFD700),
    'ship_carbon': Color(0x99404855),
    'ship_gold_trim': Color(0x55FFD166),
    kSupporterSkinId: Color(0x7733D6C9),
    'ship_xenar': Color(0x7700E5A0),
    'ship_rust': Color(0x88B5651D),
    'ship_glacier': Color(0x77BDEBFF),
    'ship_ember': Color(0x88FF5A1F),
    'ship_orbit': Color(0x777B61FF),
    'ship_redoubt': Color(0x88556B2F),
  };

  @override
  void render(Canvas canvas) {
    if (_wrecked) return;
    super.render(canvas); // no-op when renderBody = false
    final img = _shipImage;
    if (img != null) {
      final skinId = CosmeticsService.getEquippedId(CosmeticsService.catShip);
      final paint = Paint();
      final skinTint = _skinTints[skinId];
      if (skinTint != null) {
        paint.colorFilter = ColorFilter.mode(skinTint, BlendMode.srcATop);
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
      ..linearDamping = spec.linearDamping + kit.dampingAdd
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
    final levels = spec.autoLevel || kit.levelAssist;
    if (idle && levels && _launched && !_thrustInput && localAccel.length2 > 1e-4) {
      // Ease the nose to point against local gravity (θ where the nose
      // (sin θ, −cos θ) = −â).
      final target = math.atan2(-localAccel.x, localAccel.y);
      var diff = (target - body.angle) % (2 * math.pi);
      if (diff > math.pi) diff -= 2 * math.pi;
      final builtIn = spec.autoLevel;
      final maxRate = turnRate * (builtIn ? _levelMaxRate : _kitLevelMaxRate);
      final gain = builtIn ? _levelGain : _kitLevelGain;
      body.angularVelocity = (diff * gain).clamp(-maxRate, maxRate);
    } else if (idle) {
      final t = (FlightTuning.steer.releaseDecay * dt).clamp(0.0, 1.0);
      body.angularVelocity *= 1.0 - t;
    } else {
      // Constant turn rate: 360° in [secondsPerFullRotation] at |input| == 1,
      // up to [ShipSpec.turnBoost] × that in the stick's boost zone.
      final target = _rotateInput * turnRate;
      final spinUp = FlightTuning.steer.spinUp;
      if (spinUp > 0) {
        // Thruster inertia (Smooth): full boosted rate after [spinUp] s.
        final step = turnRate * spec.turnBoost / spinUp * dt;
        final w = body.angularVelocity;
        body.angularVelocity = w + (target - w).clamp(-step, step);
      } else {
        body.angularVelocity = target;
      }
    }

    _updateCannon(dt);

    // Engine spool: the throttle eases toward the input, and thrust, fuel
    // and the hover assist all follow it.
    final firing = _thrustInput && fuel > 0;
    final rate = firing ? 1 / spec.spoolUp : 2 / spec.spoolUp;
    throttle = firing
        ? math.min(1.0, throttle + rate * dt)
        : math.max(0.0, throttle - rate * dt);
    if (fuel <= 0) throttle = 0;
    if (throttle > 0) {
      fuel -= spec.fuelDrainPerSecond * kit.fuelDrainMul * fuelDrainMultiplier * throttle * dt;
      if (fuel < 0) fuel = 0;
      final dir = body.worldVector(Vector2(0, -1))
        ..scale(spec.thrustForce * throttle);
      body.applyForce(dir);
      if (spec.hoverAssist) {
        // Fly-by-wire: cancel most of the local pull while the engine burns.
        body.applyForce(localAccel * (-hoverAssistFraction * body.mass * throttle));
      }
    }
  }

  /// Engine output 0…1 (see [ShipSpec.spoolUp]).
  double throttle = 0;

  final WorldManifold _manifold = WorldManifold();

  /// Rock is forgiving: slow touches scrape or land ([classifyHullContact]),
  /// fast ones crash. Runs before the solver, so the velocity is the one
  /// the ship hit with.
  void _onRockContact(Contact contact) {
    if (_wrecked) return;
    contact.getWorldManifold(_manifold);
    final count = contact.manifold.pointCount;
    if (count == 0) return;
    // The manifold normal points from fixture A to B; flip it so it points
    // out of the rock toward the ship.
    final shipIsA = contact.fixtureA.body == body;
    final normal = shipIsA ? -_manifold.normal : _manifold.normal.clone();
    final point = count > 1
        ? (_manifold.points[0] + _manifold.points[1]) * 0.5
        : _manifold.points[0].clone();

    final approach = -body.linearVelocity.dot(normal);
    final up = localAccel.length2 > 1e-4
        ? -(localAccel.normalized())
        : normal; // zero-g: any surface you settle on is "down"
    final nose = body.worldVector(Vector2(0, -1));
    final onBase = body.localPoint(point).y >= rearLocalY * 0.5;
    final kind = classifyHullContact(
      approachSpeed: approach,
      onBase: onBase,
      tiltCos: nose.dot(up),
      groundCos: normal.dot(up),
    );
    if (kind == HullContact.crash) {
      onWallHit();
    } else {
      onRockTouch?.call(point, normal, kind);
    }
  }

  void _updateCannon(double dt) {
    if (_fireCooldown > 0) _fireCooldown -= dt;
    _laserFiring = false;
    if (!_fireInput || _wrecked || !_launched) return;
    final r = rack;
    final weapon = r?.selected ?? (spec.armed ? kCannon : null);
    if (weapon == null) return;
    if (weapon.kind != WeaponKind.cannon) {
      if (weapon.continuous) {
        if (r!.spend(weapon.id, dt)) {
          _laserFiring = true;
          onWeapon?.call(weapon, dt);
        }
        return;
      }
      if (_fireCooldown > 0 || !r!.spend(weapon.id, 1)) return;
      _fireCooldown = weapon.cooldown;
      shotsFired++;
      onWeapon?.call(weapon, dt);
      return;
    }
    if (!spec.armed || _fireCooldown > 0) return;
    final shot = spec.fuelPerShot * fuelDrainMultiplier;
    if (fuel < shot) return;
    fuel -= shot;
    _fireCooldown = spec.fireCooldown;
    shotsFired++;
    final dir = body.worldVector(Vector2(0, -1));
    final muzzle = body.worldPoint(Vector2(0, spec.noseLocalY - 0.1));
    onFire?.call(muzzle, body.linearVelocity + dir * spec.muzzleSpeed);
  }

  /// Demo flight: one recorded shot from the current pose ([shipVelocity]
  /// from the recording; a kinematic replay has no velocity of its own).
  void fireScripted(Vector2 shipVelocity) {
    final dir = body.worldVector(Vector2(0, -1));
    final muzzle = body.worldPoint(Vector2(0, spec.noseLocalY - 0.1));
    onFire?.call(muzzle, shipVelocity + dir * spec.muzzleSpeed);
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (other is RockTag) {
      _onRockContact(contact);
    } else if (other is WallTag) {
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
