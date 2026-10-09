import 'dart:math' as math;

import 'package:narrow_haul/game/services/error_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists level progress, star ratings, best times, achievements, streaks.
class ProgressService {
  ProgressService._(this._prefs);

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
    if (_bool('save_v2') ?? false) return;
    for (int i = 0; i < 10; i++) {
      final saveId = 'tut_${(i + 1).toString().padLeft(2, '0')}';
      final stars = _int('stars_$i');
      if (stars != null) await _prefs.setInt('stars2_$saveId', stars);
      final time = _double('time_$i');
      if (time != null) await _prefs.setDouble('time2_$saveId', time);
    }
    await _prefs.setBool('save_v2', true);
  }

  // ── Reset ────────────────────────────────────────────────────────────────

  /// Settings and migration flags that survive "Reset progress".
  static const _keptOnReset = {
    'sound_enabled',
    'music_enabled',
    'haptics_enabled',
    'left_handed',
    'minimap_enabled',
    'steer_mode',
    'camera_mode',
    'credits_seen',
    'save_v2',
    'save_v3',
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
  }

  // ── Stars (0–3), keyed by stable level saveId ────────────────────────────

  int getStarsById(String saveId) =>
      (_int('stars2_$saveId') ?? 0).clamp(0, 3);

  Future<void> saveStarsById(String saveId, int stars) async {
    if (stars > getStarsById(saveId)) {
      await _prefs.setInt('stars2_$saveId', stars);
    }
  }

  // ── Best time ────────────────────────────────────────────────────────────

  double? getBestTimeById(String saveId) => _double('time2_$saveId');

  Future<void> saveBestTimeById(String saveId, double seconds) async {
    final current = getBestTimeById(saveId);
    if (current == null || seconds < current) {
      await _prefs.setDouble('time2_$saveId', seconds);
    }
  }

  // ── No-retry streak ──────────────────────────────────────────────────────

  int getNoRetryStreak() => _int('no_retry_streak') ?? 0;
  Future<void> setNoRetryStreak(int v) async =>
      _prefs.setInt('no_retry_streak', v);

  // ── Achievements ─────────────────────────────────────────────────────────

  Set<String> getUnlockedAchievements() =>
      (_stringList('achievements') ?? []).toSet();

  Future<bool> unlockAchievement(String id) async {
    final current = getUnlockedAchievements();
    if (current.contains(id)) return false;
    current.add(id);
    await _prefs.setStringList('achievements', current.toList());
    return true;
  }

  // ── Stats & Currencies ───────────────────────────────────────────────────

  double getTotalFuelSpent() => _double('total_fuel_spent') ?? 0.0;

  Future<void> addFuelSpent(double amount) async {
    final current = getTotalFuelSpent();
    await _prefs.setDouble('total_fuel_spent', current + amount);
  }

  int getCosmeticCurrency() => math.max(0, _int('cosmetic_currency') ?? 0);

  Future<void> addCosmeticCurrency(int amount) async {
    final current = getCosmeticCurrency();
    await _prefs.setInt('cosmetic_currency', current + amount);
  }

  Future<void> spendCosmeticCurrency(int amount) async {
    final current = getCosmeticCurrency();
    if (current >= amount) {
      await _prefs.setInt('cosmetic_currency', current - amount);
    }
  }

  /// A consumable purchase (store transaction id) was already paid out.
  bool isTransactionGranted(String purchaseId) => _bool('iap_tx_$purchaseId') ?? false;
  Future<void> markTransactionGranted(String purchaseId) async =>
      _prefs.setBool('iap_tx_$purchaseId', true);

  // ── Weapon ammo (carried stock) ──────────────────────────────────────────

  /// Carried units of a special weapon (charges, bombs, laser seconds).
  /// Kept across a progress reset: most of it was paid for.
  double getAmmo(String weaponId) => math.max(0, _double('ammo_$weaponId') ?? 0);

  Future<void> addAmmo(String weaponId, double units) async {
    final next = math.max(0.0, getAmmo(weaponId) + units);
    await _prefs.setDouble('ammo_$weaponId', next);
  }

  // ── Route guide ──────────────────────────────────────────────────────────

  /// "Show route" was offered and taken on this level; it stays available.
  bool isRouteUnlocked(String saveId) => _bool('route_unlocked_$saveId') ?? false;
  Future<void> setRouteUnlocked(String saveId) async =>
      _prefs.setBool('route_unlocked_$saveId', true);

  // ── Cosmetics ────────────────────────────────────────────────────────────

  bool isCosmeticUnlocked(String id) => _bool('cosmetic_unlocked_$id') ?? false;

  Future<void> unlockCosmetic(String id) async {
    await _prefs.setBool('cosmetic_unlocked_$id', true);
  }

  String getEquippedCosmetic(String category, String defaultId) {
    return _string('equipped_cosmetic_$category') ?? defaultId;
  }

  Future<void> equipCosmetic(String category, String id) async {
    await _prefs.setString('equipped_cosmetic_$category', id);
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  /// The "Delivered by" credits play on the first launch only.
  bool get creditsSeen => _bool('credits_seen') ?? false;

  /// "Slow touches are safe" shows on the first scrape only.
  bool get scrapeHintSeen => _bool('scrape_hint_seen') ?? false;
  Future<void> markScrapeHintSeen() async =>
      _prefs.setBool('scrape_hint_seen', true);
  /// A crate's "loaded, tap FIRE" plate shows the first time each weapon
  /// is picked up; after that the icon flying into FIRE says it.
  bool crateHintSeen(String weaponId) => _bool('crate_hint_$weaponId') ?? false;
  Future<void> markCrateHintSeen(String weaponId) async =>
      _prefs.setBool('crate_hint_$weaponId', true);
  Future<void> markCreditsSeen() async => _prefs.setBool('credits_seen', true);

  bool get minimapEnabled => _bool('minimap_enabled') ?? true;
  Future<void> setMinimapEnabled(bool v) async =>
      _prefs.setBool('minimap_enabled', v);

  bool get soundEnabled => _bool('sound_enabled') ?? true;
  Future<void> setSoundEnabled(bool v) async =>
      _prefs.setBool('sound_enabled', v);

  bool get musicEnabled => _bool('music_enabled') ?? true;
  Future<void> setMusicEnabled(bool v) async =>
      _prefs.setBool('music_enabled', v);

  bool get hapticsEnabled => _bool('haptics_enabled') ?? true;
  Future<void> setHapticsEnabled(bool v) async =>
      _prefs.setBool('haptics_enabled', v);

  /// Mirrors the touch controls: thrust on the left, joystick on the right.
  bool get leftHanded => _bool('left_handed') ?? false;
  Future<void> setLeftHanded(bool v) async => _prefs.setBool('left_handed', v);

  /// Steering and camera presets (`SteerMode` / `CameraMode` names).
  String? get steerMode => _string('steer_mode');
  Future<void> setSteerMode(String v) async => _prefs.setString('steer_mode', v);
  String? get cameraMode => _string('camera_mode');
  Future<void> setCameraMode(String v) async =>
      _prefs.setString('camera_mode', v);

  // ── Ads & purchases (see MonetizationService / AdPacing) ─────────────────

  /// Remove-ads entitlement (from `nh_remove_ads` or the supporter pack).
  bool get adsRemoved => _bool('ads_removed') ?? false;
  Future<void> setAdsRemoved(bool v) async => _prefs.setBool('ads_removed', v);

  /// Any IAP ever made — payers never see interstitials.
  bool get hasPurchased => _bool('iap_any_purchase') ?? false;
  Future<void> setHasPurchased(bool v) async =>
      _prefs.setBool('iap_any_purchase', v);

  /// Non-consumable product ids already granted (supporter pack payout once).
  bool isProductGranted(String id) => _bool('iap_granted_$id') ?? false;
  Future<void> markProductGranted(String id) async =>
      _prefs.setBool('iap_granted_$id', true);

  /// Dev only: forgets every purchase on this device (sandbox test buys), so
  /// ads show again. A store restore grants them back.
  Future<void> debugClearPurchases() async {
    for (final key in _prefs.getKeys().toList()) {
      if (key == 'ads_removed' || key.startsWith('iap_')) {
        await _prefs.remove(key);
      }
    }
  }

  int get adClearsSinceInterstitial => _int('ads_clears_since_inter') ?? 0;
  Future<void> setAdClearsSinceInterstitial(int v) async =>
      _prefs.setInt('ads_clears_since_inter', v);

  /// Epoch ms of the last interstitial / rewarded ad (0 = never).
  int get lastInterstitialMs => _int('ads_last_inter_ms') ?? 0;
  Future<void> setLastInterstitialMs(int v) async =>
      _prefs.setInt('ads_last_inter_ms', v);

  int get lastRewardedMs => _int('ads_last_rewarded_ms') ?? 0;
  Future<void> setLastRewardedMs(int v) async =>
      _prefs.setInt('ads_last_rewarded_ms', v);

  /// Epoch ms the remove-ads offer was last shown on the result screen.
  int get removeAdsOfferMs => _int('ads_offer_ms') ?? 0;
  Future<void> setRemoveAdsOfferMs(int v) async =>
      _prefs.setInt('ads_offer_ms', v);

  // ── Pilot career (XP) ────────────────────────────────────────────────────

  int getXp() => math.max(0, _int('xp_total') ?? 0);
  Future<void> setXp(int v) async => _prefs.setInt('xp_total', v);
  Future<void> addXp(int amount) async => setXp(getXp() + amount);

  /// `save_v3`: XP backfilled from pre-rank progress (see CareerService).
  bool get isXpMigrated => _bool('save_v3') ?? false;
  Future<void> markXpMigrated() async => _prefs.setBool('save_v3', true);

  int getReplayXpToday() => _int('replay_xp_${_todayKey()}') ?? 0;
  Future<void> addReplayXpToday(int amount) async =>
      _prefs.setInt('replay_xp_${_todayKey()}', getReplayXpToday() + amount);

  // ── Contracts (per day) ──────────────────────────────────────────────────

  List<String>? getTodayContracts() =>
      _stringList('contracts_${_todayKey()}');
  Future<void> setTodayContracts(List<String> encoded) async =>
      _prefs.setStringList('contracts_${_todayKey()}', encoded);

  int getContractProgress(int i) =>
      _int('contract_${_todayKey()}_$i') ?? 0;
  Future<void> setContractProgress(int i, int v) async =>
      _prefs.setInt('contract_${_todayKey()}_$i', v);

  // ── Lifetime stats ───────────────────────────────────────────────────────

  static const statFlights = 'flights';
  static const statCrashes = 'crashes';
  static const statDeliveries = 'deliveries';
  static const statPlaytimeSeconds = 'playtime_s';
  static const statTurretsDestroyed = 'turrets_destroyed';
  static const statObstaclesWrecked = 'obstacles_wrecked';
  static const statShellsIntercepted = 'shells_intercepted';
  static const statReactorEscapes = 'reactor_escapes';
  static const statFuelCells = 'fuel_cells';

  /// Sets a one-time flag; true only the first time (e.g. first reactor
  /// escape on a level, which pays its bonus once).
  Future<bool> markOnce(String key) async {
    if (_bool('once_$key') ?? false) return false;
    await _prefs.setBool('once_$key', true);
    return true;
  }

  int getStat(String name) => _int('stat_$name') ?? 0;
  Future<void> incrementStat(String name, [int by = 1]) async =>
      _prefs.setInt('stat_$name', getStat(name) + by);

  // ── Daily challenge ──────────────────────────────────────────────────────

  String _todayKey() => _dateKey(DateTime.now());

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Consecutive days with a completed daily. Still shown as alive until a
  /// full day is missed.
  int getDailyStreak() {
    final last = _string('daily_last_date');
    final now = DateTime.now();
    final yesterday = _dateKey(DateTime(now.year, now.month, now.day - 1));
    if (last == _todayKey() || last == yesterday) {
      return _int('daily_streak') ?? 0;
    }
    return 0;
  }

  /// Call once on the first daily completion of a day; returns the new streak.
  Future<int> advanceDailyStreak() async {
    if (_string('daily_last_date') == _todayKey()) {
      return getDailyStreak();
    }
    final streak = getDailyStreak() + 1;
    await _prefs.setInt('daily_streak', streak);
    await _prefs.setString('daily_last_date', _todayKey());
    return streak;
  }

  bool isDailyChallengeComplete() =>
      _bool('daily_${_todayKey()}') ?? false;

  Future<void> markDailyChallengeComplete() async {
    await _prefs.setBool('daily_${_todayKey()}', true);
  }

  double? getDailyBestTime() => _double('daily_time_${_todayKey()}');

  Future<void> saveDailyBestTime(double seconds) async {
    final current = getDailyBestTime();
    if (current == null || seconds < current) {
      await _prefs.setDouble('daily_time_${_todayKey()}', seconds);
    }
  }
}
