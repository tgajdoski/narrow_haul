import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/level_validator.dart';
import 'package:narrow_haul/game/level/gen/expedition_generator.dart';
import 'package:narrow_haul/game/level/gen/outlines.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// The authoring-time Expedition generator (tool/generate_expedition.dart).
void main() {
  const outline = ExpeditionOutline(
    id: 'gen_test',
    name: 'Generator Test',
    themeId: 'alien',
    seed: 42,
    shipId: 'hopper',
    legs: [
      [Room.squeeze, Room.zeroG],
      [Room.bar, Room.climb],
    ],
  );

  test('a layout passes every leg of the validator', () {
    final g = generateExpedition(outline, keep: 1)!;
    expect(g.spec.legs, hasLength(2));
    expect(validateCaveSpec(g.spec, ship: kHopper), isEmpty);
    expect(g.routeLength, greaterThan(50));
    expect(g.stars.star3Fuel, inInclusiveRange(0.35, 0.65));
  });

  test('deterministic: the same outline lays the same cave', () {
    final a = generateExpedition(outline, keep: 1)!;
    final b = generateExpedition(outline, keep: 1)!;
    expect(expeditionToDart(a), expeditionToDart(b));
  });

  test('the checked-in Expeditions match their outlines', () {
    final shipped = {
      for (final d in LevelRegistry.flat)
        if (d is CaveLevelDef && d.spec.isExpedition) d.saveId: d,
    };
    for (final o in kExpeditionOutlines) {
      final def = shipped[o.id];
      expect(def, isNotNull, reason: '${o.id}: run tool/generate_expedition.dart');
      expect(def!.spec.legs, hasLength(o.legs.length), reason: o.id);
      expect(def.spec.shipId, o.shipId, reason: o.id);
      expect(def.spec.name, o.name, reason: o.id);
    }
  });
}
