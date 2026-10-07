import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';

/// Ship flown in this world unless a level overrides it: the Mule heavy lifter for ore hauls.
const mineShipId = 'mule';

/// World 2 — Rustshaft Mines. Moving machinery: bars, pendulums, crushers.
final List<LevelDef> mineLevels = [
  // Type rating: first flight in the Mule — heavy pod, slow turns, big climb.
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.6, star2Fuel: 0.3, star3Time: 60),
    spec: const LevelSpec(
      id: 'rating_mule',
      seed: 290,
      name: 'Mule Type Rating',
      themeId: 'mine',
      worldW: 32,
      worldH: 22,
      modifiers: LevelModifiers(gravityMul: 1.1, cargoDensityMul: 1.5),
      tunnels: [
        TunnelSpec([Pt(5, 7), Pt(10, 8), Pt(14, 11), Pt(16, 15)], width: 2.0),
        TunnelSpec([Pt(16, 15), Pt(20, 11), Pt(24, 8), Pt(27, 7)], width: 2.0),
      ],
      chambers: [
        ChamberSpec(Pt(5, 7), 2.5),
        ChamberSpec(Pt(16, 16), 2.0),
        ChamberSpec(Pt(27, 7), 2.5),
      ],
      shipSpawn: Pt(5, 7),
      cargoSpawn: Pt(16, 16),
      goal: GoalSpec(Pt(27, 8.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.6, star2Fuel: 0.3, star3Time: 65),
    spec: const LevelSpec(
      id: 'mine_01',
      seed: 201,
      name: 'First Shift',
      themeId: 'mine',
      worldW: 36,
      worldH: 24,
      modifiers: LevelModifiers(gravityMul: 1.1),
      tunnels: [
        TunnelSpec([Pt(5, 12), Pt(11, 10), Pt(17, 12)], width: 1.7),
        TunnelSpec([Pt(17, 12), Pt(24, 11), Pt(31, 12)], width: 1.7),
        TunnelSpec([Pt(17, 14), Pt(17, 17)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 12), 2.4),
        ChamberSpec(Pt(17, 12), 3.2),
        ChamberSpec(Pt(17, 17.5), 1.7),
        ChamberSpec(Pt(31, 12), 2.4),
      ],
      obstacles: [
        RotatingBarSpec(Pt(17, 12), halfLength: 1.8, radPerSec: 0.9),
      ],
      shipSpawn: Pt(5, 12),
      cargoSpawn: Pt(17, 17.5),
      goal: GoalSpec(Pt(31, 13.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.6, star2Fuel: 0.3, star3Time: 65),
    spec: const LevelSpec(
      id: 'mine_02',
      seed: 202,
      name: 'Conveyor',
      themeId: 'mine',
      worldW: 40,
      worldH: 24,
      modifiers: LevelModifiers(gravityMul: 1.1),
      tunnels: [
        TunnelSpec(
          [Pt(5, 12), Pt(12, 11), Pt(20, 12), Pt(28, 11), Pt(35, 12)],
          width: 1.8,
        ),
        TunnelSpec([Pt(20, 12), Pt(20, 17)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 12), 2.4),
        ChamberSpec(Pt(20, 17.5), 1.7),
        ChamberSpec(Pt(35, 12), 2.4),
      ],
      obstacles: [
        SlidingBlockSpec(Pt(14, 9), Pt(14, 15), halfW: 0.5, halfH: 0.7, periodSec: 3.2),
        SlidingBlockSpec(Pt(28, 15), Pt(28, 9), halfW: 0.5, halfH: 0.7, periodSec: 3.2, phase: 0.5),
      ],
      shipSpawn: Pt(5, 12),
      cargoSpawn: Pt(20, 17.5),
      goal: GoalSpec(Pt(35, 13.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.6, star2Fuel: 0.3, star3Time: 70),
    spec: const LevelSpec(
      id: 'mine_03',
      seed: 203,
      name: 'Swing Shaft',
      themeId: 'mine',
      worldW: 30,
      worldH: 32,
      modifiers: LevelModifiers(gravityMul: 1.15),
      tunnels: [
        TunnelSpec(
          [Pt(15, 5), Pt(14, 11), Pt(15, 15), Pt(15, 23), Pt(15, 26)],
          widths: [2.0, 1.6, 2.0, 1.6, 2.0],
        ),
        TunnelSpec([Pt(15, 17), Pt(21, 20)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(15, 5), 2.4),
        ChamberSpec(Pt(15, 15), 3.0),
        ChamberSpec(Pt(21, 20), 1.7),
        ChamberSpec(Pt(15, 26), 2.4),
      ],
      obstacles: [
        PendulumSpec(Pt(15, 12.5), length: 2.6, amplitudeRad: 0.9, periodSec: 2.6),
      ],
      fields: [
        // Ventilation fan blowing up the lower shaft — brakes the descent.
        WindZoneSpec(Pt(15, 22.5), halfW: 2.2, halfH: 2.2, ax: 0, ay: -0.5),
      ],
      shipSpawn: Pt(15, 5),
      cargoSpawn: Pt(21, 20.4),
      goal: GoalSpec(Pt(15, 27.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.6, star2Fuel: 0.3, star3Time: 70),
    spec: const LevelSpec(
      id: 'mine_04',
      seed: 204,
      name: 'Clockwork',
      themeId: 'mine',
      worldW: 42,
      worldH: 26,
      modifiers: LevelModifiers(gravityMul: 1.15),
      tunnels: [
        TunnelSpec(
          [Pt(5, 13), Pt(11, 10), Pt(17, 13), Pt(23, 10), Pt(29, 13), Pt(36, 13)],
          width: 1.7,
        ),
        TunnelSpec([Pt(23, 10), Pt(23, 14.5)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(5, 13), 2.4),
        ChamberSpec(Pt(17, 13), 2.8),
        ChamberSpec(Pt(29, 13), 2.8),
        ChamberSpec(Pt(23, 15.5), 1.7),
        ChamberSpec(Pt(36, 13), 2.4),
      ],
      obstacles: [
        RotatingBarSpec(Pt(17, 13), halfLength: 1.7, radPerSec: 1.1),
        RotatingBarSpec(Pt(29, 13), halfLength: 1.7, radPerSec: -1.1, initialAngle: 1.57),
      ],
      shipSpawn: Pt(5, 13),
      cargoSpawn: Pt(23, 15.5),
      goal: GoalSpec(Pt(36, 14.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.3, star3Time: 75),
    spec: const LevelSpec(
      id: 'mine_05',
      seed: 205,
      name: 'Heavy Load',
      themeId: 'mine',
      worldW: 40,
      worldH: 26,
      modifiers: LevelModifiers(gravityMul: 1.2, cargoDensityMul: 2.2),
      tunnels: [
        TunnelSpec(
          [Pt(5, 13), Pt(12, 15), Pt(19, 12), Pt(26, 15), Pt(33, 13)],
          width: 1.9,
        ),
        TunnelSpec([Pt(12, 15), Pt(12, 20)], width: 1.4),
      ],
      chambers: [
        ChamberSpec(Pt(5, 13), 2.4),
        ChamberSpec(Pt(12, 20), 1.8),
        ChamberSpec(Pt(33, 13), 2.4),
      ],
      obstacles: [
        SlidingBlockSpec(Pt(9.5, 17), Pt(14.5, 17), halfW: 0.6, halfH: 0.5, periodSec: 4.0),
      ],
      pickups: [
        FuelCellSpec(Pt(12.3, 17.7), amount: 15),
      ],
      shipSpawn: Pt(5, 13),
      cargoSpawn: Pt(12, 20.4),
      goal: GoalSpec(Pt(33, 14.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.3, star3Time: 75),
    spec: const LevelSpec(
      id: 'mine_06',
      seed: 206,
      name: 'The Grinder',
      themeId: 'mine',
      worldW: 44,
      worldH: 28,
      modifiers: LevelModifiers(gravityMul: 1.2),
      noise: NoiseSpec(amplitude: 0.24),
      tunnels: [
        TunnelSpec([Pt(5, 14), Pt(12, 12), Pt(18, 14), Pt(21, 14)], width: 1.7),
        TunnelSpec(
          [Pt(24, 14), Pt(29, 15), Pt(33, 12)],
          widths: [1.6, 1.0, 1.0],
        ),
        TunnelSpec([Pt(33, 12), Pt(38, 14)], width: 1.6),
        TunnelSpec([Pt(18, 14), Pt(18, 19)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 14), 2.4),
        ChamberSpec(Pt(21, 14), 2.6),
        ChamberSpec(Pt(18, 20), 1.7),
        ChamberSpec(Pt(38, 14), 2.4),
      ],
      obstacles: [
        RotatingBarSpec(Pt(21, 14), halfLength: 1.5, radPerSec: 1.4),
        // Dodge-only: the Mule is unarmed. Keep the pod between you and it.
        TurretSpec(Pt(30, 12.6), facing: kFaceDown, range: 6, cooldown: 2.6),
      ],
      shipSpawn: Pt(5, 14),
      cargoSpawn: Pt(18, 20),
      goal: GoalSpec(Pt(38, 15.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.3, star3Time: 80),
    spec: const LevelSpec(
      id: 'mine_07',
      seed: 207,
      name: 'Night Shift',
      themeId: 'mine',
      worldW: 44,
      worldH: 30,
      modifiers: LevelModifiers(gravityMul: 1.25, fuelDrainMul: 1.3),
      tunnels: [
        TunnelSpec(
          [Pt(5, 15), Pt(11, 10), Pt(17, 19), Pt(23, 10), Pt(29, 19), Pt(35, 12), Pt(39, 15)],
          width: 1.5,
        ),
        TunnelSpec([Pt(23, 10), Pt(26, 7.5)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(5, 15), 2.4),
        ChamberSpec(Pt(26.5, 7), 1.7),
        ChamberSpec(Pt(39, 15), 2.4),
      ],
      obstacles: [
        PendulumSpec(Pt(17, 13.5), length: 2.4, amplitudeRad: 0.8, periodSec: 2.4),
        PendulumSpec(Pt(29, 13.5), length: 2.4, amplitudeRad: 0.8, periodSec: 2.4, phase: 1.57),
      ],
      pickups: [
        FuelCellSpec(Pt(15.5, 17.1), amount: 10),
      ],
      shipSpawn: Pt(5, 15),
      cargoSpawn: Pt(26.5, 7),
      goal: GoalSpec(Pt(39, 16.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.5, star2Fuel: 0.25, star3Time: 85),
    spec: const LevelSpec(
      id: 'mine_08',
      seed: 208,
      name: "Foreman's Test",
      themeId: 'mine',
      worldW: 50,
      worldH: 30,
      noise: NoiseSpec(amplitude: 0.24),
      modifiers: LevelModifiers(gravityMul: 1.3, cargoDensityMul: 1.6),
      tunnels: [
        TunnelSpec(
          [Pt(5, 15), Pt(12, 11), Pt(19, 16), Pt(23, 14), Pt(28, 12)],
          widths: [1.8, 1.5, 1.5, 2.0, 1.4],
        ),
        TunnelSpec(
          [Pt(28, 12), Pt(33, 15), Pt(37, 12)],
          widths: [1.4, 1.0, 1.0],
        ),
        TunnelSpec([Pt(37, 12), Pt(42, 15), Pt(45, 16)], width: 1.5),
        TunnelSpec([Pt(19, 16), Pt(15, 20), Pt(12, 21)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 15), 2.4),
        ChamberSpec(Pt(23, 14), 3.0),
        ChamberSpec(Pt(12, 21), 1.8),
        ChamberSpec(Pt(45, 16), 2.4),
      ],
      obstacles: [
        RotatingBarSpec(Pt(23, 14), halfLength: 1.7, radPerSec: 1.0),
        SlidingBlockSpec(Pt(40, 10.5), Pt(40, 16.5), halfW: 0.55, halfH: 0.7, periodSec: 3.0),
      ],
      pickups: [
        FuelCellSpec(Pt(15.8, 18.9), amount: 10),
      ],
      shipSpawn: Pt(5, 15),
      cargoSpawn: Pt(12, 21.4),
      goal: GoalSpec(Pt(45, 17.2)),
    ),
  ),
];
