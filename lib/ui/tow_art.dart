import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Drawing shared by the menu screens that show a ship towing a pod (the
/// hangar hero and the launch intro), so they look like the same craft.

/// Tow line from [from] (the winch) to [to] (the pod), with a little sag.
void paintTowLine(Canvas canvas, Offset from, Offset to, {double opacity = 1}) {
  final mid = Offset.lerp(from, to, 0.5)! + const Offset(4, 0);
  canvas.drawPath(
    Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy),
    Paint()
      ..color = const Color(0xCC9FB3C8).withValues(alpha: 0.8 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6,
  );
}

/// Engine plume pointing down from [nozzle] (ship-local "down"), sized for a
/// ship sprite [shipSize] across; [flicker] is any running 0→1 phase.
void paintThrustPlume(
  Canvas canvas,
  Offset nozzle,
  double shipSize,
  double flicker,
) {
  final f =
      0.8 +
      0.2 * math.sin(flicker * 2 * math.pi * 9) +
      0.08 * math.sin(flicker * 2 * math.pi * 23);
  final len = shipSize * 0.42 * f;
  final w = shipSize * 0.11;
  final plume = Path()
    ..moveTo(nozzle.dx - w, nozzle.dy)
    ..quadraticBezierTo(
      nozzle.dx - w * 0.6,
      nozzle.dy + len * 0.6,
      nozzle.dx,
      nozzle.dy + len,
    )
    ..quadraticBezierTo(
      nozzle.dx + w * 0.6,
      nozzle.dy + len * 0.6,
      nozzle.dx + w,
      nozzle.dy,
    )
    ..close();
  final rect = Rect.fromLTWH(nozzle.dx - w, nozzle.dy, w * 2, len);
  canvas.drawPath(
    plume,
    Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFF3C4), Color(0xFFFF9F43), Color(0x00FF5E3A)],
      ).createShader(rect),
  );
  canvas.drawPath(
    plume,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Color(0xCCFFC46B), Color(0x00FF7B3A)],
      ).createShader(rect),
  );
}
