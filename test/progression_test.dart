// The star rule and the unlock gates: what a delivery is worth and which
// missions a save may fly.
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

import 'helpers/pump.dart';

/// A save with [stars] on each listed level.
Future<void> _save(Map<String, int> stars) =>
    freshSave({for (final e in stars.entries) 'stars2_${e.key}': e.value});

/// [n] three-star levels from the tutorial, as save entries.
Map<String, int> _tutorialStars(int levels) =>
    {for (final d in LevelRegistry.worlds.first.levels.take(levels)) d.saveId: 3};

void main() {
  group('StarSpec.rate', () {
    const s = StarSpec(star3Fuel: 0.7, star2Fuel: 0.4, star3Time: 60);

    test('the thresholds are inclusive', () {
      expect(s.rate(0.7, 60), 3);
      expect(s.rate(0.4, 61), 2);
      expect(s.rate(0.3999, 10), 1);
    });

    test('3★ needs both the fuel and the time', () {
      expect(s.rate(0.95, 60.01), 2, reason: 'too slow');
      expect(s.rate(0.69, 10), 2, reason: 'too thirsty');
    });

    test('a capped run is at most 2★, and still 1★ when thirsty', () {
      expect(s.rate(1.0, 5, capped: true), 2);
      expect(s.rate(0.1, 5, capped: true), 1);
    });

    test('a delivery is always worth a star', () {
      expect(s.rate(0, 999), 1);
    });
  });

  group('unlock gates', () {
    final worlds = LevelRegistry.worlds;
    int flatIndexOf(String saveId) =>
        LevelRegistry.flat.indexWhere((d) => d.saveId == saveId);

    test('a fresh save: only the first world and its first mission', () async {
      await _save({});
      expect(LevelRegistry.isWorldUnlocked(worlds[0]), isTrue);
      expect(LevelRegistry.isWorldUnlocked(worlds[1]), isFalse);
      expect(LevelRegistry.isLevelUnlocked(0), isTrue);
      expect(LevelRegistry.isLevelUnlocked(1), isFalse);
      expect(LevelRegistry.nextLevelIndex(), 0);
    });

    test('completing a level opens the next, and LAUNCH flies it', () async {
      await _save({LevelRegistry.flat[0].saveId: 1});
      expect(LevelRegistry.isLevelUnlocked(1), isTrue);
      expect(LevelRegistry.isLevelUnlocked(2), isFalse);
      expect(LevelRegistry.nextLevelIndex(), 1);
    });

    test('worlds open on total stars, exactly at the gate', () async {
      final gate = worlds[1].starsRequired;
      final full = gate ~/ 3;
      final stars = _tutorialStars(full);
      if (gate % 3 != 0) {
        stars[LevelRegistry.worlds.first.levels[full].saveId] = gate % 3;
      }
      await _save(stars);
      expect(LevelRegistry.totalStars(), gate);
      expect(LevelRegistry.isWorldUnlocked(worlds[1]), isTrue);
      final first = flatIndexOf(worlds[1].levels.first.saveId);
      expect(LevelRegistry.isLevelUnlocked(first), isTrue);
      expect(LevelRegistry.isLevelUnlocked(first + 1), isFalse);

      // One star short: closed again, even its first level.
      final short = Map.of(stars)..update(stars.keys.first, (v) => v - 1);
      await _save(short);
      expect(LevelRegistry.isWorldUnlocked(worlds[1]), isFalse);
      expect(LevelRegistry.isLevelUnlocked(first), isFalse);
    });

    test('a level already flown stays open when one is inserted before it',
        () async {
      // The second mission of world 2 has stars, its predecessor (say, a new
      // type-rating level) has none.
      final w = worlds[1];
      await _save({..._tutorialStars(10), w.levels[1].saveId: 2});
      expect(LevelRegistry.isLevelUnlocked(flatIndexOf(w.levels[1].saveId)), isTrue);
      expect(LevelRegistry.isLevelUnlocked(flatIndexOf(w.levels[2].saveId)), isTrue,
          reason: 'the one after a flown level opens too');
    });

    test('star gates rise world by world', () {
      for (var k = 1; k < worlds.length; k++) {
        expect(worlds[k].starsRequired, greaterThan(worlds[k - 1].starsRequired),
            reason: worlds[k].id);
      }
      expect(worlds.first.starsRequired, 0);
    });

    test('type ratings: Kestrel by the training finale, others by their rating level',
        () async {
      await _save({});
      expect(LevelRegistry.hasTypeRating(kKestrel.id), isFalse);
      expect(LevelRegistry.hasTypeRating(kMule.id), isFalse);
      await _save({LevelRegistry.trainingFinale.saveId: 1, 'rating_mule': 1});
      expect(LevelRegistry.hasTypeRating(kKestrel.id), isTrue);
      expect(LevelRegistry.hasTypeRating(kMule.id), isTrue);
      expect(LevelRegistry.hasTypeRating(kHopper.id), isFalse);
    });
  });
}
