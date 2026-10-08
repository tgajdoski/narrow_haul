import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/tags.dart';

class CargoBody extends BodyComponent {
  CargoBody({
    required Vector2 initialPosition,
    this.densityMul = 1.0,
    this.clamped = false,
    ui.Image? image,
    this.strapped = false,
  })
    : _initialPosition = initialPosition,
      _cargoImage = image,
      super(
        paint: Paint()..color = const Color(0xFFE07A5F),
      );

  final Vector2 _initialPosition;

  /// Heavy-cargo level modifier (multiplies the base density of 2.0).
  final double densityMul;

  /// Cargo lock: held in place (kinematic) until hooked, so zero-g or a
  /// nearby well can't carry it off before the pilot arrives.
  final bool clamped;

  /// Heavy pod without its own art: steel straps drawn over the sprite.
  final bool strapped;

  /// Frees a clamped pod to the physics world (called on attach).
  void release() {
    if (body.bodyType == BodyType.dynamic) return;
    body.setType(BodyType.dynamic);
    body.setAwake(true);
  }

  /// Demo flight: placed along a recorded route each frame.
  void drivePosition(Vector2 position) {
    if (body.bodyType != BodyType.kinematic) body.setType(BodyType.kinematic);
    body
      ..setTransform(position, body.angle)
      ..linearVelocity.setZero()
      ..angularVelocity = 0;
  }

  /// Smaller than ship hull (~33% reduced from prior 0.14 m).
  static const double radius = kCargoRadius;

  /// The world's pod art (`assets/themes/<id>/cargo.png`), else the shared
  /// `cargo.png`, else the plain circle.
  ui.Image? _cargoImage;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _cargoImage ??= await Flame.images.load('cargo.png');
    } catch (_) {}
    if (_cargoImage != null) renderBody = false;
  }

  // Every cargo sprite's disc fills 80% of the image; drawn at 1.15× the collision
  // radius it reads as the pod's real size (a little rim to spare).
  static const double _spriteHalf = radius * 1.15 / 0.8;

  /// Rolling resistance on rock (1/s): a ball on Box2D's frictionless-rolling
  /// floor would roll forever, e.g. out of the pad sensors after the ship
  /// settles on it. Spin decays at this rate while the pod touches rock.
  static const double rollingDecay = 2.5;

  @override
  void update(double dt) {
    super.update(dt);
    if (body.bodyType != BodyType.dynamic || !_onStaticGround()) return;
    final t = (rollingDecay * dt).clamp(0.0, 1.0);
    body.angularVelocity *= 1.0 - t;
  }

  bool _onStaticGround() {
    for (final c in body.contacts) {
      if (!c.isTouching() || c.fixtureA.isSensor || c.fixtureB.isSensor) continue;
      final other = c.bodyA == body ? c.bodyB : c.bodyA;
      if (other.bodyType == BodyType.static) return true;
    }
    return false;
  }

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
    if (strapped) _renderStraps(canvas);
  }

  static final Paint _strapPaint = Paint()..color = const Color(0xE62B2F36);
  static final Paint _strapEdge = Paint()
    ..color = const Color(0xCC9AA3AD)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.008;

  // Two steel bands across the pod, clipped to its disc; they roll with it.
  void _renderStraps(Canvas canvas) {
    const r = _spriteHalf * 0.8;
    const w = r * 0.24;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)));
    for (final x in const [-r * 0.42, r * 0.42]) {
      final band = Rect.fromLTRB(x - w / 2, -r, x + w / 2, r);
      canvas.drawRect(band, _strapPaint);
      canvas.drawRect(band, _strapEdge);
    }
    canvas.restore();
  }

  @override
  Body createBody() {
    final def = BodyDef()
      ..position = _initialPosition
      ..type = clamped ? BodyType.kinematic : BodyType.dynamic
      ..angularDamping = 0.6
      ..linearDamping = 0.05;
    final body = world.createBody(def);
    body.userData = const CargoTag();
    body.createFixture(
      FixtureDef(
        CircleShape()..radius = radius,
        density: kCargoDensity * densityMul,
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
