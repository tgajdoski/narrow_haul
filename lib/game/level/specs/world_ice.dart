import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';

const _ice = LevelModifiers(wallFriction: 0.03);

/// World 3 — Glacier Deep. Everything is slippery; walls give no grip.
final List<LevelDef> iceLevels = [
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.3, star3Time: 70),
    spec: const LevelSpec(
      id: 'ice_01',
      seed: 301,
      name: 'Cold Open',
      themeId: 'ice',
      worldW: 36,
      worldH: 24,
      modifiers: _ice,
      tunnels: [
        TunnelSpec(
          [Pt(5, 12), Pt(11, 9), Pt(17, 14), Pt(23, 9), Pt(30, 12)],
          width: 1.8,
        ),
        TunnelSpec([Pt(17, 14), Pt(17, 18)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 12), 2.4),
        ChamberSpec(Pt(17, 18.5), 1.7),
        ChamberSpec(Pt(30, 12), 2.4),
      ],
      shipSpawn: Pt(5, 12),
      cargoSpawn: Pt(17, 18.5),
      goal: GoalSpec(Pt(30, 13.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.3, star3Time: 70),
    spec: const LevelSpec(
      id: 'ice_02',
      seed: 302,
      name: 'Glass Floor',
      themeId: 'ice',
      worldW: 38,
      worldH: 24,
      noise: NoiseSpec(amplitude: 0.22),
      modifiers: _ice,
      tunnels: [
        TunnelSpec(
          [Pt(5, 12), Pt(12, 11.5), Pt(19, 12), Pt(26, 11.5), Pt(32, 12)],
          width: 1.3,
        ),
        TunnelSpec([Pt(19, 12), Pt(19, 16)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(5, 12), 2.2),
        ChamberSpec(Pt(19, 16.5), 1.6),
        ChamberSpec(Pt(32, 12), 2.2),
      ],
      shipSpawn: Pt(5, 12),
      cargoSpawn: Pt(19, 16.5),
      goal: GoalSpec(Pt(32, 13.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.3, star3Time: 75),
    spec: const LevelSpec(
      id: 'ice_03',
      seed: 303,
      name: 'Icicle Alley',
      themeId: 'ice',
      worldW: 40,
      worldH: 26,
      modifiers: _ice,
      tunnels: [
        TunnelSpec(
          [Pt(5, 13), Pt(12, 12), Pt(20, 13), Pt(28, 12), Pt(34, 13)],
          width: 1.7,
        ),
        TunnelSpec([Pt(20, 13), Pt(20, 17.5)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 13), 2.4),
        ChamberSpec(Pt(20, 18), 1.7),
        ChamberSpec(Pt(34, 13), 2.4),
      ],
      obstacles: [
        PendulumSpec(Pt(16, 9.5), length: 2.6, amplitudeRad: 0.7, periodSec: 2.8),
        PendulumSpec(Pt(28, 9.5), length: 2.6, amplitudeRad: 0.7, periodSec: 2.8, phase: 1.4),
      ],
      shipSpawn: Pt(5, 13),
      cargoSpawn: Pt(20, 18),
      goal: GoalSpec(Pt(34, 14.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.3, star3Time: 75),
    spec: const LevelSpec(
      id: 'ice_04',
      seed: 304,
      name: 'The Flue',
      themeId: 'ice',
      worldW: 30,
      worldH: 34,
      noise: NoiseSpec(amplitude: 0.24),
      modifiers: _ice,
      tunnels: [
        TunnelSpec(
          [Pt(7, 28), Pt(8, 22), Pt(6, 16), Pt(9, 10), Pt(14, 7)],
          widths: [1.8, 1.4, 1.1, 1.3, 1.6],
        ),
        TunnelSpec([Pt(14, 7), Pt(20, 8)], width: 1.5),
        TunnelSpec([Pt(20, 8), Pt(24, 12)], width: 1.4),
        TunnelSpec([Pt(9, 10), Pt(12, 12.5), Pt(14, 14.4)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(7, 28), 2.4),
        ChamberSpec(Pt(14, 15), 1.6),
        ChamberSpec(Pt(24, 12), 2.4),
      ],
      shipSpawn: Pt(7, 28),
      cargoSpawn: Pt(14, 15.2),
      goal: GoalSpec(Pt(24, 13.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.28, star3Time: 80),
    spec: const LevelSpec(
      id: 'ice_05',
      seed: 305,
      name: 'Frostbite',
      themeId: 'ice',
      worldW: 42,
      worldH: 26,
      modifiers: LevelModifiers(wallFriction: 0.03, fuelDrainMul: 1.25),
      tunnels: [
        TunnelSpec(
          [Pt(5, 13), Pt(12, 10), Pt(19, 15), Pt(26, 10), Pt(32, 13), Pt(36, 13)],
          width: 1.6,
        ),
        TunnelSpec([Pt(12, 10), Pt(12, 16.5)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(5, 13), 2.4),
        ChamberSpec(Pt(12, 17), 1.7),
        ChamberSpec(Pt(36, 13), 2.4),
      ],
      obstacles: [
        SlidingBlockSpec(Pt(22, 8), Pt(22, 17), halfW: 0.55, halfH: 0.6, periodSec: 3.4),
      ],
      shipSpawn: Pt(5, 13),
      cargoSpawn: Pt(12, 17),
      goal: GoalSpec(Pt(36, 14.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.5, star2Fuel: 0.28, star3Time: 80),
    spec: const LevelSpec(
      id: 'ice_06',
      seed: 306,
      name: 'Crevasse',
      themeId: 'ice',
      worldW: 34,
      worldH: 34,
      modifiers: LevelModifiers(wallFriction: 0.03, cargoDensityMul: 1.5),
      tunnels: [
        TunnelSpec(
          [Pt(5, 8), Pt(9, 14), Pt(13, 21), Pt(17, 27)],
          widths: [1.8, 1.4, 1.3, 1.8],
        ),
        TunnelSpec(
          [Pt(17, 27), Pt(22, 21), Pt(25, 14), Pt(28, 8)],
          widths: [1.8, 1.3, 1.4, 1.8],
        ),
      ],
      chambers: [
        ChamberSpec(Pt(5, 8), 2.4),
        ChamberSpec(Pt(17, 27), 2.6),
        ChamberSpec(Pt(28, 8), 2.4),
      ],
      shipSpawn: Pt(5, 8),
      cargoSpawn: Pt(17, 27.6),
      goal: GoalSpec(Pt(28, 9.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.5, star2Fuel: 0.28, star3Time: 85),
    spec: const LevelSpec(
      id: 'ice_07',
      seed: 307,
      name: 'Whiteout',
      themeId: 'ice',
      worldW: 46,
      worldH: 28,
      noise: NoiseSpec(amplitude: 0.22),
      modifiers: _ice,
      tunnels: [
        TunnelSpec(
          [
            Pt(5, 14), Pt(10, 9), Pt(15, 18), Pt(20, 9),
            Pt(25, 18), Pt(30, 9), Pt(35, 16), Pt(40, 14),
          ],
          widths: [1.8, 1.3, 1.3, 1.0, 1.3, 1.0, 1.4, 1.8],
        ),
        TunnelSpec([Pt(25, 18), Pt(25, 22)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(5, 14), 2.4),
        ChamberSpec(Pt(25, 22.5), 1.6),
        ChamberSpec(Pt(40, 14), 2.4),
      ],
      shipSpawn: Pt(5, 14),
      cargoSpawn: Pt(25, 22.5),
      goal: GoalSpec(Pt(40, 15.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.5, star2Fuel: 0.25, star3Time: 90),
    spec: const LevelSpec(
      id: 'ice_08',
      seed: 308,
      name: "Glacier's Maw",
      themeId: 'ice',
      worldW: 50,
      worldH: 32,
      noise: NoiseSpec(amplitude: 0.24),
      modifiers: LevelModifiers(wallFriction: 0.03, fuelDrainMul: 1.2),
      tunnels: [
        TunnelSpec(
          [Pt(5, 16), Pt(11, 11), Pt(17, 19), Pt(23, 12)],
          widths: [1.8, 1.4, 1.4, 1.5],
        ),
        TunnelSpec(
          [Pt(23, 12), Pt(28, 16), Pt(32, 13)],
          widths: [1.8, 1.0, 1.0],
        ),
        TunnelSpec([Pt(32, 13), Pt(37, 15), Pt(42, 16)], width: 1.5),
        TunnelSpec([Pt(42, 16), Pt(45, 16)], width: 1.6),
        TunnelSpec([Pt(17, 19), Pt(17, 23.5)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 16), 2.4),
        ChamberSpec(Pt(23, 12), 2.6),
        ChamberSpec(Pt(17, 24), 1.7),
        ChamberSpec(Pt(45, 16), 2.4),
      ],
      obstacles: [
        PendulumSpec(Pt(23, 8.8), length: 2.6, amplitudeRad: 0.85, periodSec: 2.5),
        SlidingBlockSpec(Pt(39, 12), Pt(39, 19), halfW: 0.55, halfH: 0.7, periodSec: 3.2),
      ],
      shipSpawn: Pt(5, 16),
      cargoSpawn: Pt(17, 24),
      goal: GoalSpec(Pt(45, 17.2)),
    ),
  ),
];
