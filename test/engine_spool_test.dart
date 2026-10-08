// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

import 'autopilot/harness.dart';

void main() {
  test('spool times: light ships fastest, heavy slowest', () {
    for (final s in kShips.values) {
      expect(s.spoolUp, inInclusiveRange(0.05, 0.2), reason: s.id);
    }
    expect(kHopper.spoolUp, lessThan(kKestrel.spoolUp));
    expect(kMule.spoolUp, greaterThan(kKestrel.spoolUp));
  });

  test('the engine spools up and down, fuel follows the throttle', () async {
    final h = GameHarness();
    await h.boot();
    await h.loadLevel(0, skipHazards: true);
    final g = h.game;
    final s = g.ship!..launch();
    final spool = s.spec.spoolUp;

    Future<void> step(int frames, {required bool thrust}) async {
      for (var i = 0; i < frames; i++) {
        g.thrustHeld = thrust;
        g.update(kStepDt);
        await Future<void>.delayed(Duration.zero);
      }
    }

    // A 0.05 s tap reaches well under full throttle and burns less fuel
    // than 0.05 s at full power would.
    final before = s.fuel;
    await step(3, thrust: true);
    // (Input reaches the ship one frame later: the game hands it over
    // after the ship's own update.)
    expect(s.throttle, inInclusiveRange(2 * kStepDt / spool - 1e-9, 3 * kStepDt / spool + 1e-9));
    final tapBurn = before - s.fuel;
    expect(tapBurn, lessThan(s.spec.fuelDrainPerSecond * 3 * kStepDt * 0.6));

    // Held, it reaches full power; released, it dies in half the time.
    await step((spool / kStepDt).ceil() + 1, thrust: true);
    expect(s.throttle, 1);
    await step((spool / 2 / kStepDt).ceil() + 1, thrust: false);
    expect(s.throttle, 0);
  });
}
