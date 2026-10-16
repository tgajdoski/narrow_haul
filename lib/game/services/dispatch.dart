/// The Daily dispatch, shared: one day and one level for every pilot at the
/// same stage of the career, so times compare on a leaderboard. Pure Dart.
///
/// The day rolls over at [kDispatchRolloverUtcHour]:00 UTC everywhere (not
/// at each phone's midnight), so a dispatch and the platform's "today"
/// leaderboard cover the same hours: Game Center's recurring board starts
/// then, and Play Games' daily board resets at midnight Pacific (08:00 UTC
/// in winter, an hour earlier in summer).
library;

/// Hour (UTC) a new dispatch goes out: midnight Pacific standard time.
const int kDispatchRolloverUtcHour = 8;

/// The dispatch day [now] falls in, as a UTC calendar date.
DateTime dispatchDay(DateTime now) {
  final u = now.toUtc().subtract(const Duration(hours: kDispatchRolloverUtcHour));
  return DateTime.utc(u.year, u.month, u.day);
}

/// `YYYY-MM-DD` of the dispatch day (save keys, the RNG seed).
String dispatchKey(DateTime now) => dateKey(dispatchDay(now));

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// When the next dispatch goes out (UTC).
DateTime nextDispatchAt(DateTime now) => dispatchDay(now).add(
  const Duration(days: 1, hours: kDispatchRolloverUtcHour),
);

/// How far along the career a pilot is, for the dispatch: everyone at the
/// same stage flies the same level and shares one leaderboard. A stage
/// draws from its worlds and every earlier one, so a pilot who has just
/// reached it may be sent somewhere not yet flown (dispatches fly the
/// level's own ship, so that's always possible).
enum DispatchTier {
  /// Still in the Training Grounds.
  cadet('Cadet', ['tutorial']),

  /// Xenar Caverns open.
  line('Line', ['tutorial', 'alien']),

  /// Glacier Deep open.
  senior('Senior', ['tutorial', 'alien', 'mine', 'ice']),

  /// The Outer Ring open. The Redoubt stays out: its turrets need the
  /// Talon's practice.
  veteran('Veteran', ['tutorial', 'alien', 'mine', 'ice', 'lava', 'orbit']);

  const DispatchTier(this.title, this.worldIds);

  final String title;

  /// World ids whose missions this stage's dispatches are drawn from.
  final List<String> worldIds;

  /// The stage for a pilot with these career worlds open.
  static DispatchTier forUnlocked(Set<String> openWorldIds) {
    if (openWorldIds.contains('orbit')) return veteran;
    if (openWorldIds.contains('ice')) return senior;
    if (openWorldIds.contains('alien')) return line;
    return cadet;
  }
}

/// Whether a mission can be a dispatch: not the first two onboarding
/// flights, not a type rating (they fly only the par ship to earn it).
bool dispatchEligible(String saveId) =>
    !saveId.startsWith('rating_') && saveId != 'tut_01' && saveId != 'tut_02';
