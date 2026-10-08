// ignore_for_file: invalid_use_of_internal_member
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/components/rock_proximity.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/ship/hull_contact.dart';

import 'autopilot/harness.dart';

void main() {
  group('classifyHullContact', () {
    HullContact touch(double speed, {bool base = true, double tilt = 0, double slope = 0}) =>
        classifyHullContact(
          approachSpeed: speed,
          onBase: base,
          tiltCos: math.cos(tilt * math.pi / 180),
          groundCos: math.cos(slope * math.pi / 180),
        );

    test('upright on the base lands up to the touchdown speed', () {
      expect(touch(0.3), HullContact.touchdown);
      expect(touch(kTouchdownMaxSpeed), HullContact.touchdown);
      expect(touch(kTouchdownMaxSpeed + 0.01), HullContact.crash);
      expect(touch(0.8, tilt: 30, slope: 35), HullContact.touchdown);
    });

    test('nose, flanks, tilted or steep: only slow scrapes survive', () {
      for (final c in [
        touch(0.5, base: false),
        touch(0.5, tilt: 50),
        touch(0.5, slope: 60),
      ]) {
        expect(c, HullContact.scrape);
      }
      expect(touch(kScrapeMaxSpeed + 0.01, base: false), HullContact.crash);
      expect(touch(0.8, tilt: 50), HullContact.crash);
    });

    test('moving away or sliding along is a scrape', () {
      expect(touch(-1, base: false), HullContact.scrape);
      expect(touch(0, base: false), HullContact.scrape);
    });
  });

  group('in the real game', () {
    late GameHarness h;
    setUpAll(() async {
      h = GameHarness();
      await h.boot();
    });

    /// Lowers the ship straight down at [speed] until it touches rock, then
    /// lets it settle for a second.
    Future<NarrowHaulGame> drop(int level, double speed) async {
      await h.loadLevel(level, skipHazards: true);
      final g = h.game;
      final s = g.ship!..launch();
      for (var i = 0; i < 60 * 30; i++) {
        if (g.scrapesThisRun > 0 || g.runState != RunState.playing) break;
        s.body
          ..linearVelocity = Vector2(0, speed)
          ..angularVelocity = 0;
        s.body.setTransform(s.body.position, 0);
        g.update(kStepDt);
        await Future<void>.delayed(Duration.zero);
      }
      for (var i = 0; i < 60; i++) {
        g.update(kStepDt);
        await Future<void>.delayed(Duration.zero);
      }
      return g;
    }

    test('the rock probe sees the floor coming, down to contact', () async {
      await h.loadLevel(10, skipHazards: true);
      final g = h.game;
      final s = g.ship!..launch();
      final gaps = <double>[];
      for (var i = 0; i < 60 * 30 && g.scrapesThisRun == 0; i++) {
        s.body
          ..linearVelocity = Vector2(0, 0.4)
          ..angularVelocity = 0;
        s.body.setTransform(s.body.position, 0);
        final near = probeRockNearby(g.world, s);
        if (near != null && near.gap < 1.0 && near.normal.y < -0.5) {
          gaps.add(near.gap);
          expect(near.approach, closeTo(0.4 * -near.normal.y, 0.05));
        }
        g.update(kStepDt);
        await Future<void>.delayed(Duration.zero);
      }
      expect(g.scrapesThisRun, greaterThan(0));
      expect(gaps.length, greaterThan(20));
      expect(gaps.first, greaterThan(0.8));
      expect(gaps.last, lessThan(0.05));
    });

    for (final (name, level) in [('tutorial walls', 0), ('cave rock', 10)]) {
      test('$name: a gentle landing rests, a hard one crashes', () async {
        var g = await drop(level, 0.6);
        expect(g.runState, RunState.playing, reason: 'soft landing crashed');
        expect(g.scrapesThisRun, greaterThan(0));
        expect(g.ship!.body.linearVelocity.length, lessThan(0.3));

        g = await drop(level, 2.5);
        expect(g.runState, RunState.gameOver);
      });
    }
  });
}
