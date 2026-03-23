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
  }

  // ── Stars (0–3) ─────────────────────────────────────────────────────────

  int getStars(int levelIndex) => _prefs.getInt('stars_$levelIndex') ?? 0;

  Future<void> saveStars(int levelIndex, int stars) async {
    if (stars > getStars(levelIndex)) {
      await _prefs.setInt('stars_$levelIndex', stars);
    }
  }

  int getTotalStars(int totalLevels) {
    int total = 0;
    for (int i = 0; i < totalLevels; i++) {
      total += getStars(i);
    }
    return total;
  }

  // ── Level unlock ─────────────────────────────────────────────────────────

  bool isUnlocked(int levelIndex) {
    if (levelIndex == 0) return true;
    return _prefs.getBool('unlocked_$levelIndex') ?? false;
  }

  Future<void> unlockLevel(int levelIndex) async {
    if (!isUnlocked(levelIndex)) {
      await _prefs.setBool('unlocked_$levelIndex', true);
    }
  }

  // ── Best time ────────────────────────────────────────────────────────────

  double? getBestTime(int levelIndex) => _prefs.getDouble('time_$levelIndex');

  Future<void> saveBestTime(int levelIndex, double seconds) async {
    final current = getBestTime(levelIndex);
    if (current == null || seconds < current) {
      await _prefs.setDouble('time_$levelIndex', seconds);
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

  // ── Daily challenge ──────────────────────────────────────────────────────

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  bool isDailyChallengeComplete() =>
      _prefs.getBool('daily_${_todayKey()}') ?? false;

  Future<void> markDailyChallengeComplete() async {
    await _prefs.setBool('daily_${_todayKey()}', true);
  }
}
