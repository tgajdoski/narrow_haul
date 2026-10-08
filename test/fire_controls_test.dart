
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/keyboard_input.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

void main() {
  group('WeaponRack.select', () {
    test('picks a weapon on board, ignores the rest', () {
      final rack = WeaponRack(hasCannon: true, carried: {kGravityBomb.id: 2});
      expect(rack.selectedId, kCannon.id);
      expect(rack.select(kGravityBomb.id), isTrue);
      expect(rack.selectedId, kGravityBomb.id);
      expect(rack.select(kFlak.id), isFalse, reason: 'no flak on board');
      expect(rack.select('nonsense'), isFalse);
      expect(rack.selectedId, kGravityBomb.id);
    });

    test('an emptied weapon drops off the rail', () {
      final rack = WeaponRack(hasCannon: true, carried: {kDemoCharge.id: 1});
      rack.select(kDemoCharge.id);
      rack.spend(kDemoCharge.id, 1);
      expect(rack.select(kDemoCharge.id), isFalse);
      expect(rack.selectedId, kCannon.id);
    });
  });

  group('WeaponRack.costsStar', () {
    test('found ammo first; the star badge shows only on carried ammo', () {
      final rack = WeaponRack(carried: {kGravityBomb.id: 2});
      rack.addFound(kGravityBomb.id, 1);
      expect(rack.costsStar(kGravityBomb.id), isFalse, reason: 'a found bomb goes first');
      rack.spend(kGravityBomb.id, 1);
      expect(rack.costsStar(kGravityBomb.id), isTrue);
      rack.spend(kGravityBomb.id, 1);
      expect(rack.usedCarried, isTrue);
      expect(rack.costsStar(kGravityBomb.id), isFalse, reason: 'the star is already gone');
    });

    test('nothing on board costs nothing', () {
      final rack = WeaponRack(hasCannon: true);
      expect(rack.costsStar(kCannon.id), isFalse);
      expect(rack.costsStar(kFlak.id), isFalse);
    });
  });

  test('number keys pick rail slots and count as flight keys', () {
    expect(KeyboardFlightInput.slotKeys, hasLength(6));
    expect(KeyboardFlightInput.slotKeys.first, LogicalKeyboardKey.digit1);
    for (final k in KeyboardFlightInput.slotKeys) {
      expect(KeyboardFlightInput.isFlightKey(k), isTrue);
    }
  });

  group('WeaponHud', () {
    WeaponSlot slot(WeaponKind kind, {String? count}) =>
        WeaponSlot(id: kind.name, kind: kind, label: 'X', name: 'X', count: count);

    test('the rail shows only when there is a choice', () {
      expect(WeaponHud(slots: [slot(WeaponKind.cannon)], selectedIndex: 0).showRail, isFalse);
      expect(
        WeaponHud(slots: [slot(WeaponKind.bomb, count: '×2')], selectedIndex: 0).showRail,
        isFalse,
        reason: 'the FIRE pad shows a lone weapon and its ammo',
      );
      expect(
        WeaponHud(
          slots: [slot(WeaponKind.cannon), slot(WeaponKind.flak, count: '×4')],
          selectedIndex: 1,
        ).showRail,
        isTrue,
      );
    });
  });

  group('ammo rail layout', () {
    const screens = [Size(568, 320), Size(667, 375), Size(844, 390), Size(1194, 834)];
    const notch = EdgeInsets.only(left: 47, right: 47, bottom: 21);
    const r = HudButtonLayout.slotRadius;

    for (final screen in screens) {
      for (final insets in [EdgeInsets.zero, notch]) {
        for (final left in [false, true]) {
          test('${screen.width.toInt()}×${screen.height.toInt()} '
              '${insets == EdgeInsets.zero ? 'flat' : 'notch'} '
              '${left ? 'left' : 'right'}-handed', () {
            final l = HudButtonLayout(screen, insets: insets, leftHanded: left);
            // Top-right minimap (≤ 150×90 at a 12 px margin) and top-left
            // fuel gauge (220×26 at 12, 8).
            final minimap = Rect.fromLTWH(
              screen.width - insets.right - 12 - 150,
              insets.top + 12,
              150,
              90,
            );
            final gauge = Rect.fromLTWH(insets.left + 12, insets.top + 8, 220, 26);
            for (var n = 1; n <= 6; n++) {
              final cs = l.railCenters(n);
              expect(cs, hasLength(n));
              for (var i = 0; i < n; i++) {
                final box = Rect.fromCircle(center: cs[i], radius: r);
                final why = 'n=$n slot $i at ${cs[i]}';
                expect(box.left >= insets.left && box.right <= screen.width - insets.right,
                    isTrue, reason: why);
                expect(box.top >= insets.top && box.bottom <= screen.height - insets.bottom,
                    isTrue, reason: why);
                expect(box.overlaps(minimap), isFalse, reason: '$why vs minimap');
                expect(box.overlaps(gauge), isFalse, reason: '$why vs fuel gauge');
                expect((cs[i] - l.thrust).distance,
                    greaterThan(HudButtonLayout.thrustRadius + r), reason: '$why vs thrust');
                expect((cs[i] - l.fire).distance,
                    greaterThan(HudButtonLayout.fireRadius + r), reason: '$why vs fire');
                if (i > 0) {
                  expect(cs[i].dy - cs[i - 1].dy, greaterThanOrEqualTo(2 * r), reason: why);
                }
                // On the screen-centre side, in the thumb's half.
                expect(left ? cs[i].dx > l.thrust.dx : cs[i].dx < l.thrust.dx, isTrue);
                expect(
                  left ? cs[i].dx < screen.width / 2 : cs[i].dx > screen.width / 2,
                  isTrue,
                  reason: '$why must stay out of the joystick half',
                );
              }
            }
          });
        }
      }
    }

    test('a short rail centres on FIRE', () {
      final l = HudButtonLayout(const Size(844, 390));
      final cs = l.railCenters(2);
      expect((cs[0].dy + cs[1].dy) / 2, closeTo(l.fire.dy, 0.01));
    });
  });
}
