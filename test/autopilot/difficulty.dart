// Per-level difficulty score and label for the autopilot report. Pure, so
// test/difficulty_test.dart can check it without flying anything.
import 'dart:math' as math;

/// A level is "3★ tight" below these margins (relative to the 3★ budget):
/// fuel already includes the player factor (1.3× the bot), so 5% left still
/// means ~1.37× the bot's burn.
const double kTightFuelMargin = 0.05;
const double kTightTimeMargin = 0.15;

/// ... or when the best flight spends this share of its time holding short
/// of moving obstacles (timing-heavy for a human).
const double kTightWaitShare = 0.25;

enum DifficultyLabel {
  comfortable('3★ comfortable'),
  tight('3★ tight'),
  needsHelp('3★ needs help'),
  botFail("bot can't pass, needs human playtest");

  const DifficultyLabel(this.text);
  final String text;
}

typedef Difficulty = ({double score, DifficultyLabel label});

/// [humanFuel]/[humanTime]: what a player is expected to need (fuel as a
/// fraction of the tank); [budget] = fuel fraction 3★ allows to burn.
/// [profilesOk] of [profiles] pilot profiles delivered with hazards on;
/// [heldSeconds] of the best flight's [seconds] were spent waiting.
Difficulty rateDifficulty({
  required bool delivered,
  required double budget,
  required double timeLimit,
  double? humanFuel,
  double? humanTime,
  required int profilesOk,
  int profiles = 4,
  double heldSeconds = 0,
  double seconds = 0,
}) {
  if (!delivered || humanFuel == null || humanTime == null) {
    return (score: 100, label: DifficultyLabel.botFail);
  }
  double clamp01(double v) => v.clamp(0.0, 1.0).toDouble();
  final fuelMargin = (budget - humanFuel) / budget;
  final timeMargin = (timeLimit - humanTime) / timeLimit;
  final waitShare = seconds > 0 ? heldSeconds / seconds : 0.0;
  final failed = math.max(0, profiles - profilesOk) / profiles;
  final score = 50 * clamp01(1 - fuelMargin / 0.5) +
      15 * clamp01(1 - timeMargin / 0.8) +
      20 * failed +
      15 * clamp01(waitShare * 3);
  final DifficultyLabel label;
  if (fuelMargin < 0 || timeMargin < 0) {
    label = DifficultyLabel.needsHelp;
  } else if (fuelMargin < kTightFuelMargin ||
      timeMargin < kTightTimeMargin ||
      profilesOk <= 1 ||
      waitShare > kTightWaitShare) {
    label = DifficultyLabel.tight;
  } else {
    label = DifficultyLabel.comfortable;
  }
  return (score: (score * 10).round() / 10, label: label);
}
