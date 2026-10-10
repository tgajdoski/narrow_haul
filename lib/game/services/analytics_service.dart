import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Gameplay analytics (Firebase Analytics on Android / iOS release builds).
///
/// Like [ErrorReporter], the backend plugs in through [sink] and
/// [userPropertySink]; without one (tests, desktop, debug) events are only
/// printed in debug builds. Every call fails safe. Events carry level ids and
/// numbers only, never anything personal. Firebase's recommended names are
/// used where one exists (`level_start`, `level_end`, `level_up`, …), so its
/// standard reports pick them up.
class Analytics {
  Analytics._();

  /// Forwards each event (set once by the Firebase setup in `main.dart`).
  static void Function(String name, Map<String, Object> params)? sink;

  /// Forwards each user property (null clears it).
  static void Function(String name, String? value)? userPropertySink;

  /// Events logged in this process, newest last (tests read it).
  @visibleForTesting
  static final List<(String, Map<String, Object>)> debugLog = [];

  static void log(String name, [Map<String, Object?> params = const {}]) {
    // Firebase takes only strings and numbers: bools become 0/1, doubles are
    // rounded to keep the reports readable, nulls are dropped.
    final clean = <String, Object>{
      for (final e in params.entries)
        if (e.value != null) e.key: _value(e.value!),
    };
    if (kDebugMode) {
      debugLog.add((name, clean));
      if (debugLog.length > 200) debugLog.removeAt(0);
      if (!_underTest) debugPrint('Analytics: $name $clean');
    }
    try {
      sink?.call(name, clean);
    } catch (_) {
      // Analytics must never break the game.
    }
  }

  /// `flutter test` (incl. the autopilot) keeps quiet; tests read [debugLog].
  static final bool _underTest =
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static void setUserProperty(String name, String? value) {
    try {
      userPropertySink?.call(name, value);
    } catch (_) {}
  }

  static Object _value(Object v) => switch (v) {
    bool b => b ? 1 : 0,
    double d => (d * 100).roundToDouble() / 100,
    num n => n,
    _ => v.toString().length > 100 ? v.toString().substring(0, 100) : '$v',
  };

  // ── Flights ───────────────────────────────────────────────────────────────

  /// A flight begins (fresh load, retry, next level or daily). [attempt]
  /// counts loads of this level since the player last switched levels.
  static void levelStart({
    required String levelId,
    required String world,
    required String ship,
    required String rope,
    required String mode,
    required int attempt,
    required bool guided,
  }) => log('level_start', {
    'level_name': levelId,
    'world': world,
    'ship': ship,
    'rope': rope,
    'mode': mode,
    'attempt': attempt,
    'guided': guided,
  });

  /// The ship was lost. [x]/[y] are the wreck's position in whole metres, so
  /// crash hot spots per level can be mapped from the export.
  static void levelFail({
    required String levelId,
    required String cause,
    required int attempt,
    required double seconds,
    required double fuelLeft,
    required bool towing,
    required int x,
    required int y,
    required String mode,
  }) => log('level_fail', {
    'level_name': levelId,
    'cause': cause,
    'attempt': attempt,
    'seconds': seconds,
    'fuel_left_pct': (fuelLeft * 100).round(),
    'towing': towing,
    'x': x,
    'y': y,
    'mode': mode,
  });

  /// Both ship and pod landed on the pad.
  static void levelEnd({
    required String levelId,
    required int stars,
    required int prevStars,
    required int attempt,
    required double seconds,
    required double fuelLeft,
    required bool guided,
    required bool continued,
    required bool carriedAmmo,
    required String mode,
  }) => log('level_end', {
    'level_name': levelId,
    'success': 1,
    'stars': stars,
    'first_clear': prevStars == 0,
    'new_stars': stars > prevStars ? stars - prevStars : 0,
    'attempt': attempt,
    'seconds': seconds,
    'fuel_left_pct': (fuelLeft * 100).round(),
    'guided': guided,
    'continued': continued,
    'carried_ammo': carriedAmmo,
    'mode': mode,
  });

  /// The player left a flight in progress ([reason]: `menu` or `restart`).
  static void levelQuit({
    required String levelId,
    required String reason,
    required double seconds,
    required bool launched,
  }) => log('level_quit', {
    'level_name': levelId,
    'reason': reason,
    'seconds': seconds,
    'launched': launched,
  });

  static void routeShown(String levelId) =>
      log('route_shown', {'level_name': levelId});

  static void demoWatched(String levelId) =>
      log('demo_watched', {'level_name': levelId});

  static void tutorialComplete() => log('tutorial_complete');

  static void worldUnlocked(String worldId) =>
      log('world_unlocked', {'world': worldId});

  // ── Career & economy ──────────────────────────────────────────────────────

  static void rankUp(int rankIndex, String rankTitle) =>
      log('level_up', {'level': rankIndex, 'character': rankTitle});

  static void achievement(String id) =>
      log('unlock_achievement', {'achievement_id': id});

  static void earnCoins(int amount, String source) => log(
    'earn_virtual_currency',
    {'virtual_currency_name': 'coins', 'value': amount, 'source': source},
  );

  static void spendCoins(int amount, String item) => log(
    'spend_virtual_currency',
    {'virtual_currency_name': 'coins', 'value': amount, 'item_name': item},
  );

  static void weaponUsed(String weaponId, {required bool carried}) =>
      log('weapon_used', {'weapon': weaponId, 'carried': carried});

  static void crateCollected(String weaponId) =>
      log('crate_collected', {'weapon': weaponId});

  /// A mystery salvage cache opened: what it rolled.
  static void salvageOpened(String effect, {required bool good}) =>
      log('salvage_opened', {'effect': effect, 'good': good});

  // ── Ads & purchases ───────────────────────────────────────────────────────

  static void rewardedAd(String placement, {required bool earned}) =>
      log('rewarded_ad', {'placement': placement, 'earned': earned});

  static void interstitialShown() => log('interstitial_shown');

  /// The player tapped buy (the store's own `in_app_purchase` event carries
  /// the price once it completes).
  static void purchaseAttempt(String productId) =>
      log('purchase_attempt', {'product_id': productId});

  /// What the store reported: purchased / restored / pending / canceled /
  /// error.
  static void purchaseResult(String productId, String status) =>
      log('purchase_result', {'product_id': productId, 'status': status});
}
