import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/contracts_service.dart';
import 'package:narrow_haul/game/services/error_reporter.dart';
import 'package:narrow_haul/game/services/garage_notices.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/reminder_plan.dart';
import 'package:narrow_haul/game/story/story.dart';
import 'package:timezone/timezone.dart' as tz;

/// Return reminders as local notifications (Android/iOS only, no server).
/// Opt-in: nothing is scheduled until the player says yes to the in-game
/// question or turns *Reminders* on in Settings. Every app open and every
/// trip to the background cancels what's pending and schedules the plan
/// again from the current state ([planReminders]), so a reminder never
/// fires on a day the game was played and stops after the last slot.
/// Fail-safe: a plugin error only loses the reminders.
abstract final class ReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// `--dart-define=REMINDER_SECONDS=30`: fire the plan 30 s, 60 s, 90 s
  /// after the app goes to the background (device testing).
  static const _debugSeconds = int.fromEnvironment('REMINDER_SECONDS');

  static bool get supported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'Mission reminders',
    channelDescription: 'Daily dispatch, streaks and the next relief run',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    icon: 'ic_launcher_monochrome',
  );
  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(),
  );

  /// Once in `main()` after the save is loaded: notes the hour, picks up a
  /// launch from a reminder and refreshes the schedule.
  static Future<void> init() async {
    if (!supported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_launcher_monochrome'),
          // The OS prompt comes only from [enable], after the player said yes.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => _opened(r.payload),
      );
      _ready = true;
      _log('ready (enabled=${ProgressService.instance.remindersEnabled})');
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _opened(launch?.notificationResponse?.payload);
      }
      await onForeground();
    } catch (e, st) {
      _log('init failed: $e');
      ErrorReporter.report(e, st, context: 'reminders init');
    }
  }

  static void _opened(String? kind) {
    if (kind != null) Analytics.reminderOpened(kind);
  }

  /// App opened or resumed: the player is here, so note the hour and
  /// schedule from now.
  static Future<void> onForeground() async {
    if (!_ready) return;
    await ProgressService.instance.recordSessionHour(DateTime.now().hour);
    await reschedule();
  }

  /// Cancels every pending reminder and, if they're on, schedules the plan
  /// for the current state.
  static Future<void> reschedule() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (ProgressService.instance.remindersEnabled != true) {
        _log('reschedule: off (enabled=${ProgressService.instance.remindersEnabled})');
        return;
      }
      final plan = planReminders(
        _state(),
        debugSpacing: _debugSeconds > 0 ? const Duration(seconds: _debugSeconds) : null,
      );
      for (final r in plan) {
        await _plugin.zonedSchedule(
          id: r.id,
          scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
          notificationDetails: _details,
          // Inexact: no exact-alarm permission, the OS batches it.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: r.title,
          body: r.body,
          payload: r.kind.name,
        );
        _log('scheduled #${r.id} ${r.kind.name} at ${r.at} "${r.title}"');
      }
    } catch (e, st) {
      _log('schedule failed: $e');
      ErrorReporter.report(e, st, context: 'reminders schedule');
    }
  }

  static ReminderState _state() {
    final p = ProgressService.instance;
    final tried = p.reminderLastTried;
    final stalled = tried != null && p.getStarsById(tried) == 0 ? _mission(tried) : null;
    return ReminderState(
      now: DateTime.now(),
      dailyStreak: p.getDailyStreak(),
      dailyDoneToday: p.isDailyChallengeComplete(),
      affordableGear: _affordableGear(),
      contractsOpen: ContractsService.isUnlocked,
      nextMission: _nextMission(),
      stalledMission: stalled,
      stalledRouteReady: stalled != null && p.isRouteUnlocked(tried!),
      newWorld: _newWorld(),
      gate: _gate(),
      expedition: _freeExpedition(),
      playHours: p.reminderHours,
    );
  }

  /// The cheapest gear the player can buy now (rank reached, coins enough).
  static String? _affordableGear() {
    final snap = GarageNotices.current();
    String? name;
    var cost = 1 << 30;
    for (final i in snap.items) {
      if (!isGear(i) || i.supporterOnly || snap.owned.contains(i.id)) continue;
      if (i.rankRequired > snap.rankIndex || i.cost > snap.coins) continue;
      if (i.cost < cost) (name, cost) = (i.name, i.cost);
    }
    return name;
  }

  /// [saveId]'s story line, with its world's settlement and contact.
  static MissionReminder? _mission(String saveId) {
    final story = storyFor(saveId);
    final i = LevelRegistry.flat.indexWhere((d) => d.saveId == saveId);
    if (story == null || i < 0) return null;
    final world = worldStoryFor(LevelRegistry.worldOf(i).$1.id);
    return MissionReminder(
      from: story.from,
      cargo: story.cargo,
      brief: story.brief,
      place: world?.place ?? '',
      contact: world?.contact ?? '',
    );
  }

  /// The first open career mission without a star.
  static MissionReminder? _nextMission() {
    final p = ProgressService.instance;
    for (var i = 0; i < LevelRegistry.totalLevels; i++) {
      if (LevelRegistry.isExpedition(i) || !LevelRegistry.isLevelUnlocked(i)) continue;
      final id = LevelRegistry.defAt(i).saveId;
      if (p.getStarsById(id) == 0) return _mission(id);
    }
    return null;
  }

  /// A career world past the Training Grounds that's open but whose chapter
  /// card hasn't been read (the player hasn't been there).
  static WorldReminder? _newWorld() {
    for (final w in LevelRegistry.worlds.skip(1)) {
      if (w.expedition || !LevelRegistry.isWorldUnlocked(w)) continue;
      if (ProgressService.instance.storySeen('intro_${w.id}')) continue;
      final story = worldStoryFor(w.id);
      if (story == null || story.intro.isEmpty) continue;
      return WorldReminder(contact: story.contact, place: story.place, teaser: story.intro.first);
    }
    return null;
  }

  /// The next locked career world and the stars it still needs.
  static GateReminder? _gate() {
    for (final w in LevelRegistry.worlds) {
      if (w.expedition || LevelRegistry.isWorldUnlocked(w)) continue;
      return GateReminder(
        place: worldStoryFor(w.id)?.place ?? w.name,
        starsToGo: w.starsRequired - LevelRegistry.totalStars(),
      );
    }
    return null;
  }

  /// The free Expedition, once it's open and while it has no stars.
  static MissionReminder? _freeExpedition() {
    for (var i = 0; i < LevelRegistry.totalLevels; i++) {
      if (!LevelRegistry.isExpedition(i)) continue;
      final id = LevelRegistry.defAt(i).saveId;
      if (!LevelRegistry.isLevelUnlocked(i) || ProgressService.instance.getStarsById(id) > 0) {
        return null;
      }
      return _mission(id);
    }
    return null;
  }

  /// A career mission launched (not a daily or demo): a day-1 reminder can
  /// pick it up if it's still unflown.
  static void noteMissionStarted(String saveId) {
    unawaited(ProgressService.instance.setReminderLastTried(saveId));
  }

  // ── Opt-in ────────────────────────────────────────────────────────────────

  /// Show the in-game question now? (Training done or a daily flown, never
  /// answered yes/no in Settings, at most twice a week apart.) Counts the ask.
  static bool takeAsk() {
    if (!_ready) return false;
    final p = ProgressService.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ask = shouldAskForReminders(
      enabled: p.remindersEnabled,
      engaged: LevelRegistry.trainingComplete || p.getDailyStreak() > 0,
      asks: p.reminderAsks,
      lastAskMs: p.reminderAskMs,
      nowMs: now,
    );
    _log('ask? $ask (enabled=${p.remindersEnabled} asks=${p.reminderAsks} '
        'training=${LevelRegistry.trainingComplete} streak=${p.getDailyStreak()})');
    if (ask) unawaited(p.recordReminderAsk(now));
    return ask;
  }

  /// The player said yes: asks the OS (iOS once ever, Android 13+) and turns
  /// reminders on if it agrees. Returns whether they are on.
  static Future<bool> enable({required String where}) async {
    if (!_ready) return false;
    var granted = false;
    try {
      if (Platform.isIOS) {
        granted = await _plugin
                .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, sound: true) ??
            false;
      } else {
        granted = await _plugin
                .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            false;
      }
    } catch (e, st) {
      _log('permission failed: $e');
      ErrorReporter.report(e, st, context: 'reminders permission');
    }
    _log('permission granted=$granted ($where)');
    await ProgressService.instance.setRemindersEnabled(granted);
    Analytics.reminderOptIn(on: true, where: where, granted: granted);
    await reschedule();
    return granted;
  }

  /// Settings switched them off: nothing pending, nothing new.
  static Future<void> disable() async {
    await ProgressService.instance.setRemindersEnabled(false);
    Analytics.reminderOptIn(on: false, where: 'settings');
    await reschedule();
  }
}

/// Debug and profile builds log every reminder decision.
void _log(String message) {
  if (!kReleaseMode) debugPrint('ReminderService: $message');
}
