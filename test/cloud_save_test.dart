import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/cloud_save.dart';
import 'package:narrow_haul/game/services/games_ids.dart';
import 'package:narrow_haul/game/services/games_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory Play Games / Game Center.
class _FakeBackend implements GamesBackend {
  String? save;
  bool offline = false;
  final unlocked = <String>{};
  int? stars;

  @override
  Future<bool> signIn() async => true;
  @override
  Future<void> unlockAchievement(String localId) async => unlocked.add(localId);
  @override
  Future<void> submitStars(int stars) async => this.stars = stars;
  @override
  Future<String?> loadSave(String slot) async {
    if (offline) throw StateError('offline');
    return save;
  }

  @override
  Future<void> writeSave(String slot, String data) async {
    if (offline) throw StateError('offline');
    save = data;
  }

  @override
  Future<void> showAchievements() async {}
  @override
  Future<void> showLeaderboard() async {}
}

void main() {
  test('every achievement has a Play Games id, all different', () {
    for (final a in AchievementService.all) {
      expect(kPlayAchievementIds[a.id], isNotNull, reason: a.id);
    }
    expect(
      kPlayAchievementIds.values.toSet(),
      hasLength(AchievementService.all.length),
    );
  });

  group('merge rules', () {
    test('only career keys travel', () {
      for (final key in [
        'stars2_tut_01',
        'time2_alien_03',
        'xp_total',
        'cosmetic_currency',
        'ammo_charge',
        'achievements',
        'ship_owned_hopper',
        'cosmetic_unlocked_rope_tractor',
        'story_intro_alien',
        'daily_2026-10-14',
        'daily_streak',
        'equipped_cosmetic_rope',
        'stat_deliveries',
        'fuel2_alien_03',
        'flawless_tut_04',
      ]) {
        expect(CloudSave.isSynced(key), isTrue, reason: key);
      }
      for (final key in [
        'sound_enabled',
        'tilt_steer',
        'steer_mode',
        'iap_granted_nh_full_game',
        'ads_removed',
        'ads_free_until',
        'reminders_enabled',
        'contracts_2026-10-14',
        'replay_xp_2026-10-14',
        'cloud_base',
        'save_v3',
        // The ghost's file stays on its device, so its time does too.
        'pbroute_tut_04',
        'race_ghost',
      ]) {
        expect(CloudSave.isSynced(key), isFalse, reason: key);
      }
    });

    test('best fuel keeps the higher, flawless only turns on', () {
      final merged = CloudSave.merge(
        local: {'fuel2_alien_03': 0.62, 'flawless_tut_04': false},
        cloud: {'fuel2_alien_03': 0.71, 'flawless_tut_04': true},
      );
      expect(merged['fuel2_alien_03'], 0.71);
      expect(merged['flawless_tut_04'], isTrue);
    });

    test('best of both: stars, times, XP, flags, lists', () {
      final merged = CloudSave.merge(
        local: {
          'stars2_tut_01': 3,
          'stars2_tut_02': 1,
          'time2_tut_01': 40.0,
          'xp_total': 900,
          'ship_owned_hopper': true,
          'achievements': ['first_haul', 'fuel_miser'],
          'equipped_cosmetic_rope': 'rope_neon',
        },
        cloud: {
          'stars2_tut_02': 3,
          'stars2_tut_03': 2,
          'time2_tut_01': 35.5,
          'xp_total': 1200,
          'ship_owned_mule': true,
          'achievements': ['first_haul', 'daily_pilot'],
          'equipped_cosmetic_rope': 'rope_cable',
        },
      );
      expect(merged['stars2_tut_01'], 3);
      expect(merged['stars2_tut_02'], 3);
      expect(merged['stars2_tut_03'], 2);
      expect(merged['time2_tut_01'], 35.5);
      expect(merged['xp_total'], 1200);
      expect(merged['ship_owned_hopper'], isTrue);
      expect(merged['ship_owned_mule'], isTrue);
      expect(merged['achievements'], [
        'daily_pilot',
        'first_haul',
        'fuel_miser',
      ]);
      // A choice stays this device's own.
      expect(merged['equipped_cosmetic_rope'], 'rope_neon');
    });

    test('coins: a new phone takes the cloud balance', () {
      final merged = CloudSave.merge(
        local: {'cosmetic_currency': 0},
        cloud: {'cosmetic_currency': 500},
      );
      expect(merged['cosmetic_currency'], 500);
    });

    test('coins spent on one device stay spent', () {
      // Both agreed on 500; this phone bought a ship for 400.
      final merged = CloudSave.merge(
        local: {'cosmetic_currency': 100, 'ship_owned_mule': true},
        cloud: {'cosmetic_currency': 500},
        base: {'cosmetic_currency': 500},
      );
      expect(merged['cosmetic_currency'], 100);
      expect(merged['ship_owned_mule'], isTrue);
    });

    test('coins earned on two devices add up', () {
      final merged = CloudSave.merge(
        local: {'cosmetic_currency': 650, 'ammo_charge': 2.0},
        cloud: {'cosmetic_currency': 580, 'ammo_charge': 5.0},
        base: {'cosmetic_currency': 500, 'ammo_charge': 3.0},
      );
      expect(merged['cosmetic_currency'], 730);
      expect(merged['ammo_charge'], 4.0);
    });

    test('a wallet never goes negative', () {
      final merged = CloudSave.merge(
        local: {'cosmetic_currency': 0},
        cloud: {'cosmetic_currency': 0},
        base: {'cosmetic_currency': 300},
      );
      expect(merged['cosmetic_currency'], 0);
    });

    test('the daily streak follows the most recent daily', () {
      final merged = CloudSave.merge(
        local: {'daily_streak': 9, 'daily_last_date': '2026-10-10'},
        cloud: {'daily_streak': 2, 'daily_last_date': '2026-10-13'},
      );
      expect(merged['daily_streak'], 2);
      expect(merged['daily_last_date'], '2026-10-13');
    });

    test('changes lists only what differs', () {
      final local = <String, Object>{
        'xp_total': 10,
        'achievements': ['a'],
      };
      final changed = CloudSave.changes(local, {
        'xp_total': 10,
        'achievements': ['a'],
        'stars2_x': 1,
      });
      expect(changed, {'stars2_x': 1});
    });

    test(
      'encode / decode round trip, unknown keys and newer formats dropped',
      () {
        final raw = CloudSave.encode({
          'xp_total': 5,
          'time2_a': 12.0,
          'achievements': ['x'],
        }, atMs: 1);
        expect(CloudSave.decode(raw), {
          'xp_total': 5,
          'time2_a': 12.0,
          'achievements': ['x'],
        });
        expect(
          CloudSave.decode('{"v":1,"at":1,"data":{"ads_removed":true}}'),
          isEmpty,
        );
        expect(CloudSave.decode('{"v":99,"at":1,"data":{}}'), isNull);
        expect(CloudSave.decode('garbage'), isNull);
      },
    );
  });

  group('GamesService sync', () {
    late _FakeBackend cloud;

    setUp(() {
      GamesService.debugReset();
      GamesService.totalStars = () => 7;
      cloud = _FakeBackend();
    });

    Future<ProgressService> device(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      await ProgressService.init();
      return ProgressService.instance;
    }

    test('first sign-in uploads this device and pushes achievements', () async {
      await device({
        'stars2_tut_01': 3,
        'achievements': ['first_haul'],
        'sound_enabled': false,
      });
      await GamesService.init(backend: cloud);
      final saved = CloudSave.decode(cloud.save)!;
      expect(saved['stars2_tut_01'], 3);
      expect(saved.containsKey('sound_enabled'), isFalse);
      expect(cloud.unlocked, {'first_haul'});
      expect(cloud.stars, 7);
    });

    test('a new phone gets the career back', () async {
      cloud.save = CloudSave.encode({
        'stars2_tut_01': 3,
        'xp_total': 4000,
        'cosmetic_currency': 640,
        'ship_owned_hopper': true,
      }, atMs: 1);
      final p = await device({});
      var redrawn = false;
      GamesService.onSaveMerged = () => redrawn = true;
      await GamesService.init(backend: cloud);
      expect(p.getStarsById('tut_01'), 3);
      expect(p.getCosmeticCurrency(), 640);
      expect(redrawn, isTrue);
      expect(p.cloudBase?['xp_total'], 4000);
    });

    test('offline: nothing is overwritten', () async {
      cloud.save = CloudSave.encode({'stars2_tut_01': 3}, atMs: 1);
      cloud.offline = true;
      final p = await device({'stars2_tut_02': 1});
      await GamesService.init(backend: cloud);
      expect(p.getStarsById('tut_02'), 1);
      expect(p.cloudBase, isNull);
      cloud.offline = false;
      expect(CloudSave.decode(cloud.save), {'stars2_tut_01': 3});
    });

    test('reset progress replaces the cloud copy', () async {
      cloud.save = CloudSave.encode({'stars2_tut_01': 3}, atMs: 1);
      final p = await device({'stars2_tut_01': 3});
      await p.resetProgress();
      await GamesService.init(backend: cloud);
      expect(p.getStarsById('tut_01'), 0);
      expect(CloudSave.decode(cloud.save), isEmpty);
      expect(p.cloudOverwritePending, isFalse);
    });

    test('uploads are throttled, a pause always uploads', () async {
      var t = 1000000;
      GamesService.now = () => t;
      addTearDown(
        () => GamesService.now = () => DateTime.now().millisecondsSinceEpoch,
      );
      final p = await device({});
      await GamesService.init(backend: cloud);
      await p.saveStarsById('tut_01', 2);
      t += 5000;
      await GamesService.sync();
      expect(
        CloudSave.decode(cloud.save)!.containsKey('stars2_tut_01'),
        isFalse,
      );
      GamesService.appPaused();
      await GamesService.sync(force: true);
      expect(CloudSave.decode(cloud.save)!['stars2_tut_01'], 2);
    });
  });
}
