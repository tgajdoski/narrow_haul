import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/run/snapshot_buffer.dart';

FlightSnapshot snap(double t, {bool attached = false}) => FlightSnapshot(
  time: t,
  shipPos: Vector2.zero(),
  shipAngle: 0,
  fuel: 1,
  cargoPos: Vector2.zero(),
  cargoAngle: 0,
  attached: attached,
);

void main() {
  test('samples every interval and keeps only the newest', () {
    final b = SnapshotBuffer(every: 0.5, keep: 3);
    expect(b.due(0.3), isFalse);
    expect(b.due(0.3), isTrue);
    expect(b.due(0.3), isFalse);
    for (var i = 0; i < 5; i++) {
      b.add(snap(i.toDouble()));
    }
    expect(b.length, 3);
    // Oldest kept is t=2.
    expect(b.pick(attached: false, crashTime: 10, rewind: 7.5)?.time, 2);
  });

  test('picks the newest snapshot far enough back with the same tow state', () {
    final b = SnapshotBuffer()
      ..add(snap(1))
      ..add(snap(2, attached: true))
      ..add(snap(3))
      ..add(snap(4));
    expect(b.pick(attached: false, crashTime: 5, rewind: 1.5)?.time, 3);
    // Nothing old enough: the newest with the same tow state.
    expect(b.pick(attached: false, crashTime: 4.2, rewind: 5)?.time, 4);
    expect(b.pick(attached: true, crashTime: 5, rewind: 1)?.time, 2);
  });

  test('clear keeps the timer, reset restarts it', () {
    final b = SnapshotBuffer(every: 1)..add(snap(0));
    b.due(0.6);
    b.clear();
    expect(b.length, 0);
    expect(b.due(0.6), isTrue);
    b.due(0.6);
    b.reset();
    expect(b.due(0.6), isFalse);
  });
}
