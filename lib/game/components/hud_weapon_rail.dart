part of 'hud_touch_controls.dart';

/// The ammo rail: a column of hex slots beside FIRE, one per weapon on
/// board, each with its icon and ammo. Tap one to load it. The loaded slot
/// is lit gold, and a weapon whose next shot spends the player's own stock
/// (2★ cap) carries a gold dot. Right after a switch the loaded slot's
/// count gives way to the weapon's full name for a moment.
class _WeaponRail extends PositionComponent with TapCallbacks {
  _WeaponRail({
    required this.layout,
    required this.weapon,
    required this.toastAlpha,
    required this.onSelect,
  });

  final HudButtonLayout layout;
  final WeaponHud? Function() weapon;
  final double Function() toastAlpha;
  final void Function(String id) onSelect;

  final _counts = List.generate(6, (_) => HudText());
  final _toast = HudText();

  List<Offset> _centers(WeaponHud w) =>
      layout.railCenters(math.min(w.slots.length, _counts.length));

  int? _slotAt(Offset p) {
    final w = weapon();
    if (w == null || !w.showRail) return null;
    final centers = _centers(w);
    for (var i = 0; i < centers.length; i++) {
      final d = p - centers[i];
      if (d.dx.abs() <= HudButtonLayout.slotRadius + 6 &&
          d.dy.abs() <= HudButtonLayout.slotSpacing / 2) {
        return i;
      }
    }
    return null;
  }

  @override
  bool containsLocalPoint(Vector2 point) => _slotAt(Offset(point.x, point.y)) != null;

  @override
  void onTapDown(TapDownEvent event) {
    final i = _slotAt(Offset(event.localPosition.x, event.localPosition.y));
    final w = weapon();
    if (i == null || w == null) return;
    onSelect(w.slots[i].id);
  }

  @override
  void render(Canvas canvas) {
    final w = weapon();
    if (w == null || !w.showRail) return;
    final centers = _centers(w);
    const r = HudButtonLayout.slotRadius;
    final side = layout.innerSide;
    final toast = toastAlpha();
    for (var i = 0; i < centers.length; i++) {
      final s = w.slots[i];
      final c = centers[i];
      final on = i == w.selectedIndex;
      final hex = hexPath(c, r);
      if (on) drawGlow(canvas, hex, HudColors.gold, 0.7);
      canvas.drawPath(hex, Paint()..color = on ? HudColors.plate : HudColors.plateDark);
      drawStroke(
        canvas,
        hex,
        on ? HudColors.gold : HudColors.cyan.withValues(alpha: 0.55),
        on ? 2 : 1.2,
      );
      // An outer slot sits at the screen edge: its count is a tag under the
      // icon. An inner slot keeps its count beside it, toward the centre.
      final outer = layout.isOuterSlot(c);
      drawWeaponGlyph(
        canvas,
        s.kind,
        outer && s.count != null ? c - Offset(0, r * 0.18) : c,
        outer && s.count != null ? r * 0.42 : r * 0.5,
        color: Colors.white.withValues(alpha: on ? 1 : 0.6),
      );
      if (s.costsStar) {
        canvas.drawCircle(c + Offset(side * r * 0.7, -r * 0.62), 3, Paint()..color = HudColors.gold);
      }
      final named = on && toast > 0;
      if (s.count case final count? when outer) {
        final tp = _counts[i].layout(TextSpan(
          text: count,
          style: hudFont(8.5, Colors.white.withValues(alpha: on ? 0.95 : 0.7), spacing: 0.3),
        ));
        final tag = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: c + Offset(0, r * 0.72),
            width: tp.width + 6,
            height: tp.height + 1,
          ),
          const Radius.circular(3),
        );
        canvas.drawRRect(tag, Paint()..color = HudColors.plateDark);
        tp.paint(canvas, Offset(tag.left + 3, tag.top + 0.5));
      }
      if (!named && outer) continue;
      // The loaded slot names its weapon for a moment after a switch, on the
      // screen-centre side (past FIRE when the slot sits beside it).
      final tp = named
          ? _toast.layout(TextSpan(
              text: [s.name.toUpperCase(), if (s.count != null) s.count].join(' '),
              style: hudFont(11, HudColors.gold.withValues(alpha: toast), spacing: 1),
            ))
          : _counts[i].layout(TextSpan(
              text: s.count ?? '',
              style: hudFont(
                10,
                Colors.white.withValues(alpha: on ? 0.95 : 0.6),
                spacing: 0.5,
              ),
            ));
      final besideFire =
          outer && (c.dy - layout.fire.dy).abs() < HudButtonLayout.fireRadius + tp.height / 2;
      final edge = besideFire
          ? layout.fire.dx + side * HudButtonLayout.fireRadius
          : c.dx + side * r;
      final x = side < 0 ? edge - 5 - tp.width : edge + 5;
      tp.paint(canvas, Offset(x, c.dy - tp.height / 2));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fuel gauge bar (rendered in HUD layer over game world)
// ─────────────────────────────────────────────────────────────────────────────
