import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/ship_body.dart';

/// Winch ↔ cargo using [RopeJoint] (max length), or [DistanceJoint] if span is very short.
class RopePhysicsCoupling extends Component with HasGameReference<Forge2DGame> {
  RopePhysicsCoupling({
    required this.ship,
    required this.cargo,
    required this.ropeMaxLengthMeters,
  });

  final ShipBody ship;
  final CargoBody cargo;

  /// Level design cap ([LevelData.ropeMaxLength]); tow length at attach is `min(dist, this)`.
  final double ropeMaxLengthMeters;

  Joint? _ropeJoint;
  Joint? _distanceJoint;

  /// [RopeJoint.maxLength] or [DistanceJoint]'s fixed length after attach.
  double? _tetherLengthMeters;

  double? get tetherLengthMeters => _tetherLengthMeters;

  /// True once ship–cargo tow joint exists.
  bool get isTethered => _ropeJoint != null || _distanceJoint != null;

  /// Slightly above Forge2D linearSlop (~0.005) so [RopeJointDef.maxLength] is valid.
  static const double _minRopeMaxLength = 0.0125;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final anchorShip = ship.body.worldPoint(Vector2(0, ShipBody.rearLocalY));
    final anchorCargo = cargo.body.worldCenter;
    final delta = anchorCargo - anchorShip;
    final dist = delta.length;
    if (dist < 0.04) return;

    // Very short: fixed distance keeps stability (same as prior bar fallback).
    if (dist < 0.12) {
      final def = DistanceJointDef<Body, Body>()..collideConnected = false;
      def.initialize(ship.body, cargo.body, anchorShip, anchorCargo);
      _distanceJoint = DistanceJoint(def);
      _tetherLengthMeters = def.length;
      game.world.createJoint(_distanceJoint!);
      return;
    }

    final maxLength = dist.clamp(_minRopeMaxLength, ropeMaxLengthMeters);
    final def = RopeJointDef<Body, Body>()..collideConnected = false;
    def.bodyA = ship.body;
    def.bodyB = cargo.body;
    def.localAnchorA.setFrom(ship.body.localPoint(anchorShip));
    def.localAnchorB.setFrom(cargo.body.localPoint(anchorCargo));
    def.maxLength = maxLength;
    _ropeJoint = RopeJoint(def);
    _tetherLengthMeters = maxLength;
    game.world.createJoint(_ropeJoint!);
  }

  @override
  void onRemove() {
    if (_ropeJoint != null) {
      game.world.destroyJoint(_ropeJoint!);
      _ropeJoint = null;
    }
    if (_distanceJoint != null) {
      game.world.destroyJoint(_distanceJoint!);
      _distanceJoint = null;
    }
    _tetherLengthMeters = null;
    super.onRemove();
  }
}
