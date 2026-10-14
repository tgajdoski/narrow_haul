import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/components/hud_text.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/guidance/flight_guidance.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

class CoachMarkHud extends PositionComponent {
  CoachMarkHud({required this.controls}) : super(priority: 5010);

  final HudTouchControls controls;

  /// Set every frame; null = no mark.
  CoachMark? mark;

  /// Where the plate was drawn last frame (the comms line keeps clear).
  Rect? get plateRect => _plateRect;
  Rect? _plateRect;

  /// The ship and the towed pod on screen, set every frame: the plate moves
  /// off them, or fades to a ghost when it can't.
  List<Rect> shield = const [];

  /// Plate opacity, eased toward 1 (clear) or [_blockedAlpha] (over the ship).
  double _vis = 1;
  double _visTarget = 1;
  static const double _blockedAlpha = 0.25;

  CoachMark? _shown;
  double _in = 0;
  double _t = 0;

  // A finished mark collapsing into its control.
  _Anchor? _exitAt;
  double _exit = 1;
  static const double _exitSeconds = 0.45;

  final _flights = <_FlyIn>[];

  final _title = HudText();
  final _detail = HudText();
  final _cost = HudText();
  final _keys = List.generate(4, (_) => HudText());

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  /// A new level: drop everything without the exit flourish.
  void clear() {
    mark = null;
    _shown = null;
    _in = 0;
    _exitAt = null;
    _exit = 1;
    _flights.clear();
    _plateRect = null;
  }

  /// A crate's weapon flies from [from] (screen px) into the FIRE pad.
  void flyIn(Offset from, WeaponKind kind) {
    _flights.add(_FlyIn(from: from, kind: kind));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    final next = mark;
    if (next?.id != _shown?.id) {
      final old = _shown;
      if (old != null && old.confirmOnExit) {
        _exitAt = _anchorFor(old.target);
        _exit = 0;
      }
      _shown = next;
      _in = 0;
      _vis = _visTarget = 1;
    }
    if (_shown != null) _in = math.min(1, _in + dt * 5);
    _vis += (_visTarget - _vis) * math.min(1, dt * 8);
    if (_exit < 1) _exit = math.min(1, _exit + dt / _exitSeconds);
    for (final f in _flights) {
      f.t += dt;
    }
    _flights.removeWhere((f) => f.t >= _FlyIn.duration + _FlyIn.flash);
  }

  _Anchor? _anchorFor(CoachTarget target) {
    final l = controls.layout;
    if (l == null) return null;
    return switch (target) {
      CoachTarget.thrust => _Anchor(
          l.thrust,
          HudButtonLayout.thrustRadius,
          HudColors.thrust,
          hexRotation: math.pi / 6,
          side: l.innerSide,
        ),
      CoachTarget.fire => controls.showFire
          ? _Anchor(
              l.fire,
              HudButtonLayout.fireRadius,
              HudColors.fire,
              hexRotation: 0,
              side: l.innerSide,
              // Past the ammo rail's slots and counts.
              extraGap: HudButtonLayout.innerReach(rail: controls.railInner) -
                  HudButtonLayout.innerReach(rail: false),
            )
          : null,
      CoachTarget.dial => _Anchor(
          l.dialRest,
          HudButtonLayout.dialRadius,
          HudColors.cyanBright,
          side: -l.innerSide,
        ),
    };
  }

  @override
  void render(Canvas canvas) {
    _plateRect = null;
    _renderExit(canvas);
    final m = _shown;
    if (m != null) {
      final a = _anchorFor(m.target);
      if (a != null) _renderMark(canvas, m, a);
    }
    _renderFlights(canvas);
  }

  void _ring(Canvas canvas, _Anchor a, double r, Color color, double width) {
    final path = a.hexRotation == null
        ? (Path()..addOval(Rect.fromCircle(center: a.c, radius: r)))
        : hexPath(a.c, r, rotation: a.hexRotation!);
    drawStroke(canvas, path, color, width);
  }

  void _renderMark(Canvas canvas, CoachMark m, _Anchor a) {
    final ease = Curves.easeOutCubic.transform(_in);
    var e = ease;
    final ringR = a.r + 7;

    // The control itself: a steady ring plus two pulses rolling outward.
    final steady = a.hexRotation == null
        ? (Path()..addOval(Rect.fromCircle(center: a.c, radius: ringR)))
        : hexPath(a.c, ringR, rotation: a.hexRotation!);
    drawGlow(canvas, steady, a.color, 0.7 * e);
    drawStroke(canvas, steady, a.color.withValues(alpha: 0.9 * e), 2);
    for (var k = 0; k < 2; k++) {
      final p = (_t * 0.9 + k * 0.5) % 1.0;
      _ring(canvas, a, ringR + 26 * p, a.color.withValues(alpha: (1 - p) * 0.55 * e), 1.6);
    }

    // Tilt steering: a phone rocking side to side where the stick would be.
    if (m.target == CoachTarget.dial && m.keys.isEmpty && FlightTuning.tilt) {
      canvas
        ..save()
        ..translate(a.c.dx, a.c.dy)
        ..rotate(math.sin(_t * 2.4) * 0.35);
      final phone = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: a.r * 1.3, height: a.r * 0.7),
        const Radius.circular(6),
      );
      canvas
        ..drawRRect(phone, Paint()..color = Colors.white.withValues(alpha: 0.14 * e))
        ..drawRRect(
          phone,
          Paint()
            ..color = a.color.withValues(alpha: 0.85 * e)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        )
        ..restore();
    } else if (m.target == CoachTarget.dial && m.keys.isEmpty) {
      // The dial teaches the drag: a ghost thumb sweeping across it.
      final sweep = math.sin(_t * 2.4);
      final knob = a.c + Offset(sweep * a.r * 0.6, 0);
      canvas.drawCircle(
        knob,
        16,
        Paint()..color = Colors.white.withValues(alpha: 0.18 * e),
      );
      canvas.drawCircle(
        knob,
        16,
        Paint()
          ..color = a.color.withValues(alpha: 0.8 * e)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Callout plate.
    const padH = 11.0;
    const padV = 7.0;
    const gap = 3.0;
    final title = _title.layout(
      TextSpan(text: m.title, style: hudFont(13, a.color, spacing: 1.4)),
    );
    final detail = _detail.layout(
      TextSpan(
        text: m.detail,
        style: const TextStyle(
          color: Color(0xE6FFFFFF),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      maxWidth: 210,
    );
    final keys = [
      for (var i = 0; i < m.keys.length && i < _keys.length; i++)
        _keys[i].layout(
          TextSpan(text: m.keys[i], style: hudFont(9, Colors.white, spacing: 0.6)),
        ),
    ];
    final cost = m.cost == null
        ? null
        : _cost.layout(
            TextSpan(text: m.cost, style: hudFont(10, HudColors.thrustHot, spacing: 0.8)),
          );

    final glyphW = m.glyph != null ? 20.0 : 0.0;
    var keysW = 0.0;
    for (final k in keys) {
      keysW += k.width + 10 + 4;
    }
    // Desktop: the keys follow the detail line ('Knock out turrets  [F]').
    final detailRowW = detail.width + (keys.isEmpty ? 0 : 6 + keysW);
    final costW = cost == null ? 0.0 : 14 + cost.width;
    final innerW = math.max(glyphW + title.width, math.max(detailRowW, costW));
    final rowKeysH = keys.isEmpty ? 0.0 : keys.first.height + 4;
    final detailH = math.max(detail.height, rowKeysH);
    final innerH =
        title.height + gap + detailH + (cost == null ? 0 : gap + cost.height + 2);
    final w = innerW + padH * 2;
    final h = innerH + padV * 2;

    final reach = a.r + 22 + a.extraGap;
    final slide = (1 - ease) * 14;
    final left = a.side > 0
        ? a.c.dx + reach - slide
        : a.c.dx - reach - w + slide;
    final minTop = 110.0 + controls.insets.top;
    final maxTop = size.y - controls.insets.bottom - 8 - h;
    final top = (a.c.dy - h / 2).clamp(minTop, math.max(minTop, maxTop)).toDouble();
    final x0 = left.clamp(4, size.x - w - 4).toDouble();
    // Beside the control; if that covers the ship, as high or as low as the
    // plate may go; if all of them do, a ghost of it.
    final (rect, clear) = placeAvoiding(
      [
        Rect.fromLTWH(x0, top, w, h),
        Rect.fromLTWH(x0, minTop, w, h),
        Rect.fromLTWH(x0, math.max(minTop, maxTop), w, h),
      ],
      shield,
    );
    _plateRect = rect;
    _visTarget = clear ? 1 : _blockedAlpha;
    // A notice (a crate's weapon) is see-through even when clear.
    e = ease * _vis * (m.subtle ? 0.7 : 1);

    // Leader: from the ring to the plate's near edge, with a node.
    final nearX = a.side > 0 ? rect.left : rect.right;
    final nodeY = (a.c.dy).clamp(rect.top + 8, rect.bottom - 8).toDouble();
    final dir = Offset(nearX - a.c.dx, nodeY - a.c.dy);
    final len = dir.distance;
    if (len > ringR + 4) {
      final from = a.c + dir / len * (ringR + 2);
      final leader = Paint()
        ..color = a.color.withValues(alpha: 0.75 * e)
        ..strokeWidth = 1.4;
      canvas.drawLine(from, Offset(nearX, nodeY), leader);
      canvas.drawPath(
        hexPath(Offset(nearX, nodeY), 3.5),
        Paint()..color = a.color.withValues(alpha: e),
      );
    }

    final plate = chamferPath(rect, 9);
    drawGlow(canvas, plate, a.color, 0.35 * e);
    canvas.drawPath(
      plate,
      Paint()..color = HudColors.plateDark.withValues(alpha: (m.subtle ? 0.6 : 0.92) * e),
    );
    drawStroke(canvas, plate, a.color.withValues(alpha: 0.8 * e), 1.3);
    // Accent bar on the side facing the control.
    final barX = a.side > 0 ? rect.left + 3 : rect.right - 6;
    canvas.drawRect(
      Rect.fromLTWH(barX, rect.top + 9, 3, rect.height - 18),
      Paint()..color = a.color.withValues(alpha: 0.85 * e),
    );

    // Fading in/out needs a layer; fully shown it's a plain save (cheaper).
    if (e < 0.99) {
      canvas.saveLayer(rect.inflate(2), Paint()..color = Colors.white.withValues(alpha: e));
    } else {
      canvas.save();
    }
    var y = rect.top + padV;
    var x = rect.left + padH;
    if (m.glyph != null) {
      drawWeaponGlyph(canvas, m.glyph!, Offset(x + 7, y + title.height / 2), 7, color: a.color);
      x += glyphW;
    }
    title.paint(canvas, Offset(x, y));
    y += title.height + gap;
    x = rect.left + padH;
    detail.paint(canvas, Offset(x, y + (detailH - detail.height) / 2));
    if (keys.isNotEmpty) {
      var kx = x + detail.width + 6;
      for (final k in keys) {
        final cap = RRect.fromRectAndRadius(
          Rect.fromLTWH(kx, y + (detailH - k.height - 4) / 2, k.width + 10, k.height + 4),
          const Radius.circular(3),
        );
        canvas.drawRRect(cap, Paint()..color = const Color(0x33FFFFFF));
        canvas.drawRRect(
          cap,
          Paint()
            ..color = const Color(0x99FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        k.paint(canvas, Offset(kx + 5, cap.top + 2));
        kx += k.width + 14;
      }
    }
    y += detailH;
    if (cost != null) {
      y += gap + 2;
      drawFlameGlyph(canvas, Offset(x + 5, y + cost.height / 2), 11, hot: true);
      cost.paint(canvas, Offset(x + 14, y));
    }
    canvas.restore();
  }

  void _renderExit(Canvas canvas) {
    final a = _exitAt;
    if (a == null || _exit >= 1) return;
    final p = Curves.easeInCubic.transform(_exit);
    final fade = 1 - _exit;
    _ring(canvas, a, (a.r + 7) * (1 - 0.45 * p), HudColors.green.withValues(alpha: 0.9 * fade), 2.4);
    // Tick in the middle of the control.
    final s = a.r * 0.32 * (0.8 + 0.4 * Curves.easeOutBack.transform(math.min(1, _exit * 2)));
    final tick = Path()
      ..moveTo(a.c.dx - s * 0.9, a.c.dy)
      ..lineTo(a.c.dx - s * 0.25, a.c.dy + s * 0.65)
      ..lineTo(a.c.dx + s, a.c.dy - s * 0.7);
    drawGlow(canvas, tick, HudColors.green, fade);
    canvas.drawPath(
      tick,
      Paint()
        ..color = HudColors.green.withValues(alpha: fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _renderFlights(Canvas canvas) {
    final l = controls.layout;
    if (l == null || _flights.isEmpty) return;
    final to = l.fire;
    for (final f in _flights) {
      if (f.t < _FlyIn.duration) {
        final p = Curves.easeInOutCubic.transform(f.t / _FlyIn.duration);
        // A lifted arc, like a coin flying to the counter.
        final ctrl = Offset((f.from.dx + to.dx) / 2, math.min(f.from.dy, to.dy) - 80);
        Offset at(double t) =>
            f.from * ((1 - t) * (1 - t)) + ctrl * (2 * t * (1 - t)) + to * (t * t);
        for (var k = 3; k >= 1; k--) {
          final tp = math.max(0.0, p - k * 0.05);
          canvas.drawCircle(
            at(tp),
            6.0 - k,
            Paint()..color = HudColors.gold.withValues(alpha: 0.25 / k),
          );
        }
        final c = at(p);
        final hex = hexPath(c, 14);
        drawGlow(canvas, hex, HudColors.gold, 0.8);
        canvas.drawPath(hex, Paint()..color = HudColors.plateDark);
        drawStroke(canvas, hex, HudColors.gold, 1.6);
        drawWeaponGlyph(canvas, f.kind, c, 8, color: HudColors.gold);
      } else {
        // Landing flash on the pad.
        final q = (f.t - _FlyIn.duration) / _FlyIn.flash;
        drawStroke(
          canvas,
          hexPath(to, HudButtonLayout.fireRadius * (1 + 0.5 * q)),
          HudColors.gold.withValues(alpha: 1 - q),
          2.5,
        );
      }
    }
  }
}

class _Anchor {
  _Anchor(
    this.c,
    this.r,
    this.color, {
    this.hexRotation,
    required this.side,
    this.extraGap = 0,
  });

  final Offset c;
  final double r;
  final Color color;

  /// Hex pad (its rotation); null = the round dial.
  final double? hexRotation;

  /// +1: the plate goes to the right of the control.
  final double side;
  final double extraGap;
}

class _FlyIn {
  _FlyIn({required this.from, required this.kind});
  static const double duration = 0.6;
  static const double flash = 0.3;
  final Offset from;
  final WeaponKind kind;
  double t = 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// World markers
// ─────────────────────────────────────────────────────────────────────────────
