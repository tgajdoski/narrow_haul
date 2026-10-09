import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/components/hud_text.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/guidance/flight_guidance.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

/// In-flight guidance drawn into the cockpit HUD (see `flight_guidance.dart`
/// for what is shown when):
///
/// * [CoachMarkHud]: a ring on the control itself (THRUST, the steering
///   dial, FIRE) with a callout plate beside it. It collapses into the
///   control with a tick once the pilot has used it.
/// * [WorldMarkerHud]: target brackets on turrets, the pod's HOOK / LOWER
///   tag, the pad beacon with its ship + pod slots, a canister ring, and
///   edge chevrons for whatever is off-screen.
/// * [CommsHud]: the radio line (TOWER / OPS) in the free band between the
///   thumbs, typed on and gone after its reading time.

const _green = Color(0xFF4ADE80);
const _amber = Color(0xFFFFB347);

// ─────────────────────────────────────────────────────────────────────────────
// Coach marks
// ─────────────────────────────────────────────────────────────────────────────

class CoachMarkHud extends PositionComponent {
  CoachMarkHud({required this.controls}) : super(priority: 5010);

  final HudTouchControls controls;

  /// Set every frame; null = no mark.
  CoachMark? mark;

  /// Where the plate was drawn last frame (the comms line keeps clear).
  Rect? get plateRect => _plateRect;
  Rect? _plateRect;

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
    }
    if (_shown != null) _in = math.min(1, _in + dt * 5);
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
              extraGap: HudButtonLayout.innerReach(rail: controls.railShown) -
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
    final e = Curves.easeOutCubic.transform(_in);
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

    // The dial teaches the drag: a ghost thumb sweeping across it.
    if (m.target == CoachTarget.dial && m.keys.isEmpty) {
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
    final slide = (1 - e) * 14;
    final left = a.side > 0
        ? a.c.dx + reach - slide
        : a.c.dx - reach - w + slide;
    final minTop = 110.0 + controls.insets.top;
    final maxTop = size.y - controls.insets.bottom - 8 - h;
    final top = (a.c.dy - h / 2).clamp(minTop, math.max(minTop, maxTop)).toDouble();
    final rect = Rect.fromLTWH(left.clamp(4, size.x - w - 4).toDouble(), top, w, h);
    _plateRect = rect;

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

    final plate = chamferRect(rect, 9);
    drawGlow(canvas, plate, a.color, 0.35 * e);
    canvas.drawPath(plate, Paint()..color = HudColors.plateDark.withValues(alpha: 0.92 * e));
    drawStroke(canvas, plate, a.color.withValues(alpha: 0.8 * e), 1.3);
    // Accent bar on the side facing the control.
    final barX = a.side > 0 ? rect.left + 3 : rect.right - 6;
    canvas.drawRect(
      Rect.fromLTWH(barX, rect.top + 9, 3, rect.height - 18),
      Paint()..color = a.color.withValues(alpha: 0.85 * e),
    );

    canvas.saveLayer(rect.inflate(2), Paint()..color = Colors.white.withValues(alpha: e));
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
    _ring(canvas, a, (a.r + 7) * (1 - 0.45 * p), _green.withValues(alpha: 0.9 * fade), 2.4);
    // Tick in the middle of the control.
    final s = a.r * 0.32 * (0.8 + 0.4 * Curves.easeOutBack.transform(math.min(1, _exit * 2)));
    final tick = Path()
      ..moveTo(a.c.dx - s * 0.9, a.c.dy)
      ..lineTo(a.c.dx - s * 0.25, a.c.dy + s * 0.65)
      ..lineTo(a.c.dx + s, a.c.dy - s * 0.7);
    drawGlow(canvas, tick, _green, fade);
    canvas.drawPath(
      tick,
      Paint()
        ..color = _green.withValues(alpha: fade)
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

/// Markers on things in the world, drawn in screen space over the world and
/// under the controls. The game sets the world positions and the projection
/// every frame.
class WorldMarkerHud extends PositionComponent {
  WorldMarkerHud() : super(priority: 4800);

  /// World (m) → screen (px), and px per metre.
  Offset Function(Offset world)? project;
  double zoom = 28;
  EdgeInsets insets = EdgeInsets.zero;

  List<Offset> turrets = const [];
  double turretRadius = 0.5;

  Offset? pod;
  double podRadius = 0.3;
  PodTag? podTag;

  Offset? padCenter;
  PadTag? pad;

  Offset? canister;

  double _t = 0;
  double _turretIn = 0;

  final _tags = <String, HudText>{};

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  void clear() {
    turrets = const [];
    pod = null;
    podTag = null;
    padCenter = null;
    pad = null;
    canister = null;
    _turretIn = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _turretIn = (_turretIn + (turrets.isEmpty ? -dt : dt) * 3).clamp(0.0, 1.0);
  }

  TextPainter _tag(String key, String text, Color color, {double size = 9}) =>
      (_tags[key] ??= HudText()).layout(
        TextSpan(text: text, style: hudFont(size, color, spacing: 1.2)),
      );

  /// The on-screen area markers may use before they turn into chevrons.
  Rect get _safe => Rect.fromLTRB(
        insets.left + 26,
        insets.top + 26,
        size.x - insets.right - 26,
        size.y - insets.bottom - 26,
      );

  @override
  void render(Canvas canvas) {
    final proj = project;
    if (proj == null || size.x <= 0) return;
    final safe = _safe;

    // Turrets: lock-on brackets that close in as they appear.
    if (_turretIn > 0 && turrets.isNotEmpty) {
      Offset? nearestOff;
      var nearestD = double.infinity;
      final centre = size.toOffset() / 2;
      for (final t in turrets) {
        final p = proj(t);
        if (safe.contains(p)) {
          final half = math.max(18.0, turretRadius * zoom + 8) *
              (1 + 0.6 * (1 - Curves.easeOutCubic.transform(_turretIn)));
          _brackets(canvas, p, half, HudColors.fire.withValues(alpha: 0.9 * _turretIn));
          final tp = _tag('turret', 'TURRET', HudColors.fire.withValues(alpha: _turretIn));
          tp.paint(canvas, p + Offset(-tp.width / 2, -half - tp.height - 3));
        } else {
          final d = (p - centre).distanceSquared;
          if (d < nearestD) {
            nearestD = d;
            nearestOff = p;
          }
        }
      }
      if (nearestOff != null) {
        _chevron(canvas, nearestOff, HudColors.fire.withValues(alpha: _turretIn), 'TURRET');
      }
    }

    // Canister: a dashed ring that breathes.
    final can = canister;
    if (can != null) {
      final p = proj(can);
      if (safe.contains(p)) {
        final r = 0.9 * zoom * (1 + 0.08 * math.sin(_t * 4));
        _dashedRing(canvas, p, r, _green.withValues(alpha: 0.85));
        final tp = _tag('fuel', '+FUEL', _green);
        tp.paint(canvas, p + Offset(-tp.width / 2, r + 4));
      } else {
        _chevron(canvas, p, _green, 'FUEL');
      }
    }

    // Pod.
    final podAt = pod;
    final tag = podTag;
    if (podAt != null && tag != null) {
      final p = proj(podAt);
      final color = tag == PodTag.hook ? HudColors.cyanBright : _amber;
      final label = tag == PodTag.hook ? 'HOOK' : 'LOWER ▼';
      if (safe.contains(p)) {
        final half = podRadius * zoom + 10 + 3 * math.sin(_t * 4);
        _brackets(canvas, p, half, color);
        final tp = _tag('pod_$label', label, color);
        tp.paint(canvas, p + Offset(-tp.width / 2, -half - tp.height - 3));
      } else {
        _chevron(canvas, p, color, 'POD');
      }
    }

    // Pad beacon: a plate above the deck with a ship slot and a pod slot.
    final padAt = padCenter;
    final padTag = pad;
    if (padAt != null && padTag != null) {
      final p = proj(padAt);
      if (safe.inflate(40).contains(p)) {
        _padBeacon(canvas, p, padTag);
      } else {
        _chevron(canvas, p, _green, 'PAD');
      }
    }
  }

  void _brackets(Canvas canvas, Offset c, double half, Color color) {
    final arm = half * 0.45;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    for (final sx in const [-1.0, 1.0]) {
      for (final sy in const [-1.0, 1.0]) {
        final corner = c + Offset(sx * half, sy * half);
        canvas.drawPath(
          Path()
            ..moveTo(corner.dx - sx * arm, corner.dy)
            ..lineTo(corner.dx, corner.dy)
            ..lineTo(corner.dx, corner.dy - sy * arm),
          paint,
        );
      }
    }
  }

  void _dashedRing(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    const n = 12;
    final spin = _t * 0.6;
    for (var i = 0; i < n; i++) {
      final a0 = spin + i * 2 * math.pi / n;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a0, math.pi / n, false, paint);
    }
  }

  /// Off-screen target: a hex chevron on the screen edge pointing at it.
  void _chevron(Canvas canvas, Offset target, Color color, String label) {
    final safe = _safe.deflate(14);
    final c = size.toOffset() / 2;
    final d = target - c;
    if (d.distance < 1) return;
    // Scale the direction until it meets the safe rect.
    final sx = d.dx.abs() < 1e-6 ? double.infinity : (safe.width / 2) / d.dx.abs();
    final sy = d.dy.abs() < 1e-6 ? double.infinity : (safe.height / 2) / d.dy.abs();
    final p = safe.center + d * math.min(sx, sy);
    final ang = math.atan2(d.dy, d.dx);
    final bob = 3 * math.sin(_t * 5);
    final tip = p + Offset(math.cos(ang), math.sin(ang)) * (bob + 4);
    final hex = hexPath(p, 11);
    canvas.drawPath(hex, Paint()..color = HudColors.plateDark);
    drawStroke(canvas, hex, color, 1.5);
    final perp = Offset(-math.sin(ang), math.cos(ang));
    final dir = Offset(math.cos(ang), math.sin(ang));
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx + dir.dx * 8, tip.dy + dir.dy * 8)
        ..lineTo(tip.dx + perp.dx * 6, tip.dy + perp.dy * 6)
        ..lineTo(tip.dx - perp.dx * 6, tip.dy - perp.dy * 6)
        ..close(),
      Paint()..color = color,
    );
    final tp = _tag('chev_$label', label, color, size: 8);
    // The label sits on the inner side of the chevron.
    final inward = p - dir * 22;
    tp.paint(canvas, inward - Offset(tp.width / 2, tp.height / 2));
  }

  void _padBeacon(Canvas canvas, Offset deck, PadTag tag) {
    final both = tag.shipIn && tag.podIn;
    final title = _tag('pad_title', 'LAND BOTH', _green);
    const slot = 9.0;
    final w = math.max(title.width + 20, slot * 4 + 34);
    final h = title.height + slot * 2 + 16;
    final rise = 26 + 3 * math.sin(_t * 2.5);
    final rect = Rect.fromCenter(
      center: deck - Offset(0, rise + h / 2),
      width: w,
      height: h,
    );
    // Stem down to the deck.
    canvas.drawLine(
      Offset(deck.dx, rect.bottom),
      deck - const Offset(0, 4),
      Paint()
        ..color = _green.withValues(alpha: 0.5)
        ..strokeWidth = 1.2,
    );
    final plate = chamferRect(rect, 7);
    drawGlow(canvas, plate, _green, 0.35);
    canvas.drawPath(plate, Paint()..color = HudColors.plateDark);
    drawStroke(canvas, plate, _green.withValues(alpha: 0.8), 1.2);
    title.paint(canvas, Offset(rect.center.dx - title.width / 2, rect.top + 5));

    final y = rect.bottom - 6 - slot;
    final shipC = Offset(rect.center.dx - slot - 6, y);
    final podC = Offset(rect.center.dx + slot + 6, y);
    final pulse = 0.5 + 0.5 * math.sin(_t * 6);
    for (final (c, inside, isShip) in [(shipC, tag.shipIn, true), (podC, tag.podIn, false)]) {
      final hex = hexPath(c, slot);
      final col = inside ? _green : Colors.white.withValues(alpha: 0.35 + 0.4 * pulse);
      if (inside) {
        canvas.drawPath(hex, Paint()..color = _green.withValues(alpha: 0.28));
        if (both) drawGlow(canvas, hex, _green, 0.8);
      }
      drawStroke(canvas, hex, col, 1.4);
      final icon = Paint()..color = col;
      if (isShip) {
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - 5)
            ..lineTo(c.dx + 4, c.dy + 4)
            ..lineTo(c.dx - 4, c.dy + 4)
            ..close(),
          icon,
        );
      } else {
        canvas.drawCircle(c, 3.6, icon);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comms line
// ─────────────────────────────────────────────────────────────────────────────

/// The radio line: a plate in the free band at the bottom, between the
/// steering dial and THRUST, that types one [CommsLine] on at a time. When a
/// coach plate sits in that band it moves under the level info, top-left.
class CommsHud extends PositionComponent {
  CommsHud({required this.controls, this.avoid, this.onLine}) : super(priority: 4990);

  final HudTouchControls controls;

  /// A rect to keep clear of (the coach plate).
  final Rect? Function()? avoid;

  /// A line went on air (the blip).
  final void Function(CommsLine line)? onLine;

  final queue = CommsQueue();

  final _call = HudText();
  final _body = HudText();
  final _typed = HudText();
  double _t = 0;

  void say(CommsLine line, {double delay = 0, bool urgent = false}) =>
      queue.say(line, delay: delay, urgent: urgent);

  void clear() => queue.clear();

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (queue.update(dt)) onLine?.call(queue.current!);
  }

  @override
  void render(Canvas canvas) {
    final line = queue.current;
    if (line == null) return;
    final a = queue.alpha;
    if (a <= 0) return;

    const padH = 12.0;
    const padV = 7.0;
    final band = controls.layout?.bottomBand(rail: controls.railShown);
    final bottomBand = band != null && band.width >= 220;
    final maxW = bottomBand ? math.min(400.0, band.width) : 320.0;

    final call = _call.layout(
      TextSpan(text: line.callsign, style: hudFont(10, HudColors.gold, spacing: 2)),
    );
    final typed = line.text.substring(0, queue.visibleChars);
    final textMax = maxW - padH * 2;
    // Lay out the full line once for the size, so the plate doesn't grow
    // while it types.
    final full = _body.layout(
      TextSpan(
        text: line.text,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25),
      ),
      maxWidth: textMax,
    );
    final w = math.max(full.width, call.width + 40) + padH * 2;
    final h = call.height + 3 + full.height + padV * 2;

    var rect = bottomBand
        ? Rect.fromLTWH(band.center.dx - w / 2, band.bottom - h, w, h)
        : Rect.zero;
    final clash = avoid?.call();
    if (!bottomBand || (clash != null && clash.inflate(8).overlaps(rect))) {
      // Under the level info, top-left.
      rect = Rect.fromLTWH(controls.insets.left + 12, controls.insets.top + 82, w, h);
    }
    // Slide up into place.
    rect = rect.shift(Offset(0, (1 - Curves.easeOutCubic.transform(a)) * 10));

    final plate = chamferRect(rect, 9);
    drawGlow(canvas, plate, HudColors.cyan, 0.3 * a);
    canvas.drawPath(plate, Paint()..color = HudColors.plateDark.withValues(alpha: 0.92 * a));
    drawStroke(canvas, plate, HudColors.cyan.withValues(alpha: 0.7 * a), 1.2);
    canvas.drawRect(
      Rect.fromLTWH(rect.left + 3, rect.top + 9, 3, rect.height - 18),
      Paint()..color = HudColors.gold.withValues(alpha: 0.9 * a),
    );

    canvas.saveLayer(rect.inflate(2), Paint()..color = Colors.white.withValues(alpha: a));
    final x = rect.left + padH;
    var y = rect.top + padV;
    call.paint(canvas, Offset(x, y));
    // Signal bars, live while the line types.
    final typing = queue.visibleChars < line.text.length;
    for (var i = 0; i < 4; i++) {
      final bh = 3.0 + i * 2;
      final lit = !typing || ((_t * 12).floor() + i) % 4 != 0;
      canvas.drawRect(
        Rect.fromLTWH(x + call.width + 8 + i * 4, y + call.height - bh - 1, 2.5, bh),
        Paint()..color = (lit ? HudColors.cyanBright : const Color(0x44FFFFFF)),
      );
    }
    y += call.height + 3;
    _typed
        .layout(
          TextSpan(
            text: typed,
            style: const TextStyle(
              color: Color(0xF2FFFFFF),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          maxWidth: textMax,
        )
        .paint(canvas, Offset(x, y));
    canvas.restore();
  }
}
