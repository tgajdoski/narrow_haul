import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/rope_line.dart';
import 'package:narrow_haul/game/components/rope_physics_coupling.dart';
import 'package:narrow_haul/game/components/combat.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/components/tractor_beam_coupling.dart';
import 'package:narrow_haul/game/components/tractor_beam_line.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/ship/loadout.dart';

/// Rope preview near cargo, then [RopePhysicsCoupling] (tow). Attach uses hook proximity or ship–cargo distance.
/// With a tractor beam ([RopeSpec.isBeam]) it locks on from [RopeSpec.beamRange]
/// through clear line of sight instead, and drops the pod when the beam breaks.
class CargoAttachment extends Component with HasGameReference<Forge2DGame> {
  CargoAttachment({
    required this.ship,
    required this.cargo,
    required this.ropeMaxLengthMeters,
    this.rope = kStockRope,
    this.onAttached,
  });

  /// Tow gear equipped for this flight.
  final RopeSpec rope;

  /// Called once when the rope successfully attaches to cargo.
  final void Function()? onAttached;

  final ShipBody ship;
  final CargoBody cargo;

  /// Design max tow length from level ([LevelData.ropeMaxLength]).
  final double ropeMaxLengthMeters;

  /// Rope UI fades in while ship–cargo centers are within this range (stock rope).
  static const double approachDistanceMeters = 3.0;

  static const double ropeRevealDuration = 1.15;

  static const double minRevealToAttach = 0.05;

  /// Winch hook (under the tail) can “grab” this far beyond touching the pod.
  static const double hookCatchExtraMeters = kStockHookReach;

  /// If hull centers are this close (m), attach even if the hook circle misses (gameplay-friendly).
  static const double attachCenterDistanceMax = kAttachCenterBase;

  bool attached = false;
  double ropeRevealProgress = 0;

  /// Demo flight: the recording says when the pod is in tow; no rope joint
  /// is made (both bodies are kinematic), only the rope is drawn.
  bool Function()? scriptedTow;

  RopePhysicsCoupling? _coupling;
  TractorBeamCoupling? _beam;
  bool _attaching = false;

  /// After a beam breaks it can't re-lock straight away.
  double _relockIn = 0;
  static const double _relockDelay = 0.6;

  /// The pilot dropped the pod: no catch until it has been out of reach
  /// once, so it doesn't snap straight back onto the hook.
  bool _rehookBlocked = false;

  /// Whether the pilot can drop the pod or winch the line right now.
  bool get canRelease => attached && scriptedTow == null && !_attaching;
  bool get canWinch => canRelease && _coupling != null;

  /// Called when the pilot drops the pod.
  void Function()? onReleased;

  /// The pilot drops the pod (TOW tap, E): the line or beam lets go.
  void release() {
    if (!canRelease) return;
    _coupling?.removeFromParent();
    _coupling = null;
    _beam?.removeFromParent();
    _beam = null;
    attached = false;
    _rehookBlocked = true;
    _lastAngle = null;
    _accumulatedAngle = 0;
    onReleased?.call();
  }

  /// The pilot's winch: [axis] −1 reels in, +1 pays out (see
  /// [RopePhysicsCoupling.winch]).
  void winch(double axis, double dt) {
    if (canWinch) _coupling!.winch(axis, dt);
  }

  /// The current line length (m), null when not on a rope.
  double? get lineLength => _coupling?.tetherLengthMeters;

  double _accumulatedAngle = 0;
  double? _lastAngle;
  bool _swingerUnlocked = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await add(
      rope.isBeam
          ? TractorBeamLine(
              ship: ship,
              cargo: cargo,
              progress: () => ropeRevealProgress,
              attached: () => attached,
              getCoupling: () => _beam,
            )
          : RopeLine(
              ship: ship,
              cargo: cargo,
              progress: () => ropeRevealProgress,
              attached: () => attached,
              getCoupling: () => _coupling,
              rope: rope,
            ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    final scripted = scriptedTow;
    if (scripted != null) {
      attached = scripted();
      final near = (ship.body.position - cargo.body.position).length < rope.approachDistance;
      ropeRevealProgress = attached
          ? 1.0
          : (ropeRevealProgress + (near ? dt / ropeRevealDuration : -dt * 0.55)).clamp(0.0, 1.0);
      return;
    }
    if (attached && (_beam?.broken ?? false)) _dropBeam();
    if (_relockIn > 0) _relockIn -= dt;
    if (attached) {
      if (!_swingerUnlocked) {
        final diff = cargo.body.position - ship.body.position;
        final angle = math.atan2(diff.y, diff.x);
        if (_lastAngle != null) {
          var delta = angle - _lastAngle!;
          while (delta > math.pi) {
            delta -= 2 * math.pi;
          }
          while (delta < -math.pi) {
            delta += 2 * math.pi;
          }
          _accumulatedAngle += delta;
          if (_accumulatedAngle.abs() >= 2 * math.pi) {
            _swingerUnlocked = true;
            AchievementService.unlock(AchievementIds.cargoSwinger, announce: true);
          }
        }
        _lastAngle = angle;
      }
      return;
    }

    final centerDist = (ship.body.position - cargo.body.position).length;
    if (centerDist < rope.approachDistance) {
      ropeRevealProgress = (ropeRevealProgress + dt / ropeRevealDuration).clamp(0.0, 1.0);
    } else {
      ropeRevealProgress = (ropeRevealProgress - dt * 0.55).clamp(0.0, 1.0);
    }

    if (_rehookBlocked) {
      // Clear of every way the hook catches: the next approach may hook it.
      final hookAt = ship.body.worldPoint(ship.hookLocal);
      final reach = ship.hookRadius + CargoBody.radius + rope.hookReach + 0.6;
      final beamClear = !rope.isBeam ||
          (cargo.body.worldCenter - ship.body.worldPoint(Vector2(0, ship.rearLocalY))).length >
              rope.beamRange + 0.6;
      if ((hookAt - cargo.body.worldCenter).length > reach &&
          centerDist > rope.attachCenterDistance + 0.3 &&
          beamClear) {
        _rehookBlocked = false;
      }
    }
    if (_attaching || _relockIn > 0 || _rehookBlocked) return;
    if (ropeRevealProgress < minRevealToAttach) return;

    if (rope.isBeam) {
      final winch = ship.body.worldPoint(Vector2(0, ship.rearLocalY));
      final pod = cargo.body.worldCenter;
      if ((pod - winch).length <= rope.beamRange &&
          ship.fuel > 0 &&
          hasLineOfSight(game.world, winch, pod, ignore: cargo.body)) {
        _attach();
      }
      return;
    }

    final hookWorld = ship.body.worldPoint(ship.hookLocal);
    final cargoCenter = cargo.body.worldCenter;
    final hookToCargo = (hookWorld - cargoCenter).length;
    final catchRadius = ship.hookRadius + CargoBody.radius + rope.hookReach;

    final hookOk = hookToCargo <= catchRadius;
    // The wide side catch must not hook a pod through a wall.
    final centerOk = centerDist <= rope.attachCenterDistance &&
        hasLineOfSight(game.world, ship.body.worldPoint(Vector2(0, ship.rearLocalY)), cargoCenter, ignore: cargo.body);
    if (hookOk || centerOk) {
      _attach();
    }
  }

  void onHookCargoTouch() {
    if (attached || _attaching || scriptedTow != null || _relockIn > 0 || _rehookBlocked) return;
    if (ropeRevealProgress < minRevealToAttach) return;
    if (rope.isBeam && ship.fuel <= 0) return;
    _attach();
  }

  Future<void> _attach() async {
    if (attached || _attaching) return;
    _attaching = true;
    try {
      cargo.release(); // a locked pod comes free once hooked
      if (rope.isBeam) {
        final beam = TractorBeamCoupling(ship: ship, cargo: cargo, rope: rope);
        await add(beam);
        _beam = beam;
        attached = true;
        ropeRevealProgress = 1.0;
        onAttached?.call();
        return;
      }
      final coupling = RopePhysicsCoupling(
        ship: ship,
        cargo: cargo,
        ropeMaxLengthMeters: ropeMaxLengthMeters,
        rope: rope,
      );
      await add(coupling);
      if (!coupling.isTethered) return;

      _coupling = coupling;
      attached = true;
      ropeRevealProgress = 1.0;
      onAttached?.call();
    } finally {
      _attaching = false;
    }
  }

  /// Beam lost: the pod falls free and can be locked again shortly.
  void _dropBeam() {
    _beam?.removeFromParent();
    _beam = null;
    attached = false;
    _relockIn = _relockDelay;
    _lastAngle = null;
    _accumulatedAngle = 0;
    onBeamLost?.call();
  }

  /// Called when a tractor beam breaks (sound / haptics).
  void Function()? onBeamLost;
}
