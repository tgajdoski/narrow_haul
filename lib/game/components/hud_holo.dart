import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:narrow_haul/ui/fonts.dart';

/// Canvas helpers for the in-flight cockpit controls, matching the menus'
/// space UI kit (`lib/ui/space_ui.dart`): hexagons, chamfered plates, glow.
abstract final class HudColors {
  static const cyan = Color(0xFF00B4D8);
  static const cyanBright = Color(0xFF5CE1FF);
  static const thrust = Color(0xFFFF8A3D);
  static const thrustHot = Color(0xFFFFC46B);
  static const fire = Color(0xFFFF5252);
  static const gold = Color(0xFFFFC857);
  static const plate = Color(0x99081222);
  static const plateDark = Color(0xCC050B18);
}

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

/// Rectangle with the top-left / bottom-right corners cut ([cut]) and the
/// other two nicked — the menus' signature plate.
Path chamferRect(Rect r, double cut) {
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

/// Soft outer glow along [path].
void drawGlow(Canvas canvas, Path path, Color color, double strength) {
  if (strength <= 0) return;
  canvas.drawPath(
    path,
    Paint()
      ..color = color.withValues(alpha: 0.5 * strength)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = MaskFilter.blur(BlurStyle.outer, 9 * strength),
  );
}

void drawStroke(Canvas canvas, Path path, Color color, double width) {
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round,
  );
}

/// Letter-spaced display text (RussoOne) for HUD labels.
TextStyle hudFont(double size, Color color, {double spacing = 1.6}) =>
    TextStyle(
      fontFamily: kDisplayFont,
      fontSize: size,
      color: color,
      letterSpacing: spacing,
      shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 3)],
    );

/// Flame glyph (filled, gradient) centred on [c], [size] tall.
void drawFlameGlyph(Canvas canvas, Offset c, double size, {required bool hot}) {
  final h = size;
  final w = size * 0.62;
  final top = c.dy - h * 0.55;
  final bottom = c.dy + h * 0.45;
  final outer = Path()
    ..moveTo(c.dx, top)
    ..cubicTo(c.dx + w * 0.15, top + h * 0.3, c.dx + w * 0.6, top + h * 0.42,
        c.dx + w * 0.5, bottom - h * 0.22)
    ..cubicTo(c.dx + w * 0.45, bottom, c.dx - w * 0.45, bottom,
        c.dx - w * 0.5, bottom - h * 0.22)
    ..cubicTo(c.dx - w * 0.55, top + h * 0.5, c.dx - w * 0.05, top + h * 0.35,
        c.dx, top)
    ..close();
  final rect = Rect.fromLTRB(c.dx - w / 2, top, c.dx + w / 2, bottom);
  canvas.drawPath(
    outer,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: hot
            ? const [Color(0xFFFFE08A), HudColors.thrust]
            : const [Color(0xCCFFB27A), Color(0xCCE0603A)],
      ).createShader(rect),
  );
  // Inner core.
  final ih = h * 0.45;
  final iw = w * 0.42;
  final itop = bottom - ih;
  final inner = Path()
    ..moveTo(c.dx, itop)
    ..cubicTo(c.dx + iw * 0.6, itop + ih * 0.45, c.dx + iw * 0.6, bottom,
        c.dx, bottom - ih * 0.05)
    ..cubicTo(c.dx - iw * 0.6, bottom, c.dx - iw * 0.6, itop + ih * 0.45,
        c.dx, itop)
    ..close();
  canvas.drawPath(
    inner,
    Paint()..color = hot ? const Color(0xFFFFFFFF) : const Color(0x99FFE8C8),
  );
}
