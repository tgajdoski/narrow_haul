import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/route/flight_route.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// Pod colour (matches [CargoBody]'s paint) for the towing part of a route.
const Color _podColor = Color(0xFFE07A5F);

/// The recorded route as a dotted line under the rope (above the rock), with
/// rings where the pod is hooked and where the flight ends.
class RouteGuideLine extends Component {
  RouteGuideLine({required this.route, required this.accent}) : super(priority: -500);

  final FlightRoute route;
  final Color accent;

  static const double _spacing = 0.5;
  static const double _dotRadius = 0.07;

  late final List<(Offset, bool)> _dots = _layDots();

  List<(Offset, bool)> _layDots() {
    final out = <(Offset, bool)>[];
    RouteSample? prev;
    var carry = 0.0;
    for (final s in route.flown) {
      final p = prev;
      prev = s;
      if (p == null) {
        out.add((Offset(s.x, s.y), s.towing));
        continue;
      }
      final dx = s.x - p.x;
      final dy = s.y - p.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) continue;
      var d = _spacing - carry;
      while (d <= len) {
        final u = d / len;
        out.add((Offset(p.x + dx * u, p.y + dy * u), s.towing));
        d += _spacing;
      }
      carry = len - (d - _spacing);
    }
    return out;
  }

  @override
  void render(Canvas canvas) {
    final free = Paint()..color = accent.withValues(alpha: 0.55);
    final tow = Paint()..color = _podColor.withValues(alpha: 0.6);
    for (final (o, towing) in _dots) {
      canvas.drawCircle(o, _dotRadius, towing ? tow : free);
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.06;
    final attachT = route.attachT;
    if (attachT != null) {
      final a = route.poseAt(attachT);
      canvas.drawCircle(Offset(a.cx, a.cy), 0.7, ring..color = _podColor.withValues(alpha: 0.7));
    }
    final end = route.samples.isEmpty ? null : route.samples.last;
    if (end != null) {
      canvas.drawCircle(Offset(end.x, end.y), 0.7, ring..color = accent.withValues(alpha: 0.7));
    }
  }
}

/// Translucent ship flying the recorded route, timed from the player's
/// launch ([flightTime] = the level clock).
class RouteGhost extends Component {
  RouteGhost({required this.route, required this.ship, required this.flightTime})
      : super(priority: -450);

  final FlightRoute route;
  final ShipSpec ship;

  /// Seconds flown since launch (null before launch: the ghost waits on the pad).
  final double? Function() flightTime;

  ui.Image? _image;

  static const double _visualScale = 4.5; // as in ShipBody
  late final Rect _rect = Rect.fromLTRB(
    -0.23 * _visualScale * ship.hullScale,
    -0.37 * _visualScale * ship.hullScale,
    0.23 * _visualScale * ship.hullScale,
    0.29 * _visualScale * ship.hullScale,
  );

  @override
  Future<void> onLoad() async {
    for (final path in {ship.sprite, kKestrel.sprite}) {
      try {
        _image = await Flame.images.load(path);
        break;
      } catch (_) {}
    }
  }

  @override
  void render(Canvas canvas) {
    final img = _image;
    if (img == null) return;
    final flown = flightTime() ?? 0;
    final t = route.launchT + flown;
    // Fade out over the last second of the recording, then vanish.
    final alpha = (0.38 * (route.endT + 1 - t).clamp(0.0, 1.0)).toDouble();
    if (alpha <= 0.01) return;
    final pose = route.poseAt(t);
    canvas
      ..save()
      ..translate(pose.x, pose.y)
      ..rotate(pose.angle);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      _rect,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..colorFilter = const ColorFilter.mode(Color(0x6600E5FF), BlendMode.srcATop),
    );
    canvas.restore();
  }
}
