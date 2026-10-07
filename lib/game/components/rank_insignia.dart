import 'dart:math' as math;
import 'dart:ui';

import 'package:narrow_haul/game/services/rank_service.dart';

const _gold = Color(0xFFFFD166);
const _silver = Color(0xFFCBD5E1);
const _board = Color(0xFF0D1B2A);

/// Paints a rank badge into [rect]: pilot wings for the licence ranks, an
/// airline epaulette (1–4 gold bars, plus star / laurel) for cockpit ranks.
/// Shared by Flutter widgets and Flame components.
void paintInsignia(Canvas canvas, Rect rect, InsigniaKind kind) {
  switch (kind) {
    case InsigniaKind.wingsOutline:
      _paintWings(canvas, rect, _silver, filled: false);
    case InsigniaKind.wingsSilver:
      _paintWings(canvas, rect, _silver, filled: true);
    case InsigniaKind.wingsGold:
      _paintWings(canvas, rect, _gold, filled: true);
    case InsigniaKind.stripes1:
      _paintEpaulette(canvas, rect, bars: 1);
    case InsigniaKind.stripes2:
      _paintEpaulette(canvas, rect, bars: 2);
    case InsigniaKind.stripes3:
      _paintEpaulette(canvas, rect, bars: 3);
    case InsigniaKind.stripes4:
      _paintEpaulette(canvas, rect, bars: 4);
    case InsigniaKind.stripes4Star:
      _paintEpaulette(canvas, rect, bars: 4, star: true);
    case InsigniaKind.stripes4Laurel:
      _paintEpaulette(canvas, rect, bars: 4, laurel: true);
    case InsigniaKind.stripes4LaurelStar:
      _paintEpaulette(canvas, rect, bars: 4, star: true, laurel: true);
  }
}

void _paintWings(Canvas canvas, Rect rect, Color color, {required bool filled}) {
  final w = rect.width;
  final h = rect.height;
  final cx = rect.center.dx;
  final cy = rect.center.dy;
  final paint = Paint()
    ..color = color
    ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
    ..strokeWidth = math.max(1, w * 0.03)
    ..strokeJoin = StrokeJoin.round;

  for (final side in [-1.0, 1.0]) {
    // Swept wing: root at the badge centre, tip raised at the outer edge.
    final wing = Path()
      ..moveTo(cx + side * w * 0.10, cy - h * 0.12)
      ..quadraticBezierTo(
        cx + side * w * 0.30, cy - h * 0.30,
        cx + side * w * 0.50, cy - h * 0.26,
      )
      ..lineTo(cx + side * w * 0.40, cy - h * 0.10)
      ..lineTo(cx + side * w * 0.44, cy - h * 0.06)
      ..lineTo(cx + side * w * 0.32, cy + h * 0.04)
      ..lineTo(cx + side * w * 0.35, cy + h * 0.08)
      ..lineTo(cx + side * w * 0.22, cy + h * 0.16)
      ..quadraticBezierTo(
        cx + side * w * 0.14, cy + h * 0.14,
        cx + side * w * 0.10, cy + h * 0.06,
      )
      ..close();
    canvas.drawPath(wing, paint);
  }

  // Centre shield.
  final shield = Path()
    ..moveTo(cx - w * 0.09, cy - h * 0.20)
    ..lineTo(cx + w * 0.09, cy - h * 0.20)
    ..lineTo(cx + w * 0.09, cy + h * 0.06)
    ..quadraticBezierTo(cx, cy + h * 0.26, cx - w * 0.09, cy + h * 0.06)
    ..close();
  canvas.drawPath(shield, paint);
}

void _paintEpaulette(
  Canvas canvas,
  Rect rect, {
  required int bars,
  bool star = false,
  bool laurel = false,
}) {
  // Board is portrait, centred in rect, with a pointed button end on top.
  final bh = rect.height * 0.92;
  final bw = math.min(rect.width * 0.62, bh * 0.52);
  final left = rect.center.dx - bw / 2;
  final top = rect.center.dy - bh / 2;
  final board = Path()
    ..moveTo(left, top + bw * 0.45)
    ..lineTo(rect.center.dx, top)
    ..lineTo(left + bw, top + bw * 0.45)
    ..lineTo(left + bw, top + bh)
    ..lineTo(left, top + bh)
    ..close();
  canvas.drawPath(board, Paint()..color = _board);
  canvas.drawPath(
    board,
    Paint()
      ..color = _gold.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, bw * 0.05),
  );

  final gold = Paint()..color = _gold;
  final barH = bh * 0.065;
  final gap = bh * 0.045;
  final barLeft = left + bw * 0.12;
  final barW = bw * 0.76;
  var y = top + bh - gap * 1.6 - barH;
  for (int i = 0; i < bars; i++) {
    canvas.drawRect(Rect.fromLTWH(barLeft, y, barW, barH), gold);
    y -= barH + gap;
  }

  // Button near the point.
  canvas.drawCircle(Offset(rect.center.dx, top + bw * 0.42), bw * 0.09, gold);

  final emblemY = top + bh * 0.42;
  if (laurel) {
    final p = Paint()
      ..color = _gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, bw * 0.05)
      ..strokeCap = StrokeCap.round;
    final r = bw * 0.30;
    final c = Offset(rect.center.dx, emblemY);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), math.pi * 0.55, math.pi * 0.8, false, p);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi * 0.35, math.pi * 0.8, false, p);
  }
  if (star) {
    _drawStar(canvas, Offset(rect.center.dx, emblemY), bw * (laurel ? 0.16 : 0.22), gold);
  }
}

void _drawStar(Canvas canvas, Offset c, double r, Paint paint) {
  final path = Path();
  for (int i = 0; i < 5; i++) {
    final a = -math.pi / 2 + i * 2 * math.pi / 5;
    final b = a + math.pi / 5;
    final o = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
    final n = Offset(c.dx + r * 0.4 * math.cos(b), c.dy + r * 0.4 * math.sin(b));
    i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    path.lineTo(n.dx, n.dy);
  }
  path.close();
  canvas.drawPath(path, paint);
}
