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
  static bool _enabled = true;
  static bool _thrustPrewarmed = false;

  static bool get isReady => _ready;
  static bool get isEnabled => _enabled;

  static void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      stopThrust();
    }
  }

  static void _log(String message, [Object? error]) {
    debugPrint('AudioService: $message${error != null ? " ($error)" : ""}');
  }

  static Future<void> init() async {
    _ready = false;
    stopThrust();
    _thrustPrewarmed = false;
    try {
      await FlameAudio.audioCache.loadAll([
        'thrust_loop.mp3',
        'attach.mp3',
        'crash.mp3',
        'land.mp3',
        'star.mp3',
      ]);
      await _prewarmThrustLoop();
      _ready = true;
      _log('initialized 5 sounds');
    } catch (e) {
      _log('init failed, audio disabled', e);
      _ready = false;
    }
  }

  static void startThrust() {
    if (!_ready || !_enabled) return;
    final player = _thrustPlayer;
    if (player == null) {
      FlameAudio.loopLongAudio('thrust_loop.mp3', volume: 0.6).then((p) {
        _thrustPlayer = p;
        _thrustPrewarmed = true;
      }).catchError((e) {
        _log('failed to start thrust loop', e);
      });
      return;
    }
    player.setVolume(0.6).then<void>(
      (_) {},
      onError: (Object e, StackTrace _) => _log('failed setting thrust volume', e),
    );
    player.resume().then<void>(
      (_) {},
      onError: (Object e, StackTrace _) => _log('failed to resume thrust loop', e),
    );
  }

  static void stopThrust() {
    if (_thrustPrewarmed) {
      final player = _thrustPlayer;
      player?.pause().then<void>(
        (_) {},
        onError: (Object e, StackTrace _) => _log('failed to pause thrust loop', e),
      );
      player?.seek(Duration.zero).then<void>(
        (_) {},
        onError: (Object e, StackTrace _) => _log('failed to seek thrust loop', e),
      );
      return;
    }
    try {
      _thrustPlayer?.stop();
    } catch (e) {
      _log('failed to stop thrust loop', e);
    }
    _thrustPlayer = null;
  }

  static void playAttach() {
    if (!_ready || !_enabled) return;
    FlameAudio.play('attach.mp3', volume: 0.8).then<void>(
      (_) {},
      onError: (Object e, StackTrace _) => _log('failed to play attach', e),
    );
  }

  static void playCrash() {
    if (!_ready || !_enabled) return;
    stopThrust();
    FlameAudio.play('crash.mp3', volume: 0.9).then<void>(
      (_) {},
      onError: (Object e, StackTrace _) => _log('failed to play crash', e),
    );
  }

  static void playLand() {
    if (!_ready || !_enabled) return;
    stopThrust();
    FlameAudio.play('land.mp3', volume: 0.9).then<void>(
      (_) {},
      onError: (Object e, StackTrace _) => _log('failed to play land', e),
    );
  }

  static void playStar() {
    if (!_ready || !_enabled) return;
    FlameAudio.play('star.mp3', volume: 0.8).then<void>(
      (_) {},
      onError: (Object e, StackTrace _) => _log('failed to play star', e),
    );
  }

  static Future<void> _prewarmThrustLoop() async {
    try {
      final player = await FlameAudio.loopLongAudio('thrust_loop.mp3', volume: 0.0);
      _thrustPlayer = player;
      await player.pause();
      await player.seek(Duration.zero);
      _thrustPrewarmed = true;
      _log('thrust loop prewarmed');
    } catch (e) {
      _thrustPrewarmed = false;
      _thrustPlayer = null;
      _log('thrust prewarm failed, falling back to lazy start', e);
    }
  }
}
