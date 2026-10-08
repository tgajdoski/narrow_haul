import 'dart:async';
import 'dart:math' as math;

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

import 'audio_service.dart';

/// Background music: one looping track at a time, crossfaded.
///
/// Sources (both free for commercial use, no credit required, not to be
/// redistributed as assets): the Space Music Pack by Goose Ninja
/// (gooseninja.itch.io/space-music-pack: menu, results, battle, travel,
/// wreckage, start-level sting) and Pixabay (ethereal, drift, nebula, orbit;
/// originals in art_src/audio/). Calling [play] with the track that's
/// already playing only changes its volume, so retrying a level never
/// restarts its music.
class MusicService {
  static const menuTrack = 'music_menu.m4a';
  static const resultsTrack = 'music_results.m4a';
  static const battleTrack = 'music_battle.m4a';

  /// Flown in random order everywhere but The Redoubt.
  static const flightPool = [
    'music_travel.m4a',
    'music_wreckage.m4a',
    'music_ethereal.m4a',
    'music_drift.m4a',
    'music_nebula.m4a',
    'music_orbit.m4a',
  ];

  /// Per-track loudness correction to about −21 dB RMS (measured), so the
  /// louder Pixabay tracks sit at the same level as the rest.
  static const _gain = {
    'music_ethereal.m4a': 0.35,
    'music_drift.m4a': 0.69,
    'music_nebula.m4a': 0.33,
    'music_orbit.m4a': 0.40,
    'music_battle.m4a': 0.45,
    'music_results.m4a': 0.65,
  };

  static const menuVolume = 0.5;
  static const resultsVolume = 0.4;

  /// Quiet under the engine, alarms and shots.
  static const flightVolume = 0.28;

  static const _fadeIn = Duration(milliseconds: 1200);
  static const _fadeOut = Duration(milliseconds: 700);
  static const _tick = Duration(milliseconds: 50);

  static String? _lastFlight;
  static final _rng = math.Random();

  /// The in-flight track for a level: battle in The Redoubt, otherwise a
  /// random pool track other than the last one. [keepCurrent] (a retry)
  /// keeps the track that's playing.
  static String flightTrackFor(String themeId, {bool keepCurrent = false}) {
    if (themeId == 'redoubt') return battleTrack;
    final last = _lastFlight;
    if (keepCurrent && last != null) return last;
    final options = [for (final t in flightPool) if (t != last) t];
    return _lastFlight = options[_rng.nextInt(options.length)];
  }

  static bool _enabled = true;
  static bool _backgrounded = false;

  /// A full-screen ad is up (its own audio plays).
  static bool _adShowing = false;

  static bool get _silenced => _backgrounded || _adShowing;

  /// What should be playing (kept while disabled or backgrounded).
  static String? _wantTrack;
  static double _wantVolume = 0;

  static _Track? _current;

  static void _log(String message, [Object? error]) {
    if (!kDebugMode) return;
    debugPrint('MusicService: $message${error != null ? " ($error)" : ""}');
  }

  static void setEnabled(bool enabled) {
    if (enabled == _enabled) return;
    _enabled = enabled;
    _apply();
  }

  /// Plays [track] at [volume], crossfading from whatever is playing.
  static void play(String track, double volume) {
    _wantTrack = track;
    _wantVolume = volume * (_gain[track] ?? 1);
    _apply();
  }

  /// Fades the music out (it stays off until the next [play]).
  static void stop() {
    _wantTrack = null;
    _apply();
  }

  /// App left the foreground: pause outright (a fade wouldn't be heard).
  static void onBackground() {
    if (_backgrounded) return;
    _backgrounded = true;
    _pauseAll();
  }

  static void onForeground() {
    if (!_backgrounded) return;
    _backgrounded = false;
    _resumeIfAudible();
  }

  /// A full-screen ad is about to show / was closed.
  static void setAdShowing(bool showing) {
    if (showing == _adShowing) return;
    _adShowing = showing;
    showing ? _pauseAll() : _resumeIfAudible();
  }

  /// Tracks still fading out are paused too (they're disposed when done).
  static final Set<_Track> _fadingOut = {};

  static void _pauseAll() {
    _current?.pause();
    for (final t in _fadingOut) {
      t.pause();
    }
  }

  static void _resumeIfAudible() {
    if (_silenced) return;
    _current?.resume();
    _apply();
  }

  static void _apply() {
    if (_silenced) return;
    final want = (_enabled && AudioService.isReady) ? _wantTrack : null;
    final current = _current;
    if (current != null && current.file == want) {
      current.fadeTo(_wantVolume, _fadeIn);
      return;
    }
    if (current != null) {
      _current = null;
      _fadingOut.add(current);
      current.fadeTo(0, _fadeOut, then: () {
        _fadingOut.remove(current);
        current.dispose().catchError((Object e) {
          _log('failed to release ${current.file}', e);
        });
      });
    }
    if (want != null) {
      _current = _Track(want)..start(_wantVolume, _fadeIn);
    }
  }

  /// Releases everything (test teardown).
  static Future<void> dispose() async {
    final current = _current;
    _current = null;
    _wantTrack = null;
    final fading = [..._fadingOut];
    _fadingOut.clear();
    await current?.dispose();
    for (final t in fading) {
      await t.dispose();
    }
  }
}

/// One looping music player with a timer-driven volume fade.
class _Track {
  _Track(this.file);

  final String file;
  AudioPlayer? _player;
  bool _disposed = false;
  double _volume = 0;
  double _target = 0;
  Timer? _fade;

  void start(double volume, Duration fade) {
    _target = volume;
    FlameAudio.loopLongAudio(
      file,
      volume: 0,
      audioContext: AudioService.context,
    ).then((p) {
      if (_disposed) {
        p.dispose();
        return;
      }
      _player = p;
      // Started while the app went to the background or an ad came up:
      // hold it paused; resuming fades it in from where it is.
      if (MusicService._silenced) {
        p.pause().catchError((Object _) {});
        return;
      }
      fadeTo(_target, fade);
    }).catchError((Object e) {
      MusicService._log('failed to start $file', e);
    });
  }

  void fadeTo(double target, Duration duration, {void Function()? then}) {
    _fade?.cancel();
    _target = target;
    final player = _player;
    if (player == null || _disposed) {
      // Not started yet (or never will be): nothing to fade.
      _fade = null;
      then?.call();
      return;
    }
    final from = _volume;
    final steps = (duration.inMilliseconds / MusicService._tick.inMilliseconds)
        .ceil()
        .clamp(1, 1000);
    var step = 0;
    _fade = Timer.periodic(MusicService._tick, (timer) {
      step++;
      _volume = from + (target - from) * (step / steps);
      player.setVolume(_volume).catchError((Object _) {});
      if (step >= steps) {
        timer.cancel();
        _fade = null;
        then?.call();
      }
    });
  }

  void pause() {
    _player?.pause().catchError((Object _) {});
  }

  void resume() {
    _player?.resume().catchError((Object _) {});
  }

  Future<void> dispose() async {
    _disposed = true;
    _fade?.cancel();
    _fade = null;
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}
