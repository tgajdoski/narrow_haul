// The autopilot flies two easy levels through the real game on every
// `flutter test`: a guard for the bot (the full run in test/autopilot is
// on demand) and the one default test where a real rope joint hooks a pod,
// tows it and lands it.
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';

import 'autopilot/autopilot.dart';
import 'autopilot/harness.dart';
import 'helpers/levels.dart';

void main() {
  final h = GameHarness();
  setUpAll(h.boot);

  for (final id in ['tut_01', 'alien_01']) {
    test('the bot hooks, tows and delivers $id', () async {
      final index = levelIndexOf(id);
      await h.loadLevel(index, skipHazards: true);
      final bot = Autopilot(h.game, h.navGrid(LevelRegistry.defAt(index)), kPilotProfiles.first);
      var hooked = false;
      final r = await h.fly(
        bot.step,
        describe: bot.describe,
        abort: () => bot.gaveUp,
        afterStep: () => hooked |= h.game.cargoAttachment?.attached ?? false,
      );
      expect(r.outcome, FlightOutcome.delivered, reason: '$r');
      expect(hooked, isTrue, reason: 'delivered without a tow?');
      expect(r.stars, greaterThanOrEqualTo(1));
    });
  }

  test('the tractor beam tows by the bot, and drops the pod when fuel runs out', () async {
    CosmeticsService.trialOverride[CosmeticsService.catRope] = 'rope_tractor';
    addTearDown(CosmeticsService.clearTrials);
    final index = levelIndexOf('tut_01');
    await h.loadLevel(index, skipHazards: true);
    final g = h.game;
    final bot = Autopilot(g, h.navGrid(LevelRegistry.defAt(index)), kPilotProfiles.first);
    final towed = await h.fly(bot.step,
        describe: bot.describe, abort: () => g.cargoAttachment?.attached ?? false);
    expect(g.cargoAttachment?.attached, isTrue, reason: 'never locked on: $towed');
    g.ship!.fuel = 0;
    await h.step(2);
    expect(g.cargoAttachment!.attached, isFalse, reason: 'beam held with an empty tank');
  });
}
