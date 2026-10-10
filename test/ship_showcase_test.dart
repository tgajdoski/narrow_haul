import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/livery.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/ui/garage_overlay.dart';
import 'package:narrow_haul/ui/mission_briefing.dart';
import 'package:narrow_haul/ui/ship_showcase.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'save_v2': true,
      'save_v3': true,
      'credits_seen': true,
      'cosmetic_currency': 20,
    });
    await ProgressService.init();
  });

  Future<void> pump(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: child)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  final turntable = find.byKey(const ValueKey('garage-turntable'));

  testWidgets('Garage: the ship turns on its stand beside the liveries', (tester) async {
    await pump(tester, const Size(844, 390), GarageOverlay(game: NarrowHaulGame()));
    await tester.tap(find.text('LIVERIES'));
    await tester.pump();
    expect(turntable, findsOneWidget);
    final ship = LevelRegistry.shipFor(LevelRegistry.nextLevelIndex());
    expect(find.text(ship.name.toUpperCase()), findsOneWidget);
    expect(tester.widget<ShipShowcase>(turntable).livery, 'ship_standard');

    // A livery the player can't afford yet still goes on the ship.
    final gold = CosmeticsService.all.firstWhere((i) => i.id == 'ship_gold');
    final tile = find.byWidgetPredicate((w) => w is CosmeticTile && w.item.id == gold.id);
    await tester.scrollUntilVisible(tile, 120, scrollable: find.byType(Scrollable).last);
    await tester.tap(tile);
    await tester.pump();
    expect(tester.widget<ShipShowcase>(turntable).livery, 'ship_gold');
    expect(find.text('${gold.name} · preview'), findsOneWidget);
  });

  testWidgets('Garage: plumes show on the stand too; gear tabs keep the full list', (
    tester,
  ) async {
    await pump(tester, const Size(844, 390), GarageOverlay(game: NarrowHaulGame()));
    await tester.tap(find.text('PLUMES'));
    await tester.pump();
    expect(turntable, findsOneWidget);
    await tester.tap(find.text('TOW GEAR'));
    await tester.pump();
    expect(turntable, findsNothing);
  });

  testWidgets('Garage: no stand on the smallest phones', (tester) async {
    await pump(tester, const Size(568, 320), GarageOverlay(game: NarrowHaulGame()));
    await tester.tap(find.text('LIVERIES'));
    await tester.pump();
    expect(turntable, findsNothing);
  });

  testWidgets('briefing: the mission ship on a small stand where there is room', (
    tester,
  ) async {
    final briefing = find.byKey(const ValueKey('briefing-ship'));
    await pump(
      tester,
      const Size(844, 390),
      MissionBriefingOverlay(game: NarrowHaulGame()..briefingLevel = 12),
    );
    expect(briefing, findsOneWidget);
    expect(tester.widget<ShipShowcase>(briefing).ship.id, LevelRegistry.shipFor(12).id);
    await pump(
      tester,
      const Size(667, 375),
      MissionBriefingOverlay(game: NarrowHaulGame()..briefingLevel = 12),
    );
    expect(briefing, findsNothing);
  });

  test('every livery and plume in the shop has its look', () {
    for (final item in CosmeticsService.all) {
      if (item.category == CosmeticsService.catShip && item.id != 'ship_standard') {
        expect(kLiveryTints, contains(item.id), reason: item.id);
      }
    }
    expect(plumePalette('plume_cryo', 0), isNot(plumePalette(null, 0)));
    expect(garageFleet().first.id, isNotEmpty);
    expect(kShips, isNotEmpty);
  });
}
