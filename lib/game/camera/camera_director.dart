import 'dart:math' as math;

/// A 2D follow camera for a thrust/cave flyer, as pure Dart (no Flame), so
/// it runs headless in tests and ports to another game unchanged. See
/// `docs/CAMERA.md` for the reasoning behind each behaviour.
///
/// The director decides *where* to look and *how far out*; the game only
/// applies the result to its engine camera (world clamp, base zoom, shake).
/// All smoothing is frame-rate independent.

/// Tuning for one camera mode. Zoom amounts are fractions of the rest zoom
/// (0.2 = 20% further out); times are in seconds; distances in metres.
class CameraProfile {
  const CameraProfile({
    this.lead = 0,
    this.leadMax = 2,
    this.leadTime = 0.45,
    this.downBias = 0,
    this.deadZone = 0,
    this.speedLo = 1.0,
    this.speedHi = 3.5,
    this.speedZoomOut = 0,
    this.impactZoomOut = 0,
    this.impactSeconds = 1.5,
    this.restZoomIn = 0,
    this.restDelay = 1.0,
    this.towZoomOut = 0,
    this.podFraming = false,
    this.podWeight = 0.35,
    this.podMargin = 0.18,
    this.zoomMul = 1,
    this.outTime = 0.25,
    this.inTime = 1.2,
    this.inHold = 0.6,
  });

  /// Seconds of velocity to look ahead by, capped at [leadMax] m and eased
  /// over [leadTime] s.
  final double lead;
  final double leadMax;
  final double leadTime;

  /// Metres the view sits toward local gravity (pads and pods are below).
  final double downBias;

  /// Soft camera window: the ship can wander this far from the focus
  /// before the camera follows, so hover jitter doesn't move the view.
  final double deadZone;

  /// Speed band (m/s) over which [speedZoomOut] ramps in (smoothstep).
  final double speedLo;
  final double speedHi;
  final double speedZoomOut;

  /// Extra zoom-out while rock ahead is under [impactSeconds] away at the
  /// current speed (full at 0.5 s).
  final double impactZoomOut;
  final double impactSeconds;

  /// Zoom-in once the ship has been slow or careful for [restDelay] s.
  final double restZoomIn;
  final double restDelay;

  /// Zoom-out while towing.
  final double towZoomOut;

  /// While towing, aim [podWeight] of the way toward the pod and zoom out
  /// enough to keep it [podMargin] (fraction of the half-view) inside.
  final bool podFraming;
  final double podWeight;
  final double podMargin;

  /// Rest zoom relative to the game's base zoom (< 1 = further out).
  final double zoomMul;

  /// Spring times for zooming out (fast) and in (slow, only after the
  /// target has stayed further in for [inHold] s — no "breathing").
  final double outTime;
  final double inTime;
  final double inHold;

  bool get isStatic =>
      lead == 0 &&
      downBias == 0 &&
      speedZoomOut == 0 &&
      impactZoomOut == 0 &&
      restZoomIn == 0 &&
      towZoomOut == 0 &&
      !podFraming;
}

/// One frame of what the camera needs to know. Positions in metres, any
/// axis orientation (the game uses y down).
class CameraInputs {
  const CameraInputs({
    required this.shipX,
    required this.shipY,
    this.velX = 0,
    this.velY = 0,
    this.launched = true,
    this.towing = false,
    this.podX,
    this.podY,
    this.aheadGap,
    this.downX = 0,
    this.downY = 1,
    required this.viewHalfW,
    required this.viewHalfH,
  });

  final double shipX, shipY, velX, velY;

  /// Before launch the ship waits on its pad (counts as resting).
  final bool launched;
  final bool towing;
  final double? podX, podY;

  /// Gap (m) to rock along the velocity, or null when nothing is in range.
  final double? aheadGap;

  /// Unit vector of local gravity, (0, 0) in zero-g.
  final double downX, downY;

  /// Half the view (m) at the rest zoom.
  final double viewHalfW, viewHalfH;

  double get speed => math.sqrt(velX * velX + velY * velY);
}

/// Where to look this frame: [x], [y] in metres, [zoom] relative to the
/// rest zoom (0.8 = 20% further out).
typedef CameraShot = ({double x, double y, double zoom});

class CameraDirector {
  CameraDirector(this.profile);

  CameraProfile profile;

  /// Zoom range relative to the rest zoom.
  static const double minZoom = 0.72;
  static const double maxZoom = 1.10;

  /// Position follow per 1/60 s (the original camera's), eased by time.
  static const double followPerFrame = 0.18;

  /// Below this speed (m/s) the ship counts as resting.
  static const double restSpeed = 0.3;

  double _x = 0, _y = 0;
  final _leadX = Spring();
  final _leadY = Spring();
  final _logZoom = Spring();
  double _inHeld = 0;
  double _slowFor = 0;

  double get zoom => math.exp(_logZoom.x);

  /// Jumps straight to the ship (level load, restart).
  void reset(double shipX, double shipY) {
    _x = shipX;
    _y = shipY;
    _leadX.set(0);
    _leadY.set(0);
    _logZoom.set(0);
    _inHeld = 0;
    _slowFor = 0;
  }

  CameraShot update(CameraInputs i, double dt) {
    if (dt <= 0) return (x: _x, y: _y, zoom: zoom);
    final p = profile;
    final speed = i.speed;

    // ── Look-ahead ──────────────────────────────────────────────────────
    var wantLX = 0.0, wantLY = 0.0;
    if (p.lead > 0 && i.launched) {
      wantLX = i.velX * p.lead;
      wantLY = i.velY * p.lead;
      final len = math.sqrt(wantLX * wantLX + wantLY * wantLY);
      if (len > p.leadMax) {
        wantLX *= p.leadMax / len;
        wantLY *= p.leadMax / len;
      }
    }
    _leadX.step(wantLX, p.leadTime, dt);
    _leadY.step(wantLY, p.leadTime, dt);

    var fx = i.shipX + _leadX.x + i.downX * p.downBias;
    var fy = i.shipY + _leadY.x + i.downY * p.downBias;
    final podX = i.podX, podY = i.podY;
    final framePod = p.podFraming && i.towing && podX != null && podY != null;
    if (framePod) {
      fx += (podX - i.shipX) * p.podWeight;
      fy += (podY - i.shipY) * p.podWeight;
    }

    // ── Zoom (log space: equal steps feel equal at any zoom) ────────────
    var out = 0.0;
    if (p.speedZoomOut > 0) {
      out += math.log(1 - p.speedZoomOut * smoothstep(p.speedLo, p.speedHi, speed));
    }
    final gap = i.aheadGap;
    if (p.impactZoomOut > 0 && gap != null && speed > 1) {
      final tti = gap / speed;
      final t = 1 - ((tti - 0.5) / (p.impactSeconds - 0.5)).clamp(0.0, 1.0);
      out += math.log(1 - p.impactZoomOut * t);
    }
    if (i.towing && p.towZoomOut > 0) {
      out = math.min(out, math.log(1 - p.towZoomOut));
    }
    if (framePod) {
      // Zoom needed so the pod stays inside the margin around the focus.
      final dx = (podX - fx).abs(), dy = (podY - fy).abs();
      final keep = 1 - p.podMargin;
      var need = 1.0;
      if (dx > 1e-6) need = math.min(need, i.viewHalfW * keep / dx);
      if (dy > 1e-6) need = math.min(need, i.viewHalfH * keep / dy);
      out = math.min(out, math.log(math.max(need, minZoom)));
    }

    // Slow or careful (a slow approach to rock or a pad): tighten up.
    final careful = gap != null && gap < 2.5 && speed < 0.8;
    if (!i.launched || speed < restSpeed || careful) {
      _slowFor += dt;
    } else {
      _slowFor = 0;
    }
    var target = out;
    if (out > -0.005 && p.restZoomIn > 0 && _slowFor >= p.restDelay) {
      target = math.log(1 + p.restZoomIn);
    }
    target = target.clamp(math.log(minZoom), math.log(maxZoom));

    // Out fast; in slowly, only once the target has stayed in for a while.
    if (target < _logZoom.x - 1e-4) {
      _inHeld = 0;
      _logZoom.step(target, p.outTime, dt);
    } else {
      _inHeld += dt;
      if (_inHeld >= p.inHold) {
        _logZoom.step(target, p.inTime, dt);
      } else {
        // Holding: settle without moving further in.
        _logZoom.step(_logZoom.x, p.outTime, dt);
      }
    }

    // ── Follow (soft dead zone, then the original exponential ease) ─────
    var ex = fx - _x, ey = fy - _y;
    if (p.deadZone > 0) {
      final len = math.sqrt(ex * ex + ey * ey);
      final keep = len > p.deadZone ? (len - p.deadZone) / len : 0.0;
      ex *= keep;
      ey *= keep;
    }
    final k = 1 - math.pow(1 - followPerFrame, dt * 60).toDouble();
    _x += ex * k;
    _y += ey * k;
    return (x: _x, y: _y, zoom: zoom);
  }
}

/// A critically damped spring: value [x] and its velocity [v].
class Spring {
  double x = 0, v = 0;

  void set(double value) {
    x = value;
    v = 0;
  }

  void step(double target, double smoothTime, double dt) {
    final (nx, nv) = springStep(x, v, target, smoothTime, dt);
    x = nx;
    v = nv;
  }
}

/// Exact critically damped spring step toward a fixed [target]: settles in
/// about [smoothTime] s with no overshoot, the same at any frame rate.
(double, double) springStep(
  double x,
  double v,
  double target,
  double smoothTime,
  double dt,
) {
  if (smoothTime <= 0) return (target, 0);
  final w = 2 / smoothTime;
  final d = x - target;
  final e = math.exp(-w * dt);
  final c = v + w * d;
  return (target + (d + c * dt) * e, (v - w * c * dt) * e);
}

double smoothstep(double lo, double hi, double x) {
  final t = ((x - lo) / (hi - lo)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Trauma screen shake (Eiserloh, GDC 2016): events add trauma 0…1, which
/// decays linearly; the offset is [maxOffset] × trauma² × smooth noise. It
/// is an offset added after the follow, never stored in it. [floor] keeps a
/// steady rumble (meltdown) under the decaying trauma.
class TraumaShake {
  TraumaShake({this.maxOffset = 0.45, this.decayPerSecond = 1.6});

  final double maxOffset;
  final double decayPerSecond;

  /// Multiplies every offset (reduced motion turns it down).
  double scale = 1;
  double floor = 0;
  double _trauma = 0;
  double _t = 0;

  double get trauma => math.max(_trauma, floor);

  void add(double amount) => _trauma = math.min(1, _trauma + amount);

  void clear() {
    _trauma = 0;
    floor = 0;
  }

  void update(double dt) {
    _trauma = math.max(0, _trauma - decayPerSecond * dt);
    _t += dt;
  }

  /// Offset (m) for this frame; zero once calm.
  (double, double) get offset {
    final tr = trauma;
    if (tr <= 0) return (0, 0);
    final a = maxOffset * tr * tr * scale;
    // Sums of incommensurate sines: smooth, deterministic, ~25 Hz.
    final x = 0.6 * math.sin(_t * 151) + 0.4 * math.sin(_t * 197 + 1.3);
    final y = 0.6 * math.sin(_t * 167 + 2.1) + 0.4 * math.sin(_t * 229 + 0.4);
    return (x * a, y * a);
  }
}
