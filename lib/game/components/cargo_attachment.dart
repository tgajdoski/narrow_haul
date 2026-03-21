import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/rope_line.dart';
import 'package:narrow_haul/game/components/rope_physics_coupling.dart';
import 'package:narrow_haul/game/components/ship_body.dart';

/// Rope preview near cargo, then hook contact → [RopePhysicsCoupling] (ship–rope–cargo).
class CargoAttachment extends Component with HasGameReference<Forge2DGame> {
  CargoAttachment({
    required this.ship,
    required this.cargo,
  });

  final ShipBody ship;
  final CargoBody cargo;

  /// ~3.5× approximate hull length — rope UI only appears inside this range.
  static const double approachDistanceMeters = 2.5;

  /// Seconds to fade rope in from 0 → 1 while in range (not yet hooked).
  static const double ropeRevealDuration = 1.15;

  /// Minimum rope visibility (0–1) before a hook contact can attach.
  static const double minRevealToAttach = 0.35;

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

    final d = (ship.body.position - cargo.body.position).length;
    if (d < approachDistanceMeters) {
      ropeRevealProgress = (ropeRevealProgress + dt / ropeRevealDuration).clamp(0.0, 1.0);
    } else {
      ropeRevealProgress = (ropeRevealProgress - dt * 0.55).clamp(0.0, 1.0);
    }
  }

  /// Called from [ShipBody] when the hook sensor touches cargo.
  void onHookCargoTouch() {
    if (attached || _attaching) return;
    if (ropeRevealProgress < minRevealToAttach) return;
    _attach();
  }

  Future<void> _attach() async {
    _attaching = true;
    try {
      final coupling = RopePhysicsCoupling(
        ship: ship,
        cargo: cargo,
      );
      await add(coupling);
      if (coupling.ropeSegment == null) return;

      _coupling = coupling;
      attached = true;
      ropeRevealProgress = 1.0;
    } finally {
      _attaching = false;
    }
  }
}
