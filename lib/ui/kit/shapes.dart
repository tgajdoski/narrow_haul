import 'dart:math' as math;
import 'dart:ui';

/// Paths shared by the menus' space UI kit and the in-flight HUD.

/// Pointy-top hexagon around [c].
Path hexPath(Offset c, double r, {double rotation = 0}) {
  final p = Path();
  for (var i = 0; i < 6; i++) {
    final a = rotation + math.pi / 6 + i * math.pi / 3;
    final v = c + Offset(math.cos(a), math.sin(a)) * r;
    i == 0 ? p.moveTo(v.dx, v.dy) : p.lineTo(v.dx, v.dy);
  }
  return p..close();
}

/// A rectangle with the top-left and bottom-right corners cut ([cut]) and the
/// other two slightly cut — the kit's signature silhouette.
Path chamferPath(Rect r, double cut) {
  final c = math.min(cut, math.min(r.width, r.height) / 2);
  final s = c * 0.35;
  return Path()
    ..moveTo(r.left + c, r.top)
    ..lineTo(r.right - s, r.top)
    ..lineTo(r.right, r.top + s)
    ..lineTo(r.right, r.bottom - c)
    ..lineTo(r.right - c, r.bottom)
    ..lineTo(r.left + s, r.bottom)
    ..lineTo(r.left, r.bottom - s)
    ..lineTo(r.left, r.top + c)
    ..close();
}

/// Five-pointed star around [c], point up, inner radius [inner] × [r].
Path starPath(Offset c, double r, {double inner = 0.4}) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final d = i.isEven ? r : r * inner;
    final v = c + Offset(math.cos(a), math.sin(a)) * d;
    i == 0 ? p.moveTo(v.dx, v.dy) : p.lineTo(v.dx, v.dy);
  }
  return p..close();
}

/// One reusable Paint for blurred outer-glow strokes. Callers draw with it
/// straight away; the blur filter is rebuilt only when the radius changes.
abstract final class GlowPaint {
  static final Paint _paint = Paint()..style = PaintingStyle.stroke;
  static double _sigma = -1;

  static Paint of(Color color, double width, double sigma) {
    if (sigma != _sigma) {
      _sigma = sigma;
      _paint.maskFilter = MaskFilter.blur(BlurStyle.outer, sigma);
    }
    return _paint
      ..color = color
      ..strokeWidth = width;
  }
}
