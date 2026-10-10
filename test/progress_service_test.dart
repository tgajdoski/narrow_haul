import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/pump.dart';

void main() {
  tearDown(() => ProgressService.clock = DateTime.now);

  group('save_v2 migration', () {
    test('moves index-keyed tutorial progress to save ids, once', () async {
      SharedPreferences.setMockInitialValues({
        'stars_0': 3,
        'time_0': 41.5,
        'stars_9': 1,
        'stars_12': 2, // a dropped level: orphaned on purpose
      });
      await ProgressService.init();
      final p = ProgressService.instance;
      expect(p.getStarsById('tut_01'), 3);
      expect(p.getStarsById('tut_10'), 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('time2_tut_01'), 41.5);
      expect(prefs.getKeys().where((k) => k.startsWith('stars2_')), hasLength(2));
      expect(prefs.getBool('save_v2'), isTrue);

      // Runs once: newer progress isn't overwritten by the old keys.
      await prefs.setInt('stars2_tut_01', 1);
      await ProgressService.init();
      expect(ProgressService.instance.getStarsById('tut_01'), 1);
    });
  });

  group('daily streak', () {
    void today(int day) => ProgressService.clock = () => DateTime(2026, 3, day, 12);

    test('grows day by day, once per day, and breaks after a missed day', () async {
      await freshSave();
      final p = ProgressService.instance;
      today(1);
      expect(p.getDailyStreak(), 0);
      expect(await p.advanceDailyStreak(), 1);
      expect(await p.advanceDailyStreak(), 1, reason: 'same day: no change');
      today(2);
      expect(p.getDailyStreak(), 1, reason: 'still alive the next day');
      expect(await p.advanceDailyStreak(), 2);
      today(4);
      expect(p.getDailyStreak(), 0, reason: 'a full day missed');
      expect(await p.advanceDailyStreak(), 1);
    });

    test('carries across a month end', () async {
      await freshSave();
      final p = ProgressService.instance;
      ProgressService.clock = () => DateTime(2026, 2, 28, 23);
      await p.advanceDailyStreak();
      ProgressService.clock = () => DateTime(2026, 3, 1, 1);
      expect(await p.advanceDailyStreak(), 2);
    });
  });

  test('replay XP is counted per day', () async {
    await freshSave();
    final p = ProgressService.instance;
    ProgressService.clock = () => DateTime(2026, 3, 1);
    await p.addReplayXpToday(120);
    expect(p.getReplayXpToday(), 120);
    ProgressService.clock = () => DateTime(2026, 3, 2);
    expect(p.getReplayXpToday(), 0);
  });

  test('reset progress keeps settings, purchases and paid cosmetics', () async {
    await freshSave({
      'stars2_tut_01': 3,
      'xp_total': 900,
      'cosmetic_currency': 250,
      'cosmetic_unlocked_ship_red': true,
      'cosmetic_unlocked_ship_supporter': true,
      'achievements': <String>['first_flight'],
      'left_handed': true,
      'ads_removed': true,
      'iap_granted_nh_supporter_pack': true,
    });
    final p = ProgressService.instance;
    await p.resetProgress(keepCosmeticIds: {'ship_supporter'});
    final prefs = await SharedPreferences.getInstance();
    expect(p.getStarsById('tut_01'), 0);
    expect(prefs.containsKey('xp_total'), isFalse);
    expect(p.getCosmeticCurrency(), 0);
    expect(p.isCosmeticUnlocked('ship_red'), isFalse);
    expect(prefs.containsKey('achievements'), isFalse);
    expect(p.isCosmeticUnlocked('ship_supporter'), isTrue);
    expect(p.leftHanded, isTrue);
    expect(prefs.getBool('ads_removed'), isTrue);
    expect(prefs.getBool('iap_granted_nh_supporter_pack'), isTrue);
    expect(prefs.getBool('save_v3'), isTrue);
  });

  test('corrupt save values read as safe defaults', () async {
    await freshSave({
      'stars2_tut_01': 'three', // wrong type
      'stars2_tut_02': 9, // out of range
      'cosmetic_currency': -40,
      'left_handed': 1,
    });
    final p = ProgressService.instance;
    expect(p.getStarsById('tut_01'), 0);
    expect(p.getStarsById('tut_02'), 3);
    expect(p.getCosmeticCurrency(), 0);
    expect(p.leftHanded, isFalse);
  });
}
