import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/ui/delivered_by_screen.dart';

import 'helpers/pump.dart';

Opacity _nameOpacity(WidgetTester tester, String name) =>
    tester.widget<Opacity>(
      find.ancestor(of: find.text(name), matching: find.byType(Opacity)).first,
    );

void main() {
  Future<int Function()> pump(WidgetTester tester, Future<void> ready) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DeliveredByScreen(ready: ready, onDone: () => done++),
      ),
    );
    return () => done;
  }

  testWidgets('names appear one by one, then it waits for the game', (
    tester,
  ) async {
    final ready = Completer<void>();
    final done = await pump(tester, ready.future);
    final names = kDeliveredBy.map((c) => c.name).toList();

    // Before the first pop nobody is visible.
    await advance(tester, const Duration(milliseconds: 400));
    for (final n in names) {
      expect(_nameOpacity(tester, n).opacity, 0);
    }
    // Each name shows after its own pop, in order.
    for (var i = 0; i < names.length; i++) {
      await advance(tester, const Duration(milliseconds: 450));
      expect(_nameOpacity(tester, names[i]).opacity, greaterThan(0));
      if (i + 1 < names.length) {
        expect(_nameOpacity(tester, names[i + 1]).opacity, 0);
      }
    }

    // Animation over, game not loaded: it holds, and taps don't skip.
    await advance(tester, const Duration(seconds: 3));
    await tester.tap(find.byType(DeliveredByScreen));
    await advance(tester, const Duration(seconds: 1));
    expect(done(), 0);

    ready.complete();
    await advance(tester, const Duration(seconds: 2));
    expect(done(), 1);
  });

  testWidgets('a tap skips once the game is ready', (tester) async {
    final done = await pump(tester, Future<void>.value());
    await advance(tester, const Duration(milliseconds: 300));
    await tester.tap(find.byType(DeliveredByScreen));
    await advance(tester, const Duration(milliseconds: 500));
    expect(done(), 1);
    await advance(tester, const Duration(seconds: 3));
    expect(done(), 1, reason: 'onDone fires once');
  });

  testWidgets('plays about three seconds when already loaded', (tester) async {
    final done = await pump(tester, Future<void>.value());
    await advance(tester, const Duration(milliseconds: 2400));
    expect(done(), 0, reason: 'not too short');
    await advance(tester, const Duration(milliseconds: 1200));
    await advance(tester, const Duration(milliseconds: 400));
    expect(done(), 1, reason: 'not too long');
  });
}
