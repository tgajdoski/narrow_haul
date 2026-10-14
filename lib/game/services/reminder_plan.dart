// Return reminders: what to say and when (pure Dart, no plugin, no prefs).
// ReminderService turns the plan into local notifications; the rules live
// here so tests can check them without a device.

/// What a reminder is about. The name goes into analytics.
enum ReminderKind { streak, daily, gear, mission }

/// The player's state when the app opens or goes to the background.
class ReminderState {
  const ReminderState({
    required this.now,
    this.dailyStreak = 0,
    this.dailyDoneToday = false,
    this.affordableGear,
    this.nextMission,
    this.playHours = const [],
  });

  final DateTime now;
  final int dailyStreak;
  final bool dailyDoneToday;

  /// The cheapest tow gear or handling kit the player can buy right now.
  final String? affordableGear;

  /// The next career mission's story, null when every mission is flown.
  final MissionReminder? nextMission;

  /// Hours (0–23) of recent session starts, newest last.
  final List<int> playHours;
}

/// The radio line for the next mission (from its `LevelStory`).
class MissionReminder {
  const MissionReminder({required this.from, required this.cargo, required this.brief});
  final String from;
  final String cargo;
  final String brief;
}

class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.kind,
    required this.title,
    required this.body,
  });

  /// Notification id: the slot (0, 1, 2), so a reschedule replaces it.
  final int id;
  final DateTime at;
  final ReminderKind kind;
  final String title;
  final String body;
}

/// Days after the last session that each reminder fires; then nothing until
/// the player comes back (the next open reschedules from there).
const kReminderDays = [1, 3, 7];

/// Reminders go out at the player's usual hour, never earlier or later.
const kReminderEarliestHour = 10;
const kReminderLatestHour = 21;
const kReminderDefaultHour = 18;

/// A streak this long is worth a nudge to keep it.
const kReminderStreakMin = 3;

/// The hour to send at: the median of recent session starts, clamped to
/// waking hours.
int reminderHour(List<int> playHours) {
  if (playHours.isEmpty) return kReminderDefaultHour;
  final sorted = [...playHours]..sort();
  return sorted[sorted.length ~/ 2].clamp(kReminderEarliestHour, kReminderLatestHour);
}

/// Up to one reminder per slot in [kReminderDays], each about something
/// different where possible. [debugSpacing] (device testing) fires slot k at
/// (k + 1) × spacing from now instead.
List<PlannedReminder> planReminders(ReminderState s, {Duration? debugSpacing}) {
  final hour = reminderHour(s.playHours);
  final mission = s.nextMission;
  final gear = s.affordableGear;

  PlannedReminder? make(int slot, ReminderKind kind, DateTime at) => switch (kind) {
        ReminderKind.streak => s.dailyDoneToday && s.dailyStreak >= kReminderStreakMin && slot == 0
            ? PlannedReminder(
                id: slot,
                at: at,
                kind: kind,
                title: 'OPS · ${s.dailyStreak}-day streak',
                body: "Fly today's dispatch to keep your streak alive.",
              )
            : null,
        ReminderKind.daily => PlannedReminder(
            id: slot,
            at: at,
            kind: kind,
            title: 'OPS · Daily dispatch',
            body: 'A new relief run is posted. One flight, today only.',
          ),
        ReminderKind.gear => gear == null
            ? null
            : PlannedReminder(
                id: slot,
                at: at,
                kind: kind,
                title: 'OPS · Hangar note',
                body: 'You have the coins for the $gear. The Garage is holding it for you.',
              ),
        ReminderKind.mission => mission == null
            ? null
            : PlannedReminder(
                id: slot,
                at: at,
                kind: kind,
                title: '${mission.from} · ${mission.cargo}',
                body: mission.brief,
              ),
      };

  const preference = [
    [ReminderKind.streak, ReminderKind.daily, ReminderKind.mission],
    [ReminderKind.gear, ReminderKind.mission, ReminderKind.daily],
    [ReminderKind.mission, ReminderKind.daily],
  ];

  final out = <PlannedReminder>[];
  final used = <ReminderKind>{};
  for (var slot = 0; slot < kReminderDays.length; slot++) {
    final at = debugSpacing != null
        ? s.now.add(debugSpacing * (slot + 1))
        : DateTime(s.now.year, s.now.month, s.now.day + kReminderDays[slot], hour);
    PlannedReminder? pick;
    // An unused kind first, then any that fits.
    for (final fresh in [true, false]) {
      for (final kind in preference[slot]) {
        if (fresh && used.contains(kind)) continue;
        pick = make(slot, kind, at);
        if (pick != null) break;
      }
      if (pick != null) break;
    }
    if (pick == null) continue;
    used.add(pick.kind);
    out.add(pick);
  }
  return out;
}

/// Whether to show the in-game "radio calls?" question: never once answered,
/// only after the player has something to come back for, at most
/// [kReminderMaxAsks] times, [kReminderAskGap] apart.
bool shouldAskForReminders({
  required bool? enabled,
  required bool engaged,
  required int asks,
  required int lastAskMs,
  required int nowMs,
}) {
  if (enabled != null || !engaged) return false;
  if (asks >= kReminderMaxAsks) return false;
  return asks == 0 || nowMs - lastAskMs >= kReminderAskGap.inMilliseconds;
}

const kReminderMaxAsks = 2;
const kReminderAskGap = Duration(days: 7);
