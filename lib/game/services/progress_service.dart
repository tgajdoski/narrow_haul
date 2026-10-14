import 'dart:math' as math;

import 'package:narrow_haul/game/services/cloud_save.dart';
import 'package:narrow_haul/game/services/error_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:narrow_haul/game/services/monetization_ids.dart';

part 'progress_ads.dart';
part 'progress_career.dart';
part 'progress_daily.dart';
part 'progress_prefs.dart';
part 'progress_settings.dart';

/// Persists level progress, star ratings, best times, achievements, streaks,
/// settings and purchases in `shared_preferences`.
///
/// The API is split by domain into part files (extensions on this class):
/// career, settings, ads & purchases, daily. Keys with a default are
/// [_Pref]s in `progress_prefs.dart`, so each key string is written once.
class ProgressService {
  ProgressService._(this._prefs);

  /// Today's date source for dailies, streaks and the replay-XP cap
  /// (tests set a fixed day).
  static DateTime Function() clock = DateTime.now;

  static ProgressService? _instance;
  static ProgressService get instance {
    assert(_instance != null, 'ProgressService.init() must be called first');
    return _instance!;
  }

  final SharedPreferences _prefs;

  // Type-safe reads: a value of the wrong type (a corrupted or hand-edited
  // prefs file, or a key reused across versions) reads as missing instead of
  // throwing in the middle of a frame.
  int? _int(String key) {
    final v = _prefs.get(key);
    return v is int ? v : null;
  }

  double? _double(String key) {
    final v = _prefs.get(key);
    return v is num ? v.toDouble() : null;
  }

  bool? _bool(String key) {
    final v = _prefs.get(key);
    return v is bool ? v : null;
  }

  String? _string(String key) {
    final v = _prefs.get(key);
    return v is String ? v : null;
  }

  T _read<T extends Object>(_Pref<T> p) {
    final v = _prefs.get(p.key);
    if (v is T) return v;
    if (p.fallback is double && v is num) return v.toDouble() as T;
    return p.fallback;
  }

  Future<void> _write<T extends Object>(_Pref<T> p, T v) => switch (v) {
    final bool b => _prefs.setBool(p.key, b),
    final int i => _prefs.setInt(p.key, i),
    final double d => _prefs.setDouble(p.key, d),
    final String s => _prefs.setString(p.key, s),
    _ => throw ArgumentError.value(v, p.key),
  };

  List<String>? _stringList(String key) {
    try {
      return _prefs.getStringList(key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _instance = ProgressService._(prefs);
    try {
      await _instance!._migrateToV2();
    } catch (e, st) {
      // A failed migration must not keep the game from starting.
      ErrorReporter.report(e, st, context: 'save_v2 migration');
    }
  }

  /// One-time migration from index-keyed progress (`stars_0`…) to stable
  /// string save ids. The first 10 TMX levels became the trimmed tutorial;
  /// progress on dropped levels 11-20 is orphaned intentionally.
  Future<void> _migrateToV2() async {
    if (_bool(_Keys.saveV2) ?? false) return;
    for (int i = 0; i < 10; i++) {
      final saveId = 'tut_${(i + 1).toString().padLeft(2, '0')}';
      final stars = _int('stars_$i');
      if (stars != null) await _prefs.setInt('stars2_$saveId', stars);
      final time = _double('time_$i');
      if (time != null) await _prefs.setDouble('time2_$saveId', time);
    }
    await _prefs.setBool(_Keys.saveV2, true);
  }

  // ── Reset ────────────────────────────────────────────────────────────────

  /// Settings and migration flags that survive "Reset progress".
  static final _keptOnReset = {
    _soundEnabled.key,
    _musicEnabled.key,
    _hapticsEnabled.key,
    _leftHanded.key,
    _minimapEnabled.key,
    _Keys.steerMode,
    _Keys.cameraMode,
    _Keys.tiltSteer,
    _Keys.tiltSensitivity,
    _Keys.tiltMode,
    _creditsSeen.key,
    _Keys.remindersEnabled,
    _reminderAsks.key,
    _reminderAskMs.key,
    _Keys.reminderHours,
    _Keys.saveV2,
    _xpMigrated.key,
  };

  /// Wipes the career (stars, times, XP, coins, achievements, Garage,
  /// dailies, contracts, stats) but keeps settings, purchases (`iap_*`,
  /// `ads_removed`), weapon ammo (`ammo_*`), ad pacing and the cosmetics in
  /// [keepCosmeticIds]
  /// (paid items such as the Supporter Livery).
  Future<void> resetProgress({Set<String> keepCosmeticIds = const {}}) async {
    for (final key in _prefs.getKeys().toList()) {
      final kept = _keptOnReset.contains(key) ||
          key.startsWith('iap_') ||
          key.startsWith('ads_') ||
          key.startsWith('ammo_') ||
          key.startsWith('crate_hint_') ||
          keepCosmeticIds.any((id) => key == 'cosmetic_unlocked_$id');
      if (!kept) await _prefs.remove(key);
    }
    // The next cloud sync replaces the cloud copy instead of merging it
    // back in (which would undo the reset).
    await _prefs.setBool(_cloudOverwrite, true);
  }

  // ── Cloud save (rules in CloudSave) ──────────────────────────────────────

  static const _cloudBase = 'cloud_base';
  static const _cloudOverwrite = 'cloud_overwrite';

  /// Every [CloudSave.isSynced] key on this device.
  Map<String, Object> exportSynced() => {
    for (final key in _prefs.getKeys())
      if (CloudSave.isSynced(key))
        if (_prefs.get(key) case final Object v) key: v,
  };

  /// Writes merged values back (only [CloudSave.isSynced] keys).
  Future<void> importSynced(Map<String, Object> values) async {
    for (final MapEntry(:key, :value) in values.entries) {
      if (!CloudSave.isSynced(key)) continue;
      switch (value) {
        case final bool v:
          await _prefs.setBool(key, v);
        case final int v:
          await _prefs.setInt(key, v);
        case final double v:
          await _prefs.setDouble(key, v);
        case final String v:
          await _prefs.setString(key, v);
        case final List<String> v:
          await _prefs.setStringList(key, v);
        default:
          break;
      }
    }
  }

  /// The snapshot this device and the cloud last agreed on (null = never
  /// synced, or reset since).
  Map<String, Object>? get cloudBase => CloudSave.decode(_string(_cloudBase));

  Future<void> setCloudBase(Map<String, Object> data, {required int atMs}) =>
      _prefs.setString(_cloudBase, CloudSave.encode(data, atMs: atMs));

  /// "Reset progress" ran since the last sync: upload, don't merge.
  bool get cloudOverwritePending => _bool(_cloudOverwrite) ?? false;
  Future<void> clearCloudOverwrite() => _prefs.remove(_cloudOverwrite);

  // ── Lifetime stat names (getStat / incrementStat) ─────────────────────

  static const statFlights = 'flights';
  static const statCrashes = 'crashes';
  static const statDeliveries = 'deliveries';
  static const statPlaytimeSeconds = 'playtime_s';
  static const statTurretsDestroyed = 'turrets_destroyed';
  static const statObstaclesWrecked = 'obstacles_wrecked';
  static const statShellsIntercepted = 'shells_intercepted';
  static const statReactorEscapes = 'reactor_escapes';
  static const statFuelCells = 'fuel_cells';
  static const statSalvageOpened = 'salvage_opened';
  static const statSalvageCurses = 'salvage_curses';
  static const statSalvageGrit = 'salvage_grit';

  /// Boons opened in a row (Four-Leaf Clover at 3).
  static const statSalvageBoonStreak = 'salvage_boon_streak';
}
