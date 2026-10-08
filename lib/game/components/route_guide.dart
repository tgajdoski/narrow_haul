import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/defences.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/route/flight_route.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// Pod colour (matches [CargoBody]'s paint) for the towing part of a route.
const Color _podColor = Color(0xFFE07A5F);

/// Turret fire colour for the stretch of route a live turret covers.
const Color _dangerColor = Color(0xFFFF4D4D);

/// The recorded route as a dotted line under the rope (above the rock), with
/// rings where the pod is hooked and where the flight ends. Where turrets
/// are involved: dots a live turret covers turn red, a crosshair marks
/// each spot the recorded flight fired from (with its aim), and a dashed
/// ring marks where it held still (waiting for a gap or lining up a shot).
class RouteGuideLine extends Component {
  RouteGuideLine({
    required this.route,
    required this.accent,
    this.turrets = _noTurrets,
    this.turretsOffline = _never,
  }) : super(priority: -500);

  final FlightRoute route;
  final Color accent;

  /// The level's turrets and whether they're powered down (reactor).
  final List<Turret> Function() turrets;
  final bool Function() turretsOffline;

  static List<Turret> _noTurrets() => const [];
  static bool _never() => false;

  static const double _spacing = 0.5;
  static const double _dotRadius = 0.07;

  late final List<(Offset, bool)> _dots = _layDots();
  late final List<FireMark> _fireMarks = route.fireMarks();
  late final List<Offset> _holds = _findHolds();

  /// Per dot: a live turret covers it. Recomputed when a turret goes down.
  List<bool> _covered = const [];
  String _coverKey = '';

  @override
  void update(double dt) {
    super.update(dt);
    final all = turrets();
    final offline = turretsOffline();
    final key = '$offline ${all.where((t) => t.destroyed).length}/${all.where((t) => t.isMounted).length}';
    if (key == _coverKey) return;
    _coverKey = key;
    final live = offline ? const <Turret>[] : [for (final t in all) if (!t.destroyed && t.isMounted) t];
    _covered = [
      for (final (o, _) in _dots) live.any((t) => t.covers(Vector2(o.dx, o.dy))),
    ];
  }

  /// Spots where the flight sat (nearly) still for 0.8 s or more.
  List<Offset> _findHolds() {
    final out = <Offset>[];
    final pts = route.flown.toList();
    var start = 0;
    for (var k = 1; k <= pts.length; k++) {
      final moving = k == pts.length ||
          math.sqrt(math.pow(pts[k].x - pts[start].x, 2) + math.pow(pts[k].y - pts[start].y, 2)) > 0.35;
      if (!moving) continue;
      final last = pts[k - 1];
      if (last.t - pts[start].t >= 0.8 && k < pts.length) {
        out.add(Offset((pts[start].x + last.x) / 2, (pts[start].y + last.y) / 2));
      }
      start = k;
    }
    return out;
  }

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
    final danger = Paint()..color = _dangerColor.withValues(alpha: 0.75);
    for (final (k, (o, towing)) in _dots.indexed) {
      final hot = k < _covered.length && _covered[k];
      canvas.drawCircle(o, hot ? _dotRadius * 1.3 : _dotRadius, hot ? danger : (towing ? tow : free));
    }
    _renderHolds(canvas);
    _renderFireMarks(canvas);
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

  void _renderHolds(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05
      ..color = accent.withValues(alpha: 0.6);
    for (final h in _holds) {
      // Dashed ring: "stop here".
      for (var k = 0; k < 8; k++) {
        canvas.drawArc(Rect.fromCircle(center: h, radius: 0.5), k * math.pi / 4, math.pi / 7, false, paint);
      }
    }
  }

  void _renderFireMarks(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.06
      ..color = _dangerColor.withValues(alpha: 0.85);
    for (final m in _fireMarks) {
      final c = Offset(m.x, m.y);
      canvas.drawCircle(c, 0.42, paint);
      for (final (dx, dy) in const [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)]) {
        canvas.drawLine(c + Offset(dx * 0.25, dy * 0.25), c + Offset(dx * 0.6, dy * 0.6), paint);
      }
      // Aim: dashes along the nose toward the target.
      for (var d = 0.8; d < 3.2; d += 0.4) {
        final a = c + Offset(m.dirX * d, m.dirY * d);
        final b = c + Offset(m.dirX * (d + 0.2), m.dirY * (d + 0.2));
        canvas.drawLine(a, b, paint);
      }
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

  late final Rect _rect = shipSpriteRect(ship); // as in ShipBody

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
    // Muzzle flash where the recorded flight fired.
    if (route.shots.any((s) => t >= s && t - s < 0.15)) {
      final nose = Offset(0, ship.noseLocalY - 0.15);
      canvas
        ..drawCircle(nose, 0.28, Paint()..color = _dangerColor.withValues(alpha: alpha * 1.6))
        ..drawLine(nose, nose + const Offset(0, -1.2),
            Paint()
              ..strokeWidth = 0.08
              ..color = Colors.white.withValues(alpha: alpha * 2));
    }
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
