import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// True while running under `flutter test`, where looping animations, real
/// services and the hull lighting bake are switched off.
final bool kInFlutterTest =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
