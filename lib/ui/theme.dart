
import 'package:flutter/material.dart';
import 'package:narrow_haul/ui/fonts.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// Dark theme; display/headline/title styles use the bundled RussoOne face
/// (titles only — body text stays on the platform font for legibility).
ThemeData buildAppTheme() {
  final base = ThemeData.dark().copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: SpaceColors.cyan,
      brightness: Brightness.dark,
    ),
  );
  TextStyle? display(TextStyle? s) => s?.copyWith(fontFamily: kDisplayFont);
  final t = base.textTheme;
  return base.copyWith(
    textTheme: t.copyWith(
      displayLarge: display(t.displayLarge),
      displayMedium: display(t.displayMedium),
      displaySmall: display(t.displaySmall),
      headlineLarge: display(t.headlineLarge),
      headlineMedium: display(t.headlineMedium),
      headlineSmall: display(t.headlineSmall),
      titleLarge: display(t.titleLarge),
      titleMedium: display(t.titleMedium),
    ),
  );
}
