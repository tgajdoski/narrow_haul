import 'dart:collection';

import 'package:flame/components.dart';

/// One safe point of a flight, for "continue after crash".
class FlightSnapshot {
  FlightSnapshot({
    required this.time,
    required this.shipPos,
    required this.shipAngle,
    required this.fuel,
    required this.cargoPos,
    required this.cargoAngle,
    required this.attached,
  });

  final double time;
  final Vector2 shipPos;
  final double shipAngle;
  final double fuel;
  final Vector2 cargoPos;
  final double cargoAngle;
  final bool attached;
}

/// The newest few seconds of safe points: one every [every] seconds of
/// flight, at most [keep] of them (oldest dropped first).
class SnapshotBuffer {
  SnapshotBuffer({this.every = 0.5, this.keep = 10});

  final double every;
  final int keep;
  final ListQueue<FlightSnapshot> _snaps = ListQueue();
  double _timer = 0;

  int get length => _snaps.length;

  /// Forgets every snapshot and restarts the sample timer.
  void reset() {
    _snaps.clear();
    _timer = 0;
  }

  /// Forgets every snapshot; the sample timer keeps running.
  void clear() => _snaps.clear();

  /// Advances the timer by [dt]; true when a sample is due (the timer then
  /// starts over, whether or not the caller finds a safe spot to add).
  bool due(double dt) {
    _timer += dt;
    if (_timer < every) return false;
    _timer = 0;
    return true;
  }

  void add(FlightSnapshot snap) {
    _snaps.addLast(snap);
    if (_snaps.length > keep) _snaps.removeFirst();
  }

  /// Newest snapshot at least [rewind] seconds before [crashTime] with the
  /// same tow state ([attached]: the rope never has to snap to a different
  /// length); else the newest one with that tow state.
  FlightSnapshot? pick({
    required bool attached,
    required double crashTime,
    required double rewind,
  }) {
    FlightSnapshot? fallback;
    for (var i = _snaps.length - 1; i >= 0; i--) {
      final snap = _snaps.elementAt(i);
      if (snap.attached != attached) continue;
      if (crashTime - snap.time >= rewind) return snap;
      fallback ??= snap;
    }
    return fallback;
  }
}
