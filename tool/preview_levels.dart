// Authoring aid: `dart run tool/preview_levels.dart [level_id ...]`
// Prints an ASCII rendering + validation issues for cave levels without
// launching the game. No args = validate everything, print only failures.
// ignore_for_file: avoid_print
import 'package:narrow_haul/game/level/cave/level_validator.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/specs/world_alien.dart';
import 'package:narrow_haul/game/level/specs/world_ice.dart';
import 'package:narrow_haul/game/level/specs/world_lava.dart';
import 'package:narrow_haul/game/level/specs/world_mine.dart';
import 'package:narrow_haul/game/level/specs/world_orbit.dart';
import 'package:narrow_haul/game/level/specs/world_redoubt.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main(List<String> args) {
  final all = <(CaveLevelDef, String)>[
    for (final (levels, shipId) in [
      (alienLevels, alienShipId),
      (mineLevels, mineShipId),
      (iceLevels, iceShipId),
      (lavaLevels, lavaShipId),
      (orbitLevels, orbitShipId),
      (redoubtLevels, redoubtShipId),
    ])
      for (final def in levels.whereType<CaveLevelDef>()) (def, def.shipId ?? shipId),
  ];

  var failures = 0;
  for (final (def, shipId) in all) {
    final spec = def.spec;
    final ship = shipById(shipId);
    final requested = args.isEmpty || args.contains(spec.id);
    if (!requested) continue;
    final issues = validateCaveSpec(spec, ship: ship);
    final flight = analyzeFlight(spec, ship: ship);
    // Heuristic star check (warning only): can a clean run keep enough fuel?
    final star3Budget = 1 - def.stars.star3Fuel;
    final starNote = flight != null && flight.fuelFraction > star3Budget
        ? '  ⚠ 3★ tight (needs ≤${(star3Budget * 100).round()}%)'
        : '';
    if (issues.isEmpty && args.isEmpty) {
      print('OK   ${spec.id.padRight(10)} ${ship.id.padRight(8)} $flight$starNote');
      continue;
    }
    failures += issues.isEmpty ? 0 : 1;
    print('== ${spec.id} — ${spec.name} ==');
    print('   ${ship.name}: $flight$starNote');
    for (final issue in issues) {
      print('   ! $issue');
    }
    if (args.isNotEmpty || issues.isNotEmpty) {
      print(asciiPreview(spec));
    }
    print('');
  }
  if (failures > 0) {
    print('$failures level(s) failed validation');
  }
}
