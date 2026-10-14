import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/components/salvage_glyphs.dart';
import 'package:narrow_haul/game/components/hud_text.dart';
import 'package:narrow_haul/game/salvage/salvage.dart';

/// The salvage badge (top left, under the fuel gauge): a slot-machine
/// roulette while a cache is being opened, then the effect's icon, name and
/// a draining countdown bar.
class SalvageHud extends PositionComponent {
  SalvageHud({required this.state, this.onTick}) : super(priority: 4910);

  final ActiveSalvage state;

  /// One roulette click (a tick sound).
  final void Function()? onTick;

  /// Safe-area insets (the badge keeps clear of the notch).
  EdgeInsets insets = EdgeInsets.zero;

  static const double rouletteSeconds = 0.9;

  /// Plate rect (left, top) relative to the safe area; below the fuel gauge
  /// and level info (`HudButtonLayout.topClear`).
  static const Offset origin = Offset(12, 110);
  static const Size plateSize = Size(196, 38);

  SalvageSpec? _shown;
  double _roulette = 0;
  int _face = -1;
  double _pop = 1;
  double _hold = 0;
  double _fade = 0;
  double _t = 0;

  final _name = HudText();
  final _sub = HudText();

  /// A cache opened: spin, then land on [result] (the game applies it).
  void spin(SalvageSpec result) {
    _shown = result;
    _roulette = rouletteSeconds;
    _face = -1;
    _pop = 0;
    _hold = 0;
  }

  bool get spinning => _roulette > 0;

  /// Clears the badge (new level).
  void clear() {
    _shown = null;
    _roulette = 0;
    _fade = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_roulette > 0) {
      _roulette = math.max(0, _roulette - dt);
      // Faces flick by fast, then slow down (ease-out).
      final k = 1 - _roulette / rouletteSeconds;
      final face = (Curves.easeOut.transform(k) * 9).floor();
      if (face != _face) {
        _face = face;
        if (_roulette > 0) onTick?.call();
      }
      if (_roulette == 0) _hold = 1.6;
    } else {
      _pop = math.min(1, _pop + dt / 0.3);
      if (_hold > 0) _hold -= dt;
    }
    final visible = _shown != null && (_roulette > 0 || state.active || _hold > 0);
    _fade = (_fade + (visible ? dt : -dt) * 5).clamp(0.0, 1.0);
    if (_fade == 0 && !visible) _shown = null;
  }

  @override
  void render(Canvas canvas) {
    final spec = _shown;
    if (spec == null || _fade <= 0) return;
    final spinning = _roulette > 0;
    final color = spinning
        ? Color.lerp(kSalvageGood, kSalvageBad, 0.5 + 0.5 * math.sin(_t * 18))!
        : salvageColor(spec);
    final left = insets.left + origin.dx;
    final top = insets.top + origin.dy;
    final scale = spinning ? 1.0 : 1 + 0.15 * (1 - Curves.easeOutBack.transform(_pop));
    canvas.save();
    canvas.translate(left, top);
    canvas.scale(scale);
    if (_fade < 1) {
      canvas.saveLayer(
        Offset.zero & plateSize,
        Paint()..color = Color.fromRGBO(255, 255, 255, _fade),
      );
    }
    final plate = chamferPath(Offset.zero & plateSize, 9);
    drawGlow(canvas, plate, color, spinning ? 0.7 : 0.45);
    canvas.drawPath(plate, Paint()..color = HudColors.plateDark);
    drawStroke(canvas, plate, color.withValues(alpha: 0.85), 1.4);

    const hexC = Offset(21, 19);
    final hex = hexPath(hexC, 14);
    canvas.drawPath(hex, Paint()..color = color.withValues(alpha: 0.18));
    drawStroke(canvas, hex, color, 1.2);
    final face = spinning
        ? (_face <= 0 ? null : kSalvage[(_face * 3) % kSalvage.length].effect)
        : spec.effect;
    drawSalvageGlyph(canvas, hexC, 16, face, spinning ? Colors.white : color);

    final title = spinning ? 'SALVAGE  ? ? ?' : spec.name;
    final name = _name.layout(TextSpan(text: title, style: hudFont(11, Colors.white)));
    name.paint(canvas, const Offset(42, 6));
    final subText = spinning
        ? 'OPENING…'
        : spec.timed
            ? (spec.good ? 'BOON' : 'CURSE')
            : (spec.good ? 'BOON · INSTANT' : 'CURSE');
    final sub = _sub.layout(
      TextSpan(text: subText, style: hudFont(8, color.withValues(alpha: 0.9), spacing: 1.2)),
    );
    sub.paint(canvas, Offset(plateSize.width - 10 - sub.width, 8));

    // Countdown bar.
    final bar = Rect.fromLTWH(42, 25, plateSize.width - 42 - 12, 5);
    canvas.drawRect(bar, Paint()..color = Colors.white.withValues(alpha: 0.12));
    final frac = spinning ? (1 - _roulette / rouletteSeconds) : (spec.timed ? state.fraction : (_hold / 1.6).clamp(0.0, 1.0));
    final blink = !spinning && spec.timed && state.left < 2 && (state.left * 6).floor().isEven;
    canvas.drawRect(
      Rect.fromLTWH(bar.left, bar.top, bar.width * frac, bar.height),
      Paint()..color = color.withValues(alpha: blink ? 0.35 : 0.95),
    );
    if (_fade < 1) canvas.restore();
    canvas.restore();
  }
}
