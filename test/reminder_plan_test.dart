import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/reminder_plan.dart';
import 'package:narrow_haul/game/story/story.dart';
import 'package:narrow_haul/game/story/story_act1.dart';
import 'package:narrow_haul/game/story/story_act2.dart';

void main() {
  final now = DateTime(2026, 10, 14, 20, 30);
  const mission = MissionReminder(
    from: 'CRUCIBLE',
    cargo: 'Relay core',
    brief: 'Cast the relay core before the tubes flood again.',
    place: 'The Crucible',
    contact: 'CRUCIBLE',
  );
  const stalled = MissionReminder(from: 'PITHEAD', cargo: 'Pump parts', brief: 'The pumps are failing.');
  const world = WorldReminder(
    contact: 'FROSTLINE',
    place: 'Kalt Station',
    teaser: 'The ice moon that waters the Narrows.',
  );

  List<ReminderKind> kinds(List<PlannedReminder> plan) => [for (final r in plan) r.kind];

  group('planReminders', () {
    test('four reminders on days 1, 3, 7 and 14, never today', () {
      final plan = planReminders(ReminderState(now: now, nextMission: mission));
      expect(plan.map((r) => r.id), [0, 1, 2, 3]);
      expect(plan.map((r) => (r.at.month, r.at.day)), [(10, 15), (10, 17), (10, 21), (10, 28)]);
      for (final r in plan) {
        expect(r.at.isAfter(now), isTrue);
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

    test('day 1: a long streak flown today comes first', () {
      final plan = planReminders(ReminderState(
        now: now,
        dailyStreak: 5,
        dailyDoneToday: true,
        stalledMission: stalled,
        nextMission: mission,
      ));
      expect(plan.first.kind, ReminderKind.streak);
      expect(plan.first.title, 'OPS · 5-day streak');
    });

    test('day 1: no streak nudge for a short streak or one not flown today', () {
      for (final s in [
        ReminderState(now: now, dailyStreak: 2, dailyDoneToday: true),
        ReminderState(now: now, dailyStreak: 6),
      ]) {
        expect(planReminders(s).first.kind, ReminderKind.daily);
      }
    });

    test('day 1: a mission left unfinished, with the route guide when it is ready', () {
      var plan = planReminders(ReminderState(now: now, stalledMission: stalled, nextMission: mission));
      expect(plan.first.kind, ReminderKind.stalled);
      expect(plan.first.title, 'PITHEAD · Pump parts');
      plan = planReminders(ReminderState(
        now: now,
        stalledMission: stalled,
        stalledRouteReady: true,
      ));
      expect(plan.first.body, contains('route guide'));
    });

    test('day 3: a world opened but never entered beats a near gate and gear', () {
      final plan = planReminders(ReminderState(
        now: now,
        newWorld: world,
        gate: const GateReminder(place: 'The Crucible', starsToGo: 2),
        affordableGear: 'Tow Chain',
        nextMission: mission,
      ));
      expect(plan[1].kind, ReminderKind.newWorld);
      expect(plan[1].title, 'FROSTLINE · Kalt Station');
      expect(plan[1].body, world.teaser);
    });

    test('day 3: a gate only when it is close', () {
      PlannedReminder day3(int stars) => planReminders(ReminderState(
            now: now,
            gate: GateReminder(place: 'The Crucible', starsToGo: stars),
            affordableGear: 'Tow Chain',
          ))[1];
      expect(day3(1).title, 'OPS · 1 star to The Crucible');
      expect(day3(3).title, 'OPS · 3 stars to The Crucible');
      expect(day3(4).kind, ReminderKind.gear);
    });

    test('day 3: gear, then relief requests, then the daily', () {
      expect(planReminders(ReminderState(now: now, affordableGear: 'Tow Chain'))[1].body,
          contains('Tow Chain'));
      expect(planReminders(ReminderState(now: now, contractsOpen: true))[1].kind,
          ReminderKind.contracts);
      // Day 1 already used the daily: day 3 repeats it only when nothing else fits.
      expect(kinds(planReminders(ReminderState(now: now))).take(2), [ReminderKind.daily, ReminderKind.daily]);
    });

    test('day 7: the next mission in its own voice; day 14: a soft last call', () {
      final plan = planReminders(ReminderState(now: now, affordableGear: 'Tow Chain', nextMission: mission));
      expect(kinds(plan), [
        ReminderKind.daily,
        ReminderKind.gear,
        ReminderKind.mission,
        ReminderKind.farewell,
      ]);
      expect(plan[2].title, 'CRUCIBLE · Relay core');
      expect(plan[2].body, mission.brief);
      expect(plan[3].title, 'CRUCIBLE · The Crucible');
      expect(plan[3].body, contains('Relay core'));
    });

    test('every mission flown: the Expedition, then dailies, and no day-14 call', () {
      const exp = MissionReminder(from: 'GROVE', cargo: 'Seed vaults', brief: 'Three farms, one long cave.');
      final plan = planReminders(ReminderState(now: now, expedition: exp));
      expect(kinds(plan), [ReminderKind.daily, ReminderKind.daily, ReminderKind.expedition]);
      expect(plan[2].body, startsWith('Expedition: '));
      expect(planReminders(ReminderState(now: now)), hasLength(3));
    });

    test('wordings vary by date', () {
      final bodies = {
        for (var d = 0; d < 6; d++)
          planReminders(ReminderState(now: now.add(Duration(days: d)))).first.body,
      };
      expect(bodies.length, greaterThan(1));
    });

    test('every line fits a notification', () {
      final plan = planReminders(ReminderState(
        now: now,
        dailyStreak: 12,
        dailyDoneToday: true,
        newWorld: world,
        nextMission: mission,
      ));
      for (final r in plan) {
        expect(r.title.length, lessThanOrEqualTo(40), reason: r.title);
        expect(r.body.length, lessThanOrEqualTo(120), reason: r.body);
      }
    });

    test('real story lines fit too', () {
      for (final world in [...kWorldStories.values, ...kExpeditionWorldStories.values]) {
        expect('${world.contact} · ${world.place}'.length, lessThanOrEqualTo(40));
        if (world.intro.isNotEmpty) expect(world.intro.first.length, lessThanOrEqualTo(120), reason: world.place);
      }
      for (final LevelStory m in [...kLevelStories.values, ...kExpeditionStories.values]) {
        expect('${m.from} · ${m.cargo}'.length, lessThanOrEqualTo(40), reason: m.cargo);
        expect('Expedition: ${m.brief}'.length, lessThanOrEqualTo(120), reason: m.brief);
      }
    });

    test('debug spacing fires within seconds', () {
      final plan = planReminders(
        ReminderState(now: now, nextMission: mission),
        debugSpacing: const Duration(seconds: 30),
      );
      expect(plan.map((r) => r.at.difference(now).inSeconds), [30, 60, 90, 120]);
    });

    test('a month end rolls over', () {
      final plan = planReminders(ReminderState(now: DateTime(2026, 10, 30, 9), nextMission: mission));
      expect(plan.map((r) => (r.at.month, r.at.day)), [(10, 31), (11, 2), (11, 6), (11, 13)]);
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
