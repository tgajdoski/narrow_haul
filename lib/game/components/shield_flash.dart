import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:narrow_haul/game/components/ship_body.dart';

/// The hull's deflector shield flaring where it met rock: a bubble around
/// the ship lights up brightest at the impact, a patch of hex cells glows
/// there and a ripple runs out across the bubble, all gone in ~0.55 s.
/// Follows the ship (drawn in its frame), so the flare stays on the side
/// that hit. World space, meters.
class ShieldFlash extends Component {
  ShieldFlash({
    required this.ship,
    required Vector2 rockNormal,
    this.strength = 1.0,
  }) : super(priority: 1050) {
    // Direction from the ship toward the rock, in the ship's own frame.
    final toRock = ship.body.localVector(-rockNormal);
    _dir = toRock.length2 > 1e-9 ? (toRock..normalize()) : Vector2(0, 1);
    _radius = ship.spec.circumradius * 1.22;
    _cells = _hexCells(_radius, _radius * 0.17);
  }

  final ShipBody ship;

  /// 1 for a scrape, less for a gentle touchdown.
  final double strength;

  late final Vector2 _dir;
  late final double _radius;
  late final List<Path> _cells;
  late final List<Offset> _cellCenters;
  double _t = 0;

  static const double _life = 0.55;
  static const Color _core = Color(0xFFE8FBFF);
  static const Color _cyan = Color(0xFF6FE3FF);
  static const Color _deep = Color(0xFF2F7BFF);

  List<Path> _hexCells(double r, double s) {
    final paths = <Path>[];
    final centers = <Offset>[];
    final w = math.sqrt(3) * s;
    final h = 1.5 * s;
    final rows = (r / h).ceil() + 1;
    final cols = (r / w).ceil() + 1;
    for (var row = -rows; row <= rows; row++) {
      for (var col = -cols; col <= cols; col++) {
        final c = Offset(col * w + (row.isOdd ? w / 2 : 0), row * h);
        if (c.distance > r + s) continue;
        final p = Path();
        for (var i = 0; i < 6; i++) {
          final a = math.pi / 6 + i * math.pi / 3;
          final v = c + Offset(math.cos(a), math.sin(a)) * (s * 0.9);
          i == 0 ? p.moveTo(v.dx, v.dy) : p.lineTo(v.dx, v.dy);
        }
        paths.add(p..close());
        centers.add(c);
      }
    }
    _cellCenters = centers;
    return paths;
  }

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= _life || !ship.isMounted) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final k = (_t / _life).clamp(0.0, 1.0);
    final fade = math.pow(1 - k, 1.6) * strength;
    if (fade <= 0.01) return;
    final r = _radius;
    final hit = Offset(_dir.x, _dir.y) * r;
    final bubble = Rect.fromCircle(center: Offset.zero, radius: r);
    final ripple = 0.15 * r + k * 2.2 * r;

    canvas.save();
    canvas.translate(ship.body.position.x, ship.body.position.y);
    canvas.rotate(ship.body.angle);

    canvas.save();
    canvas.clipPath(Path()..addOval(bubble));

    // Energy fill, white-hot at the impact, fading round the bubble.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = Gradient.radial(
          hit,
          r * 1.6,
          [
            _core.withValues(alpha: 0.75 * fade),
            _cyan.withValues(alpha: 0.35 * fade),
            _deep.withValues(alpha: 0.06 * fade),
          ],
          const [0, 0.3, 1],
        ),
    );

    // Hex cells: a patch lit round the impact, plus the ripple's band.
    final band = 0.2 * r;
    final stroke = Paint()
      ..blendMode = BlendMode.plus
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.014;
    final fill = Paint()..blendMode = BlendMode.plus;
    for (var i = 0; i < _cells.length; i++) {
      final d = (_cellCenters[i] - hit).distance;
      final patch = math.max(0.0, 1 - d / (1.1 * r));
      final wave = math.exp(-math.pow((d - ripple) / band, 2));
      final a = fade * (0.5 * patch * patch + 0.75 * wave);
      if (a < 0.02) continue;
      canvas.drawPath(_cells[i], fill..color = _cyan.withValues(alpha: a * 0.22));
      canvas.drawPath(_cells[i], stroke..color = _cyan.withValues(alpha: a));
    }

    // Ripple ring running across the bubble from the impact.
    canvas.drawCircle(
      hit,
      ripple,
      Paint()
        ..blendMode = BlendMode.plus
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.03
        ..color = _core.withValues(alpha: 0.55 * fade),
    );

    // The hit itself: a white flash for the first ~0.15 s.
    final flash = (1 - k * 3.5).clamp(0.0, 1.0) * strength;
    if (flash > 0) {
      canvas.drawCircle(
        hit,
        r * (0.28 + 0.3 * k),
        Paint()
          ..blendMode = BlendMode.plus
          ..color = _core.withValues(alpha: 0.9 * flash)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.1),
      );
    }
    canvas.restore();

    // Rim: a soft glow all round, a bright arc where it was hit.
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.07
        ..color = _cyan.withValues(alpha: 0.3 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.05),
    );
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.02
        ..color = _cyan.withValues(alpha: 0.45 * fade),
    );
    final ang = math.atan2(hit.dy, hit.dx);
    const spread = 0.7;
    canvas.drawArc(
      bubble,
      ang - spread,
      spread * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.05
        ..color = _core.withValues(alpha: 0.9 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.03),
    );
    canvas.restore();
  }
}
