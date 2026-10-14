import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/camera.dart';
import 'package:flame/experimental.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:narrow_haul/game/camera/camera_director.dart';
import 'package:narrow_haul/game/components/rock_proximity.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';

/// What the camera needs from the flight each frame.
class CameraFrame {
  const CameraFrame({
    required this.ship,
    required this.worldSize,
    required this.towing,
    required this.pod,
    required this.delivered,
    required this.demo,
  });

  final ShipBody ship;
  final Vector2 worldSize;

  /// Towing the pod ([pod] is where it is, else null).
  final bool towing;
  final Vector2? pod;

  /// Ship and pod are on the pad: a close-up frames both.
  final bool delivered;
  final bool demo;
}

/// The flight camera: follow (focus and zoom from the pure
/// [CameraDirector]), the safe frame clear of the controls, close-ups,
/// trauma shake and the world bounds. The game feeds it a [CameraFrame]
/// and pokes [shake] / [closeUp] on events.
class CameraRig {
  CameraRig(this.camera, {required this.world});

  final CameraComponent camera;
  final Forge2DWorld world;

  /// Decides focus and zoom from the flight; this class only clamps it to
  /// the world and adds the shake.
  final CameraDirector director = CameraDirector(FlightTuning.camera.profile);

  /// Crash, blasts and the meltdown rumble, added after the follow.
  final TraumaShake shake = TraumaShake();

  /// Level-start close-up of the ship and the delivery push-in.
  final CloseUp closeUp = CloseUp();

  /// The system asks for reduced motion (set by the app): softer zoom and
  /// shake.
  bool reducedMotion = false;

  /// Seconds since the player last thrust, turned or fired (the camera
  /// zooms in once they let go).
  double idleFor = 0;

  /// Flight zoom (px/m) before the camera mode's multiplier (it follows
  /// the screen size).
  double Function() baseZoom = () => 28;

  /// Screen rects (px) the ship should keep out from under: the touch
  /// controls and the top-left gauges.
  List<({double l, double t, double r, double b})> Function() avoidZones =
      () => const [];

  /// Close-up zooms (× the flight zoom): a first look at a new mission, a
  /// new ship's first flight (shown off longest), and a quick one on retry.
  static const double closeUpFirst = 2.2;
  static const double closeUpNewShip = 2.6;
  static const double closeUpRetry = 1.5;
  static const double closeUpDelivery = 1.5;

  /// Where the ship sits in a close-up (fraction of the screen height):
  /// below the level card (top third) and the 3 · 2 · 1 (centre).
  static const double closeUpShipY = 0.72;

  /// Smallest zoom that still keeps the view inside the world.
  double _minContainZoom = 0;
  Vector2 _shakeApplied = Vector2.zero();

  /// Rock along the velocity, refreshed every other frame.
  double? _aheadGap;
  bool _aheadTick = false;

  /// Camera shift (m) that keeps the ship out from under the controls,
  /// eased in quickly and out slowly.
  final Spring _nudgeX = Spring();
  final Spring _nudgeY = Spring();

  /// Opens a level on the ship: it holds through the level card, then
  /// eases out over 3 · 2 · 1 to the flight view at GO. Without a
  /// [countdown] (onboarding) it holds until the first input.
  void startCloseUp({
    required bool retry,
    required bool newShip,
    required double? countdown,
    required bool enabled,
  }) {
    closeUp.reset();
    if (!enabled || FlightTuning.camera.profile.isStatic) return;
    var peak = retry ? closeUpRetry : (newShip ? closeUpNewShip : closeUpFirst);
    if (reducedMotion) peak = 1 + (peak - 1) * 0.4;
    closeUp.intro(
      peak: peak,
      hold: countdown == null ? double.infinity : countdown - 3,
      out: 3,
    );
  }

  /// The delivery push-in on ship and pod, held for [hold] seconds.
  void pushInForDelivery(double hold) =>
      closeUp.pushIn(reducedMotion ? 1.2 : closeUpDelivery, hold);

  /// Zoom floor and Flame bounds for a world of [worldSize].
  void fitWorld(Vector2 worldSize) {
    final viewportSize = camera.viewport.size;
    if (viewportSize.x > 0 && viewportSize.y > 0) {
      final minZoomX = viewportSize.x / worldSize.x;
      final minZoomY = viewportSize.y / worldSize.y;
      _minContainZoom = math.max(minZoomX, minZoomY) * 1.01;
      camera.viewfinder.zoom =
          math.max(_restZoom * director.zoom, _minContainZoom);
    }
    // Flame's own bounds allow the overscroll; [_clamped] keeps the view
    // inside the world unless the controls need the room.
    camera.setBounds(
      Rectangle.fromLTRB(
        -kCameraOverscroll,
        -kCameraOverscrollTop,
        worldSize.x + kCameraOverscroll,
        worldSize.y + kCameraOverscroll,
      ),
      considerViewport: true,
    );
  }

  /// Normal zoom for the camera mode, never showing outside the world.
  double get _restZoom => math.max(
    baseZoom() * FlightTuning.camera.profile.zoomMul,
    _minContainZoom,
  );

  void follow(CameraFrame f, double dt) {
    final s = f.ship;
    director.profile = FlightTuning.camera.profile;
    final vel = s.body.linearVelocity;
    final speed = vel.length;
    if (_aheadTick = !_aheadTick) {
      _aheadGap = speed > 0.5 && director.profile.impactZoomOut > 0
          ? probeAhead(world, s, vel / speed)
          : null;
    }
    final pod = f.towing ? f.pod : null;
    // Local gravity (fields included) sets "down"; none in zero-g.
    final g = s.localAccel;
    final gLen = g.length;
    final down = gLen > 0.2 * baseGravityY() ? g / gLen : Vector2.zero();
    final restZoom = _restZoom;
    final view = camera.viewport.size;
    final shot = director.update(
      CameraInputs(
        shipX: s.body.position.x,
        shipY: s.body.position.y,
        velX: vel.x,
        velY: vel.y,
        launched: s.launched,
        towing: f.towing,
        podX: pod?.x,
        podY: pod?.y,
        aheadGap: _aheadGap,
        downX: down.x,
        downY: down.y,
        idleFor: f.demo ? 0 : idleFor,
        viewHalfW: view.x / restZoom / 2,
        viewHalfH: view.y / restZoom / 2,
      ),
      dt,
    );
    // Reduced motion halves the zoom swings (in log space).
    final factor = reducedMotion ? math.sqrt(shot.zoom) : shot.zoom;
    if (s.launched) closeUp.release();
    closeUp.update(dt);
    final close = closeUp.factor;
    final zoom = math.max(restZoom * factor * close, _minContainZoom);
    camera.viewfinder.zoom = zoom;
    var focus = Vector2(shot.x, shot.y);
    final w = closeUp.weight;
    if (w > 0) {
      // Frame the subject: the ship a little low (level start), or ship
      // and pod together on the pad (delivery).
      final podNow = f.pod;
      final subject = f.delivered && podNow != null
          ? (s.body.position + podNow) / 2
          : s.body.position -
                Vector2(0, (closeUpShipY - 0.5) * view.y / zoom);
      focus += (subject - focus) * w;
    }
    final base = _clamped(focus, f.worldSize);
    final want = _safeFrameShift(s, base, demo: f.demo);
    double time(Spring n, double w) => w.abs() > n.x.abs() ? 0.3 : 0.8;
    _nudgeX.step(want.x, time(_nudgeX, want.x), dt);
    _nudgeY.step(want.y, time(_nudgeY, want.y), dt);
    camera.viewfinder.position = _clamped(
      base + Vector2(_nudgeX.x, _nudgeY.x),
      f.worldSize,
      overscroll: true,
    );
  }

  /// Screen boxes (px) round the ship and the pod, for help text to keep
  /// off.
  List<Rect> shipShield(ShipBody s, Vector2? pod) {
    final zoom = camera.viewfinder.zoom;
    Rect box(Vector2 p, double r) {
      final c = camera.localToGlobal(p);
      return Rect.fromCircle(center: Offset(c.x, c.y), radius: r * zoom + 10);
    }

    return [
      box(s.body.position, s.spec.circumradius),
      if (pod != null) box(pod, kCargoRadius),
    ];
  }

  /// Camera shift (m) from [base] that keeps the ship clear of the
  /// [avoidZones]. Near the world's floor or walls the clamp would leave
  /// the ship under THRUST or the dial; this lets the view look a little
  /// past the edge.
  Vector2 _safeFrameShift(ShipBody s, Vector2 base, {required bool demo}) {
    final view = camera.viewport.size;
    final zoom = camera.viewfinder.zoom;
    if (demo || view.x <= 0 || zoom <= 0) return Vector2.zero();
    final zones = avoidZones();
    if (zones.isEmpty) return Vector2.zero();
    final p = (s.body.position - base) * zoom + view / 2;
    final (dx, dy) = safeFrameNudge(
      p.x,
      p.y,
      s.spec.circumradius * 0.7 * zoom,
      zones,
      view.x,
      view.y,
    );
    // The ship moves by (dx, dy) px when the camera moves the other way.
    return Vector2(-dx, -dy) / zoom;
  }

  /// Takes last frame's shake out of the camera, so nothing reads or keeps
  /// it.
  void removeShake() {
    if (_shakeApplied.x == 0 && _shakeApplied.y == 0) return;
    camera.viewfinder.position -= _shakeApplied;
    _shakeApplied = Vector2.zero();
  }

  /// Adds this frame's shake on top of the settled camera. The meltdown
  /// rumble ([TraumaShake.floor]) only runs while [meltdown] is on.
  void applyShake(double dt, {required bool meltdown}) {
    if (!meltdown) shake.floor = 0;
    shake
      ..scale = reducedMotion ? 0.3 : 1
      ..update(dt);
    final (x, y) = shake.offset;
    if (x == 0 && y == 0) return;
    _shakeApplied = Vector2(x, y);
    camera.viewfinder.position += _shakeApplied;
  }

  /// Puts the camera on the ship at once, already clear of the controls.
  void snapTo(ShipBody s, Vector2 worldSize, {required bool demo}) {
    director
      ..profile = FlightTuning.camera.profile
      ..reset(s.body.position.x, s.body.position.y);
    shake.clear();
    _shakeApplied = Vector2.zero();
    _aheadGap = null;
    idleFor = 0;
    camera.viewfinder.zoom = math.max(_restZoom, _minContainZoom);
    final base = _clamped(s.body.position, worldSize);
    // Start already clear of the controls (a pad on the world's floor).
    final shift = _safeFrameShift(s, base, demo: demo);
    _nudgeX.set(shift.x);
    _nudgeY.set(shift.y);
    camera.viewfinder.position =
        _clamped(base + shift, worldSize, overscroll: true);
  }

  /// Keeps the view inside the world, or with [overscroll] up to
  /// [kCameraOverscroll] past it (the rock is drawn that far out).
  Vector2 _clamped(Vector2 desired, Vector2 worldSize, {bool overscroll = false}) {
    final viewportSize = camera.viewport.size;
    final zoom = camera.viewfinder.zoom;
    if (viewportSize.x <= 0 || viewportSize.y <= 0 || zoom <= 0) return desired;

    final halfViewW = (viewportSize.x / zoom) / 2;
    final halfViewH = (viewportSize.y / zoom) / 2;
    final side = overscroll ? kCameraOverscroll : 0.0;
    final top = overscroll ? kCameraOverscrollTop : 0.0;

    final minX = halfViewW - side;
    final maxX = worldSize.x - halfViewW + side;
    final minY = halfViewH - top;
    final maxY = worldSize.y - halfViewH + side;

    final x = minX > maxX ? worldSize.x / 2 : desired.x.clamp(minX, maxX);
    final y = minY > maxY ? worldSize.y / 2 : desired.y.clamp(minY, maxY);
    return Vector2(x.toDouble(), y.toDouble());
  }
}
