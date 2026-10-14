import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

/// One weapon on board, as the FIRE pad and the ammo rail show it.
class WeaponSlot {
  const WeaponSlot({
    required this.id,
    required this.kind,
    required this.label,
    required this.name,
    this.count,
    this.ammo = 0,
    this.peak = 0,
    this.costsStar = false,
  });

  final String id;
  final WeaponKind kind;

  /// Short label under the FIRE icon ('BOMB'), and the full name the rail
  /// shows for a moment after a switch ('Gravity Bomb').
  final String label;
  final String name;

  /// '×3' / '8s'; null for the cannon (it costs fuel, not ammo).
  final String? count;

  /// Units left and the most held this flight: the FIRE pad's ammo ring.
  final double ammo;
  final double peak;

  /// The next shot would spend the player's own stock and cap the run at 2★.
  final bool costsStar;

  bool get continuous => kind == WeaponKind.laser;
}

/// Everything the weapon HUD shows: the slots in rail order and the one
/// FIRE fires.
class WeaponHud {
  const WeaponHud({required this.slots, required this.selectedIndex});

  final List<WeaponSlot> slots;
  final int selectedIndex;

  WeaponSlot get selected => slots[selectedIndex];

  /// The rail shows only when there's a choice; a lone weapon's icon and
  /// ammo are on the FIRE pad already.
  bool get showRail => slots.length > 1;
}

/// Where THRUST, FIRE and the ammo rail sit, in screen pixels. Pure
/// geometry, shared by the HUD and its layout test.
class HudButtonLayout {
  HudButtonLayout(this.screen, {this.insets = EdgeInsets.zero, this.leftHanded = false}) {
    final x = leftHanded
        ? insets.left + margin + thrustRadius
        : screen.width - insets.right - margin - thrustRadius;
    final y = screen.height - insets.bottom - margin - thrustRadius;
    thrust = Offset(x, y);
    // Directly above thrust: the same thumb rocks between the two.
    fire = Offset(x, y - thrustRadius - 18 - fireRadius);
  }

  static const double thrustRadius = 52;
  static const double fireRadius = 40;
  static const double margin = 28;

  /// Rail slot hexagon radius and centre-to-centre spacing.
  static const double slotRadius = 15;
  static const double slotSpacing = 35;

  /// The top-right minimap (12 px margin, at most 90 px tall) and the
  /// top-left fuel gauge end above this line; the rail stays below it.
  static const double topClear = 106;

  final Size screen;
  final EdgeInsets insets;
  final bool leftHanded;
  late final Offset thrust;
  late final Offset fire;

  /// Toward the screen centre: −1 for a right-hand layout.
  double get innerSide => leftHanded ? 1 : -1;

  /// Outer radius of the steering dial.
  static const double dialRadius = 68;

  /// Where the steering dial rests (it floats to the thumb while dragged):
  /// 22% into its half of the screen, clear of the safe-area edge.
  Offset get dialRest {
    final half = screen.width / 2;
    const edge = dialRadius + 12;
    // The dial covers one half: only that half's outer edge is inset.
    final inL = leftHanded ? 0.0 : insets.left;
    final inR = leftHanded ? insets.right : 0.0;
    final local = (half * (leftHanded ? 0.78 : 0.22))
        .clamp(inL + edge, math.max(inL + edge, half - inR - edge))
        .toDouble();
    return Offset(
      (leftHanded ? half : 0) + local,
      screen.height - insets.bottom - dialRadius - 16,
    );
  }

  /// How far past THRUST's centre the inner-side controls reach: the pad,
  /// plus rail slots that spilled to the inner side ([railInnerCount]).
  static double innerReach({required bool rail}) =>
      thrustRadius + 14 + (rail ? slotRadius * 2 + 44 : 0);

  /// The free strip along the bottom between the steering dial and THRUST
  /// (or a spilled rail): where the comms line goes.
  Rect bottomBand({required bool rail}) {
    final dialEdge = dialRest.dx - innerSide * (dialRadius + 14);
    final thrustEdge = thrust.dx + innerSide * innerReach(rail: rail);
    return Rect.fromLTRB(
      math.min(dialEdge, thrustEdge),
      0,
      math.max(dialEdge, thrustEdge),
      screen.height - insets.bottom - 12,
    );
  }

  /// Bottom of the mystery-salvage badge under the top-left fuel gauge
  /// (`SalvageHud.origin` + `plateSize`, + 4 px): a left-handed rail at the
  /// screen edge starts below it.
  static const double salvageClear = 152;

  /// Where the rail may start: below the minimap (right-handed), or below
  /// the salvage badge for a left-handed rail on the gauge's side.
  double get _topLimit => leftHanded ? salvageClear : topClear;

  /// Gap between FIRE and the outer rail column.
  static const double _outerGap = 6;

  /// Outer rail column: beside FIRE on the screen-edge side, out of the
  /// pilot's view of the cave.
  double get _outerX => fire.dx - innerSide * (fireRadius + _outerGap + slotRadius);

  /// The outer column's free height: below the minimap (right-handed) or
  /// the salvage badge (left-handed), above THRUST.
  (double, double) get _outerRange {
    final dx = (_outerX - thrust.dx).abs();
    final clear = thrustRadius + slotRadius + 4;
    final minY = insets.top + _topLimit + slotRadius;
    final maxY = thrust.dy - math.sqrt(math.max(0, clear * clear - dx * dx));
    return (minY, maxY);
  }

  /// How many of [n] slots fit in the outer column (at least 2·[slotRadius]
  /// apart). The rest spill to an inner column (small phones, full racks).
  int railOuterCount(int n) {
    final (minY, maxY) = _outerRange;
    if (maxY < minY) return 0;
    final fit = ((maxY - minY) / (slotRadius * 2)).floor() + 1;
    return math.min(n, fit);
  }

  /// Rail slots on the screen-centre side of THRUST/FIRE.
  int railInnerCount(int n) => n - railOuterCount(n);

  /// Centres of [n] rail slots, top to bottom: a column on the screen-edge
  /// side of FIRE, centred on FIRE where it fits, squeezed (never tighter
  /// than the slots) when it doesn't. Slots that still don't fit continue
  /// in columns on the screen-centre side.
  List<Offset> railCenters(int n) {
    if (n <= 0) return const [];
    final outer = railOuterCount(n);
    final (oMin, oMax) = _outerRange;
    final out = _column(outer, _outerX, oMin, oMax);
    // Spill columns, each one further in (room for the counts between).
    final minY = insets.top + _topLimit + slotRadius;
    final maxY = screen.height - insets.bottom - 6 - slotRadius;
    final cap = ((maxY - minY) / (slotRadius * 2)).floor() + 1;
    var x = thrust.dx + innerSide * (thrustRadius + 14 + slotRadius);
    for (var left = n - outer; left > 0; left -= cap) {
      out.addAll(_column(math.min(left, cap), x, minY, maxY));
      x += innerSide * (slotRadius * 2 + 34);
    }
    return out;
  }

  /// Whether a rail slot at [c] is in the outer column.
  bool isOuterSlot(Offset c) => (c.dx - fire.dx) * innerSide < 0;

  List<Offset> _column(int n, double x, double minY, double maxY) {
    if (n <= 0) return [];
    final room = math.max(0.0, maxY - minY);
    final step = n == 1
        ? 0.0
        : math.max(slotRadius * 2, math.min(slotSpacing, room / (n - 1)));
    final span = step * (n - 1);
    final top = (fire.dy - span / 2).clamp(minY, math.max(minY, maxY - span));
    return [for (var i = 0; i < n; i++) Offset(x, top + i * step)];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating Joystick
// ─────────────────────────────────────────────────────────────────────────────
