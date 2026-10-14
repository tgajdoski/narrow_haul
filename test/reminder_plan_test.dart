import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/reminder_plan.dart';

void main() {
  final now = DateTime(2026, 10, 14, 20, 30);
  const mission = MissionReminder(
    from: 'OPS',
    cargo: 'Rations',
    brief: 'Supply run through the switchbacks for the outer dorms.',
  );

  group('planReminders', () {
    test('three reminders on days 1, 3 and 7, never today', () {
      final plan = planReminders(ReminderState(now: now, nextMission: mission));
      expect(plan.map((r) => r.id), [0, 1, 2]);
      expect(plan.map((r) => r.at.day), [15, 17, 21]);
      for (final r in plan) {
        expect(r.at.isAfter(now), isTrue);
        expect(r.at.day, isNot(now.day));
      }
    });

    test('goes out at the usual play hour, clamped to waking hours', () {
      expect(reminderHour(const []), kReminderDefaultHour);
      expect(reminderHour(const [19, 20, 20, 21, 9]), 20);
      expect(reminderHour(const [23, 0, 1, 23]), kReminderLatestHour);
      expect(reminderHour(const [6, 7, 7]), kReminderEarliestHour);
      final plan = planReminders(ReminderState(now: now, playHours: const [13, 13, 14]));
      expect(plan.every((r) => r.at.hour == 13 && r.at.minute == 0), isTrue);
    });

    test('a long streak flown today gets the streak nudge first', () {
      final plan = planReminders(ReminderState(
        now: now,
        dailyStreak: 5,
        dailyDoneToday: true,
        nextMission: mission,
      ));
      expect(plan.first.kind, ReminderKind.streak);
      expect(plan.first.title, contains('5-day'));
    });

    test('no streak nudge for a short streak or one not flown today', () {
      for (final s in [
        ReminderState(now: now, dailyStreak: 2, dailyDoneToday: true),
        ReminderState(now: now, dailyStreak: 6),
      ]) {
        expect(planReminders(s).first.kind, ReminderKind.daily);
      }
    });

    test('each slot says something different when it can', () {
      final plan = planReminders(ReminderState(
        now: now,
        affordableGear: 'Tow Chain',
        nextMission: mission,
      ));
      expect(plan.map((r) => r.kind), [ReminderKind.daily, ReminderKind.gear, ReminderKind.mission]);
      expect(plan[1].body, contains('Tow Chain'));
      expect(plan[2].title, 'OPS · Rations');
      expect(plan[2].body, mission.brief);
    });

    test('without gear the next mission comes earlier and again on day 7', () {
      final plan = planReminders(ReminderState(now: now, nextMission: mission));
      expect(plan.map((r) => r.kind), [ReminderKind.daily, ReminderKind.mission, ReminderKind.mission]);
    });

    test('every mission flown: daily reminders only', () {
      final plan = planReminders(ReminderState(now: now));
      expect(plan, hasLength(3));
      expect(plan.every((r) => r.kind == ReminderKind.daily), isTrue);
    });

    test('debug spacing fires within seconds', () {
      final plan = planReminders(
        ReminderState(now: now, nextMission: mission),
        debugSpacing: const Duration(seconds: 30),
      );
      expect(plan.map((r) => r.at.difference(now).inSeconds), [30, 60, 90]);
    });

    test('a month end rolls over', () {
      final plan = planReminders(ReminderState(now: DateTime(2026, 10, 30, 9)));
      expect(plan.map((r) => (r.at.month, r.at.day)), [(10, 31), (11, 2), (11, 6)]);
    });
  });

  group('shouldAskForReminders', () {
    const week = Duration(days: 7);
    final t = DateTime(2026, 10, 14).millisecondsSinceEpoch;

    bool ask({bool? enabled, bool engaged = true, int asks = 0, int lastAskMs = 0, int? nowMs}) =>
        shouldAskForReminders(
          enabled: enabled,
          engaged: engaged,
          asks: asks,
          lastAskMs: lastAskMs,
          nowMs: nowMs ?? t,
        );

    test('asks once the player is engaged and has not answered', () {
      expect(ask(), isTrue);
      expect(ask(engaged: false), isFalse);
      expect(ask(enabled: true), isFalse);
      expect(ask(enabled: false), isFalse);
    });

    test('a "not now" is asked again only after a week, and only once', () {
      expect(ask(asks: 1, lastAskMs: t - week.inMilliseconds + 1), isFalse);
      expect(ask(asks: 1, lastAskMs: t - week.inMilliseconds), isTrue);
      expect(ask(asks: kReminderMaxAsks, lastAskMs: 0), isFalse);
    });
  });
}
