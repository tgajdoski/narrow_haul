import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/rope_line.dart';
import 'package:narrow_haul/game/components/rope_physics_coupling.dart';
import 'package:narrow_haul/game/components/ship_body.dart';

/// Rope preview near cargo, then [RopePhysicsCoupling] (tow). Attach uses hook proximity or ship–cargo distance.
class CargoAttachment extends Component with HasGameReference<Forge2DGame> {
  CargoAttachment({
    required this.ship,
    required this.cargo,
  });

  final ShipBody ship;
  final CargoBody cargo;

  /// Rope UI fades in while ship–cargo centers are within this range.
  static const double approachDistanceMeters = 2.5;

  static const double ropeRevealDuration = 1.15;

  static const double minRevealToAttach = 0.05;

  /// Nose hook can “grab” within this radius of cargo center.
  static const double hookCatchExtraMeters = 0.35;

  /// If hull centers are this close (m), attach even if the hook circle misses (gameplay-friendly).
  static const double attachCenterDistanceMax = 1.2;

  bool attached = false;
  double ropeRevealProgress = 0;

  RopePhysicsCoupling? _coupling;
  bool _attaching = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await add(
      RopeLine(
        ship: ship,
        cargo: cargo,
        progress: () => ropeRevealProgress,
        attached: () => attached,
        getCoupling: () => _coupling,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (attached) return;

    final centerDist = (ship.body.position - cargo.body.position).length;
    if (centerDist < approachDistanceMeters) {
      ropeRevealProgress = (ropeRevealProgress + dt / ropeRevealDuration).clamp(0.0, 1.0);
    } else {
      ropeRevealProgress = (ropeRevealProgress - dt * 0.55).clamp(0.0, 1.0);
    }

    if (_attaching) return;
    if (ropeRevealProgress < minRevealToAttach) return;

    final hookWorld = ship.body.worldPoint(ShipBody.hookLocal);
    final cargoCenter = cargo.body.worldCenter;
    final hookToCargo = (hookWorld - cargoCenter).length;
    final catchRadius = ShipBody.hookRadius + CargoBody.radius + hookCatchExtraMeters;

    final hookOk = hookToCargo <= catchRadius;
    final centerOk = centerDist <= attachCenterDistanceMax;
    if (hookOk || centerOk) {
      _attach();
    }
  }

  void onHookCargoTouch() {
    if (attached || _attaching) return;
    if (ropeRevealProgress < minRevealToAttach) return;
    _attach();
  }

  Future<void> _attach() async {
    if (attached || _attaching) return;
    _attaching = true;
    try {
      final coupling = RopePhysicsCoupling(
        ship: ship,
        cargo: cargo,
      );
      await add(coupling);
      if (!coupling.isTethered) return;

      _coupling = coupling;
      attached = true;
      ropeRevealProgress = 1.0;
    } finally {
      _attaching = false;
    }
  }
}
