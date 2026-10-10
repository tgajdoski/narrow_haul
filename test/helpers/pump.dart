// Widget-test timing and save helpers.
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Advances time in frame-sized steps so tickers and timers both run.
Future<void> advance(WidgetTester tester, Duration d) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < d; t += step) {
    await tester.pump(step);
  }
}

/// A fresh, already-migrated save holding [prefs], loaded into
/// [ProgressService].
Future<void> freshSave([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues({'save_v2': true, 'save_v3': true, ...prefs});
  await ProgressService.init();
}
