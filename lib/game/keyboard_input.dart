import 'package:flutter/services.dart';

/// Keyboard flight controls (desktop): the same inputs the touch HUD gives.
///
/// ← → / A D rotate, ↑ / W / Space thrust, F / Enter fire, Q / Tab switch
/// weapon, 1–6 pick one, E drops the pod, Z / X reel the line in / out.
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

  /// Drop the towed pod (a key press, handled by the game on key down).
  static final Set<LogicalKeyboardKey> releaseKeys = {LogicalKeyboardKey.keyE};

  /// The winch, held: reel the line in / pay it out.
  static final Set<LogicalKeyboardKey> reelInKeys = {LogicalKeyboardKey.keyZ};
  static final Set<LogicalKeyboardKey> payOutKeys = {LogicalKeyboardKey.keyX};

  /// 1–6 pick that slot of the ammo rail directly.
  static final List<LogicalKeyboardKey> slotKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
  ];

  /// + / − zoom the camera a notch in / out, 0 resets it: the notches for
  /// [key] (0 = reset), or null when it isn't a zoom key.
  static int? zoomNotches(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      return 1;
    }
    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      return -1;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) return 0;
    return null;
  }

  double rotateAxis = 0;
  bool thrust = false;
  bool fire = false;

  /// −1 reel in, +1 pay out.
  double winchAxis = 0;

  /// Recomputes the inputs from the keys currently held down.
  void update(Set<LogicalKeyboardKey> keysPressed) {
    final left = keysPressed.any(rotateLeftKeys.contains);
    final right = keysPressed.any(rotateRightKeys.contains);
    rotateAxis = (right ? 1.0 : 0.0) - (left ? 1.0 : 0.0);
    thrust = keysPressed.any(thrustKeys.contains);
    fire = keysPressed.any(fireKeys.contains);
    winchAxis = (keysPressed.any(payOutKeys.contains) ? 1.0 : 0.0) -
        (keysPressed.any(reelInKeys.contains) ? 1.0 : 0.0);
  }

  void reset() {
    rotateAxis = 0;
    thrust = false;
    fire = false;
    winchAxis = 0;
  }

  /// Whether [key] is one of the flight keys (handled, not passed on).
  static bool isFlightKey(LogicalKeyboardKey key) =>
      rotateLeftKeys.contains(key) ||
      rotateRightKeys.contains(key) ||
      thrustKeys.contains(key) ||
      fireKeys.contains(key) ||
      cycleKeys.contains(key) ||
      slotKeys.contains(key) ||
      releaseKeys.contains(key) ||
      reelInKeys.contains(key) ||
      payOutKeys.contains(key);
}
