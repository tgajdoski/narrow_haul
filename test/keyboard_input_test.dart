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

  test('non-flight keys are not swallowed', () {
    expect(KeyboardFlightInput.isFlightKey(LogicalKeyboardKey.keyW), isTrue);
    expect(KeyboardFlightInput.isFlightKey(LogicalKeyboardKey.keyQ), isTrue,
        reason: 'Q switches weapons');
    expect(KeyboardFlightInput.isFlightKey(LogicalKeyboardKey.keyZ), isFalse);
  });
}
