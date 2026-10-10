import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSVColor;
import 'package:narrow_haul/game/services/cosmetics_service.dart';

/// Garage looks, shared by everything that draws the ship outside a flight
/// (the Garage turntable, the briefing's ship card).
///
/// The values match `ShipBody._skinTints` and `ThrustPlume`'s procedural
/// colours; those copies move here once their files are free to edit.

/// Livery tints over the ship's own art (`srcATop`).
const Map<String, Color> kLiveryTints = {
  'ship_neon': Color(0x88FF00FF),
  'ship_stealth': Color(0xCC000000),
  'ship_gold': Color(0xAAFFD700),
  'ship_carbon': Color(0x99404855),
  'ship_gold_trim': Color(0x55FFD166),
  kSupporterSkinId: Color(0x7733D6C9),
  'ship_xenar': Color(0x7700E5A0),
  'ship_rust': Color(0x88B5651D),
  'ship_glacier': Color(0x77BDEBFF),
  'ship_ember': Color(0x88FF5A1F),
  'ship_orbit': Color(0x777B61FF),
  'ship_redoubt': Color(0x88556B2F),
};

/// A plume's core, middle and outer colours at [time] s (the rainbow and
/// aurora plumes cycle).
(Color, Color, Color) plumePalette(String? id, double time) {
  switch (id) {
    case 'plume_green':
      return (const Color(0xFFCCFFCC), const Color(0xFF00AA00), const Color(0xFF004400));
    case 'plume_red':
      return (const Color(0xFFFFCCCC), const Color(0xFFAA0000), const Color(0xFF440000));
    case 'plume_rainbow':
      final hue = (time * 200) % 360;
      return (
        HSVColor.fromAHSV(1, hue, 0.2, 1).toColor(),
        HSVColor.fromAHSV(1, hue, 0.8, 1).toColor(),
        HSVColor.fromAHSV(1, hue, 1, 0.8).toColor(),
      );
    case 'plume_cryo':
      return (const Color(0xFFE0FFFF), const Color(0xFF00B8D4), const Color(0xFF004D60));
    case 'plume_plasma':
      return (const Color(0xFFF8E1FF), const Color(0xFFD500F9), const Color(0xFF4A148C));
    case 'plume_afterburner':
      return (const Color(0xFFE0F2FF), const Color(0xFFFF9F1C), const Color(0xFF7B2CBF));
    case 'plume_aurora':
      final hue = 150 + 70 * math.sin(time * 3);
      return (
        HSVColor.fromAHSV(1, hue, 0.2, 1).toColor(),
        HSVColor.fromAHSV(1, hue, 0.8, 1).toColor(),
        HSVColor.fromAHSV(1, (hue + 60) % 360, 1, 0.8).toColor(),
      );
    default:
      return (const Color(0xFFFFEFCC), const Color(0xFFFFAA00), const Color(0xFFFF4400));
  }
}
