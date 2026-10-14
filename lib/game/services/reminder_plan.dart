// Return reminders: what to say and when (pure Dart, no plugin, no prefs).
// ReminderService turns the plan into local notifications; the rules live
// here so tests can check them without a device.
//
// Reminders are radio traffic from the Narrows: each slot has a job (pick up
// where you left off, something new you've earned, the story, a soft last
// call), and the text comes from story the player has already reached (the
// next mission's brief, the opening line of a world they've unlocked). Never
// a debrief or a world's ending, never a purchase.

/// What a reminder is about. The name goes into analytics.
enum ReminderKind {
  streak,
  stalled,
  mission,
  newWorld,
  gate,
  gear,
  contracts,
  daily,
  expedition,
  farewell,
}

/// The player's state when the app opens or goes to the background.
class ReminderState {
  const ReminderState({
    required this.now,
    this.dailyStreak = 0,
    this.dailyDoneToday = false,
    this.affordableGear,
    this.contractsOpen = false,
    this.nextMission,
    this.stalledMission,
    this.stalledRouteReady = false,
    this.newWorld,
    this.gate,
    this.expedition,
    this.playHours = const [],
  });

  final DateTime now;
  final int dailyStreak;
  final bool dailyDoneToday;

  /// The cheapest tow gear or handling kit the player can buy right now.
  final String? affordableGear;

  /// Relief requests (contracts) are unlocked: three new ones every day.
  final bool contractsOpen;

  /// The next career mission, null when every one is flown.
  final MissionReminder? nextMission;

  /// The mission the player last launched and hasn't cleared yet.
  final MissionReminder? stalledMission;

  /// Its route guide is unlocked.
  final bool stalledRouteReady;

  /// A world the player has unlocked but never entered.
  final WorldReminder? newWorld;

  /// The next locked world, when it's at most [kReminderGateStars] away.
  final GateReminder? gate;

  /// The free Expedition, while it has no stars.
  final MissionReminder? expedition;

  /// Hours (0–23) of recent session starts, newest last.
  final List<int> playHours;
}

/// A mission's radio line (from its `LevelStory`) and where it is.
class MissionReminder {
  const MissionReminder({
    required this.from,
    required this.cargo,
    required this.brief,
    this.place = '',
    this.contact = '',
  });

  /// Who says the brief (a callsign).
  final String from;
  final String cargo;
  final String brief;

  /// The world's settlement and its radio contact (`WorldStory`).
  final String place;
  final String contact;
}

class WorldReminder {
  const WorldReminder({required this.contact, required this.place, required this.teaser});
  final String contact;
  final String place;

  /// The first line of the world's intro.
  final String teaser;
}

class GateReminder {
  const GateReminder({required this.place, required this.starsToGo});
  final String place;
  final int starsToGo;
}

class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.kind,
    required this.title,
    required this.body,
  });

  /// Notification id: the slot, so a reschedule replaces it.
  final int id;
  final DateTime at;
  final ReminderKind kind;
  final String title;
  final String body;
}

/// Days after the last session that each reminder fires; then nothing until
/// the player comes back (the next open plans again from there).
const kReminderDays = [1, 3, 7, 14];

/// Reminders go out at the player's usual hour, never earlier or later.
const kReminderEarliestHour = 10;
const kReminderLatestHour = 21;
const kReminderDefaultHour = 18;

/// A streak this long is worth a nudge to keep it.
const kReminderStreakMin = 3;

/// A locked world this close is worth a nudge.
const kReminderGateStars = 3;

/// Each slot's job, as kinds in order of preference.
const _slotKinds = [
  // Day 1: pick up where you left off.
  [ReminderKind.streak, ReminderKind.stalled, ReminderKind.daily, ReminderKind.mission],
  // Day 3: something new you've earned.
  [
    ReminderKind.newWorld,
    ReminderKind.gate,
    ReminderKind.gear,
    ReminderKind.contracts,
    ReminderKind.daily,
    ReminderKind.mission,
  ],
  // Day 7: the story pulls you back.
  [ReminderKind.mission, ReminderKind.expedition, ReminderKind.daily],
  // Day 14: one soft last call, only while the story has somewhere to go.
  [ReminderKind.farewell],
];

/// The hour to send at: the median of recent session starts, clamped to
/// waking hours.
int reminderHour(List<int> playHours) {
  if (playHours.isEmpty) return kReminderDefaultHour;
  final sorted = [...playHours]..sort();
  return sorted[sorted.length ~/ 2].clamp(kReminderEarliestHour, kReminderLatestHour);
}

/// One reminder per slot in [kReminderDays], each about something different
/// where possible. [debugSpacing] (device testing) fires slot k at
/// (k + 1) × spacing from now instead.
List<PlannedReminder> planReminders(ReminderState s, {Duration? debugSpacing}) {
  final hour = reminderHour(s.playHours);
  final out = <PlannedReminder>[];
  final used = <ReminderKind>{};
  for (var slot = 0; slot < kReminderDays.length; slot++) {
    final at = debugSpacing != null
        ? s.now.add(debugSpacing * (slot + 1))
        : DateTime(s.now.year, s.now.month, s.now.day + kReminderDays[slot], hour);
    (String, String)? text;
    ReminderKind? kind;
    // An unused kind first, then any that fits, but never the same words twice.
    for (final fresh in [true, false]) {
      for (final k in _slotKinds[slot]) {
        if (fresh && used.contains(k)) continue;
        // A repeated kind tries its other wording.
        for (var variant = 0; variant < 2 && kind == null; variant++) {
          final t = _text(s, k, slot, at, variant);
          if (t == null || out.any((r) => r.title == t.$1 && r.body == t.$2)) continue;
          (text, kind) = (t, k);
        }
        if (kind != null) break;
      }
      if (kind != null) break;
    }
    if (kind == null || text == null) continue;
    used.add(kind);
    out.add(PlannedReminder(id: slot, at: at, kind: kind, title: text.$1, body: text.$2));
  }
  return out;
}

/// Title and body for [kind], or null when it doesn't apply. Kinds with
/// several wordings pick one by date (so a regular doesn't see the same line
/// every time), shifted by [variant] when that line is already in the plan.
(String, String)? _text(ReminderState s, ReminderKind kind, int slot, DateTime at, int variant) {
  String pick(List<String> lines) => lines[(at.day + at.month * 31 + variant) % lines.length];
  switch (kind) {
    case ReminderKind.streak:
      final n = s.dailyStreak;
      if (slot != 0 || !s.dailyDoneToday || n < kReminderStreakMin) return null;
      return (
        'OPS · $n-day streak',
        pick([
          "Today's dispatch keeps it alive. One flight.",
          'One dispatch today and the streak holds at ${n + 1}.',
        ]),
      );
    case ReminderKind.stalled:
      final m = s.stalledMission;
      if (m == null) return null;
      return (
        '${m.from} · ${m.cargo}',
        s.stalledRouteReady
            ? 'Still waiting on that run, pilot. The route guide is ready when you are.'
            : pick([
                "Still waiting on that run, pilot. Tank's full for another try.",
                m.brief,
              ]),
      );
    case ReminderKind.mission:
      final m = s.nextMission;
      if (m == null) return null;
      return ('${m.from} · ${m.cargo}', m.brief);
    case ReminderKind.newWorld:
      final w = s.newWorld;
      if (w == null) return null;
      return ('${w.contact} · ${w.place}', w.teaser);
    case ReminderKind.gate:
      final g = s.gate;
      if (g == null || g.starsToGo < 1 || g.starsToGo > kReminderGateStars) return null;
      final stars = g.starsToGo == 1 ? '1 star' : '${g.starsToGo} stars';
      return (
        'OPS · $stars to ${g.place}',
        pick([
          'Fly a cleared mission again on less fuel and ${g.place} opens.',
          'A better score on any cleared mission and ${g.place} opens up.',
        ]),
      );
    case ReminderKind.gear:
      final gear = s.affordableGear;
      if (gear == null) return null;
      return (
        'OPS · Hangar note',
        pick([
          'You have the coins for the $gear. The Garage is holding it for you.',
          'The $gear is in reach. The Garage is holding it for you.',
        ]),
      );
    case ReminderKind.contracts:
      if (!s.contractsOpen) return null;
      return (
        'OPS · Relief requests',
        pick([
          'Three new requests on the board. Bonus XP for all three.',
          'New relief requests are up. Clear all three for a bonus.',
        ]),
      );
    case ReminderKind.daily:
      return (
        'OPS · Daily dispatch',
        pick([
          'A new relief run is posted. One flight, today only.',
          "Today's dispatch is up: one run, one twist, today only.",
        ]),
      );
    case ReminderKind.expedition:
      final e = s.expedition;
      if (e == null) return null;
      return ('${e.from} · ${e.cargo}', 'Expedition: ${e.brief}');
    case ReminderKind.farewell:
      final m = s.nextMission;
      if (m == null || m.place.isEmpty) return null;
      final who = m.contact.isEmpty ? 'OPS' : m.contact;
      return (
        '$who · ${m.place}',
        pick([
          '${m.place} is holding your next run: ${m.cargo}.',
          'The Narrows still need pilots. ${m.cargo} is waiting at ${m.place}.',
        ]),
      );
  }
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
