import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:games_services/games_services.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/cloud_save.dart';
import 'package:narrow_haul/game/services/dispatch.dart';
import 'package:narrow_haul/game/services/error_reporter.dart';
import 'package:narrow_haul/game/services/games_ids.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/env.dart';

/// What [GamesService] needs from Play Games / Game Center. The real one is
/// [PluginGamesBackend]; tests pass a fake.
abstract class GamesBackend {
  /// Signs in (silently where the platform allows). True when signed in.
  Future<bool> signIn();
  Future<void> unlockAchievement(String localId);
  Future<void> submitStars(int stars);

  /// The saved data, or null when there is no save in [slot] yet. Throws
  /// when the cloud can't be reached (the sync then stops: an offline new
  /// phone must never overwrite the cloud with its empty save).
  Future<String?> loadSave(String slot);
  Future<void> writeSave(String slot, String data);
  Future<void> showAchievements();
  Future<void> showLeaderboard();

  /// A Daily dispatch delivered in [ms] by a pilot at stage [tier] (each
  /// stage has its own board; the platform keeps the best of the day).
  Future<void> submitDailyTime(DispatchTier tier, int ms);

  /// Today's board of [tier].
  Future<void> showDailyLeaderboard(DispatchTier tier);
}

/// Play Games Services (Android) and Game Center (iOS): sign-in, mirrored
/// achievements, the total-stars leaderboard and the cloud save
/// ([CloudSave] rules). Fail-safe like the other services: every call is
/// caught, and the game never waits on it.
class GamesService {
  GamesService._();

  /// Android/iOS release and profile builds; never under `flutter test`.
  static bool get supported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      !kInFlutterTest;

  static String get platformName =>
      !kIsWeb && Platform.isIOS ? 'Game Center' : 'Play Games';

  static GamesBackend? _backend;
  static final ValueNotifier<bool> signedIn = ValueNotifier(false);

  /// Runs after a cloud merge changed this device's save (the game redraws
  /// the hangar).
  static VoidCallback? onSaveMerged;

  /// Epoch ms; tests fix it.
  static int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  /// Uploads closer together than this wait (a pause always uploads).
  static const uploadGap = Duration(seconds: 45);

  static Future<void>? _sync;
  static bool _syncAgain = false;
  static int _lastUploadMs = 0;

  /// Signs in and catches up: achievements earned offline, the stars
  /// score, and the cloud save. [backend] is for tests.
  static Future<void> init({GamesBackend? backend}) async {
    if (backend == null && !supported) return;
    _backend = backend ?? PluginGamesBackend();
    try {
      signedIn.value = await _backend!.signIn();
    } catch (e, st) {
      _report(e, st, 'sign-in');
      signedIn.value = false;
    }
    if (!signedIn.value) return;
    await sync(force: true);
  }

  /// Interactive sign-in from Settings (after the player declined or it
  /// failed at start).
  static Future<bool> signIn() async {
    if (_backend == null) return false;
    try {
      signedIn.value = await _backend!.signIn();
    } catch (e, st) {
      _report(e, st, 'sign-in');
    }
    if (signedIn.value) await sync(force: true);
    return signedIn.value;
  }

  /// A new local unlock (from [AchievementService.unlock]).
  static void achievementUnlocked(String id) {
    if (!signedIn.value) return;
    unawaited(_guard('unlock $id', () => _backend!.unlockAchievement(id)));
  }

  /// After a delivery: the leaderboard and (throttled) the cloud save.
  static void progressChanged() {
    if (!signedIn.value) return;
    unawaited(sync());
  }

  /// App backgrounded: upload now, whatever the throttle says.
  static void appPaused() {
    if (!signedIn.value) return;
    unawaited(sync(force: true));
  }

  /// Merges the cloud save into this device, uploads the result, and
  /// pushes achievements and the stars score. One run at a time; a call
  /// during a run schedules one more.
  static Future<void> sync({bool force = false}) async {
    if (!signedIn.value || _backend == null) return;
    if (!force && now() - _lastUploadMs < uploadGap.inMilliseconds) return;
    if (_sync != null) {
      _syncAgain = true;
      return _sync;
    }
    _sync = _run();
    try {
      await _sync;
    } finally {
      _sync = null;
    }
    if (_syncAgain) {
      _syncAgain = false;
      await sync(force: true);
    }
  }

  static Future<void> _run() async {
    final progress = ProgressService.instance;
    final backend = _backend!;
    await _guard('cloud save', () async {
      final local = progress.exportSynced();
      Map<String, Object> merged;
      if (progress.cloudOverwritePending) {
        merged = local;
      } else {
        final raw = await backend.loadSave(CloudSave.slot);
        final cloud = CloudSave.decode(raw);
        merged = cloud == null
            ? local
            : CloudSave.merge(
                local: local,
                cloud: cloud,
                base: progress.cloudBase,
              );
        final changed = CloudSave.changes(local, merged);
        if (changed.isNotEmpty) {
          await progress.importSynced(changed);
          onSaveMerged?.call();
        }
      }
      final at = now();
      await backend.writeSave(
        CloudSave.slot,
        CloudSave.encode(merged, atMs: at),
      );
      _lastUploadMs = at;
      await progress.setCloudBase(merged, atMs: at);
      await progress.clearCloudOverwrite();
    });
    for (final id in AchievementService.unlocked) {
      await _guard('unlock $id', () => backend.unlockAchievement(id));
    }
    await _guard('stars', () => backend.submitStars(totalStars()));
  }

  /// Career stars, the leaderboard's score (set by the game, which knows
  /// the level list).
  static int Function() totalStars = () => 0;

  /// A Daily dispatch delivered: its time goes on the stage's board.
  static void dailyDelivered(DispatchTier tier, double seconds) {
    if (!signedIn.value) return;
    final ms = (seconds * 1000).round();
    unawaited(_guard('daily time', () => _backend!.submitDailyTime(tier, ms)));
  }

  /// Whether today's board can open (signed in, and the board exists on
  /// this platform).
  static bool dailyBoardAvailable(DispatchTier tier) =>
      signedIn.value &&
      _backend != null &&
      (kIsWeb || !Platform.isAndroid || (kPlayDailyLeaderboards[tier.name] ?? '').isNotEmpty);

  static Future<void> showDailyLeaderboard(DispatchTier tier) =>
      _guard('show daily board', () => _backend!.showDailyLeaderboard(tier));

  static Future<void> showAchievements() =>
      _guard('show achievements', () => _backend!.showAchievements());

  static Future<void> showLeaderboard() =>
      _guard('show leaderboard', () => _backend!.showLeaderboard());

  static Future<void> _guard(String what, Future<void> Function() f) async {
    if (_backend == null) return;
    try {
      await f();
    } catch (e, st) {
      _report(e, st, what);
    }
  }

  static void _report(Object e, StackTrace st, String what) {
    // A player who isn't signed in, or is offline, is normal: log it in
    // development, report only the unexpected.
    if (e is PlatformException) {
      debugPrint('GamesService: $what failed: ${e.code} ${e.message}');
      return;
    }
    ErrorReporter.report(e, st, context: 'GamesService $what');
  }

  @visibleForTesting
  static void debugReset() {
    _backend = null;
    signedIn.value = false;
    _sync = null;
    _syncAgain = false;
    _lastUploadMs = 0;
    onSaveMerged = null;
  }
}

/// [GamesBackend] on the `games_services` plugin.
class PluginGamesBackend implements GamesBackend {
  @override
  Future<bool> signIn() async {
    await GamesServices.signIn();
    return GamesServices.isSignedIn;
  }

  @override
  Future<void> unlockAchievement(String localId) async {
    final play = kPlayAchievementIds[localId];
    if (Platform.isAndroid && play == null) return;
    await GamesServices.unlock(
      achievement: Achievement(
        androidID: play ?? '',
        iOSID: gameCenterAchievementId(localId),
        // The game shows its own toast.
        showsCompletionBanner: false,
      ),
    );
  }

  @override
  Future<void> submitStars(int stars) async {
    if (Platform.isAndroid && kStarsLeaderboardPlay.isEmpty) return;
    await GamesServices.submitScore(
      score: Score(
        androidLeaderboardID: kStarsLeaderboardPlay,
        iOSLeaderboardID: kStarsLeaderboardGameCenter,
        value: stars,
      ),
    );
  }

  @override
  Future<String?> loadSave(String slot) async {
    // Loading a missing save is an error, like being offline: list first.
    final saves = await GamesServices.getSavedGames(
      forceRefresh: true,
      ignoreImages: true,
    );
    if (saves == null) {
      throw PlatformException(code: 'offline', message: 'no saved games list');
    }
    if (!saves.any((s) => s.name == slot)) return null;
    return GamesServices.loadGame(name: slot);
  }

  @override
  Future<void> writeSave(String slot, String data) async {
    Uint8List? cover;
    try {
      cover = (await rootBundle.load('assets/ship.png')).buffer.asUint8List();
    } catch (_) {}
    await SaveGame.saveGame(
      data: data,
      name: slot,
      coverImage: cover,
      description: 'Narrow Haul career',
    );
  }

  @override
  Future<void> showAchievements() => GamesServices.showAchievements();

  @override
  Future<void> showLeaderboard() => GamesServices.showLeaderboards(
    androidLeaderboardID: kStarsLeaderboardPlay,
    iOSLeaderboardID: kStarsLeaderboardGameCenter,
  );

  @override
  Future<void> submitDailyTime(DispatchTier tier, int ms) async {
    final play = kPlayDailyLeaderboards[tier.name] ?? '';
    if (Platform.isAndroid && play.isEmpty) return;
    await GamesServices.submitScore(
      score: Score(
        androidLeaderboardID: play,
        iOSLeaderboardID: gameCenterDailyLeaderboard(tier.name),
        // Play's time format is milliseconds; Game Center's finest elapsed
        // time format is hundredths.
        value: Platform.isIOS ? (ms / 10).round() : ms,
      ),
    );
  }

  @override
  Future<void> showDailyLeaderboard(DispatchTier tier) => GamesServices.showLeaderboards(
    androidLeaderboardID: kPlayDailyLeaderboards[tier.name] ?? '',
    iOSLeaderboardID: gameCenterDailyLeaderboard(tier.name),
    timeScope: TimeScope.today,
  );
}
