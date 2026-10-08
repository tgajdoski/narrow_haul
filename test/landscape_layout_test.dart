import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/route/flight_route.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/ui/career_overlays.dart';
import 'package:narrow_haul/ui/garage_overlay.dart';
import 'package:narrow_haul/ui/level_select_overlay.dart';
import 'package:narrow_haul/ui/menu_overlay.dart';
import 'package:narrow_haul/ui/pause_settings_overlays.dart';
import 'package:narrow_haul/ui/result_overlays.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Landscape phones (and an iPad) the menus must fit without overflowing.
const _sizes = [
  Size(844, 390), // iPhone 14
  Size(667, 375), // iPhone SE
  Size(568, 320), // smallest landscape we care about
  Size(1366, 1024), // iPad Pro 12.9"
];

/// Seeded mid-career save: contracts unlocked, coins, stars, awards.
Map<String, Object> _career({bool dailyDone = false}) {
  final now = DateTime.now();
  final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  return {
    for (final def in LevelRegistry.flat.take(14)) 'stars2_${def.saveId}': 3,
    'xp_total': 6000,
    'cosmetic_currency': 1240,
    'save_v2': true,
    'save_v3': true,
    'credits_seen': true,
    'achievements': ['first_haul', 'fuel_miser'],
    if (dailyDone) 'daily_$today': true,
  };
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    Size size,
    double textScale,
    Widget child,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// No vertical scroll view on [screen] has anything to scroll.
  void expectNoVerticalScroll(WidgetTester tester, String screen, Size size) {
    for (final s in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
      final p = s.position;
      if (p.axis != Axis.vertical) continue;
      expect(
        p.maxScrollExtent,
        lessThan(1),
        reason: '$screen scrolls ${p.maxScrollExtent.round()} px at $size',
      );
    }
  }

  Future<void> each(
    WidgetTester tester,
    String screen,
    Widget Function() build, {
    bool mustNotScroll = true,
  }) async {
    for (final size in _sizes) {
      for (final scale in [1.0, 1.3]) {
        await pump(tester, size, scale, build());
        expect(
          tester.takeException(),
          isNull,
          reason: '$screen at $size ×$scale',
        );
        // Tiny screens and big text may scroll as a last resort.
        if (mustNotScroll && size.height >= 360 && scale == 1.0) {
          expectNoVerticalScroll(tester, screen, size);
        }
      }
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(_career());
    await ProgressService.init();
  });

  testWidgets('hangar menu fits without scrolling', (tester) async {
    await each(tester, 'menu', () => MenuOverlay(game: NarrowHaulGame()));
    expect(find.text('LAUNCH'), findsOneWidget);
    expect(find.text('GARAGE'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
  });

  testWidgets('a flown daily shrinks to a top-bar chip', (tester) async {
    await pump(tester, _sizes.first, 1, MenuOverlay(game: NarrowHaulGame()));
    expect(find.text('DAILY'), findsOneWidget, reason: 'daily button');

    SharedPreferences.setMockInitialValues(_career(dailyDone: true));
    await ProgressService.init();
    await pump(tester, _sizes.first, 1, MenuOverlay(game: NarrowHaulGame()));
    expect(find.text('DAILY'), findsNothing, reason: 'button gone');
    expect(find.textContaining('DAILY ✓'), findsOneWidget, reason: 'chip');
  });

  testWidgets('pause fits without scrolling', (tester) async {
    await each(tester, 'pause', () => PauseOverlay(game: NarrowHaulGame()));
  });

  testWidgets('settings lays out', (tester) async {
    await each(
      tester,
      'settings',
      () => SettingsOverlay(game: NarrowHaulGame()),
      mustNotScroll: false,
    );
  });

  testWidgets('crash screen with every help option fits', (tester) async {
    final caveIndex = LevelRegistry.flat.indexWhere((d) => d is CaveLevelDef);
    final def = LevelRegistry.defAt(caveIndex);
    final json = jsonDecode(
      File('assets/routes/${def.saveId}.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    NarrowHaulGame crashed() {
      final g = NarrowHaulGame()
        ..levelIndex = caveIndex
        ..runState = RunState.gameOver
        ..currentRoute = FlightRoute.fromJson(json);
      for (var i = 0; i < 3; i++) {
        g.crashStreak.onCrash(def.saveId);
      }
      return g;
    }

    expect(crashed().canShowRoute, isTrue);
    expect(crashed().canOfferAmmo, isTrue);
    await each(tester, 'gameOver', () => GameOverOverlay(game: crashed()));
    expect(find.text('RETRY'), findsOneWidget);
    expect(find.text('SHOW ROUTE'), findsOneWidget);
  });

  testWidgets('mission complete with a long XP breakdown fits', (tester) async {
    NarrowHaulGame won() => NarrowHaulGame()
      ..levelIndex = 3
      ..runState = RunState.won
      ..lastLevelStars = 2
      ..lastLevelTimeSeconds = 74.2
      ..lastLevelFuelFraction = 0.31
      ..lastRunReward = RunReward(
        xp: const XpBreakdown([
          XpLine('First clear', 60),
          XpLine('New stars ×2', 60),
          XpLine('Clean flight', 15),
          XpLine('Personal best', 20),
          XpLine('Contract: deliver 3 pods', 80),
          XpLine('Contract: 3★ a level', 80),
          XpLine('All contracts done', 100),
          XpLine('Achievement: First Flight', 100),
          XpLine('Achievement: First Delivery', 100),
        ]),
        xpBefore: 6000,
        xpAfter: 6615,
        currency: 45,
        newAchievements: [
          AchievementService.all.first,
          AchievementService.all[1],
        ],
      );

    await each(
      tester,
      'levelComplete',
      () => LevelCompleteOverlay(game: won()),
    );
    expect(find.text('NEXT MISSION'), findsOneWidget);
  });

  testWidgets('XP breakdown folds into five lines', (tester) async {
    final lines = XpSummary.foldXpLines([
      for (var i = 0; i < 9; i++) XpLine('Line $i', 10),
    ]);
    expect(lines, hasLength(5));
    expect(lines.last.xp, 50);
  });

  testWidgets('full-screen menus lay out', (tester) async {
    await each(
      tester,
      'levelSelect',
      () => LevelSelectOverlay(game: NarrowHaulGame()),
    );
    await each(
      tester,
      'garage',
      () => GarageOverlay(game: NarrowHaulGame()),
      mustNotScroll: false,
    );
    await each(
      tester,
      'achievements',
      () => AchievementsOverlay(game: NarrowHaulGame()),
      mustNotScroll: false,
    );
    await each(
      tester,
      'logbook',
      () => PilotLogbookOverlay(game: NarrowHaulGame()),
      mustNotScroll: false,
    );
  });
}
