import 'package:flutter/material.dart';

/// Atmospheric particle style drifting through a world's caves.
enum AmbientKind { none, spores, dust, snow, embers }

/// Per-world visual identity: backdrop, rock palette, parallax tint, pad and
/// UI accent colors. Purely cosmetic — physics modifiers live on the level.
class ThemeSpec {
  const ThemeSpec({
    required this.id,
    required this.name,
    required this.backdropColor,
    required this.rockFill,
    required this.rockEdge,
    required this.rockHighlight,
    required this.parallaxTint,
    this.parallaxAlphas = const [0.50, 0.72, 0.92],
    required this.padBase,
    required this.padAccent,
    required this.uiAccent,
    required this.decorTip,
    this.edgeGlow,
    this.ambient = AmbientKind.none,
    this.decorDensity = 1.0,
    this.rockTextureMeters = 8.0,
  });

  final String id;
  final String name;
  final Color backdropColor;
  final Color rockFill;
  final Color rockEdge;
  final Color rockHighlight;

  /// Modulate-blended onto the shared far/mid/near parallax sprites.
  final Color parallaxTint;
  final List<double> parallaxAlphas;
  final Color padBase;
  final Color padAccent;
  final Color uiAccent;

  /// Tip color of the procedural stalactite/stalagmite spikes drawn when the
  /// world has no `decor.png` sprite sheet.
  final Color decorTip;

  /// Blurred glow along cave edges (lava heat, ice frost); null = none.
  final Color? edgeGlow;
  final AmbientKind ambient;

  /// Multiplier on how many edge props are placed (0 disables decor).
  final double decorDensity;

  /// World size (meters) one tile of `rock.png` covers.
  final double rockTextureMeters;

  /// Optional art lives in `assets/themes/<id>/` — see the README there.
  String get assetDir => 'themes/$id';
}

/// Matches the game's original look — used by the TMX tutorial world.
const tutorialTheme = ThemeSpec(
  id: 'tutorial',
  name: 'Training Grounds',
  backdropColor: Color(0xFF0B132B),
  rockFill: Color(0xFF1D3461),
  rockEdge: Color(0xFF0B1929),
  rockHighlight: Color(0x2287B5E0),
  parallaxTint: Colors.white,
  padBase: Color(0xFF415A77),
  padAccent: Color(0xFF94D2BD),
  uiAccent: Color(0xFF00B4D8),
  decorTip: Color(0xFF87B5E0),
  decorDensity: 0.0,
);

const alienTheme = ThemeSpec(
  id: 'alien',
  name: 'Xenar Caverns',
  backdropColor: Color(0xFF150A2E),
  rockFill: Color(0xFF3B2166),
  rockEdge: Color(0xFF1B0B33),
  rockHighlight: Color(0x3387E0C8),
  parallaxTint: Color(0xFFB58CFF),
  padBase: Color(0xFF4A3A77),
  padAccent: Color(0xFF7EF9D2),
  uiAccent: Color(0xFFB388FF),
  decorTip: Color(0xFF7EF9D2),
  edgeGlow: Color(0x557EF9D2),
  ambient: AmbientKind.spores,
);

const mineTheme = ThemeSpec(
  id: 'mine',
  name: 'Rustshaft Mines',
  backdropColor: Color(0xFF19110A),
  rockFill: Color(0xFF4A3524),
  rockEdge: Color(0xFF211509),
  rockHighlight: Color(0x33E0B587),
  parallaxTint: Color(0xFFD2A268),
  parallaxAlphas: [0.35, 0.55, 0.80],
  padBase: Color(0xFF5E4A34),
  padAccent: Color(0xFFFFC974),
  uiAccent: Color(0xFFFFB74D),
  decorTip: Color(0xFFB08A5E),
  ambient: AmbientKind.dust,
  decorDensity: 0.7,
);

const iceTheme = ThemeSpec(
  id: 'ice',
  name: 'Glacier Deep',
  backdropColor: Color(0xFF0A1B2B),
  rockFill: Color(0xFF35617F),
  rockEdge: Color(0xFF122B3B),
  rockHighlight: Color(0x55CFEBFF),
  parallaxTint: Color(0xFFA8D8FF),
  padBase: Color(0xFF3E6A8A),
  padAccent: Color(0xFFBDEBFF),
  uiAccent: Color(0xFF81D4FA),
  decorTip: Color(0xFFE6F7FF),
  edgeGlow: Color(0x66BDEBFF),
  ambient: AmbientKind.snow,
  decorDensity: 1.4,
);

const lavaTheme = ThemeSpec(
  id: 'lava',
  name: 'Ember Core',
  backdropColor: Color(0xFF1A0605),
  rockFill: Color(0xFF4A1B12),
  rockEdge: Color(0xFF200604),
  rockHighlight: Color(0x66FF6B35),
  parallaxTint: Color(0xFFFF8A65),
  parallaxAlphas: [0.40, 0.60, 0.85],
  padBase: Color(0xFF5E2A1E),
  padAccent: Color(0xFFFFAB70),
  uiAccent: Color(0xFFFF7043),
  decorTip: Color(0xFFFF8A3D),
  edgeGlow: Color(0x99FF5A1F),
  ambient: AmbientKind.embers,
);

const Map<String, ThemeSpec> gameThemes = {
  'tutorial': tutorialTheme,
  'alien': alienTheme,
  'mine': mineTheme,
  'ice': iceTheme,
  'lava': lavaTheme,
};
