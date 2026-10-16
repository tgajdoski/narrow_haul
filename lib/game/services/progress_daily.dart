part of 'progress_service.dart';

/// The daily challenge: today's completion and best time, and the streak.
/// The daily's "today" is the shared dispatch day ([dispatchDay], rolling
/// over at 08:00 UTC), from [ProgressService.clock]; other per-day keys
/// (contracts, the replay XP cap) use [_todayKey], the phone's own day.
extension ProgressDaily on ProgressService {
  String _todayKey() => _dateKey(ProgressService.clock());

  String _dispatchKey() => dispatchKey(ProgressService.clock());

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Consecutive days with a completed daily. Still shown as alive until a
  /// full day is missed.
  int getDailyStreak() {
    final last = _string(_Keys.dailyLastDate);
    final day = dispatchDay(ProgressService.clock());
    final yesterday = dateKey(day.subtract(const Duration(days: 1)));
    if (last == _dispatchKey() || last == yesterday) {
      return _int(_Keys.dailyStreak) ?? 0;
    }
    return 0;
  }

  /// Call once on the first daily completion of a day; returns the new streak.
  Future<int> advanceDailyStreak() async {
    if (_string(_Keys.dailyLastDate) == _dispatchKey()) {
      return getDailyStreak();
    }
    final streak = getDailyStreak() + 1;
    await _prefs.setInt(_Keys.dailyStreak, streak);
    await _prefs.setString(_Keys.dailyLastDate, _dispatchKey());
    return streak;
  }

  /// The dispatch stage the pilot had when today's dispatch was first
  /// looked at: kept for the day, so a world opened mid-day doesn't swap
  /// the level (or the leaderboard) halfway through.
  String? dispatchTierToday() =>
      _string('dispatch_tier_day') == _dispatchKey() ? _string('dispatch_tier') : null;

  void setDispatchTierToday(String tier) {
    unawaited(_prefs.setString('dispatch_tier', tier));
    unawaited(_prefs.setString('dispatch_tier_day', _dispatchKey()));
  }

  bool isDailyChallengeComplete() => _bool('daily_${_dispatchKey()}') ?? false;

  Future<void> markDailyChallengeComplete() async =>
      _prefs.setBool('daily_${_dispatchKey()}', true);

  double? getDailyBestTime() => _double('daily_time_${_dispatchKey()}');

  Future<void> saveDailyBestTime(double seconds) async {
    final current = getDailyBestTime();
    if (current == null || seconds < current) {
      await _prefs.setDouble('daily_time_${_dispatchKey()}', seconds);
    }
  }
}
