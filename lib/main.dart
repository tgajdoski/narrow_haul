import 'dart:io' show Platform;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/firebase_options.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/error_reporter.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/ui/career_overlays.dart';
import 'package:narrow_haul/ui/delivered_by_screen.dart';
import 'package:narrow_haul/ui/fonts.dart';
import 'package:narrow_haul/ui/garage_overlay.dart';
import 'package:narrow_haul/ui/level_select_overlay.dart';
import 'package:narrow_haul/ui/menu_overlay.dart';
import 'package:narrow_haul/ui/mission_briefing.dart';
import 'package:narrow_haul/ui/pause_settings_overlays.dart';
import 'package:narrow_haul/ui/result_overlays.dart';
import 'package:narrow_haul/ui/route_guide_overlays.dart';
import 'package:narrow_haul/ui/space_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorReporter.install();
  await _initFirebase();
  // The bundled title font's licence, shown in Settings → Licenses.
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
  // Point the global Flame image cache at assets/ (not the default assets/images/).
  Flame.images.prefix = 'assets/';
  await ProgressService.init();
  try {
    await CareerService.migrateIfNeeded();
  } catch (e, st) {
    // A failed XP backfill must not keep the game from starting.
    ErrorReporter.report(e, st, context: 'save_v3 migration');
  }
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final game = NarrowHaulGame();
  runApp(_NarrowHaulApp(game: game));
  // After runApp: the UMP consent form needs a live UI. Never blocks play.
  MonetizationService.instance.init();
}

/// Firebase (Android / iOS only). Crashlytics: native crashes are captured by
/// the SDK, Dart errors arrive through [ErrorReporter.sink]. Analytics:
/// installs, retention and purchases are automatic, gameplay events come
/// through [Analytics.sink]. Both are off in debug builds so development runs
/// don't fill the dashboards.
Future<void> _initFirebase() async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
    ErrorReporter.sink = (error, stack, context) => crashlytics.recordError(
      error,
      stack,
      reason: context,
      fatal: context == 'uncaught',
    );
    final analytics = FirebaseAnalytics.instance;
    await analytics.setAnalyticsCollectionEnabled(!kDebugMode);
    Analytics.sink = (name, params) =>
        analytics.logEvent(name: name, parameters: params);
    Analytics.userPropertySink = (name, value) =>
        analytics.setUserProperty(name: name, value: value);
  } catch (e, st) {
    ErrorReporter.report(e, st, context: 'firebase init');
  }
}

/// Dark theme; display/headline/title styles use the bundled RussoOne face
/// (titles only — body text stays on the platform font for legibility).
ThemeData _theme() {
  final base = ThemeData.dark().copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: SpaceColors.cyan,
      brightness: Brightness.dark,
    ),
  );
  TextStyle? display(TextStyle? s) => s?.copyWith(fontFamily: kDisplayFont);
  final t = base.textTheme;
  return base.copyWith(
    textTheme: t.copyWith(
      displayLarge: display(t.displayLarge),
      displayMedium: display(t.displayMedium),
      displaySmall: display(t.displaySmall),
      headlineLarge: display(t.headlineLarge),
      headlineMedium: display(t.headlineMedium),
      headlineSmall: display(t.headlineSmall),
      titleLarge: display(t.titleLarge),
      titleMedium: display(t.titleMedium),
    ),
  );
}

class _NarrowHaulApp extends StatelessWidget {
  const _NarrowHaulApp({required this.game});
  final NarrowHaulGame game;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // The HUD (drawn by Flame) keeps clear of the notch / home indicator.
        game.setSafeInsets(mq.viewPadding);
        // Large system font sizes would overflow buttons on short landscape
        // phones; allow some scaling, not unlimited.
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
          ),
          child: child!,
        );
      },
      // Android back steps back through screens (pause mid-flight) instead of
      // closing the app; only the main menu lets it exit.
      home: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !game.handleBack()) SystemNavigator.pop();
        },
        child: Scaffold(
          backgroundColor: SpaceColors.bg,
          body: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GameWidget(
                    game: game,
                    overlayBuilderMap: {
                      'menu': (context, game) =>
                          MenuOverlay(game: game as NarrowHaulGame),
                      'levelSelect': (context, game) =>
                          LevelSelectOverlay(game: game as NarrowHaulGame),
                      'achievements': (context, game) =>
                          AchievementsOverlay(game: game as NarrowHaulGame),
                      'cosmetics': (context, game) =>
                          GarageOverlay(game: game as NarrowHaulGame),
                      'gameOver': (context, game) =>
                          GameOverOverlay(game: game as NarrowHaulGame),
                      'demo': (context, game) =>
                          DemoFlightOverlay(game: game as NarrowHaulGame),
                      'levelComplete': (context, game) =>
                          LevelCompleteOverlay(game: game as NarrowHaulGame),
                      'rankUp': (context, game) =>
                          RankUpOverlay(game: game as NarrowHaulGame),
                      'pause': (context, game) =>
                          PauseOverlay(game: game as NarrowHaulGame),
                      'settings': (context, game) =>
                          SettingsOverlay(game: game as NarrowHaulGame),
                      'pilotProfile': (context, game) =>
                          PilotLogbookOverlay(game: game as NarrowHaulGame),
                      'briefing': (context, game) =>
                          MissionBriefingOverlay(game: game as NarrowHaulGame),
                    },
                  ),
                ),
                const _AchievementToastHost(),
                // "Delivered by" credits: above everything, so on the first
                // launch they also cover the game while it loads. Always
                // positioned: a non-positioned child would size the Stack to
                // itself and collapse the GameWidget to 0×0.
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: game.creditsVisible,
                    builder: (context, visible, _) => visible
                        ? DeliveredByScreen(
                            ready: game.loaded,
                            onDone: () {
                              game.creditsVisible.value = false;
                              ProgressService.instance.markCreditsSeen();
                            },
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Achievement toast
// ─────────────────────────────────────────────────────────────────────────────

/// Slides a banner in from the top when an achievement is announced
/// mid-flight.
class _AchievementToastHost extends StatefulWidget {
  const _AchievementToastHost();

  @override
  State<_AchievementToastHost> createState() => _AchievementToastHostState();
}

class _AchievementToastHostState extends State<_AchievementToastHost> {
  AchievementMeta? _shown;
  bool _visible = false;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    AchievementService.announced.addListener(_onAnnounced);
  }

  @override
  void dispose() {
    AchievementService.announced.removeListener(_onAnnounced);
    super.dispose();
  }

  void _onAnnounced() {
    final a = AchievementService.announced.value;
    if (a == null) return;
    final token = ++_token;
    setState(() {
      _shown = a;
      _visible = true;
    });
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted && token == _token) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _shown;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: SafeArea(
          child: AnimatedSlide(
            offset: _visible ? Offset.zero : const Offset(0, -1.5),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            child: Center(
              child: a == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: HoloPanel(
                        accent: SpaceColors.gold,
                        cut: 12,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(a.icon, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'ACHIEVEMENT UNLOCKED',
                                  style: TextStyle(
                                    color: Color(0xFFFFD166),
                                    fontSize: 9,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${a.title}  ·  +100 XP',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
