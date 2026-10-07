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

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _instance = ProgressService._(prefs);
    await _instance!._migrateToV2();
  }

  /// One-time migration from index-keyed progress (`stars_0`…) to stable
  /// string save ids. The first 10 TMX levels became the trimmed tutorial;
  /// progress on dropped levels 11-20 is orphaned intentionally.
  Future<void> _migrateToV2() async {
    if (_prefs.getBool('save_v2') ?? false) return;
    for (int i = 0; i < 10; i++) {
      final saveId = 'tut_${(i + 1).toString().padLeft(2, '0')}';
      final stars = _prefs.getInt('stars_$i');
      if (stars != null) await _prefs.setInt('stars2_$saveId', stars);
      final time = _prefs.getDouble('time_$i');
      if (time != null) await _prefs.setDouble('time2_$saveId', time);
    }
    await _prefs.setBool('save_v2', true);
  }

  // ── Stars (0–3), keyed by stable level saveId ────────────────────────────

  int getStarsById(String saveId) => _prefs.getInt('stars2_$saveId') ?? 0;

  Future<void> saveStarsById(String saveId, int stars) async {
    if (stars > getStarsById(saveId)) {
      await _prefs.setInt('stars2_$saveId', stars);
    }
  }

  // ── Best time ────────────────────────────────────────────────────────────

  double? getBestTimeById(String saveId) => _prefs.getDouble('time2_$saveId');

  Future<void> saveBestTimeById(String saveId, double seconds) async {
    final current = getBestTimeById(saveId);
    if (current == null || seconds < current) {
      await _prefs.setDouble('time2_$saveId', seconds);
    }
  }

  // ── No-retry streak ──────────────────────────────────────────────────────

  int getNoRetryStreak() => _prefs.getInt('no_retry_streak') ?? 0;
  Future<void> setNoRetryStreak(int v) async =>
      _prefs.setInt('no_retry_streak', v);

  // ── Achievements ─────────────────────────────────────────────────────────

  Set<String> getUnlockedAchievements() =>
      (_prefs.getStringList('achievements') ?? []).toSet();

  Future<bool> unlockAchievement(String id) async {
    final current = getUnlockedAchievements();
    if (current.contains(id)) return false;
    current.add(id);
    await _prefs.setStringList('achievements', current.toList());
    return true;
  }

  // ── Stats & Currencies ───────────────────────────────────────────────────

  double getTotalFuelSpent() => _prefs.getDouble('total_fuel_spent') ?? 0.0;

  Future<void> addFuelSpent(double amount) async {
    final current = getTotalFuelSpent();
    await _prefs.setDouble('total_fuel_spent', current + amount);
  }

  int getCosmeticCurrency() => _prefs.getInt('cosmetic_currency') ?? 0;

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

  // ── Cosmetics ────────────────────────────────────────────────────────────

  bool isCosmeticUnlocked(String id) => _prefs.getBool('cosmetic_unlocked_$id') ?? false;

  Future<void> unlockCosmetic(String id) async {
    await _prefs.setBool('cosmetic_unlocked_$id', true);
  }

  String getEquippedCosmetic(String category, String defaultId) {
    return _prefs.getString('equipped_cosmetic_$category') ?? defaultId;
  }

  Future<void> equipCosmetic(String category, String id) async {
    await _prefs.setString('equipped_cosmetic_$category', id);
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  bool get minimapEnabled => _prefs.getBool('minimap_enabled') ?? true;
  Future<void> setMinimapEnabled(bool v) async =>
      _prefs.setBool('minimap_enabled', v);

  bool get soundEnabled => _prefs.getBool('sound_enabled') ?? true;
  Future<void> setSoundEnabled(bool v) async =>
      _prefs.setBool('sound_enabled', v);

  bool get hapticsEnabled => _prefs.getBool('haptics_enabled') ?? true;
  Future<void> setHapticsEnabled(bool v) async =>
      _prefs.setBool('haptics_enabled', v);

  /// Mirrors the touch controls: thrust on the left, joystick on the right.
  bool get leftHanded => _prefs.getBool('left_handed') ?? false;
  Future<void> setLeftHanded(bool v) async => _prefs.setBool('left_handed', v);

  // ── Pilot career (XP) ────────────────────────────────────────────────────

  int getXp() => _prefs.getInt('xp_total') ?? 0;
  Future<void> setXp(int v) async => _prefs.setInt('xp_total', v);
  Future<void> addXp(int amount) async => setXp(getXp() + amount);

  /// `save_v3`: XP backfilled from pre-rank progress (see CareerService).
  bool get isXpMigrated => _prefs.getBool('save_v3') ?? false;
  Future<void> markXpMigrated() async => _prefs.setBool('save_v3', true);

  int getReplayXpToday() => _prefs.getInt('replay_xp_${_todayKey()}') ?? 0;
  Future<void> addReplayXpToday(int amount) async =>
      _prefs.setInt('replay_xp_${_todayKey()}', getReplayXpToday() + amount);

  // ── Contracts (per day) ──────────────────────────────────────────────────

  List<String>? getTodayContracts() =>
      _prefs.getStringList('contracts_${_todayKey()}');
  Future<void> setTodayContracts(List<String> encoded) async =>
      _prefs.setStringList('contracts_${_todayKey()}', encoded);

  int getContractProgress(int i) =>
      _prefs.getInt('contract_${_todayKey()}_$i') ?? 0;
  Future<void> setContractProgress(int i, int v) async =>
      _prefs.setInt('contract_${_todayKey()}_$i', v);

  // ── Lifetime stats ───────────────────────────────────────────────────────

  static const statFlights = 'flights';
  static const statCrashes = 'crashes';
  static const statDeliveries = 'deliveries';
  static const statPlaytimeSeconds = 'playtime_s';

  int getStat(String name) => _prefs.getInt('stat_$name') ?? 0;
  Future<void> incrementStat(String name, [int by = 1]) async =>
      _prefs.setInt('stat_$name', getStat(name) + by);

  // ── Daily challenge ──────────────────────────────────────────────────────

  String _todayKey() => _dateKey(DateTime.now());

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Consecutive days with a completed daily. Still shown as alive until a
  /// full day is missed.
  int getDailyStreak() {
    final last = _prefs.getString('daily_last_date');
    final now = DateTime.now();
    final yesterday = _dateKey(DateTime(now.year, now.month, now.day - 1));
    if (last == _todayKey() || last == yesterday) {
      return _prefs.getInt('daily_streak') ?? 0;
    }
    return 0;
  }

  /// Call once on the first daily completion of a day; returns the new streak.
  Future<int> advanceDailyStreak() async {
    if (_prefs.getString('daily_last_date') == _todayKey()) {
      return getDailyStreak();
    }
    final streak = getDailyStreak() + 1;
    await _prefs.setInt('daily_streak', streak);
    await _prefs.setString('daily_last_date', _todayKey());
    return streak;
  }

  bool isDailyChallengeComplete() =>
      _prefs.getBool('daily_${_todayKey()}') ?? false;

  Future<void> markDailyChallengeComplete() async {
    await _prefs.setBool('daily_${_todayKey()}', true);
  }

  double? getDailyBestTime() => _prefs.getDouble('daily_time_${_todayKey()}');

  Future<void> saveDailyBestTime(double seconds) async {
    final current = getDailyBestTime();
    if (current == null || seconds < current) {
      await _prefs.setDouble('daily_time_${_todayKey()}', seconds);
    }
  }
}
