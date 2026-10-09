import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/camera/camera_director.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';

const _dt = 1 / 60;

CameraInputs _in({
  double x = 0,
  double y = 0,
  double vx = 0,
  double vy = 0,
  bool launched = true,
  bool towing = false,
  double? podX,
  double? podY,
  double? gap,
  double idle = 0,
}) =>
    CameraInputs(
      shipX: x,
      shipY: y,
      velX: vx,
      velY: vy,
      launched: launched,
      towing: towing,
      podX: podX,
      podY: podY,
      aheadGap: gap,
      idleFor: idle,
      viewHalfW: 15,
      viewHalfH: 7,
    );

/// Runs [seconds] of constant input; returns the last shot.
CameraShot _run(CameraDirector d, CameraInputs i, double seconds, {double dt = _dt}) {
  late CameraShot shot;
  for (var t = 0.0; t < seconds - 1e-9; t += dt) {
    shot = d.update(i, dt);
  }
  return shot;
}

CameraDirector _dynamic() => CameraDirector(CameraMode.dynamicZoom.profile)..reset(0, 0);

void main() {
  group('Dynamic camera', () {
    test('a still ship zooms in after the rest delay, not before', () {
      final d = _dynamic();
      final p = CameraMode.dynamicZoom.profile;
      expect(_run(d, _in(), p.restDelay - 0.05).zoom, closeTo(1, 1e-6));
      final shot = _run(d, _in(), 4);
      expect(shot.zoom, closeTo(1 + p.restZoomIn, 0.005));
    });

    test('speeding up zooms out quickly', () {
      final d = _dynamic();
      final p = CameraMode.dynamicZoom.profile;
      final shot = _run(d, _in(vx: 3.5), 0.5);
      final full = 1 - p.speedZoomOut;
      expect(1 - shot.zoom, greaterThan(0.9 * (1 - full)));
    });

    test('speed wobbling at the threshold does not pump the zoom', () {
      final d = _dynamic();
      final p = CameraMode.dynamicZoom.profile;
      // Settle first, then wobble ±0.3 m/s around the low threshold.
      _run(d, _in(vx: p.speedLo), 3);
      final zooms = <double>[];
      for (var f = 0; f < 600; f++) {
        final v = p.speedLo + 0.3 * math.sin(f * 2 * math.pi / 40);
        zooms.add(d.update(_in(vx: v), _dt).zoom);
      }
      final tail = zooms.sublist(300);
      expect(tail.reduce(math.max) - tail.reduce(math.min), lessThan(0.01));
    });

    test('fast at a wall zooms out more; creeping up to it zooms in', () {
      final open = _run(_dynamic(), _in(vx: 3), 2).zoom;
      final wall = _run(_dynamic(), _in(vx: 3, gap: 3), 2).zoom;
      expect(wall, lessThan(open - 0.03));
      final creep = _run(_dynamic(), _in(vx: 0.4, gap: 1.5), 4).zoom;
      expect(creep, greaterThan(1.05));
    });

    test('letting go of the controls zooms in, even while falling', () {
      final d = _dynamic();
      final p = CameraMode.dynamicZoom.profile;
      // Flying fast: zoomed out.
      expect(_run(d, _in(vy: 2.5), 2).zoom, lessThan(0.95));
      // Hands off, still falling at 2.5 m/s in open space: closes in.
      var idle = 0.0;
      late CameraShot shot;
      for (var f = 0; f < 240; f++) {
        idle += _dt;
        shot = d.update(_in(vy: 2.5, idle: idle), _dt);
      }
      expect(shot.zoom, closeTo(1 + p.restZoomIn, 0.01));
    });

    test('hands off but rock coming up fast still opens the view', () {
      final shot = _run(_dynamic(), _in(vy: 3, gap: 2, idle: 5), 2);
      expect(shot.zoom, lessThan(1));
    });

    test('never further out than the floor', () {
      final d = _dynamic();
      final shot = _run(d, _in(vx: 9, gap: 0.5), 3);
      expect(shot.zoom, greaterThanOrEqualTo(CameraDirector.minZoom - 1e-9));
      expect(CameraDirector.minZoom, greaterThanOrEqualTo(0.85));
    });

    test('a towed pod 6 m below stays inside the view margin', () {
      final d = _dynamic();
      final p = CameraMode.dynamicZoom.profile;
      final shot = _run(d, _in(towing: true, podX: 0, podY: 6), 3);
      final halfH = 7 / shot.zoom;
      expect((6 - shot.y).abs(), lessThanOrEqualTo(halfH * (1 - p.podMargin) + 0.05));
      expect(shot.y, greaterThan(0.5)); // aimed toward the pod
    });

    test('stays within the zoom range', () {
      final d = _dynamic();
      final shot = _run(d, _in(vx: 9, gap: 0.5, towing: true, podX: 0, podY: 20), 3);
      expect(shot.zoom, greaterThanOrEqualTo(CameraDirector.minZoom - 1e-9));
    });

    test('60 Hz and 120 Hz give the same flight', () {
      CameraShot fly(double dt) {
        final d = _dynamic();
        _run(d, _in(), 2, dt: dt);
        _run(d, _in(vx: 3, vy: -1), 1, dt: dt);
        return _run(d, _in(x: 3, vx: 0.2), 3, dt: dt);
      }

      final a = fly(1 / 60), b = fly(1 / 120);
      expect(a.zoom, closeTo(b.zoom, 2e-3));
      expect(a.x, closeTo(b.x, 2e-2));
      expect(a.y, closeTo(b.y, 2e-2));
    });
  });

  test('Centred keeps the ship centred at one zoom', () {
    final d = CameraDirector(CameraMode.centered.profile)..reset(0, 0);
    _run(d, _in(vx: 5, gap: 1, towing: true, podX: 0, podY: 9), 2);
    final shot = _run(d, _in(x: 4, y: 2), 2);
    expect(shot.zoom, 1);
    expect(shot.x, closeTo(4, 1e-3));
    expect(shot.y, closeTo(2, 1e-3));
  });

  test('Look-ahead keeps the original tow zoom-out', () {
    final d = CameraDirector(CameraMode.lookAhead.profile)..reset(0, 0);
    final shot = _run(d, _in(towing: true, podX: 0, podY: 1), 3);
    expect(shot.zoom, closeTo(1 - CameraMode.lookAhead.profile.towZoomOut, 0.005));
  });

  group('safe frame', () {
    const w = 844.0, h = 390.0;
    // A dial bottom-left and a THRUST cluster bottom-right.
    const dial = (l: 30.0, t: 230.0, r: 200.0, b: 380.0);
    const thrust = (l: 650.0, t: 160.0, r: 844.0, b: 390.0);
    const zones = [dial, thrust];

    test('a ship under the dial is pushed up, out of it', () {
      final (dx, dy) = safeFrameNudge(110, 260, 20, zones, w, h);
      expect(dx, 0);
      expect(260 + dy, lessThanOrEqualTo(dial.t - 20));
    });

    test('in a low corner of the cluster it takes the shorter way, inward', () {
      final (dx, dy) = safeFrameNudge(665, 370, 10, zones, w, h);
      expect(dy, 0);
      expect(665 + dx, lessThanOrEqualTo(thrust.l - 10));
    });

    test('never pushes toward a screen edge', () {
      final (dx, dy) = safeFrameNudge(60, 300, 10, zones, w, h);
      expect(dx, greaterThanOrEqualTo(0));
      expect(dy, lessThanOrEqualTo(0));
    });

    test('a top gauge pushes down, not up', () {
      const gauge = (l: 0.0, t: 0.0, r: 240.0, b: 96.0);
      final (_, dy) = safeFrameNudge(120, 60, 10, [gauge], w, h);
      expect(dy, greaterThan(0));
    });

    test('clear of every zone: no nudge', () {
      expect(safeFrameNudge(422, 195, 30, zones, w, h), (0.0, 0.0));
    });
  });

  test('trauma shake is bounded and calms down', () {
    final s = TraumaShake()..add(1);
    var peak = 0.0;
    for (var f = 0; f < 120; f++) {
      s.update(_dt);
      final (x, y) = s.offset;
      peak = math.max(peak, math.sqrt(x * x + y * y));
    }
    expect(peak, lessThanOrEqualTo(s.maxOffset * math.sqrt2));
    expect(peak, greaterThan(0));
    expect(s.offset, (0.0, 0.0));
    s.floor = 0.3;
    s.update(_dt);
    expect(s.trauma, 0.3);
  });
}
