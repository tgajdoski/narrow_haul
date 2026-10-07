import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'autopilot/difficulty.dart';

Difficulty _rate({
  bool delivered = true,
  double budget = 0.3,
  double humanFuel = 0.15,
  double timeLimit = 60,
  double humanTime = 30,
  int profilesOk = 4,
  double held = 0,
  double seconds = 30,
}) =>
    rateDifficulty(
      delivered: delivered,
      budget: budget,
      timeLimit: timeLimit,
      humanFuel: humanFuel,
      humanTime: humanTime,
      profilesOk: profilesOk,
      heldSeconds: held,
      seconds: seconds,
    );

void main() {
  test('labels', () {
    expect(_rate().label, DifficultyLabel.comfortable);
    expect(_rate(humanFuel: 0.29).label, DifficultyLabel.tight); // 3% margin
    expect(_rate(humanTime: 55).label, DifficultyLabel.tight); // 8% margin
    expect(_rate(profilesOk: 1).label, DifficultyLabel.tight);
    expect(_rate(held: 10, seconds: 30).label, DifficultyLabel.tight);
    expect(_rate(humanFuel: 0.31).label, DifficultyLabel.needsHelp);
    expect(_rate(humanTime: 61).label, DifficultyLabel.needsHelp);
    expect(_rate(delivered: false).label, DifficultyLabel.botFail);
    expect(_rate(delivered: false).score, 100);
  });

  test('score grows with every difficulty factor', () {
    final base = _rate().score;
    expect(_rate(humanFuel: 0.25).score, greaterThan(base));
    expect(_rate(humanTime: 50).score, greaterThan(base));
    expect(_rate(profilesOk: 2).score, greaterThan(base));
    expect(_rate(held: 5).score, greaterThan(base));
    expect(_rate(humanFuel: 0.0, humanTime: 0).score, 0);
    expect(_rate(humanFuel: 0.3, humanTime: 60, profilesOk: 0, held: 30).score, 100);
  });

  // Spread over the last real autopilot run (local build output, if any).
  // A partial run (LEVELS=…) says nothing about the spread: skipped.
  final report = File('build/autopilot_report.json');
  final rows = report.existsSync()
      ? (jsonDecode(report.readAsStringSync()) as List).cast<Map<String, dynamic>>()
      : const <Map<String, dynamic>>[];
  test('labels spread over the last autopilot report', () {
    final counts = <DifficultyLabel, int>{};
    for (final r in rows) {
      final real = r['real'] as Map<String, dynamic>?;
      final d = rateDifficulty(
        delivered: real?['outcome'] == 'delivered',
        budget: (r['budgetFuel'] as num).toDouble(),
        timeLimit: (r['star3Time'] as num).toDouble(),
        humanFuel: (r['humanFuel'] as num?)?.toDouble(),
        humanTime: (r['humanTime'] as num?)?.toDouble(),
        profilesOk: (r['profilesOk'] as num?)?.toInt() ?? 4,
        heldSeconds: (r['heldSeconds'] as num?)?.toDouble() ?? 0,
        seconds: (real?['seconds'] as num?)?.toDouble() ?? 0,
      );
      counts[d.label] = (counts[d.label] ?? 0) + 1;
    }
    // ignore: avoid_print
    print({for (final e in counts.entries) e.key.text: e.value});
    // Neither label should swallow the game.
    expect(counts[DifficultyLabel.comfortable] ?? 0, greaterThan(rows.length ~/ 4));
    expect(counts[DifficultyLabel.tight] ?? 0, lessThan(rows.length * 3 ~/ 4));
  }, skip: rows.length >= 30 ? false : 'no full build/autopilot_report.json');
}
