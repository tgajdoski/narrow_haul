import 'package:flutter/services.dart';

/// Keyboard flight controls (desktop): the same inputs the touch HUD gives.
///
/// ← → / A D rotate, ↑ / W / Space thrust, F / Enter fire, Q / Tab switch
/// weapon, 1–6 pick one.
class KeyboardFlightInput {
  static final Set<LogicalKeyboardKey> rotateLeftKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.keyA,
  };
  static final Set<LogicalKeyboardKey> rotateRightKeys = {
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyD,
  };
  static final Set<LogicalKeyboardKey> thrustKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.space,
  };
  static final Set<LogicalKeyboardKey> fireKeys = {
    LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  };

  /// Next weapon (a key press, handled by the game on key down).
  static final Set<LogicalKeyboardKey> cycleKeys = {
    LogicalKeyboardKey.keyQ,
    LogicalKeyboardKey.tab,
  };

  /// 1–6 pick that slot of the ammo rail directly.
  static final List<LogicalKeyboardKey> slotKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
  ];

  double rotateAxis = 0;
  bool thrust = false;
  bool fire = false;

  /// Recomputes the inputs from the keys currently held down.
  void update(Set<LogicalKeyboardKey> keysPressed) {
    final left = keysPressed.any(rotateLeftKeys.contains);
    final right = keysPressed.any(rotateRightKeys.contains);
    rotateAxis = (right ? 1.0 : 0.0) - (left ? 1.0 : 0.0);
    thrust = keysPressed.any(thrustKeys.contains);
    fire = keysPressed.any(fireKeys.contains);
  }

  void reset() {
    rotateAxis = 0;
    thrust = false;
    fire = false;
  }

  /// Whether [key] is one of the flight keys (handled, not passed on).
  static bool isFlightKey(LogicalKeyboardKey key) =>
      rotateLeftKeys.contains(key) ||
      rotateRightKeys.contains(key) ||
      thrustKeys.contains(key) ||
      fireKeys.contains(key) ||
      cycleKeys.contains(key) ||
      slotKeys.contains(key);
}
