
import 'package:flutter/material.dart';

import '../../game/env.dart';
import '../fonts.dart';


abstract final class SpaceColors {
  static const bg = Color(0xFF050816);
  static const panel = Color(0xFF0D1B2A);
  static const panelDeep = Color(0xE6081222);
  static const track = Color(0xFF1B263B);
  static const cyan = Color(0xFF00B4D8);
  static const cyanBright = Color(0xFF5CE1FF);
  static const gold = Color(0xFFFFD166);
  static const green = Color(0xFF4ADE80);
  static const coral = Color(0xFFE07A5F);
  static const red = Color(0xFFFF6B6B);
  static const violet = Color(0xFF9B8CFF);
  static const textDim = Color(0x8AFFFFFF);
  static const textFaint = Color(0x5CFFFFFF);
}

/// Letter-spaced display label (RussoOne).
TextStyle hudLabel(
  double size, {
  Color color = Colors.white,
  double spacing = 1.6,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: kDisplayFont,
  fontSize: size,
  color: color,
  letterSpacing: spacing,
  fontWeight: weight,
  height: 1.1,
);

/// Looping UI animations (starfield, pulses) are off in widget tests, where
/// `pumpAndSettle` would never settle, and when the system asks for reduced
/// motion.
bool spaceAnimationsOn(BuildContext context) =>
    !kInFlutterTest && !MediaQuery.disableAnimationsOf(context);

/// `1m02s` / `12.4s`.
String formatFlightTime(double seconds) {
  if (seconds.isInfinite || seconds.isNaN) return '--';
  if (seconds >= 60) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toStringAsFixed(0).padLeft(2, '0');
    return '${m}m${s}s';
  }
  return '${seconds.toStringAsFixed(1)}s';
}
