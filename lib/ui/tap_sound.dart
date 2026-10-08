import 'package:flutter/foundation.dart';

import '../game/services/audio_service.dart';

/// Wraps a button callback so it plays the UI tap first. Null stays null, so
/// disabled buttons stay disabled.
VoidCallback? withTapSound(VoidCallback? action) => action == null
    ? null
    : () {
        AudioService.playTap();
        action();
      };

/// [withTapSound] for value callbacks (switches). The tap plays after the
/// change, so switching Sound on clicks and switching it off is silent.
ValueChanged<T>? withTapSoundValue<T>(ValueChanged<T>? action) =>
    action == null
        ? null
        : (v) {
            action(v);
            AudioService.playTap();
          };
