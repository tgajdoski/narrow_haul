part of 'progress_service.dart';

/// The daily challenge: today's completion and best time, and the streak.
/// "Today" comes from [ProgressService.clock].
extension ProgressDaily on ProgressService {
  String _todayKey() => _dateKey(ProgressService.clock());

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Consecutive days with a completed daily. Still shown as alive until a
  /// full day is missed.
  int getDailyStreak() {
    final last = _string(_Keys.dailyLastDate);
    final now = ProgressService.clock();
    final yesterday = _dateKey(DateTime(now.year, now.month, now.day - 1));
    if (last == _todayKey() || last == yesterday) {
      return _int(_Keys.dailyStreak) ?? 0;
    }
    return 0;
  }

  /// Call once on the first daily completion of a day; returns the new streak.
  Future<int> advanceDailyStreak() async {
    if (_string(_Keys.dailyLastDate) == _todayKey()) {
      return getDailyStreak();
    }
    final streak = getDailyStreak() + 1;
    await _prefs.setInt(_Keys.dailyStreak, streak);
    await _prefs.setString(_Keys.dailyLastDate, _todayKey());
    return streak;
  }

  bool isDailyChallengeComplete() => _bool('daily_${_todayKey()}') ?? false;

  Future<void> markDailyChallengeComplete() async =>
      _prefs.setBool('daily_${_todayKey()}', true);

  double? getDailyBestTime() => _double('daily_time_${_todayKey()}');

  Future<void> saveDailyBestTime(double seconds) async {
    final current = getDailyBestTime();
    if (current == null || seconds < current) {
      await _prefs.setDouble('daily_time_${_todayKey()}', seconds);
    }
  }
}
