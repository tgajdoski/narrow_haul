import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper around flame_audio. Fails silently when sound files are absent.
///
/// To add sounds, place these files in assets/audio/ and register the folder in
/// pubspec.yaml under flutter.assets:
///   - assets/audio/
///
/// Required files:
///   thrust_loop.mp3   – looped engine sound while thrusting
///   attach.mp3        – rope attachment snap
///   crash.mp3         – hull breach / wall hit
///   land.mp3          – successful landing
///   star.mp3          – star(s) earned jingle
class AudioService {
  static bool _ready = false;
  static AudioPlayer? _thrustPlayer;

  static Future<void> init() async {
    try {
      await FlameAudio.audioCache.loadAll([
        'thrust_loop.mp3',
        'attach.mp3',
        'crash.mp3',
        'land.mp3',
        'star.mp3',
      ]);
      _ready = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AudioService: sound files not found, running silent. $e');
      }
      _ready = false;
    }
  }

  static void startThrust() {
    if (!_ready) return;
    if (_thrustPlayer != null) return;
    FlameAudio.loopLongAudio('thrust_loop.mp3', volume: 0.6)
        .then((p) => _thrustPlayer = p);
  }

  static void stopThrust() {
    if (!_ready) return;
    _thrustPlayer?.stop();
    _thrustPlayer = null;
  }

  static void playAttach() {
    if (!_ready) return;
    FlameAudio.play('attach.mp3', volume: 0.8);
  }

  static void playCrash() {
    if (!_ready) return;
    stopThrust();
    FlameAudio.play('crash.mp3', volume: 0.9);
  }

  static void playLand() {
    if (!_ready) return;
    stopThrust();
    FlameAudio.play('land.mp3', volume: 0.9);
  }

  static void playStar() {
    if (!_ready) return;
    FlameAudio.play('star.mp3', volume: 0.8);
  }
}
