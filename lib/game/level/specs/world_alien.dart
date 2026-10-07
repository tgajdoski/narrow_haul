import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';

/// Ship flown in this world unless a level overrides it: the light Hopper scout for the low-gravity caverns.
const alienShipId = 'hopper';

/// World 1 — Xenar Caverns. Pure flying skill: curves, chambers, squeezes.
final List<LevelDef> alienLevels = [
  // Type rating: first flight in the Hopper — quick turns, short hops.
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.6, star2Fuel: 0.3, star3Time: 50),
    spec: const LevelSpec(
      id: 'rating_hopper',
      seed: 190,
      name: 'Hopper Type Rating',
      themeId: 'alien',
      worldW: 30,
      worldH: 20,
      modifiers: LevelModifiers(gravityMul: 0.8),
      tunnels: [
        TunnelSpec(
          [Pt(5, 9), Pt(10, 7), Pt(15, 9), Pt(20, 7), Pt(25, 9)],
          width: 2.0,
        ),
        TunnelSpec([Pt(15, 9), Pt(15, 12.5)], width: 1.5),
      ],
      chambers: [
        ChamberSpec(Pt(5, 9), 2.4),
        ChamberSpec(Pt(15, 13), 1.8),
        ChamberSpec(Pt(25, 9), 2.4),
      ],
      shipSpawn: Pt(5, 9),
      cargoSpawn: Pt(15, 13),
      goal: GoalSpec(Pt(25, 10.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.65, star2Fuel: 0.35, star3Time: 55),
    spec: const LevelSpec(
      id: 'alien_01',
      seed: 101,
      name: 'Gentle Descent',
      themeId: 'alien',
      worldW: 34,
      worldH: 22,
      modifiers: LevelModifiers(gravityMul: 0.85),
      tunnels: [
        TunnelSpec(
          [Pt(5, 11), Pt(10, 8), Pt(14, 10), Pt(17, 14), Pt(21, 9), Pt(25, 9), Pt(29, 11)],
          widths: [2.0, 1.8, 1.6, 1.8, 1.6, 1.8, 2.0],
        ),
      ],
      chambers: [
        ChamberSpec(Pt(5, 11), 2.4),
        ChamberSpec(Pt(17, 15), 1.8),
        ChamberSpec(Pt(29, 11), 2.4),
      ],
      shipSpawn: Pt(5, 11),
      cargoSpawn: Pt(17, 15),
      goal: GoalSpec(Pt(29, 12.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.65, star2Fuel: 0.35, star3Time: 55),
    spec: const LevelSpec(
      id: 'alien_02',
      seed: 102,
      name: 'The Wobble',
      themeId: 'alien',
      worldW: 36,
      worldH: 24,
      modifiers: LevelModifiers(gravityMul: 0.8),
      tunnels: [
        TunnelSpec(
          [Pt(5, 12), Pt(9, 8), Pt(13, 16), Pt(18, 7), Pt(23, 16), Pt(27, 8), Pt(31, 12)],
          width: 1.5,
        ),
        TunnelSpec([Pt(13, 16), Pt(18, 17.5)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 12), 2.4),
        ChamberSpec(Pt(18, 17.5), 1.7),
        ChamberSpec(Pt(31, 12), 2.4),
      ],
      shipSpawn: Pt(5, 12),
      cargoSpawn: Pt(18, 17.5),
      goal: GoalSpec(Pt(31, 13.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.65, star2Fuel: 0.35, star3Time: 60),
    spec: const LevelSpec(
      id: 'alien_03',
      seed: 103,
      name: 'First Squeeze',
      themeId: 'alien',
      worldW: 38,
      worldH: 24,
      modifiers: LevelModifiers(gravityMul: 0.75),
      noise: NoiseSpec(amplitude: 0.25),
      tunnels: [
        TunnelSpec([Pt(5, 12), Pt(10, 11), Pt(14, 10)], width: 1.8),
        TunnelSpec(
          [Pt(14, 10), Pt(18, 10.5), Pt(22, 12), Pt(26, 13)],
          widths: [2.0, 1.0, 1.0, 2.0],
        ),
        TunnelSpec([Pt(26, 13), Pt(29, 12), Pt(32, 12)], width: 1.7),
      ],
      chambers: [
        ChamberSpec(Pt(5, 12), 2.4),
        ChamberSpec(Pt(14, 10), 2.6),
        ChamberSpec(Pt(26, 13), 2.8),
        ChamberSpec(Pt(32, 12), 2.4),
      ],
      shipSpawn: Pt(5, 12),
      cargoSpawn: Pt(26, 13.5),
      goal: GoalSpec(Pt(32, 13.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.65, star2Fuel: 0.35, star3Time: 60),
    spec: const LevelSpec(
      id: 'alien_04',
      seed: 104,
      name: 'Down the Gullet',
      themeId: 'alien',
      worldW: 30,
      worldH: 34,
      modifiers: LevelModifiers(gravityMul: 0.7),
      tunnels: [
        TunnelSpec(
          [Pt(15, 5), Pt(10, 10), Pt(18, 15), Pt(9, 21), Pt(15, 26), Pt(15, 29)],
          widths: [2.0, 1.5, 1.4, 1.4, 1.6, 2.0],
        ),
        TunnelSpec([Pt(18, 15), Pt(21, 16)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(15, 5), 2.4),
        ChamberSpec(Pt(21, 16), 1.7),
        ChamberSpec(Pt(15, 29), 2.4),
      ],
      shipSpawn: Pt(15, 5),
      cargoSpawn: Pt(21, 16),
      goal: GoalSpec(Pt(15, 30.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.65, star2Fuel: 0.35, star3Time: 65),
    spec: const LevelSpec(
      id: 'alien_05',
      seed: 105,
      name: 'Antler',
      themeId: 'alien',
      worldW: 40,
      worldH: 26,
      modifiers: LevelModifiers(gravityMul: 0.65),
      tunnels: [
        TunnelSpec(
          [Pt(5, 13), Pt(11, 10), Pt(17, 12), Pt(23, 9), Pt(29, 12), Pt(34, 13)],
          widths: [1.9, 1.6, 1.5, 1.5, 1.7, 2.0],
        ),
        TunnelSpec([Pt(17, 12), Pt(15, 7), Pt(19, 5)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(5, 13), 2.4),
        ChamberSpec(Pt(19, 5), 1.7),
        ChamberSpec(Pt(34, 13), 2.4),
      ],
      shipSpawn: Pt(5, 13),
      cargoSpawn: Pt(19, 5),
      goal: GoalSpec(Pt(34, 14.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.65, star2Fuel: 0.35, star3Time: 65),
    spec: const LevelSpec(
      id: 'alien_06',
      seed: 106,
      name: 'The Loop',
      themeId: 'alien',
      worldW: 40,
      worldH: 28,
      modifiers: LevelModifiers(gravityMul: 0.6),
      tunnels: [
        TunnelSpec(
          [
            Pt(20, 6), Pt(26, 8), Pt(28, 14), Pt(26, 20), Pt(20, 22),
            Pt(14, 20), Pt(12, 14), Pt(14, 8), Pt(20, 6),
          ],
          width: 1.6,
        ),
        TunnelSpec([Pt(6, 14), Pt(12, 14)], width: 1.5),
        TunnelSpec([Pt(28, 14), Pt(34, 14)], width: 1.5),
      ],
      chambers: [
        ChamberSpec(Pt(6, 14), 2.4),
        ChamberSpec(Pt(20, 22), 1.8),
        ChamberSpec(Pt(34, 14), 2.4),
      ],
      shipSpawn: Pt(6, 14),
      cargoSpawn: Pt(20, 22.4),
      goal: GoalSpec(Pt(34, 15.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.65, star2Fuel: 0.35, star3Time: 70),
    spec: const LevelSpec(
      id: 'alien_07',
      seed: 107,
      name: 'Chimneys',
      themeId: 'alien',
      worldW: 36,
      worldH: 32,
      modifiers: LevelModifiers(gravityMul: 0.55),
      tunnels: [
        TunnelSpec([Pt(6, 26), Pt(7, 20), Pt(6, 13), Pt(8, 7)], width: 1.4),
        TunnelSpec([Pt(8, 7), Pt(14, 6), Pt(20, 7)], width: 1.5),
        TunnelSpec([Pt(20, 7), Pt(19, 14), Pt(21, 21), Pt(20, 25)], width: 1.4),
        TunnelSpec([Pt(20, 25), Pt(26, 26), Pt(30, 26)], width: 1.7),
        TunnelSpec([Pt(19, 14), Pt(24, 15)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(6, 26), 2.4),
        ChamberSpec(Pt(24, 15), 1.7),
        ChamberSpec(Pt(30, 26), 2.4),
      ],
      fields: [
        // Zero-g pocket across the top: momentum carries you.
        GravityZoneSpec(Pt(14, 6.5), halfW: 4, halfH: 2.5, gx: 0, gy: 0, feather: 1.2),
      ],
      shipSpawn: Pt(6, 26),
      cargoSpawn: Pt(24, 15.4),
      goal: GoalSpec(Pt(30, 27.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.6, star2Fuel: 0.3, star3Time: 75),
    spec: const LevelSpec(
      id: 'alien_08',
      seed: 108,
      name: 'Xenar Heart',
      themeId: 'alien',
      worldW: 46,
      worldH: 30,
      noise: NoiseSpec(amplitude: 0.24),
      modifiers: LevelModifiers(gravityMul: 0.5),
      tunnels: [
        TunnelSpec(
          [Pt(5, 15), Pt(10, 10), Pt(15, 17), Pt(20, 8), Pt(24, 16)],
          widths: [1.8, 1.4, 1.4, 1.3, 1.6],
        ),
        TunnelSpec(
          [Pt(24, 16), Pt(28, 18), Pt(31, 14)],
          widths: [1.8, 1.0, 1.0],
        ),
        TunnelSpec([Pt(31, 14), Pt(34, 10)], width: 1.2),
        TunnelSpec(
          [Pt(34, 10), Pt(38, 16), Pt(41, 18)],
          widths: [1.5, 1.3, 1.8],
        ),
      ],
      chambers: [
        ChamberSpec(Pt(5, 15), 2.4),
        ChamberSpec(Pt(24, 16), 2.2),
        ChamberSpec(Pt(34, 10), 2.4),
        ChamberSpec(Pt(41, 18), 2.4),
      ],
      shipSpawn: Pt(5, 15),
      cargoSpawn: Pt(24, 16.6),
      goal: GoalSpec(Pt(41, 19.2)),
    ),
  ),
];
