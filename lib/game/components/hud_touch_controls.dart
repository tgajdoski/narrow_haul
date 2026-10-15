import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/camera/camera_director.dart';
import 'package:narrow_haul/game/components/hud_button_layout.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';
import 'package:narrow_haul/game/components/hud_text.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

export 'package:narrow_haul/game/components/hud_button_layout.dart';

part 'hud_joystick.dart';
part 'hud_pads.dart';
part 'hud_weapon_rail.dart';

/// On-screen controls for landscape play.
///
/// Left 50% of screen → [_FloatingJoystick]: appears where the thumb lands.
/// Horizontal axis [-1..1] drives rotation.
///
/// Right side → [_ThrustButton]: large circular hold-button for engine thrust.
/// A ship with something to fire adds [_FireButton] above it (tap = one
/// shot, hold = auto-fire) and the [_WeaponRail] beside both.
class HudTouchControls extends PositionComponent {
  HudTouchControls({
    required this.onRotateAxis,
    this.onStick,
    required this.onThrust,
    this.onFire,
    this.onSelectWeapon,
    this.onTiltTap,
  }) : super(priority: 5000);

  /// A tap on the steering side while tilting: recentre.
  final void Function()? onTiltTap;

  final void Function(double axis) onRotateAxis;

  /// The stick as a direction (x, y in −1…1, screen axes) for point-to-steer.
  final void Function(double x, double y)? onStick;
  final void Function(bool pressed) onThrust;
  final void Function(bool pressed)? onFire;

  /// Tap on an ammo rail slot: pick that weapon.
  final void Function(String id)? onSelectWeapon;

  /// What's on board and which one FIRE fires; null = nothing to fire.
  WeaponHud? get weapon => _weapon;
  WeaponHud? _weapon;
  set weapon(WeaponHud? v) {
    final before = _weapon?.selected.id;
    final after = v?.selected.id;
    // A switch (rail, key, crate) names the new weapon; a level's first
    // sync doesn't.
    if (v == null) {
      _toastLeft = 0;
    } else if (before != null && after != before) {
      _toastLeft = toastSeconds;
    }
    _weapon = v;
  }

  /// How long the full name of a newly picked weapon shows on the rail.
  static const double toastSeconds = 1.2;
  double _toastLeft = 0;

  /// 0–1 opacity of that name (fades over the last 0.3 s).
  double get toastAlpha => (_toastLeft / 0.3).clamp(0.0, 1.0);

  @override
  void update(double dt) {
    super.update(dt);
    if (_toastLeft > 0) _toastLeft = math.max(0, _toastLeft - dt);
  }

  /// Show the FIRE button (only for armed ships).
  bool get showFire => _showFire;
  bool _showFire = false;
  set showFire(bool v) {
    if (v == _showFire) return;
    _showFire = v;
    _relayout(size);
  }

  /// Mirror the layout: thrust bottom-left, joystick on the right half.
  bool get leftHanded => _leftHanded;
  bool _leftHanded = false;
  set leftHanded(bool v) {
    if (v == _leftHanded) return;
    _leftHanded = v;
    _relayout(size);
  }

  /// Safe-area insets: buttons and the joystick hint stay clear of them.
  EdgeInsets get insets => _insets;
  EdgeInsets _insets = EdgeInsets.zero;
  set insets(EdgeInsets v) {
    if (v == _insets) return;
    _insets = v;
    _relayout(size);
  }

  /// Where the controls sit right now; null before the first layout.
  HudButtonLayout? get layout => _layout;
  HudButtonLayout? _layout;

  /// The ammo rail is on screen.
  bool get railShown => _rail != null && (weapon?.showRail ?? false);

  /// Rail slots spilled to the screen-centre side of THRUST/FIRE (small
  /// phones with a full rack): the comms line and safe frame make room.
  bool get railInner =>
      railShown && (_layout?.railInnerCount(weapon!.slots.length) ?? 0) > 0;

  /// Screen areas the ship shouldn't sit under: the steering dial (where it
  /// rests, and where it floats while held) and the THRUST / FIRE / rail
  /// cluster. The camera nudges the view so the ship stays clear of them.
  List<ScreenZone> get controlZones {
    final l = _layout;
    if (l == null) return const [];
    const pad = 12.0;
    ScreenZone around(Offset c, double r) =>
        (l: c.dx - r - pad, t: c.dy - r - pad, r: c.dx + r + pad, b: c.dy + r + pad);
    const dialR = HudButtonLayout.dialRadius;
    // Tilt steering hides the stick: nothing to keep the ship clear of.
    final zones = <ScreenZone>[if (!FlightTuning.tilt) around(l.dialRest, dialR)];
    final held = _joystick?.heldCenter;
    if (held != null) {
      zones.add(around(Offset(held.x + _joystick!.position.x, held.y), dialR));
    }
    zones.add(padsZone!);
    return zones;
  }

  /// The THRUST / FIRE / rail cluster, with a margin (a pinch never starts
  /// there).
  ScreenZone? get padsZone {
    final l = _layout;
    if (l == null) return null;
    const pad = 12.0;
    const thrustR = HudButtonLayout.thrustRadius;
    var top = l.thrust.dy - thrustR;
    if (_showFire) top = math.min(top, l.fire.dy - HudButtonLayout.fireRadius);
    final rail = railShown ? l.railCenters(weapon!.slots.length) : const <Offset>[];
    if (rail.isNotEmpty) top = math.min(top, rail.first.dy - HudButtonLayout.slotRadius);
    final inner = l.thrust.dx + l.innerSide * HudButtonLayout.innerReach(rail: railInner);
    final outer = l.thrust.dx - l.innerSide * thrustR;
    return (
      l: math.min(inner, outer) - pad,
      t: top - pad,
      r: math.max(inner, outer) + pad,
      b: l.thrust.dy + thrustR + pad,
    );
  }

  _FloatingJoystick? _joystick;
  _ThrustButton? _thrustBtn;
  _FireButton? _fireBtn;
  _WeaponRail? _rail;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    anchor = Anchor.topLeft;
    position = Vector2.zero();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
    _relayout(size);
  }

  void _relayout(Vector2 sz) {
    if (sz.x <= 0 || sz.y <= 0) return;

    _joystick?.removeFromParent();
    _thrustBtn?.removeFromParent();
    if (_fireBtn?.pressed == true) onFire?.call(false);
    _fireBtn?.removeFromParent();
    _fireBtn = null;
    _rail?.removeFromParent();
    _rail = null;

    final layout = _layout = HudButtonLayout(
      Size(sz.x, sz.y),
      insets: _insets,
      leftHanded: _leftHanded,
    );
    final joyLeft = _leftHanded ? sz.x * 0.5 : 0.0;
    _joystick = _FloatingJoystick(
      areaSize: Vector2(sz.x * 0.5, sz.y),
      position: Vector2(joyLeft, 0),
      onAxisChanged: onRotateAxis,
      onStick: onStick,
      restCenter: layout.dialRest - Offset(joyLeft, 0),
      onTap: onTiltTap,
    );
    _thrustBtn = _ThrustButton(
      center: Vector2(layout.thrust.dx, layout.thrust.dy),
      radius: HudButtonLayout.thrustRadius,
      onChanged: onThrust,
    );

    add(_joystick!);
    add(_thrustBtn!);

    if (_showFire && onFire != null) {
      _fireBtn = _FireButton(
        center: Vector2(layout.fire.dx, layout.fire.dy),
        radius: HudButtonLayout.fireRadius,
        onChanged: onFire!,
        weapon: () => weapon,
        innerSide: layout.innerSide,
      );
      add(_fireBtn!);
      _rail = _WeaponRail(
        layout: layout,
        weapon: () => weapon,
        toastAlpha: () => toastAlpha,
        onSelect: (id) => onSelectWeapon?.call(id),
      )..size = sz;
      add(_rail!);
    }
  }
}
