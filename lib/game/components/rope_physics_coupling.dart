import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/rope_segment_body.dart';
import 'package:narrow_haul/game/components/ship_body.dart';

/// Ship ↔ rope segment ↔ cargo with [RevoluteJoint]s. Rope length is fixed at attach (rigid bar).
class RopePhysicsCoupling extends Component with HasGameReference<Forge2DGame> {
  RopePhysicsCoupling({
    required this.ship,
    required this.cargo,
  });

  final ShipBody ship;
  final CargoBody cargo;

  RopeSegmentBody? _rope;
  Joint? _jointShipRope;
  Joint? _jointRopeCargo;

  RopeSegmentBody? get ropeSegment => _rope;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final anchorShip = ship.body.worldPoint(Vector2(0, ShipBody.rearLocalY));
    final anchorCargo = cargo.body.worldCenter;
    final delta = anchorCargo - anchorShip;
    final dist = delta.length;
    if (dist < 0.08) return;

    final angle = math.atan2(delta.y, delta.x);
    final halfLen = dist * 0.5;
    final mid = (anchorShip + anchorCargo) * 0.5;

    final rope = RopeSegmentBody(
      center: mid,
      angle: angle,
      halfLength: halfLen,
    );
    _rope = rope;
    await game.world.add(rope);

    final j1 = RevoluteJointDef<Body, Body>()
      ..collideConnected = false
      ..initialize(ship.body, rope.body, anchorShip);
    _jointShipRope = RevoluteJoint(j1);
    game.world.createJoint(_jointShipRope!);

    final j2 = RevoluteJointDef<Body, Body>()
      ..collideConnected = false
      ..initialize(rope.body, cargo.body, anchorCargo);
    _jointRopeCargo = RevoluteJoint(j2);
    game.world.createJoint(_jointRopeCargo!);
  }

  @override
  void onRemove() {
    if (_jointShipRope != null) {
      game.world.destroyJoint(_jointShipRope!);
      _jointShipRope = null;
    }
    if (_jointRopeCargo != null) {
      game.world.destroyJoint(_jointRopeCargo!);
      _jointRopeCargo = null;
    }
    _rope?.removeFromParent();
    _rope = null;
    super.onRemove();
  }
}
