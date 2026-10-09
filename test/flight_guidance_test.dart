import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/guidance_hud.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/guidance/flight_guidance.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

void main() {
  group('coach marks', () {
    const armed = GuidanceInputs(
      armed: true,
      combatLevel: true,
      fuelPerShotFrac: 0.6 / 115,
    );

    test('FIRE is coached on a defended level until the first shot', () {
      final g = resolveGuidance(armed);
      expect(g.coach?.target, CoachTarget.fire);
      expect(g.coach?.title, 'FIRE');
      expect(g.coach?.detail, 'Tap to knock out turrets');
      expect(g.coach?.cost, '0.5% fuel / shot');
      expect(g.coach?.keys, isEmpty);
      expect(g.markTurrets, isTrue, reason: 'the turrets get lock-on brackets');

      const fired = GuidanceInputs(armed: true, combatLevel: true, shotsFired: 1);
      expect(resolveGuidance(fired).coach, isNull);
      expect(resolveGuidance(fired).markTurrets, isFalse);
    });

    test('FIRE is not coached once the level has a star, or without turrets', () {
      expect(
        resolveGuidance(const GuidanceInputs(
          armed: true,
          combatLevel: true,
          levelStarred: true,
        )).coach,
        isNull,
      );
      expect(resolveGuidance(const GuidanceInputs(armed: true)).coach, isNull);
      expect(resolveGuidance(const GuidanceInputs(combatLevel: true)).coach, isNull);
    });

    test('the Talon\'s real shot cost is what the chip shows', () {
      final frac = kTalon.fuelPerShot / kTalon.maxFuel;
      final g = resolveGuidance(GuidanceInputs(
        armed: true,
        combatLevel: true,
        fuelPerShotFrac: frac,
      ));
      expect(g.coach?.cost, '${formatFuelPercent(frac)} fuel / shot');
    });

    test('desktop names the keys instead of tapping', () {
      final g = resolveGuidance(const GuidanceInputs(
        desktop: true,
        armed: true,
        combatLevel: true,
      ));
      expect(g.coach?.keys, ['F', 'ENTER']);
      expect(g.coach?.detail, isNot(contains('Tap')));
    });

    test('tutorial: thrust, then steering, then the pod', () {
      var g = resolveGuidance(const GuidanceInputs(tutorial: true));
      expect(g.coach?.target, CoachTarget.thrust);
      expect(g.coach?.confirmOnExit, isTrue);
      expect(g.pod, isNull, reason: 'controls first');

      g = resolveGuidance(const GuidanceInputs(tutorial: true, thrustUsed: 1));
      expect(g.coach?.target, CoachTarget.dial);
      expect(g.coach?.detail, 'Drag left or right to rotate');

      g = resolveGuidance(const GuidanceInputs(
        tutorial: true,
        thrustUsed: 1,
        pointSteer: true,
      ));
      expect(g.coach?.detail, contains('nose'));

      g = resolveGuidance(const GuidanceInputs(tutorial: true, thrustUsed: 1, rotateUsed: 1));
      expect(g.coach, isNull);
      expect(g.pod, PodTag.hook);

      g = resolveGuidance(const GuidanceInputs(
        tutorial: true,
        thrustUsed: 1,
        rotateUsed: 1,
        attached: true,
      ));
      expect(g.pod, isNull);
      expect(g.pad, const PadTag(shipIn: false, podIn: false));
    });

    test('tut_02 on the pad: the star rules, no control coaching', () {
      final g = resolveGuidance(const GuidanceInputs(tutorial: true, starRulesStep: true));
      expect(g.coach, isNull);
      expect(g.frameStarTarget, isTrue);
    });

    test('a crate is coached on FIRE ahead of everything, and just times out', () {
      const crate = CrateNotice(
        kind: WeaponKind.seeker,
        name: 'Seeker Missile',
        label: 'SEEKER',
        amount: '×3',
      );
      final g = resolveGuidance(const GuidanceInputs(
        tutorial: true,
        armed: true,
        combatLevel: true,
        crate: crate,
      ));
      expect(g.coach?.target, CoachTarget.fire);
      expect(g.coach?.title, 'SEEKER MISSILE ×3');
      expect(g.coach?.detail, 'Loaded. Tap SEEKER to fire');
      expect(g.coach?.glyph, WeaponKind.seeker);
      expect(g.coach?.confirmOnExit, isFalse);
    });

    test('a demo shows nothing', () {
      final g = resolveGuidance(const GuidanceInputs(
        demo: true,
        armed: true,
        combatLevel: true,
        shipOnPad: true,
        canisterUnseen: true,
      ));
      expect(g.coach, isNull);
      expect(g.pad, isNull);
      expect(g.markCanister, isFalse);
    });
  });

  group('landing slots', () {
    test('match which of ship and pod are on the pad', () {
      var g = resolveGuidance(const GuidanceInputs(shipOnPad: true));
      expect(g.pad, const PadTag(shipIn: true, podIn: false));
      expect(g.pod, PodTag.lower, reason: 'the pod is what is missing');

      g = resolveGuidance(const GuidanceInputs(podOnPad: true));
      expect(g.pad, const PadTag(shipIn: false, podIn: true));
      expect(g.pod, isNull);

      // Both down (the delivery) or neither: no beacon outside the tutorial.
      expect(resolveGuidance(const GuidanceInputs(shipOnPad: true, podOnPad: true)).pad, isNull);
      expect(resolveGuidance(const GuidanceInputs()).pad, isNull);
    });
  });

  test('fuel percent reads well', () {
    expect(formatFuelPercent(0.6 / 115), '0.5%');
    expect(formatFuelPercent(0.034), '3%');
    expect(formatFuelPercent(0), '0%');
  });

  group('CommsQueue', () {
    const a = CommsLine(id: 'a', callsign: 'OPS', text: 'First line here.');
    const b = CommsLine(id: 'b', callsign: 'TOWER', text: 'Second.');

    test('one line at a time, each id once per flight', () {
      final q = CommsQueue();
      expect(q.say(a), isTrue);
      expect(q.say(a), isFalse);
      q.say(b);
      expect(q.update(0.01), isTrue);
      expect(q.current?.id, 'a');
      // Holds for its reading time, then the next one goes on air.
      final hold = CommsQueue.holdSeconds(a) + CommsQueue.fadeOut;
      var t = 0.0;
      while (q.current?.id == 'a' && t < 30) {
        q.update(0.05);
        t += 0.05;
      }
      expect(t, closeTo(hold, 0.1));
      expect(q.current?.id, 'b');

      q.clear();
      expect(q.current, isNull);
      expect(q.say(a), isTrue, reason: 'a new flight can say it again');
    });

    test('types on and waits for its delay; urgent jumps the queue', () {
      final q = CommsQueue();
      q.say(a, delay: 1);
      q.update(0.5);
      expect(q.current, isNull);
      q.say(b, urgent: true);
      q.update(0.01);
      expect(q.current?.id, 'b');
      expect(q.visibleChars, lessThan(b.text.length));
      q.update(1);
      expect(q.visibleChars, b.text.length);
      expect(q.alpha, 1);
    });
  });

  group('HUD anchors', () {
    const phones = [Size(844, 390), Size(667, 375), Size(568, 320), Size(932, 430)];

    test('the dial rests where it always did', () {
      final l = HudButtonLayout(const Size(844, 390));
      expect(l.dialRest.dx, closeTo(422 * 0.22, 1e-9));
      expect(l.dialRest.dy, 390 - 68 - 16);
      final lh = HudButtonLayout(const Size(844, 390), leftHanded: true);
      expect(lh.dialRest.dx, closeTo(422 + 422 * 0.78, 1e-9));
      // Clear of the notch.
      final notch = HudButtonLayout(
        const Size(844, 390),
        insets: const EdgeInsets.only(left: 47, right: 47, bottom: 21),
      );
      expect(notch.dialRest.dx - HudButtonLayout.dialRadius, greaterThanOrEqualTo(47));
    });

    test('the comms band sits between the dial and THRUST on every phone', () {
      for (final size in phones) {
        for (final left in [false, true]) {
          final l = HudButtonLayout(size, leftHanded: left);
          final band = l.bottomBand(rail: false);
          expect(band.width, greaterThanOrEqualTo(220), reason: '$size left=$left');
          final dial = l.dialRest;
          final dialSpan = (dial.dx - HudButtonLayout.dialRadius, dial.dx + HudButtonLayout.dialRadius);
          expect(band.left >= dialSpan.$2 || band.right <= dialSpan.$1, isTrue,
              reason: 'band clear of the dial ($size left=$left)');
          final t = l.thrust.dx;
          expect(
            band.right <= t - HudButtonLayout.thrustRadius ||
                band.left >= t + HudButtonLayout.thrustRadius,
            isTrue,
            reason: 'band clear of THRUST ($size left=$left)',
          );
          // With the rail up the band only shrinks, and stays clear of it.
          final railBand = l.bottomBand(rail: true);
          expect(railBand.width, lessThan(band.width));
          final railX = l.railCenters(3).first.dx;
          expect(
            railBand.right <= railX - HudButtonLayout.slotRadius ||
                railBand.left >= railX + HudButtonLayout.slotRadius,
            isTrue,
          );
        }
      }
    });
  });

  group('placeAvoiding', () {
    const ship = Rect.fromLTWH(400, 180, 40, 40);
    const beside = Rect.fromLTWH(380, 170, 200, 50);
    const high = Rect.fromLTWH(380, 110, 200, 50);

    test('takes the first candidate clear of the ship', () {
      final (r, clear) = placeAvoiding([beside, high], [ship]);
      expect(r, high);
      expect(clear, isTrue);
    });

    test('keeps the first when nothing is in the way', () {
      expect(placeAvoiding([beside, high], const []), (beside, true));
    });

    test('falls back to the first, not clear, when all cover the ship', () {
      expect(placeAvoiding([beside], [ship]), (beside, false));
    });
  });
}
