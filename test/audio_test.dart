import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/music_service.dart';
import 'package:narrow_haul/game/services/thrust_envelope.dart';

const _dt = 1 / 60;

/// Runs [frames] frames and returns the volumes actually sent.
List<double> _run(ThrustEnvelope env, bool thrusting, int frames) => [
      for (var i = 0; i < frames; i++) env.step(thrusting, _dt),
    ].whereType<double>().toList();

void main() {
  group('ThrustEnvelope', () {
    test('a one-frame tap is audible and lasts at least the hold', () {
      final env = ThrustEnvelope()..reset();
      env.step(true, _dt);
      var audibleFrames = 1;
      while (env.volume > 0) {
        env.step(false, _dt);
        audibleFrames++;
        expect(audibleFrames, lessThan(120), reason: 'never released');
      }
      expect(audibleFrames * _dt, greaterThanOrEqualTo(env.minHoldSeconds));
    });

    test('a tap reaches full volume', () {
      final env = ThrustEnvelope()..reset();
      env.step(true, _dt);
      var peak = env.volume;
      for (var i = 0; i < 30; i++) {
        env.step(false, _dt);
        if (env.volume > peak) peak = env.volume;
      }
      expect(peak, closeTo(env.maxVolume, 1e-9));
    });

    test('attack is fast and release decays to silence', () {
      final env = ThrustEnvelope()..reset();
      _run(env, true, 2);
      expect(env.volume, closeTo(env.maxVolume, 1e-9));
      _run(env, true, 60);
      _run(env, false, 30);
      expect(env.volume, 0);
    });

    test('sends nothing while idle or held steady', () {
      final env = ThrustEnvelope()..reset();
      expect(_run(env, false, 1), [0.0]); // reset forces one send
      expect(_run(env, false, 120), isEmpty);
      _run(env, true, 10);
      expect(_run(env, true, 120), isEmpty);
    });

    test('ends exactly on 0 and on full volume', () {
      final env = ThrustEnvelope()..reset();
      expect(_run(env, true, 10).last, env.maxVolume);
      expect(_run(env, false, 30).last, 0);
    });
  });

  test('every sound and music file the services name is bundled', () {
    final listed = {
      for (final f in [
        'lib/game/services/audio_service.dart',
        'lib/game/services/music_service.dart',
      ])
        ...RegExp(r"'(\w+\.(?:wav|mp3|m4a))'")
            .allMatches(File(f).readAsStringSync())
            .map((m) => m.group(1)!),
    };
    expect(listed, isNotEmpty);
    for (final f in listed) {
      expect(File('assets/audio/$f').existsSync(), isTrue, reason: f);
    }
  });

  test('every one-shot sound plays from a pool (loops excepted)', () {
    // Pooled players recycle on completion; one-off low-latency players
    // pile up on Android.
    const loops = {'thrust_loop.wav', 'alarm.wav'};
    expect(AudioService.poolSizes.keys.toSet(), AudioService.files.toSet().difference(loops));
  });

  test('ads and backgrounding toggle music safely with nothing playing', () {
    expect(() {
      MusicService.setAdShowing(true);
      MusicService.onBackground();
      MusicService.setAdShowing(false);
      MusicService.onForeground();
      MusicService.play(MusicService.menuTrack, MusicService.menuVolume);
      MusicService.stop();
    }, returnsNormally);
  });

  group('MusicService rotation', () {
    test('The Redoubt always flies to the battle track', () {
      expect(MusicService.flightTrackFor('redoubt'), MusicService.battleTrack);
      expect(MusicService.flightTrackFor('redoubt'), MusicService.battleTrack,
          reason: 'not rotated away on the next flight');
    });

    test('never repeats a track twice in a row, and uses the whole pool', () {
      final seen = <String>{};
      var last = MusicService.flightTrackFor('alien');
      for (var i = 0; i < 200; i++) {
        final next = MusicService.flightTrackFor('ice');
        expect(next, isNot(last));
        expect(MusicService.flightPool, contains(next));
        seen.add(next);
        last = next;
      }
      expect(seen, MusicService.flightPool.toSet());
    });

    test('a retry keeps the current track', () {
      final t = MusicService.flightTrackFor('mine');
      expect(MusicService.flightTrackFor('mine', keepCurrent: true), t);
      expect(MusicService.flightTrackFor('mine', keepCurrent: true), t);
    });
  });
}
