import 'dart:math' as math;
import 'dart:ui';

import 'package:narrow_haul/game/ship/flight_tuning.dart';

/// Two-finger pinch on the flight view, pure Dart. Fingers that land on a
/// [blocked] spot (THRUST, FIRE, the ammo rail) never count; any two others
/// make a pinch, and the zoom follows the spread between them.
class PinchZoom {
  /// Spread (px) the fingers must change by before the zoom moves, so two
  /// thumbs landing together don't nudge it.
  static const double slop = 12;

  final _free = <int, Offset>{};
  final _blocked = <int>{};

  double? _startSpread;
  double _startZoom = 1;
  bool _moved = false;

  /// Two free fingers are down: steering waits until they lift.
  bool get active => _free.length == 2 && _startSpread != null;

  /// Returns true when a pinch starts.
  bool down(int id, Offset at, {required double zoom, bool blocked = false}) {
    if (blocked || _free.length >= 2) {
      _blocked.add(id);
      return false;
    }
    _free[id] = at;
    if (_free.length < 2) return false;
    _startSpread = _spread;
    _startZoom = zoom;
    _moved = false;
    return true;
  }

  /// The new zoom while pinching, else null.
  double? move(int id, Offset at) {
    if (!_free.containsKey(id)) return null;
    _free[id] = at;
    final start = _startSpread;
    if (!active || start == null || start < 1) return null;
    final spread = _spread;
    if (!_moved && (spread - start).abs() < slop) return null;
    _moved = true;
    return clampZoom(_startZoom * spread / start);
  }

  /// Returns true when a pinch that changed the zoom ends.
  bool up(int id) {
    _blocked.remove(id);
    if (_free.remove(id) == null) return false;
    final ended = _startSpread != null && _moved;
    _startSpread = null;
    _moved = false;
    return ended;
  }

  void clear() {
    _free.clear();
    _blocked.clear();
    _startSpread = null;
    _moved = false;
  }

  double get _spread {
    final p = _free.values.toList();
    return (p[0] - p[1]).distance;
  }

  static double clampZoom(double z) => FlightTuning.clampZoom(z);

  /// One mouse-wheel notch or key press: 10% in or out.
  static double step(double zoom, int notches) =>
      clampZoom(zoom * math.pow(1.1, notches));
}
