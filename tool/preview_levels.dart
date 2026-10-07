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
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main(List<String> args) {
  final all = <CaveLevelDef>[
    ...alienLevels.whereType<CaveLevelDef>(),
    ...mineLevels.whereType<CaveLevelDef>(),
    ...iceLevels.whereType<CaveLevelDef>(),
    ...lavaLevels.whereType<CaveLevelDef>(),
  ];

  var failures = 0;
  for (final def in all) {
    final spec = def.spec;
    final requested = args.isEmpty || args.contains(spec.id);
    if (!requested) continue;
    // Level override only — world default ships live in LevelRegistry,
    // which needs Flutter; `flutter test` validates the resolved ship.
    final issues = validateCaveSpec(spec, ship: shipById(spec.shipId));
    if (issues.isEmpty && args.isEmpty) {
      print('OK   ${spec.id}');
      continue;
    }
    failures += issues.isEmpty ? 0 : 1;
    print('== ${spec.id} — ${spec.name} ==');
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
