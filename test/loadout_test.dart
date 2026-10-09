import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/cargo_attachment.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/physics_core.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/ship/loadout.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main() {
  test('stock cable is the original tow', () {
    expect(kStockRope.kind, TowKind.rope);
    expect(kStockRope.isElastic, isFalse);
    expect(kStockRope.swingDamping, 0);
    expect(kStockRope.approachDistance, CargoAttachment.approachDistanceMeters);
    expect(kStockRope.hookReach, CargoAttachment.hookCatchExtraMeters);
    expect(kStockRope.attachCenterDistance, CargoAttachment.attachCenterDistanceMax);
  });

  test('stock hook catches from a hover, with air under the tail', () {
    for (final ship in kShips.values) {
      // Hovering straight above the pod: the winch hook reaches it while
      // the tail is still well clear of the pod's top.
      final catchRadius = ship.hookRadius + kCargoRadius + kStockRope.hookReach;
      final air = catchRadius - kCargoRadius;
      expect(air, greaterThanOrEqualTo(0.6), reason: ship.id);
      // ...and the hook really is under the tail, where the rope hangs.
      expect(ship.hookLocalY, ship.rearLocalY, reason: ship.id);
    }
    // The shortest tow keeps the pod clear of the hull.
    expect(kStockRope.minTowLength, greaterThan(kCargoRadius + 0.6));
  });

  test('every rope in the Garage has tow stats, and only those', () {
    final ropes = CosmeticsService.all.where((i) => i.category == CosmeticsService.catRope);
    expect({for (final r in ropes) r.id}, kRopes.keys.toSet());
    expect(ropeById('nope'), same(kStockRope));
  });

  test('tow gear stays inside sane bounds', () {
    for (final r in kRopes.values) {
      expect(r.hookReach, inInclusiveRange(kStockHookReach, 1.25), reason: r.id); // never below stock: pods on slopes roll away
      expect(r.approachDistance, greaterThanOrEqualTo(r.attachCenterDistance + 0.5), reason: r.id);
      expect(r.minTowLength, inInclusiveRange(0.8, 2.0), reason: r.id);
      if (r.isElastic && !r.isBeam) {
        expect(r.stiffnessHz, inInclusiveRange(0.8, 8), reason: r.id);
        expect(r.maxStretch, inInclusiveRange(0.1, 1.0), reason: r.id);
      }
      if (r.isBeam) {
        expect(r.beamRange, greaterThan(r.beamHoldLength), reason: r.id);
        expect(r.approachDistance, greaterThan(r.beamRange), reason: r.id);
        expect(r.beamFuelFracPerSec, inInclusiveRange(0.001, 0.01), reason: r.id);
      }
      final s = RopeStats.of(r);
      for (final v in [s.reach, s.give, s.steadiness, s.economy]) {
        expect(v, inInclusiveRange(0.0, 1.0), reason: r.id);
      }
    }
  });

  group('handling kits', () {
    ShipBody ship(KitSpec kit) => ShipBody(
      initialPosition: Vector2.zero(),
      onWallHit: () {},
      kit: kit,
    );

    test('the standard fit is exactly the ship', () {
      final b = ship(kStockKit);
      expect(b.turnRate, kKestrel.rotationSpeedRadPerSec);
      expect(b.maxFuel, kKestrel.maxFuel);
      expect(b.fuel, kKestrel.maxFuel);
      expect([kStockKit.dampingAdd, kStockKit.fuelDrainMul], [0, 1]);
    });

    test('every kit in the Garage has stats, and only those', () {
      final kits = CosmeticsService.all.where((i) => i.category == CosmeticsService.catKit);
      expect({for (final k in kits) k.id}, kKits.keys.toSet());
      expect(kitById('nope'), same(kStockKit));
      expect(kKits['kit_none'], same(kStockKit)); // the Garage default
    });

    test('every kit is a sidegrade: it pays in fuel or tank', () {
      for (final k in kKits.values.where((k) => k != kStockKit)) {
        expect(k.fuelDrainMul > 1 || k.tankMul < 1, isTrue, reason: k.id);
      }
    });

    test('verniers turn faster and shrink the tank', () {
      final b = ship(kKits['kit_verniers']!);
      expect(b.turnRate, closeTo(kKestrel.rotationSpeedRadPerSec * 1.25, 1e-9));
      expect(b.maxFuel, closeTo(kKestrel.maxFuel * 0.9, 1e-9));
      expect(b.fuel, b.maxFuel);
    });
  });
}
