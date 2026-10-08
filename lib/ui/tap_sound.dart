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

/// [withTapSound] for value callbacks (switches).
ValueChanged<T>? withTapSoundValue<T>(ValueChanged<T>? action) =>
    action == null
        ? null
        : (v) {
            AudioService.playTap();
            action(v);
          };
