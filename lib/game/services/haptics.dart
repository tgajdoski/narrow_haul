import 'package:flutter/services.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

/// Vibration cues, gated by the player's haptics setting.
class Haptics {
  static bool get _on => ProgressService.instance.hapticsEnabled;

  /// Rope attached, UI ticks.
  static void light() {
    if (_on) HapticFeedback.lightImpact();
  }

  /// Successful landing.
  static void medium() {
    if (_on) HapticFeedback.mediumImpact();
  }

  /// Crash.
  static void heavy() {
    if (_on) HapticFeedback.heavyImpact();
  }
}
