import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/ui/feedback_mail.dart';
import 'package:narrow_haul/ui/space_ui.dart';

Widget _box(Widget child, {double width = 120}) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: width, child: child)),
  ),
);

double _textX(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dx;

void main() {
  testWidgets('text that fits is a plain Text, no animation', (tester) async {
    await tester.pumpWidget(_box(const MarqueeText('HANGAR', animate: true)));
    expect(
      find.descendant(
        of: find.byType(MarqueeText),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('cut-off text holds, scrolls to its end and comes back', (
    tester,
  ) async {
    const long = 'WATCH A DEMO FLIGHT THROUGH THE WHOLE CAVE';
    await tester.pumpWidget(_box(const MarqueeText(long, animate: true)));
    final start = _textX(tester, long);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_textX(tester, long), start, reason: 'holds at the start');
    await tester.pump(const Duration(seconds: 3));
    expect(_textX(tester, long), lessThan(start - 20), reason: 'scrolled');
    // A full loop later it's back at the start.
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with animations off it keeps the ellipsis', (tester) async {
    const long = 'WATCH A DEMO FLIGHT THROUGH THE WHOLE CAVE';
    await tester.pumpWidget(_box(const MarqueeText(long)));
    final text = tester.widget<Text>(find.text(long));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.hasRunningAnimations, isFalse);
  });

  test('feedback mail is addressed and pre-filled', () {
    final uri = feedbackMailUri(
      version: '1.0.0+5',
      os: 'ios 18.0',
      levelId: 'lava_08',
      rank: 'Captain',
    );
    expect(uri.scheme, 'mailto');
    expect(uri.path, kFeedbackEmail);
    final s = uri.toString();
    expect(s, isNot(contains('+')), reason: 'spaces are %20, not +');
    expect(Uri.decodeComponent(s), contains('Narrow Haul feedback'));
    expect(Uri.decodeComponent(s), contains('App 1.0.0+5 · ios 18.0'));
    expect(Uri.decodeComponent(s), contains('Mission lava_08 · Captain'));
  });
}
