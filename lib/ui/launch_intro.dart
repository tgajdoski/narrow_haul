import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/services/error_reporter.dart';
import 'fonts.dart';
import 'space_ui.dart';
import 'tow_art.dart';

// Timeline.
const _entrance = Duration(milliseconds: 900);
const _fadeOut = Duration(milliseconds: 350);

/// The intro and credits leave after this even if the game never finished
/// loading, so a failed load can't trap the player on them.
const kReadyFallback = Duration(seconds: 15);

/// Seconds per orbit.
const _orbitPeriod = 7.0;

/// The orbit ellipse's tilt (radians, screen space).
const _orbitTilt = -0.2;

/// Launch screen on every start without the "Delivered by" credits: it takes
/// over from the native splash (same backdrop colour, the ship starts centred
/// like the splash logo) and the ship eases onto an orbit round a planet,
/// towing a pod, while the game loads. It leaves once [ready] has completed
/// and the entrance has played (~1 s): it never holds a loaded game back
/// longer than that. A tap skips it, but only after [ready].
class LaunchIntro extends StatefulWidget {
  const LaunchIntro({super.key, required this.ready, required this.onDone});

  final Future<void> ready;
  final VoidCallback onDone;

  /// Tests: pins the orbit clock (seconds), since looping animations are off
  /// under `flutter test`.
  @visibleForTesting
  static double? debugOrbitTime;

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

class _LaunchIntroState extends State<LaunchIntro>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: _entrance,
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: _fadeOut,
  );

  /// Orbit clock (seconds); stays 0 with reduced motion and in tests.
  final _time = ValueNotifier<double>(0);
  Ticker? _ticker;
  bool _ready = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _intro
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _maybeLeave();
      })
      ..forward();
    // A load that fails or hangs must not keep the player here: leave
    // anyway (the failure is reported) after [kReadyFallback] at the latest.
    _fallback = Timer(kReadyFallback, _markReady);
    widget.ready.then(
      (_) => _markReady(),
      onError: (Object e, StackTrace st) {
        ErrorReporter.report(e, st, context: 'game load');
        _markReady();
      },
    );
  }

  Timer? _fallback;

  void _markReady() {
    _fallback?.cancel();
    if (!mounted || _ready) return;
    _ready = true;
    _maybeLeave();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ticker == null && spaceAnimationsOn(context)) {
      _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)
        ..start();
    }
  }

  void _maybeLeave() {
    if (_ready && _intro.isCompleted) _leave();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _exit.forward();
    if (mounted) widget.onDone();
  }

  void _onTap() {
    if (_ready) _leave(); // the game underneath isn't there before that
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _ticker?.dispose();
    _time.dispose();
    _intro.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: FadeTransition(
        opacity: ReverseAnimation(_exit),
        child: Stack(
          children: [
            const Positioned.fill(child: SpaceBackdrop()),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) => AnimatedBuilder(
                  animation: Listenable.merge([_intro, _time]),
                  builder: (context, _) => _scene(context, box.biggest),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scene(BuildContext context, Size size) {
    if (size.isEmpty) return const SizedBox.shrink();
    final e = Curves.easeInOutCubic.transform(_intro.value);
    final t = LaunchIntro.debugOrbitTime ?? _time.value;
    final g = OrbitGeometry(size);

    // The ship starts where the splash logo was (centred, upright) and eases
    // onto the orbit; the orbit itself is already turning underneath.
    final theta = math.pi / 2 + 2 * math.pi * t / _orbitPeriod;
    final ship = g.craftAt(theta);
    final shipPos = Offset.lerp(g.splashCenter, ship.pos, e)!;
    final shipSize = _lerp(g.splashShipSize, g.shipSize * ship.scale, e);
    final shipAngle = _lerp(0, ship.heading, e);
    final winch = shipPos + _rotate(Offset(0, shipSize * 0.2), shipAngle);
    // The pod trails a tow length behind, hanging a little below the line.
    final back = Offset(-math.sin(shipAngle), math.cos(shipAngle));
    final podPos = shipPos + back * shipSize * 0.8 + Offset(0, shipSize * 0.3);
    final podSize = shipSize * 0.3;

    final shipLayer = _Layer(
      depth: ship.depth,
      child: _ShipSprite(
        center: shipPos,
        size: shipSize,
        angle: shipAngle,
        flicker: t,
      ),
    );
    final podLayer = _Layer(
      depth: ship.depth - 0.01,
      child: Opacity(
        opacity: e,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _RopePainter(winch, podPos, e)),
            ),
            Positioned(
              left: podPos.dx - podSize / 2,
              top: podPos.dy - podSize / 2,
              width: podSize,
              height: podSize,
              child: Image.asset(
                'assets/cargo.png',
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
    // During the entrance the ship flies in front of everything.
    if (e < 1) shipLayer.depth = 2;
    final layers = [podLayer, shipLayer]
      ..sort((a, b) => a.depth.compareTo(b.depth));

    final planetIn = Curves.easeOut.transform(_intro.value);
    final title = Curves.easeOut.transform(
      ((_intro.value - 0.35) / 0.65).clamp(0.0, 1.0),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final l in layers)
          if (l.depth < 0) Positioned.fill(child: l.child),
        Positioned.fill(
          child: CustomPaint(painter: _PlanetPainter(g, planetIn)),
        ),
        for (final l in layers)
          if (l.depth >= 0) Positioned.fill(child: l.child),
        Positioned(
          left: 0,
          right: 0,
          top: g.titleTop,
          child: Opacity(
            opacity: title,
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - title)),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'NARROW HAUL',
                    style: TextStyle(
                      fontFamily: kDisplayFont,
                      decoration: TextDecoration.none,
                      fontSize: g.titleSize,
                      color: Colors.white,
                      letterSpacing: g.titleSize * 0.28,
                      shadows: [
                        Shadow(
                          color: SpaceColors.cyan.withValues(alpha: 0.7),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

Offset _rotate(Offset v, double a) => Offset(
  v.dx * math.cos(a) - v.dy * math.sin(a),
  v.dx * math.sin(a) + v.dy * math.cos(a),
);

/// One thing on the orbit, drawn in front of the planet when [depth] ≥ 0.
class _Layer {
  _Layer({required this.depth, required this.child});
  double depth;
  final Widget child;
}

/// Where a craft is on the orbit: screen position, nose angle (0 = up,
/// clockwise), perspective scale and depth (−1 far side … 1 near side).
class OrbitPoint {
  const OrbitPoint(this.pos, this.heading, this.scale, this.depth);
  final Offset pos;
  final double heading;
  final double scale;
  final double depth;
}

/// Layout of the intro scene for a screen [size] (landscape or portrait).
class OrbitGeometry {
  OrbitGeometry(this.size)
    : planetCenter = Offset(size.width / 2, size.height * 0.43),
      planetRadius = math.min(size.height * 0.19, size.width * 0.16),
      shipSize = math.min(size.height * 0.24, size.width * 0.17) {
    rx = math.min(planetRadius * 2.5, size.width * 0.42);
    ry = planetRadius * 0.8;
  }

  final Size size;
  final Offset planetCenter;
  final double planetRadius;
  final double shipSize;
  late final double rx;
  late final double ry;

  /// The native splash logo (`tool/store/make_icon.py --splash`): 256 pt,
  /// the ship's hull ~77 pt wide, nose 64 pt above the centre. The sprite's
  /// hull spans 55% of its width, nose at 9% from the top.
  double get splashShipSize => math.min(140, size.shortestSide * 0.36);
  Offset get splashCenter =>
      size.center(Offset.zero) - Offset(0, splashShipSize * 0.05);

  double get titleSize => (size.height * 0.075).clamp(20.0, 44.0);
  double get titleTop => planetCenter.dy + planetRadius + size.height * 0.15;

  Offset orbit(double theta) =>
      planetCenter +
      _rotate(Offset(rx * math.cos(theta), ry * math.sin(theta)), _orbitTilt);

  OrbitPoint craftAt(double theta) {
    final v = _rotate(
      Offset(-rx * math.sin(theta), ry * math.cos(theta)),
      _orbitTilt,
    );
    final depth = math.sin(theta);
    return OrbitPoint(
      orbit(theta),
      math.atan2(v.dx, -v.dy),
      0.82 + 0.18 * depth,
      depth,
    );
  }
}

class _ShipSprite extends StatelessWidget {
  const _ShipSprite({
    required this.center,
    required this.size,
    required this.angle,
    required this.flicker,
  });

  final Offset center;
  final double size;
  final double angle;
  final double flicker;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: center.dx - size / 2,
          top: center.dy - size / 2,
          width: size,
          height: size,
          child: Transform.rotate(
            angle: angle,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _PlumePainter(flicker)),
                ),
                Positioned.fill(
                  child: Image.asset(
                    'assets/ship.png',
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlumePainter extends CustomPainter {
  _PlumePainter(this.flicker);
  final double flicker;

  @override
  void paint(Canvas canvas, Size size) {
    // Sprite: hull bottom (nozzle line) at y 181 of 256.
    final s = size.width;
    paintThrustPlume(canvas, Offset(s / 2, s * 0.7), s, flicker);
  }

  @override
  bool shouldRepaint(_PlumePainter o) => o.flicker != flicker;
}

class _RopePainter extends CustomPainter {
  _RopePainter(this.from, this.to, this.opacity);
  final Offset from;
  final Offset to;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) =>
      paintTowLine(canvas, from, to, opacity: opacity);

  @override
  bool shouldRepaint(_RopePainter o) =>
      o.from != from || o.to != to || o.opacity != opacity;
}

/// The planet (lit from the top left, banded, with a cyan atmosphere rim)
/// and its orbit ring: the far half before the planet, the near half after.
class _PlanetPainter extends CustomPainter {
  _PlanetPainter(this.g, this.appear);
  final OrbitGeometry g;
  final double appear;

  @override
  void paint(Canvas canvas, Size size) {
    if (appear <= 0) return;
    final c = g.planetCenter;
    final r = g.planetRadius * (0.85 + 0.15 * appear);
    final a = appear;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Far half of the orbit (hidden by the planet where they overlap).
    canvas.drawPath(
      _arc(math.pi, 2 * math.pi),
      ring..color = SpaceColors.cyan.withValues(alpha: 0.18 * a),
    );

    // Halo.
    final halo = Rect.fromCircle(center: c, radius: r * 1.6);
    canvas.drawCircle(
      c,
      r * 1.6,
      Paint()
        ..shader = RadialGradient(
          colors: [
            SpaceColors.cyan.withValues(alpha: 0.16 * a),
            SpaceColors.cyan.withValues(alpha: 0),
          ],
          stops: const [0.6, 1],
        ).createShader(halo),
    );

    // Body.
    final disc = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(disc));
    canvas.drawRect(
      disc,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.5),
          radius: 1.1,
          colors: [
            Color.fromRGBO(0x4A, 0x86, 0xB8, a),
            Color.fromRGBO(0x23, 0x45, 0x7A, a),
            Color.fromRGBO(0x10, 0x1A, 0x3A, a),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(disc),
    );
    // Cloud bands, tilted with the orbit.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(_orbitTilt);
    for (final (y, h, alpha) in const [
      (-0.55, 0.10, 0.10),
      (-0.22, 0.16, 0.08),
      (0.12, 0.08, 0.12),
      (0.42, 0.14, 0.07),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, y * r),
          width: r * 2.4,
          height: h * r,
        ),
        Paint()
          ..color = const Color(0xFFB8E4FF).withValues(alpha: alpha * a)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.04),
      );
    }
    canvas.restore();
    // Night side.
    canvas.drawRect(
      disc,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.9, 0.9),
          radius: 1.3,
          colors: [
            Color.fromRGBO(0x03, 0x05, 0x0D, 0.85 * a),
            Color.fromRGBO(0x03, 0x05, 0x0D, 0),
          ],
        ).createShader(disc),
    );
    canvas.restore();

    // Atmosphere rim, brightest on the lit side.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.04)
        // Sweep starts at 3 o'clock, clockwise: the lit top-left is ~0.62.
        ..shader = SweepGradient(
          colors: [
            SpaceColors.cyan.withValues(alpha: 0.08 * a),
            SpaceColors.cyan.withValues(alpha: 0.15 * a),
            SpaceColors.cyan.withValues(alpha: 0.75 * a),
            SpaceColors.cyan.withValues(alpha: 0.15 * a),
            SpaceColors.cyan.withValues(alpha: 0.08 * a),
          ],
          stops: const [0, 0.4, 0.62, 0.85, 1],
        ).createShader(disc),
    );

    // Near half of the orbit, over the planet.
    canvas.drawPath(
      _arc(0, math.pi),
      ring..color = SpaceColors.cyan.withValues(alpha: 0.32 * a),
    );
  }

  Path _arc(double from, double to) {
    final p = Path();
    const steps = 48;
    for (var i = 0; i <= steps; i++) {
      final o = g.orbit(from + (to - from) * i / steps);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p;
  }

  @override
  bool shouldRepaint(_PlanetPainter o) =>
      o.appear != appear || o.g.size != g.size;
}
