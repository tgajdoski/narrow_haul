import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/game/route/flight_route.dart';

/// Bundled recorded flights: `assets/routes/<saveId>.json`, written by the
/// autopilot (`--dart-define=EXPORT_ROUTES=true`). Missing file = no route.
class RouteRepository {
  RouteRepository._();

  static String assetPath(String saveId) => 'assets/routes/$saveId.json';

  static final Map<String, FlightRoute?> _cache = {};

  static Future<FlightRoute?> load(String saveId, {AssetBundle? bundle}) async {
    if (_cache.containsKey(saveId)) return _cache[saveId];
    FlightRoute? route;
    try {
      final text = await (bundle ?? rootBundle).loadString(assetPath(saveId));
      route = FlightRoute.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (e) {
      // Missing asset is the normal "no route" case; anything else is a bug.
      if (e is! FlutterError) debugPrint('RouteRepository: $saveId: $e');
      route = null;
    }
    _cache[saveId] = route;
    return route;
  }

  @visibleForTesting
  static void debugSet(String saveId, FlightRoute? route) => _cache[saveId] = route;

  @visibleForTesting
  static void debugClear() => _cache.clear();
}
