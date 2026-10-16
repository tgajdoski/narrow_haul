import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/components/hud_text.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/guidance/flight_guidance.dart';

/// The radio line: a plate in the free band at the bottom, between the
/// steering dial and THRUST, that types one [CommsLine] on at a time. When a
/// coach plate sits in that band it moves under the level info, top-left.
class CommsHud extends PositionComponent {
  CommsHud({required this.controls, this.avoid, this.onLine}) : super(priority: 4990);

  final HudTouchControls controls;

  /// A rect to keep clear of (the coach plate).
  final Rect? Function()? avoid;

  /// The ship and the towed pod on screen (see [CoachMarkHud.shield]).
  List<Rect> shield = const [];
  double _vis = 1;
  double _visTarget = 1;

  /// A line went on air (the blip).
  final void Function(CommsLine line)? onLine;

  final queue = CommsQueue();

  final _call = HudText();
  final _body = HudText();
  final _typed = HudText();
  double _t = 0;

  void say(
    CommsLine line, {
    double delay = 0,
    bool urgent = false,
    double? expiresIn,
  }) =>
      queue.say(line, delay: delay, urgent: urgent, expiresIn: expiresIn);

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
    _vis += (_visTarget - _vis) * math.min(1, dt * 8);
  }

  @override
  void render(Canvas canvas) {
    final line = queue.current;
    if (line == null) return;
    final shown = queue.alpha;
    if (shown <= 0) return;

    const padH = 12.0;
    const padV = 7.0;
    final band = controls.layout?.bottomBand(
      rail: controls.railInner,
      reach: controls.innerReach,
    );
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

    // Under the level info, top-left.
    final topLeft = Rect.fromLTWH(controls.insets.left + 12, controls.insets.top + 82, w, h);
    final clash = avoid?.call();
    // The coach plate must stay readable: never place over it.
    final candidates = [
      if (bottomBand) Rect.fromLTWH(band.center.dx - w / 2, band.bottom - h, w, h),
      topLeft,
    ].where((r) => clash == null || !clash.inflate(8).overlaps(r)).toList();
    final (placed, clear) = placeAvoiding(
      candidates.isEmpty ? [topLeft] : candidates,
      shield,
    );
    var rect = placed;
    // Over the ship either way: a ghost of the line.
    _visTarget = clear ? 1 : 0.3;
    final a = shown * _vis;
    // Slide up into place.
    rect = rect.shift(Offset(0, (1 - Curves.easeOutCubic.transform(shown)) * 10));

    final plate = chamferPath(rect, 9);
    drawGlow(canvas, plate, HudColors.cyan, 0.3 * a);
    canvas.drawPath(plate, Paint()..color = HudColors.plateDark.withValues(alpha: 0.92 * a));
    drawStroke(canvas, plate, HudColors.cyan.withValues(alpha: 0.7 * a), 1.2);
    canvas.drawRect(
      Rect.fromLTWH(rect.left + 3, rect.top + 9, 3, rect.height - 18),
      Paint()..color = HudColors.gold.withValues(alpha: 0.9 * a),
    );

    if (a < 0.99) {
      canvas.saveLayer(rect.inflate(2), Paint()..color = Colors.white.withValues(alpha: a));
    } else {
      canvas.save();
    }
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
