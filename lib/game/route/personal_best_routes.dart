import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:narrow_haul/game/env.dart';
import 'package:narrow_haul/game/route/flight_route.dart';
import 'package:narrow_haul/game/services/error_reporter.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:path_provider/path_provider.dart';

/// The pilot's own best flight per level, kept on this device for the ghost
/// race: `<app support>/pb_routes/<saveId>.json`. The time lives in prefs
/// ([ProgressCareer.pbRouteSeconds]); a file without it (after a reset) is
/// ignored and later overwritten.
class PersonalBestRoutes {
  PersonalBestRoutes._();

  /// Tests point this at a temp folder (no platform channel there).
  @visibleForTesting
  static Directory? debugDir;

  static final Map<String, FlightRoute?> _cache = {};

  static Future<Directory> _dir() async {
    final base = debugDir ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/pb_routes');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Under `flutter test` there's no app folder: only a test that sets
  /// [debugDir] keeps ghosts.
  static bool get _off => kInFlutterTest && debugDir == null;

  /// Whether [seconds] would beat the saved ghost (or there is none).
  static bool beats(String saveId, double seconds) {
    final best = ProgressService.instance.pbRouteSeconds(saveId);
    return best == null || seconds < best;
  }

  static Future<FlightRoute?> load(String saveId) async {
    if (_off) return null;
    if (ProgressService.instance.pbRouteSeconds(saveId) == null) return null;
    if (_cache.containsKey(saveId)) return _cache[saveId];
    FlightRoute? route;
    try {
      final file = File('${(await _dir()).path}/$saveId.json');
      if (file.existsSync()) {
        route = FlightRoute.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'pb route $saveId');
    }
    _cache[saveId] = route;
    return route;
  }

  /// Keeps [route] as the level's ghost if it's faster than the saved one.
  static Future<void> saveIfBest(FlightRoute route) async {
    if (_off || !beats(route.saveId, route.seconds)) return;
    try {
      final file = File('${(await _dir()).path}/${route.saveId}.json');
      await file.writeAsString(jsonEncode(route.toJson()));
      await ProgressService.instance.setPbRouteSeconds(route.saveId, route.seconds);
      _cache[route.saveId] = route;
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'save pb route ${route.saveId}');
    }
  }

  @visibleForTesting
  static void debugClearCache() => _cache.clear();
}
