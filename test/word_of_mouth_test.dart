import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/review_ask.dart';
import 'package:narrow_haul/ui/share_run.dart';

void main() {
  group('review ask', () {
    const day = 24 * 3600 * 1000;
    bool ask({
      int stars = 3,
      int deliveries = 20,
      int asks = 0,
      int lastMs = 0,
      int nowMs = 1000 * day,
      bool other = false,
    }) => shouldAskForReview(
      stars: stars,
      lifetimeDeliveries: deliveries,
      asksSoFar: asks,
      lastAskMs: lastMs,
      nowMs: nowMs,
      otherCardShowing: other,
    );

    test('asks on a 3★ delivery once the pilot has flown enough', () {
      expect(ask(), isTrue);
      expect(ask(deliveries: kReviewMinDeliveries - 1), isFalse);
      expect(ask(deliveries: kReviewMinDeliveries), isTrue);
    });

    test('never after a 1–2★ run or over another card', () {
      expect(ask(stars: 2), isFalse);
      expect(ask(other: true), isFalse);
    });

    test('at most kReviewMaxAsks, kReviewGap apart', () {
      expect(ask(asks: kReviewMaxAsks), isFalse);
      expect(ask(asks: 1, lastMs: 1000 * day - 59 * day), isFalse);
      expect(ask(asks: 1, lastMs: 1000 * day - 60 * day), isTrue);
    });
  });

  group('share text', () {
    test('a career run names the cargo, mission and world', () {
      final t = shareRunText(
        mission: 'Shaft Seven',
        world: 'Rustshaft Mines',
        stars: 3,
        time: '42.3s',
        fuelPct: 64,
        cargo: 'Water drum',
        badge: 'FLAWLESS',
      );
      expect(
        t,
        'Hauled water drum through "Shaft Seven" (Rustshaft Mines) in '
        'Narrow Haul: ★★★ · 42.3s · 64% fuel left. FLAWLESS. $kShareUrl',
      );
    });

    test('a daily is a challenge to the tier', () {
      final t = shareRunText(
        mission: 'x',
        world: 'y',
        stars: 2,
        time: '1m02s',
        fuelPct: 30,
        dailyTier: 'Line',
      );
      expect(t, startsWith("Today's Narrow Haul dispatch (Line pilots)"));
      expect(t, contains('★★☆ · 1m02s'));
      expect(t, contains('Can you beat it?'));
      expect(t, endsWith(kShareUrl));
    });
  });
}
