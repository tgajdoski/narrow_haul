// Level lookup by id for the tests.
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';

/// Flat index of the level whose save id (or cave spec id) is [id].
int levelIndexOf(String id) {
  final i = LevelRegistry.flat.indexWhere(
    (d) => d.saveId == id || (d is CaveLevelDef && d.spec.id == id),
  );
  if (i < 0) throw StateError('no level $id');
  return i;
}

/// Flat index of the first cave level matching [test].
int caveLevelWhere(bool Function(CaveLevelDef def) test) {
  final i = LevelRegistry.flat.indexWhere((d) => d is CaveLevelDef && test(d));
  if (i < 0) throw StateError('no such level');
  return i;
}
