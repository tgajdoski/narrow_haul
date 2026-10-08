import 'package:flutter/foundation.dart';

import '../game/services/audio_service.dart';

/// Wraps a button callback so it plays a UI sound first ([UiSound.tap] by
/// default). Null stays null, so disabled buttons stay disabled.
VoidCallback? withTapSound(
  VoidCallback? action, [
  UiSound sound = UiSound.tap,
]) => action == null
    ? null
    : () {
        AudioService.playUi(sound);
        action();
      };

/// [withTapSound] for value callbacks (switches). The click plays after the
/// change, so switching Sound on clicks and switching it off is silent. Bool
/// switches click up when turned on and down when turned off.
ValueChanged<T>? withTapSoundValue<T>(ValueChanged<T>? action) => action == null
    ? null
    : (v) {
        action(v);
        AudioService.playUi(switch (v) {
          true => UiSound.toggleOn,
          false => UiSound.toggleOff,
          _ => UiSound.tap,
        });
      };
