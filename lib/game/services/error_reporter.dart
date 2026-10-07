import 'package:flutter/foundation.dart';

/// One place for uncaught and caught-but-unexpected errors.
///
/// [install] routes Flutter framework errors and uncaught async errors here,
/// so a bug in release builds is reported instead of silently killing a frame.
/// A crash-reporting service plugs in through [sink] (e.g. Crashlytics'
/// `recordError`); without one, errors are only printed in debug builds.
class ErrorReporter {
  ErrorReporter._();

  /// Forwards every reported error (set once by the crash-reporting setup).
  static void Function(Object error, StackTrace? stack, String? context)? sink;

  static void report(Object error, StackTrace? stack, {String? context}) {
    if (kDebugMode) {
      debugPrint('ErrorReporter${context == null ? '' : ' ($context)'}: $error');
      if (stack != null) debugPrint('$stack');
    }
    try {
      sink?.call(error, stack, context);
    } catch (_) {
      // Reporting must never throw.
    }
  }

  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details); // keeps the red-screen / console dump in debug
      report(details.exception, details.stack, context: details.context?.toString());
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, context: 'uncaught');
      return true; // handled: don't crash the app over a stray async error
    };
  }
}
