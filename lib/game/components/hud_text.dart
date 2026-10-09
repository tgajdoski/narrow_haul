import 'package:flutter/painting.dart';

/// [alpha] snapped to 1/32 steps, so a fading label re-lays out ~32 times
/// per fade instead of every frame (the difference isn't visible).
double quantizeAlpha(double alpha) => (alpha.clamp(0.0, 1.0) * 32).round() / 32;

/// A HUD text slot that re-lays out only when its content, style or width
/// changes. `TextPainter.layout` is the costliest per-frame call in the HUD,
/// and most labels stay the same for many frames.
class HudText {
  TextPainter? _painter;
  InlineSpan? _span;
  double _maxWidth = double.infinity;

  TextPainter layout(
    InlineSpan span, {
    double maxWidth = double.infinity,
    TextAlign textAlign = TextAlign.start,
  }) {
    final cached = _painter;
    if (cached != null && maxWidth == _maxWidth && span == _span) return cached;
    cached?.dispose();
    _span = span;
    _maxWidth = maxWidth;
    return _painter = TextPainter(
      text: span,
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
  }
}
