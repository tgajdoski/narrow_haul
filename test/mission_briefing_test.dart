import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/ui/mission_briefing.dart';
import 'package:shared_preferences/shared_preferences.dart';

int _firstWhere(bool Function(LevelDef d) test) {
  final i = LevelRegistry.flat.indexWhere(test);
  expect(i, isNot(-1));
  return i;
}

List<String> _labels(int index, {DailyChallengeConfig? daily}) => [
  for (final f in briefingFacts(index, daily: daily)) f.label,
];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ProgressService.init();
  });

  test('the first tutorial mission lists only its ship', () {
    final labels = _labels(0);
    expect(labels, hasLength(1));
    expect(labels.single, startsWith(LevelRegistry.shipFor(0).name));
  });

  test('a zero-g level says so', () {
    final i = _firstWhere((d) => d.modifiers.gravityMul == 0);
    expect(_labels(i), contains('Zero-g'));
  });

  test('a heavy-gravity level shows its pull', () {
    final i = _firstWhere((d) => d.modifiers.gravityMul > 1);
    final g = LevelRegistry.defAt(i).modifiers.gravityMul;
    expect(
      _labels(i).any((l) => l.startsWith('Heavy gravity') && l.endsWith(' g')),
      isTrue,
      reason: 'gravity $g',
    );
  });

  test('turret levels list turrets and the reactor', () {
    final i = _firstWhere(
      (d) =>
          d is CaveLevelDef && d.spec.obstacles.any((o) => o is ReactorSpec),
    );
    final labels = _labels(i);
    expect(labels.any((l) => l.contains('urret')), isTrue);
    expect(labels, contains('Reactor'));
  });

  test('fuel canisters are counted', () {
    final i = _firstWhere(
      (d) => d is CaveLevelDef && d.spec.pickups.isNotEmpty,
    );
    expect(
      _labels(i).any((l) => l.toLowerCase().contains('fuel canister')),
      isTrue,
    );
  });

  test('daily modifiers stack on the level', () {
    const heavy = DailyChallengeConfig(
      levelIndex: 0,
      gravityMultiplier: 1.8,
      fuelDrainMultiplier: 2,
      modifierName: 'x',
      modifierDesc: '',
    );
    final labels = _labels(0, daily: heavy);
    expect(labels, contains('Heavy gravity 1.8 g'));
    expect(labels, contains('Fuel burn ×2'));
  });

  test('a ship without its type rating is flagged new', () async {
    final i = _firstWhere((d) => d.saveId.startsWith('rating_'));
    final ship = LevelRegistry.shipFor(i);
    expect(LevelRegistry.hasTypeRating(ship.id), isFalse);
    expect(_labels(i).first, '${ship.name} · new ship');

    await ProgressService.instance.saveStarsById(LevelRegistry.defAt(i).saveId, 1);
    expect(_labels(i).first, ship.name);
  });

  test('star targets match the level StarSpec', () {
    const s = StarSpec(star3Fuel: 0.7, star2Fuel: 0.4, star3Time: 60);
    final (three, two) = starTargets(s);
    expect(three, '≥ 70% fuel · ≤ 1m00s');
    expect(two, '≥ 40% fuel');
  });

  test('daily reward matches the XP the delivery pays', () {
    for (final streak in [1, 2, 5, 9]) {
      final xp = computeRunXp(
        challenge: true,
        firstClear: false,
        newStars: 0,
        tier: 1,
        cleanFlight: false,
        personalBest: false,
        dailyFirstToday: true,
        dailyStreak: streak,
      ).total;
      expect(xp, kDailyXp + dailyStreakBonusXp(streak), reason: '$streak');
    }
  });

  testWidgets('hangar LAUNCH briefs a new mission once per session', (
    tester,
  ) async {
    final game = NarrowHaulGame();
    Widget blank(BuildContext _, Game _) => const SizedBox.shrink();
    await tester.pumpWidget(
      GameWidget(
        game: game,
        overlayBuilderMap: {for (final k in ['menu', 'briefing']) k: blank},
      ),
    );
    game.overlays
      ..clear()
      ..add('menu');
    final next = LevelRegistry.nextLevelIndex();
    expect(game.needsBriefing(next), isTrue, reason: 'never flown');

    await game.beginPlay();
    expect(game.overlays.activeOverlays, ['menu', 'briefing']);
    expect(game.briefingLevel, next);
    expect(game.briefingDaily, isFalse);
    expect(game.needsBriefing(next), isFalse, reason: 'briefed this session');

    // A flown mission never needs the briefing on LAUNCH / NEXT MISSION.
    final other = next + 1;
    expect(game.needsBriefing(other), isTrue);
    await ProgressService.instance.saveStarsById(
      LevelRegistry.defAt(other).saveId,
      1,
    );
    expect(game.needsBriefing(other), isFalse);
  });
}
