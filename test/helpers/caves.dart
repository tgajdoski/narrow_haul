// Shared cave-level fixtures for the tests.
import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// Every cave level, in play order.
final List<CaveLevelDef> allCaveDefs =
    LevelRegistry.flat.whereType<CaveLevelDef>().toList(growable: false);

/// The ship [def] is actually flown with.
ShipSpec shipOfCave(CaveLevelDef def) =>
    LevelRegistry.shipFor(LevelRegistry.flat.indexOf(def));

/// Builds every cave on background isolates at once, so the first test of a
/// cave-heavy file doesn't build ~50 caves one after another (each test
/// file runs in its own isolate with an empty cache). Use in `setUpAll`.
Future<void> prebuildAllCaves() =>
    Future.wait([for (final d in allCaveDefs) prebuildCave(d.spec)]);
