import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/ui/launch_intro.dart';

import 'helpers/pump.dart';

void main() {
  Future<int Function()> pump(
    WidgetTester tester,
    Future<void> ready, {
    Size size = const Size(844, 390),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LaunchIntro(ready: ready, onDone: () => done++),
      ),
    );
    return () => done;
  }

  testWidgets('holds until the game has loaded, then fades out', (
    tester,
  ) async {
    final ready = Completer<void>();
    final done = await pump(tester, ready.future);
    expect(find.text('NARROW HAUL'), findsOneWidget);

    // Loading takes a while: it stays, and a tap can't skip it.
    await advance(tester, const Duration(seconds: 3));
    await tester.tap(find.byType(LaunchIntro));
    await advance(tester, const Duration(seconds: 1));
    expect(done(), 0);

    ready.complete();
    await advance(tester, const Duration(milliseconds: 500));
    expect(done(), 1);
  });

  testWidgets('a fast load waits only for the ~1 s entrance', (tester) async {
    final done = await pump(tester, Future<void>.value());
    await advance(tester, const Duration(milliseconds: 700));
    expect(done(), 0, reason: 'no flicker');
    await advance(tester, const Duration(milliseconds: 700));
    expect(done(), 1, reason: 'never holds a loaded game back');
    await advance(tester, const Duration(seconds: 2));
    expect(done(), 1, reason: 'onDone fires once');
  });

  testWidgets('a tap after loading skips the entrance', (tester) async {
    final done = await pump(tester, Future<void>.value());
    await advance(tester, const Duration(milliseconds: 100));
    await tester.tap(find.byType(LaunchIntro));
    await advance(tester, const Duration(milliseconds: 600));
    expect(done(), 1, reason: 'well before the 900 ms entrance ends');
  });

  testWidgets('a failed load still lets the player in', (tester) async {
    final ready = Completer<void>();
    final done = await pump(tester, ready.future);
    ready.completeError(StateError('load failed'));
    await advance(tester, const Duration(seconds: 2));
    expect(done(), 1, reason: 'leaves after the entrance');
  });

  testWidgets('a hung load leaves after kReadyFallback', (tester) async {
    final done = await pump(tester, Completer<void>().future);
    await advance(tester, kReadyFallback - const Duration(seconds: 1));
    expect(done(), 0);
    await advance(tester, const Duration(seconds: 2));
    expect(done(), 1);
  });

  testWidgets('lays out on phones, tablets and portrait', (tester) async {
    for (final size in const [
      Size(568, 320),
      Size(844, 390),
      Size(1366, 1024),
      Size(390, 844),
    ]) {
      await pump(tester, Completer<void>().future, size: size);
      await advance(tester, const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  test('the orbit passes behind the planet and back in front', () {
    final g = OrbitGeometry(const Size(844, 390));
    expect(g.craftAt(1.5708).depth, greaterThan(0.9));
    expect(g.craftAt(-1.5708).depth, lessThan(-0.9));
    expect(g.craftAt(1.5708).scale, greaterThan(g.craftAt(-1.5708).scale));
  });
}
