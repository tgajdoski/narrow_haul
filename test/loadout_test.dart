import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/cargo_attachment.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/ship/loadout.dart';

void main() {
  test('stock cable is the original tow', () {
    expect(kStockRope.kind, TowKind.rope);
    expect(kStockRope.isElastic, isFalse);
    expect(kStockRope.swingDamping, 0);
    expect(kStockRope.approachDistance, CargoAttachment.approachDistanceMeters);
    expect(kStockRope.hookReach, CargoAttachment.hookCatchExtraMeters);
    expect(kStockRope.attachCenterDistance, CargoAttachment.attachCenterDistanceMax);
  });

  test('every rope in the Garage has tow stats, and only those', () {
    final ropes = CosmeticsService.all.where((i) => i.category == CosmeticsService.catRope);
    expect({for (final r in ropes) r.id}, kRopes.keys.toSet());
    expect(ropeById('nope'), same(kStockRope));
  });

  test('tow gear stays inside sane bounds', () {
    for (final r in kRopes.values) {
      expect(r.hookReach, inInclusiveRange(0.35, 1.0), reason: r.id); // never below stock: pods on slopes roll away
      expect(r.approachDistance, greaterThanOrEqualTo(r.attachCenterDistance), reason: r.id);
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
}
