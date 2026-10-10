import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/route/flight_route.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/garage_notices.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/ui/career_overlays.dart';
import 'package:narrow_haul/ui/garage_overlay.dart';
import 'package:narrow_haul/ui/level_select_overlay.dart';
import 'package:narrow_haul/ui/menu_overlay.dart';
import 'package:narrow_haul/ui/mission_briefing.dart';
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
  final today =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-'
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
    for (final s in tester.stateList<ScrollableState>(
      find.byType(Scrollable),
    )) {
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
    final json =
        jsonDecode(File('assets/routes/${def.saveId}.json').readAsStringSync())
            as Map<String, dynamic>;
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

  testWidgets('mission briefing fits, busiest level with the route', (
    tester,
  ) async {
    // The level with the most facts, its route unlocked and stars flown.
    var busiest = 0;
    for (var i = 0; i < LevelRegistry.totalLevels; i++) {
      if (briefingFacts(i).length > briefingFacts(busiest).length) busiest = i;
    }
    final def = LevelRegistry.defAt(busiest);
    await ProgressService.instance.setRouteUnlocked(def.saveId);
    await ProgressService.instance.saveStarsById(def.saveId, 2);
    await each(
      tester,
      'briefing',
      () => MissionBriefingOverlay(
        game: NarrowHaulGame()..briefingLevel = busiest,
      ),
    );
    expect(find.text('LAUNCH'), findsOneWidget);
    expect(find.text('WITH ROUTE'), findsOneWidget);
  });

  testWidgets('daily briefing fits', (tester) async {
    await each(
      tester,
      'daily briefing',
      () => MissionBriefingOverlay(
        game: NarrowHaulGame()
          ..briefingDaily = true
          ..briefingLevel = DailyChallengeConfig.peekToday(
            NarrowHaulGame.unlockedLevelIndices(),
          ).$1,
      ),
    );
    expect(find.text('LAUNCH'), findsOneWidget);
    expect(find.text('WITH ROUTE'), findsNothing, reason: 'never in a daily');
    expect(find.textContaining('XP'), findsOneWidget);
  });

  test('XP breakdown folds into five lines', () {
    final lines = XpSummary.foldXpLines([
      for (var i = 0; i < 9; i++) XpLine('Line $i', 10),
    ]);
    expect(lines, hasLength(5));
    expect(lines.last.xp, 50);
  });

  testWidgets('world tabs fly the missions map to a world', (tester) async {
    await pump(
      tester,
      _sizes[2],
      1,
      LevelSelectOverlay(game: NarrowHaulGame()),
    );
    await tester.pumpAndSettle();
    final map = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((s) => s.position.maxScrollExtent > 5000)
        .position;

    final last = LevelRegistry.worlds.last;
    await tester.ensureVisible(find.byKey(ValueKey('worldTab_${last.id}')));
    await tester.tap(find.byKey(ValueKey('worldTab_${last.id}')));
    await tester.pumpAndSettle();
    expect(
      map.pixels,
      greaterThan(map.maxScrollExtent - 1000),
      reason: '${last.name} near the end',
    );

    final first = LevelRegistry.worlds.first;
    await tester.ensureVisible(find.byKey(ValueKey('worldTab_${first.id}')));
    await tester.tap(find.byKey(ValueKey('worldTab_${first.id}')));
    await tester.pumpAndSettle();
    expect(map.pixels, lessThan(50), reason: '${first.name} at the start');
  });

  testWidgets('every Garage tab lays out (liveries, tow gear, handling, armory)', (
    tester,
  ) async {
    for (final size in _sizes) {
      for (final scale in [1.0, 1.3]) {
        await pump(tester, size, scale, GarageOverlay(game: NarrowHaulGame()));
        expect(tester.takeException(), isNull, reason: 'garage at $size ×$scale');
        for (final (tab, icon) in const [
          ('tow gear', Icons.link_rounded),
          ('handling', Icons.tune_rounded),
          ('plumes', Icons.local_fire_department_outlined),
          ('armory', Icons.gps_fixed_rounded),
        ]) {
          await tester.tap(find.byIcon(icon).first);
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            tester.takeException(),
            isNull,
            reason: 'garage $tab at $size ×$scale',
          );
        }
      }
    }
  });

  testWidgets('full-screen menus lay out', (tester) async {
    await each(
      tester,
      'levelSelect',
      () => LevelSelectOverlay(game: NarrowHaulGame()),
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

  testWidgets('rank-up lists the Garage items it unlocks, with Fit now', (
    tester,
  ) async {
    await ProgressService.instance.setXp(2600);
    NarrowHaulGame promoted() => NarrowHaulGame()
      ..lastRunReward = RunReward(
        xp: const XpBreakdown([XpLine('First clear', 200)]),
        xpBefore: 2400,
        xpAfter: 2600,
        currency: 50,
        newAchievements: const [],
      );
    await each(tester, 'rankUp', () => RankUpOverlay(game: promoted()));
    expect(find.text('Long Line'), findsOneWidget);
    expect(find.textContaining('Next: First Officer'), findsOneWidget);
    await tester.tap(find.text('FIT NOW'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      CosmeticsService.getSavedEquippedId(CosmeticsService.catRope),
      'rope_braided',
    );
    expect(find.text('FITTED'), findsOneWidget);
  });

  testWidgets('mission complete names what the coins just bought', (
    tester,
  ) async {
    await ProgressService.instance.spendCosmeticCurrency(1240 - 85);
    final game = NarrowHaulGame()
      ..levelIndex = 3
      ..runState = RunState.won
      ..lastLevelStars = 3
      ..lastRunReward = RunReward(
        xp: const XpBreakdown([XpLine('First clear', 60)]),
        xpBefore: 6000,
        xpAfter: 6060,
        currency: 45,
        newAchievements: const [],
        coinsBefore: 40,
      );
    await pump(tester, _sizes.first, 1, LevelCompleteOverlay(game: game));
    expect(
      find.textContaining('New in the Garage: Tow Chain (80 💰)'),
      findsOneWidget,
    );
  });

  testWidgets('Garage news: hangar badge clears once the tab is seen', (
    tester,
  ) async {
    await pump(tester, _sizes.first, 1, MenuOverlay(game: NarrowHaulGame()));
    final news = GarageNotices.current().fresh;
    expect(news, isNotEmpty);
    expect(find.text('${news.length} NEW'), findsOneWidget);

    // Opening the Garage marks the first tab with news as seen.
    await pump(tester, _sizes.first, 1, GarageOverlay(game: NarrowHaulGame()));
    expect(GarageNotices.current().fresh.length, lessThan(news.length));
    for (final (_, icon) in const [
      ('ship', Icons.rocket_rounded),
      ('rope', Icons.link_rounded),
      ('kit', Icons.tune_rounded),
      ('plume', Icons.local_fire_department_outlined),
    ]) {
      await tester.tap(find.byIcon(icon).first);
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(GarageNotices.current().fresh, isEmpty);
    await pump(tester, _sizes.first, 1, MenuOverlay(game: NarrowHaulGame()));
    expect(find.textContaining(' NEW'), findsNothing);
  });

  testWidgets('Garage asks before spending coins, and says why when it can\'t', (
    tester,
  ) async {
    await pump(tester, _sizes.first, 1, GarageOverlay(game: NarrowHaulGame()));
    await tester.tap(find.byIcon(Icons.link_rounded).first);
    await tester.pump(const Duration(milliseconds: 400));
    // Tow Chain: affordable → confirm first, nothing spent yet.
    await tester.tap(find.text('Tow Chain'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('BUY · 80'), findsOneWidget);
    expect(ProgressService.instance.getCosmeticCurrency(), 1240);
    await tester.tap(find.textContaining('BUY · 80'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(ProgressService.instance.getCosmeticCurrency(), 1160);
    expect(
      CosmeticsService.getSavedEquippedId(CosmeticsService.catRope),
      'rope_chain',
    );

    // Out of coins: the tap explains the shortfall.
    await ProgressService.instance.spendCosmeticCurrency(1160 - 10);
    await pump(tester, _sizes.first, 1, GarageOverlay(game: NarrowHaulGame()));
    await tester.tap(find.byIcon(Icons.link_rounded).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(
      find.text('Magnetic Grapple'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Magnetic Grapple'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Need 190 more'), findsOneWidget);
  });

  testWidgets('briefing shows the loadout and nudges unfitted gear', (
    tester,
  ) async {
    // Rank 5 owns the Long Line (Second Officer) but never fitted it.
    await pump(
      tester,
      _sizes.first,
      1,
      MissionBriefingOverlay(game: NarrowHaulGame()..briefingLevel = 3),
    );
    expect(find.textContaining('Loadout: Steel Winch Cable'), findsOneWidget);
    expect(find.text('You own Long Line: not fitted'), findsOneWidget);
    expect(find.text('FIT GEAR'), findsOneWidget);
  });
}
