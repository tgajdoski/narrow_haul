import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/game/components/ship_body.dart' show shipSpriteRect;
import 'package:narrow_haul/game/components/ship_fx.dart';
import 'package:narrow_haul/game/ship/livery.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// The ship on a display stand: the real sprite with its baked hull
/// lighting, livery tint, plume and nav lights, lying on a holo pad tilted
/// back in perspective and turning slowly, so the world-fixed light sweeps
/// across the hull. Stacked darker copies of the sprite give the hull some
/// thickness and it casts a shadow on the pad: a 3D look from 2D art.
/// Drag sideways to turn it by hand.
///
/// [livery] / [plume] are cosmetic ids (null: stock). [tilt] is how far
/// the pad leans back (0 = straight down from above). Still in widget tests
/// and with reduced motion.
class ShipShowcase extends StatefulWidget {
  const ShipShowcase({
    super.key,
    required this.ship,
    this.livery,
    this.plume,
    this.accent = SpaceColors.cyan,
    this.tilt = 0.95,
    this.spinSeconds = 14,
    this.interactive = true,
  });

  /// Bake the hull lighting (off in `flutter test`, where it's slow).
  @visibleForTesting
  static bool bakeLighting = !_inTest;

  /// The spin angle to start from (rad).
  @visibleForTesting
  static double startAngle = 0.7;

  /// The clock to start from (s; 0.8 is mid engine burst).
  @visibleForTesting
  static double startTime = 0;

  final ShipSpec ship;
  final String? livery;
  final String? plume;
  final Color accent;
  final double tilt;
  final double spinSeconds;
  final bool interactive;

  @override
  State<ShipShowcase> createState() => _ShipShowcaseState();
}

class _ShipShowcaseState extends State<ShipShowcase> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _last = Duration.zero;

  /// Spin angle (rad, clockwise) and the extra spin from a drag or fling.
  double _angle = ShipShowcase.startAngle;
  double _fling = 0;
  bool _dragging = false;
  double _time = ShipShowcase.startTime;

  ui.Image? _sprite;
  ui.Image? _atlas;
  bool _fallbackArt = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ShipShowcase old) {
    super.didUpdateWidget(old);
    if (old.ship.id != widget.ship.id) _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = spaceAnimationsOn(context);
    if (animate && _ticker == null) {
      _ticker = createTicker(_tick)..start();
    } else if (!animate && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    setState(() {
      _time += dt;
      if (!_dragging) {
        _angle += dt * 2 * math.pi / widget.spinSeconds + _fling * dt;
        _fling *= math.exp(-dt * 2.5);
      }
    });
  }

  Future<void> _load() async {
    final ship = widget.ship;
    for (final path in {ship.sprite, kKestrel.sprite}) {
      final got = showcaseImage(path);
      final img = got is ui.Image? ? got : await got;
      if (img == null) continue;
      if (!mounted || widget.ship.id != ship.id) return;
      setState(() {
        _sprite = img;
        _atlas = null;
        _fallbackArt = path != ship.sprite;
      });
      if (ShipShowcase.bakeLighting) {
        final atlas = await hullLightAtlas(path, img, HullLighting.defaultRim);
        if (mounted && widget.ship.id == ship.id) setState(() => _atlas = atlas);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      painter: _ShowcasePainter(
        ship: widget.ship,
        sprite: _sprite,
        atlas: _atlas,
        tint: kLiveryTints[widget.livery] ??
            (_fallbackArt && widget.ship.tint != null ? Color(widget.ship.tint!) : null),
        plume: widget.plume,
        accent: widget.accent,
        tilt: widget.tilt,
        angle: _angle,
        time: _time,
      ),
      size: Size.infinite,
    );
    if (!widget.interactive) return paint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _dragging = true,
      onHorizontalDragUpdate: (d) => setState(() => _angle += d.delta.dx * 0.012),
      onHorizontalDragEnd: (d) {
        _dragging = false;
        _fling = (d.velocity.pixelsPerSecond.dx * 0.004).clamp(-8.0, 8.0);
      },
      child: paint,
    );
  }
}

final bool _inTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

final Map<String, Future<ui.Image?>> _loading = {};
final Map<String, ui.Image?> _decoded = {};

/// A ship sprite from `assets/`, decoded once (null if it's missing).
/// Once decoded it's handed back synchronously, so a second showcase of
/// the same ship draws it on its first frame.
FutureOr<ui.Image?> showcaseImage(String path) {
  if (_decoded.containsKey(path)) return _decoded[path];
  return _loading[path] ??= () async {
    ui.Image? img;
    try {
      final data = await rootBundle.load('assets/$path');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      img = (await codec.getNextFrame()).image;
    } catch (_) {}
    _decoded[path] = img;
    return img;
  }();
}

class _ShowcasePainter extends CustomPainter {
  _ShowcasePainter({
    required this.ship,
    required this.sprite,
    required this.atlas,
    required this.tint,
    required this.plume,
    required this.accent,
    required this.tilt,
    required this.angle,
    required this.time,
  });

  final ShipSpec ship;
  final ui.Image? sprite;
  final ui.Image? atlas;
  final Color? tint;
  final String? plume;
  final Color accent;
  final double tilt;
  final double angle;
  final double time;

  static final HullLighting _lighting = HullLighting();
  static final NavLights _nav = NavLights();
  static final EngineHeat _heat = EngineHeat();

  /// Hull thickness (m) and how many slices fake it.
  static const double _thickness = 0.16;
  static const int _slices = 14;

  /// The pad sits this far (m) under the hull.
  static const double _padDrop = 0.32;

  /// Engine burst: on for ~1.2 s of every 3.5 s, eased.
  double get _thrust {
    final t = time % 3.5;
    if (t > 1.6) return 0;
    return math.sin(math.min(1.0, t / 1.6) * math.pi).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = shipSpriteRect(ship);
    // Fit the hull (not the sprite's empty margins) with room for the pad.
    final reach = math.max(ship.circumradius, 0.6) * 1.12;
    final scale = math.min(size.width, size.height) / (2 * reach);
    final centre = Offset(size.width / 2, size.height * 0.46);

    Matrix4 view({required bool spin}) {
      final persp = Matrix4.identity()..setEntry(3, 2, 0.7 / size.height);
      final m = Matrix4.translationValues(centre.dx, centre.dy, 0)
        ..multiply(persp)
        // Lean the pad back: its far edge recedes; local +z is down,
        // under the hull.
        ..multiply(Matrix4.rotationX(-tilt));
      if (spin) m.multiply(Matrix4.rotationZ(angle));
      m.multiply(Matrix4.diagonal3Values(scale, scale, scale));
      return m;
    }

    final hullC = Offset(0, (ship.noseLocalY + ship.rearLocalY) / 2);

    // The pad: rings that don't spin, ticks that do.
    canvas.save();
    canvas.transform((view(spin: false)..translateByDouble(0, 0, _padDrop, 1)).storage);
    _pad(canvas, reach);
    canvas.restore();

    final m = view(spin: true);
    final img = sprite;
    // Shadow on the pad.
    canvas.save();
    canvas.transform((m.clone()..translateByDouble(0, 0, _padDrop, 1)).storage);
    canvas.drawOval(
      Rect.fromCenter(center: hullC, width: rect.width * 0.62, height: rect.height * 0.55),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.12),
    );
    canvas.restore();
    if (img == null) return;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());

    // Hull thickness: darker slices from the belly up.
    for (var i = _slices; i >= 1; i--) {
      final z = _thickness * i / _slices;
      canvas.save();
      canvas.transform((m.clone()..translateByDouble(0, 0, z, 1)).storage);
      // A solid side wall: the silhouette in one colour per slice, a touch
      // lighter toward the deck.
      final up = 1 - i / _slices;
      canvas.drawImageRect(
        img,
        src,
        rect,
        Paint()
          ..colorFilter = ColorFilter.mode(
            Color.lerp(const Color(0xFF0B1020), const Color(0xFF2A3346), up)!,
            BlendMode.srcIn,
          ),
      );
      canvas.restore();
    }

    canvas.save();
    canvas.transform(m.storage);
    final level = _thrust;
    _plumeAt(canvas, ship.rearLocalY, level);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (tint != null) paint.colorFilter = ColorFilter.mode(tint!, BlendMode.srcATop);
    canvas.drawImageRect(img, src, rect, paint);
    final a = atlas;
    if (a != null) _lighting.draw(canvas, a, angle, rect, img.width, img.height);
    _heat.render(canvas, ship.rearLocalY, level, ship.hullScale);
    _nav.render(canvas, HullPoints.of(ship), time, ship.hullScale);
    canvas.restore();
  }

  void _pad(Canvas canvas, double reach) {
    final r = reach * 0.8;
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        r,
        [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0.0)],
      );
    canvas.save();
    canvas.drawCircle(Offset.zero, r, glow);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = accent.withValues(alpha: 0.55)
      ..strokeWidth = 0.025;
    canvas.drawCircle(Offset.zero, r * 0.98, ring);
    canvas.drawCircle(Offset.zero, r * 0.72, ring..color = accent.withValues(alpha: 0.25));
    // Ticks round the rim turn with the ship.
    final tick = Paint()
      ..color = accent.withValues(alpha: 0.7)
      ..strokeWidth = 0.02;
    for (var i = 0; i < 24; i++) {
      final a = angle + i * math.pi / 12;
      final c = math.cos(a), s = math.sin(a);
      final long = i % 6 == 0;
      canvas.drawLine(
        Offset(c * r * (long ? 0.86 : 0.91), s * r * (long ? 0.86 : 0.91)),
        Offset(c * r * 0.98, s * r * 0.98),
        tick,
      );
    }
    canvas.restore();
  }

  /// A three-layer flame under the nozzle in the plume's colours.
  void _plumeAt(Canvas canvas, double y, double level) {
    if (level < 0.02) return;
    final (core, mid, outer) = plumePalette(plume, time);
    final flicker = (0.85 + math.sin(time * 28) * 0.15) * (0.35 + 0.65 * level);
    final k = ship.hullScale * 1.6;
    canvas.drawCircle(
      Offset(0, y + 0.05 * k),
      0.22 * flicker * k,
      Paint()
        ..color = outer.withValues(alpha: 0.25 * level)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.1),
    );
    const widths = [0.12, 0.09, 0.06];
    final lengths = [0.40, 0.28, 0.18];
    final colors = [outer, mid, core];
    for (var i = 0; i < 3; i++) {
      final w = widths[i] * k * (0.9 + math.sin(time * 18 + i) * 0.1);
      final len = lengths[i] * k * flicker;
      final path = Path()
        ..moveTo(-w, y)
        ..cubicTo(-w * 0.6, y + len * 0.4, -w * 0.3, y + len * 0.7, 0, y + len)
        ..cubicTo(w * 0.3, y + len * 0.7, w * 0.6, y + len * 0.4, w, y)
        ..close();
      canvas.drawPath(path, Paint()..color = colors[i].withValues(alpha: (0.7 + 0.1 * i) * level));
    }
  }

  @override
  bool shouldRepaint(_ShowcasePainter old) =>
      old.angle != angle ||
      old.time != time ||
      old.sprite != sprite ||
      old.atlas != atlas ||
      old.tint != tint ||
      old.plume != plume ||
      old.ship.id != ship.id ||
      old.accent != accent;
}
