import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/firebase_options.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/error_reporter.dart';
import 'package:narrow_haul/game/services/games_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';

// Start-up work that main() kicks off: licences, Firebase, and the ad /
// store / games services once the first-launch credits are gone.

/// Licences for bundled assets that don't come from a package, shown in
/// Settings → Licenses.
void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'RussoOne',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Music'],
      'Music and level-start sound: "Space Music Pack" by Goose Ninja '
      '(https://gooseninja.itch.io/space-music-pack). Additional music by '
      'maksymmalko, paulyudin, starostin and tatamusic via Pixabay '
      '(Pixabay Content License).',
    );
  });
}

/// Ads, the store and Play Games / Game Center, once the first-launch
/// credits are gone.
void startServicesAfterCredits(NarrowHaulGame game) {
  final credits = game.creditsVisible;
  if (!credits.value) {
    unawaited(MonetizationService.instance.init());
    unawaited(GamesService.init());
    return;
  }
  var started = false;
  late final VoidCallback listener;
  void start() {
    if (started) return;
    started = true;
    credits.removeListener(listener);
    unawaited(MonetizationService.instance.init());
    // Play Games / Game Center sign-in (its welcome banner or sign-in sheet
    // also waits for the credits).
    unawaited(GamesService.init());
  }

  listener = () {
    if (!credits.value) start();
  };
  credits.addListener(listener);
  // Safety net: the credits never take this long.
  Timer(const Duration(seconds: 20), start);
}

/// Firebase (Android / iOS only). Crashlytics: native crashes are captured by
/// the SDK, Dart errors arrive through [ErrorReporter.sink]. Analytics:
/// installs, retention and purchases are automatic, gameplay events come
/// through [Analytics.sink]. Both are off in debug builds so development runs
/// don't fill the dashboards. Capped at 5 s so the game always starts
/// (offline it's local and quick; on a time-out reports just stay off).
Future<void> initFirebase() async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
  try {
    await _connectFirebase().timeout(const Duration(seconds: 5));
  } catch (e, st) {
    ErrorReporter.report(e, st, context: 'firebase init');
  }
}

/// Crash reports and analytics go to the live Firebase project only from
/// release builds (profile builds are playtests: they'd skew the
/// dashboards). `--dart-define=FIREBASE_COLLECT=true` turns them on in a
/// profile build, e.g. for a DebugView check.
const bool _firebaseCollect =
    kReleaseMode || bool.fromEnvironment('FIREBASE_COLLECT');

Future<void> _connectFirebase() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(_firebaseCollect);
  ErrorReporter.sink = (error, stack, context) => crashlytics.recordError(
    error,
    stack,
    reason: context,
    fatal: context == 'uncaught',
  );
  final analytics = FirebaseAnalytics.instance;
  await analytics.setAnalyticsCollectionEnabled(_firebaseCollect);
  Analytics.sink = (name, params) =>
      analytics.logEvent(name: name, parameters: params);
  Analytics.userPropertySink = (name, value) =>
      analytics.setUserProperty(name: name, value: value);
}
