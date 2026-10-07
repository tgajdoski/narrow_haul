import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';

/// Ship flown in this world unless a level overrides it: the Mule heavy lifter for the heavy-gravity forges.
const lavaShipId = 'mule';

/// World 4 — Ember Core. The final exam: heavy gravity, thin fuel, dead
/// weight, machinery — usually several at once.
final List<LevelDef> lavaLevels = [
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.5, star2Fuel: 0.25, star3Time: 75),
    spec: const LevelSpec(
      id: 'lava_01',
      seed: 401,
      name: 'Warm Up',
      themeId: 'lava',
      worldW: 38,
      worldH: 24,
      modifiers: LevelModifiers(gravityMul: 1.4),
      tunnels: [
        TunnelSpec(
          [Pt(5, 12), Pt(11, 9), Pt(17, 13), Pt(23, 9), Pt(29, 12), Pt(32, 12)],
          width: 1.6,
        ),
        TunnelSpec([Pt(17, 13), Pt(17, 17)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 12), 2.4),
        ChamberSpec(Pt(17, 17.5), 1.7),
        ChamberSpec(Pt(32, 12), 2.4),
      ],
      shipSpawn: Pt(5, 12),
      cargoSpawn: Pt(17, 17.5),
      goal: GoalSpec(Pt(32, 13.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.5, star2Fuel: 0.25, star3Time: 80),
    spec: const LevelSpec(
      id: 'lava_02',
      seed: 402,
      name: 'Rising Heat',
      themeId: 'lava',
      worldW: 36,
      worldH: 28,
      modifiers: LevelModifiers(gravityMul: 1.45, fuelDrainMul: 1.3),
      tunnels: [
        TunnelSpec(
          [Pt(6, 23), Pt(9, 17), Pt(7, 11), Pt(12, 7)],
          widths: [1.8, 1.4, 1.3, 1.5],
        ),
        TunnelSpec([Pt(12, 7), Pt(19, 8), Pt(25, 7)], width: 1.5),
        TunnelSpec([Pt(25, 7), Pt(30, 10)], width: 1.4),
        TunnelSpec([Pt(19, 8), Pt(19, 12)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(6, 23), 2.4),
        ChamberSpec(Pt(19, 12.5), 1.6),
        ChamberSpec(Pt(30, 10), 2.4),
      ],
      shipSpawn: Pt(6, 23),
      cargoSpawn: Pt(19, 12.5),
      goal: GoalSpec(Pt(30, 11.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.5, star2Fuel: 0.25, star3Time: 80),
    spec: const LevelSpec(
      id: 'lava_03',
      seed: 403,
      name: 'Molten Run',
      themeId: 'lava',
      worldW: 44,
      worldH: 26,
      modifiers: LevelModifiers(gravityMul: 1.5),
      tunnels: [
        TunnelSpec(
          [Pt(5, 13), Pt(12, 11), Pt(19, 14), Pt(26, 11), Pt(33, 14), Pt(38, 13)],
          width: 1.7,
        ),
        TunnelSpec([Pt(26, 11), Pt(24.5, 6.8), Pt(22, 7.5)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(5, 13), 2.4),
        ChamberSpec(Pt(15.5, 12.5), 2.6),
        ChamberSpec(Pt(29.5, 12.5), 2.6),
        ChamberSpec(Pt(22, 7.5), 1.6),
        ChamberSpec(Pt(38, 13), 2.4),
      ],
      obstacles: [
        RotatingBarSpec(Pt(15.5, 12.5), halfLength: 1.5, radPerSec: 1.2),
        RotatingBarSpec(Pt(29.5, 12.5), halfLength: 1.5, radPerSec: -1.2, initialAngle: 1.57),
      ],
      shipSpawn: Pt(5, 13),
      cargoSpawn: Pt(22, 7.5),
      goal: GoalSpec(Pt(38, 14.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.45, star2Fuel: 0.25, star3Time: 85),
    spec: const LevelSpec(
      id: 'lava_04',
      seed: 404,
      name: 'Dead Weight',
      themeId: 'lava',
      worldW: 40,
      worldH: 26,
      noise: NoiseSpec(amplitude: 0.24),
      modifiers: LevelModifiers(gravityMul: 1.55, cargoDensityMul: 2.5),
      tunnels: [
        TunnelSpec(
          [Pt(5, 13), Pt(12, 15), Pt(19, 11), Pt(24, 15)],
          width: 1.9,
        ),
        TunnelSpec(
          [Pt(24, 15), Pt(28, 13), Pt(31, 14)],
          widths: [1.9, 1.05, 1.05],
        ),
        TunnelSpec([Pt(31, 14), Pt(35, 14)], width: 1.5),
        TunnelSpec([Pt(12, 15), Pt(12, 19.5)], width: 1.4),
      ],
      chambers: [
        ChamberSpec(Pt(5, 13), 2.4),
        ChamberSpec(Pt(12, 20), 1.8),
        ChamberSpec(Pt(35, 14), 2.4),
      ],
      shipSpawn: Pt(5, 13),
      cargoSpawn: Pt(12, 20.4),
      goal: GoalSpec(Pt(35, 15.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.45, star2Fuel: 0.25, star3Time: 85),
    spec: const LevelSpec(
      id: 'lava_05',
      seed: 405,
      name: 'Pressure',
      themeId: 'lava',
      worldW: 44,
      worldH: 28,
      modifiers: LevelModifiers(gravityMul: 1.6),
      tunnels: [
        TunnelSpec(
          [Pt(5, 14), Pt(12, 12), Pt(19, 15), Pt(26, 12), Pt(33, 15), Pt(38, 14)],
          width: 1.7,
        ),
        TunnelSpec([Pt(26, 12), Pt(24.5, 7.8), Pt(22, 8.5)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(5, 14), 2.4),
        ChamberSpec(Pt(22, 8.5), 1.6),
        ChamberSpec(Pt(38, 14), 2.4),
      ],
      obstacles: [
        SlidingBlockSpec(Pt(16, 11), Pt(16, 19), halfW: 0.55, halfH: 0.7, periodSec: 2.8),
        SlidingBlockSpec(Pt(30, 19), Pt(30, 11), halfW: 0.55, halfH: 0.7, periodSec: 2.8, phase: 0.5),
      ],
      shipSpawn: Pt(5, 14),
      cargoSpawn: Pt(22, 8.5),
      goal: GoalSpec(Pt(38, 15.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.45, star2Fuel: 0.22, star3Time: 90),
    spec: const LevelSpec(
      id: 'lava_06',
      seed: 406,
      name: 'The Vent',
      themeId: 'lava',
      worldW: 32,
      worldH: 36,
      modifiers: LevelModifiers(gravityMul: 1.65, fuelDrainMul: 1.4),
      tunnels: [
        TunnelSpec(
          [Pt(16, 31), Pt(15, 26), Pt(16, 19), Pt(15, 12), Pt(16, 8)],
          widths: [1.8, 1.3, 1.6, 1.2, 1.6],
        ),
        TunnelSpec([Pt(15, 26), Pt(19, 25), Pt(22, 24)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(16, 31), 2.4),
        ChamberSpec(Pt(16, 19), 2.4),
        ChamberSpec(Pt(22, 24), 1.7),
        ChamberSpec(Pt(16, 7), 2.4),
      ],
      obstacles: [
        PendulumSpec(Pt(16, 15.8), length: 2.4, amplitudeRad: 0.8, periodSec: 2.6),
      ],
      shipSpawn: Pt(16, 31),
      cargoSpawn: Pt(22, 24.4),
      goal: GoalSpec(Pt(16, 8.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.45, star2Fuel: 0.22, star3Time: 95),
    spec: const LevelSpec(
      id: 'lava_07',
      seed: 407,
      name: 'Inferno Gate',
      themeId: 'lava',
      worldW: 48,
      worldH: 30,
      noise: NoiseSpec(amplitude: 0.24),
      modifiers: LevelModifiers(gravityMul: 1.7, fuelDrainMul: 1.2),
      tunnels: [
        TunnelSpec(
          [Pt(5, 15), Pt(11, 11), Pt(17, 18), Pt(23, 13)],
          widths: [1.8, 1.4, 1.4, 1.6],
        ),
        TunnelSpec(
          [Pt(23, 13), Pt(28, 17), Pt(32, 13)],
          widths: [1.8, 1.0, 1.0],
        ),
        TunnelSpec([Pt(32, 13), Pt(37, 16), Pt(41, 15)], width: 1.5),
        TunnelSpec([Pt(41, 15), Pt(44, 16)], width: 1.5),
        TunnelSpec([Pt(17, 18), Pt(13, 21), Pt(11, 22)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 15), 2.4),
        ChamberSpec(Pt(23, 13), 2.8),
        ChamberSpec(Pt(11, 22), 1.7),
        ChamberSpec(Pt(44, 16), 2.4),
      ],
      obstacles: [
        RotatingBarSpec(Pt(23, 13), halfLength: 1.6, radPerSec: 1.3),
        SlidingBlockSpec(Pt(39, 11.5), Pt(39, 18.5), halfW: 0.55, halfH: 0.7, periodSec: 3.0),
      ],
      shipSpawn: Pt(5, 15),
      cargoSpawn: Pt(11, 22.4),
      goal: GoalSpec(Pt(44, 17.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.4, star2Fuel: 0.2, star3Time: 110),
    spec: const LevelSpec(
      id: 'lava_08',
      seed: 408,
      name: 'Ember Throne',
      themeId: 'lava',
      worldW: 56,
      worldH: 34,
      noise: NoiseSpec(amplitude: 0.24),
      modifiers: LevelModifiers(gravityMul: 1.7, fuelDrainMul: 1.3, cargoDensityMul: 2.0),
      tunnels: [
        TunnelSpec(
          [Pt(5, 17), Pt(11, 12), Pt(17, 20), Pt(23, 13)],
          widths: [1.8, 1.4, 1.4, 1.5],
        ),
        TunnelSpec([Pt(23, 13), Pt(27, 19), Pt(31, 23)], width: 1.4),
        TunnelSpec(
          [Pt(31, 23), Pt(36, 19), Pt(39, 15)],
          widths: [1.6, 1.0, 1.0],
        ),
        TunnelSpec([Pt(39, 15), Pt(44, 17), Pt(48, 16)], width: 1.5),
        TunnelSpec([Pt(48, 16), Pt(51, 17)], width: 1.5),
        TunnelSpec([Pt(17, 20), Pt(17, 25.5)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 17), 2.4),
        ChamberSpec(Pt(23, 13), 2.8),
        ChamberSpec(Pt(31, 23), 2.6),
        ChamberSpec(Pt(17, 26), 1.8),
        ChamberSpec(Pt(51, 17), 2.4),
      ],
      obstacles: [
        RotatingBarSpec(Pt(23, 13), halfLength: 1.6, radPerSec: 1.1),
        PendulumSpec(Pt(31, 19.8), length: 2.4, amplitudeRad: 0.85, periodSec: 2.5),
        SlidingBlockSpec(Pt(46, 12.5), Pt(46, 20.5), halfW: 0.55, halfH: 0.75, periodSec: 3.0),
      ],
      shipSpawn: Pt(5, 17),
      cargoSpawn: Pt(17, 26.4),
      goal: GoalSpec(Pt(51, 18.2)),
    ),
  ),
];
