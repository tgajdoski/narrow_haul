import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/ui/licenses_screen.dart';
import 'package:narrow_haul/ui/space_ui.dart';

Stream<LicenseEntry> _entries() async* {
  yield const LicenseEntryWithLineBreaks([
    'flame',
  ], 'MIT License\n\nFlame text');
  yield const LicenseEntryWithLineBreaks(['Music'], 'Music credit');
  yield const LicenseEntryWithLineBreaks(['RussoOne'], 'OFL text');
  yield const LicenseEntryWithLineBreaks([
    'flame',
    'forge2d',
  ], 'BSD License\n\nShared text');
}

void main() {
  test('groups by package, the game assets first', () async {
    final groups = groupLicenses(await _entries().toList());
    expect(groups.map((g) => g.package), [
      'RussoOne',
      'Music',
      'flame',
      'forge2d',
    ]);
    expect(groups[2].texts, hasLength(2));
  });

  Future<void> pump(WidgetTester tester, Size size, double scale) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LicensesScreen(entries: _entries()),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final size in const [
    Size(844, 390),
    Size(667, 375),
    Size(568, 320),
    Size(1366, 1024),
  ]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('lays out and opens a licence at $size ×$scale', (
        tester,
      ) async {
        await pump(tester, size, scale);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('forge2d'));
        await tester.pumpAndSettle();
        expect(find.text('Shared text'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Back: a narrow screen returns to the list first, then Settings.
        final wide = size.width - 24 >= 600;
        await tester.tap(find.byType(HoloBackButton));
        await tester.pumpAndSettle();
        if (!wide) {
          expect(find.text('forge2d'), findsOneWidget);
          await tester.tap(find.byType(HoloBackButton));
          await tester.pumpAndSettle();
        }
        expect(find.text('open'), findsOneWidget);
      });
    }
  }
}
