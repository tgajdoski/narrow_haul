import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';

void main() {
  test('daily only picks from the offered (unlocked) levels', () {
    const unlocked = [0, 1, 2, 3];
    final config = DailyChallengeConfig.forToday(unlocked);
    expect(unlocked, contains(config.levelIndex));
  });

  test('daily falls back to the first level when none are offered', () {
    expect(DailyChallengeConfig.forToday(const []).levelIndex, 0);
  });
}
