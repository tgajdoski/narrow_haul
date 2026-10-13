import 'package:flutter/services.dart';

/// Full screen, as a game should be: hides the status bar (clock, battery)
/// and the navigation bar. A swipe from the edge shows them for a moment,
/// then they hide again. Android brings the bars back after the app is
/// backgrounded or a full-screen ad closes, so the game calls this again on
/// every resume. iOS ignores it in landscape (no status bar there anyway).
Future<void> applyImmersiveMode() =>
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
