import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/keyboard_input.dart';

void main() {
  test('arrow keys and WASD map to the touch HUD inputs', () {
    final k = KeyboardFlightInput();
    k.update({LogicalKeyboardKey.arrowLeft});
    expect(k.rotateAxis, -1);
    k.update({LogicalKeyboardKey.keyD, LogicalKeyboardKey.space});
    expect(k.rotateAxis, 1);
    expect(k.thrust, isTrue);
    expect(k.fire, isFalse);
    k.update({LogicalKeyboardKey.keyA, LogicalKeyboardKey.arrowRight});
    expect(k.rotateAxis, 0, reason: 'both directions cancel');
    k.update({LogicalKeyboardKey.keyF, LogicalKeyboardKey.arrowUp});
    expect(k.fire, isTrue);
    expect(k.thrust, isTrue);
    k.update({});
    expect([k.rotateAxis, k.thrust, k.fire], [0, false, false]);
  });

  test('flight keys (incl. Q and the 1–6 rail slots) are claimed; others pass', () {
    expect(KeyboardFlightInput.isFlightKey(LogicalKeyboardKey.keyW), isTrue);
    expect(KeyboardFlightInput.isFlightKey(LogicalKeyboardKey.keyQ), isTrue,
        reason: 'Q switches weapons');
    expect(KeyboardFlightInput.slotKeys.first, LogicalKeyboardKey.digit1);
    for (final k in KeyboardFlightInput.slotKeys) {
      expect(KeyboardFlightInput.isFlightKey(k), isTrue, reason: '$k');
    }
    expect(KeyboardFlightInput.isFlightKey(LogicalKeyboardKey.keyZ), isFalse);
  });
}
