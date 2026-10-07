import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';

/// Ship flown in this world: the armed Talon escort hauler.
const redoubtShipId = 'talon';

/// World 6 — The Redoubt. Thrust's fortified caves: wall turrets that shoot
/// back, fuel canisters worth the detour, and reactor cores that silence the
/// guns — or, destroyed, start a meltdown you have to outrun with the pod.
final List<LevelDef> redoubtLevels = [
  // Type rating: one turret guarding the middle chamber, a canister to grab.
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.6, star2Fuel: 0.3, star3Time: 60),
    spec: const LevelSpec(
      id: 'rating_talon',
      seed: 601,
      name: 'Talon Type Rating',
      themeId: 'redoubt',
      worldW: 36,
      worldH: 22,
      tunnels: [
        TunnelSpec([Pt(5, 8), Pt(10, 8.5), Pt(15, 10)], width: 1.8),
        TunnelSpec([Pt(19, 10), Pt(25, 9), Pt(31, 8)], width: 1.8),
        TunnelSpec([Pt(25, 9), Pt(25, 14)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 8), 2.4),
        ChamberSpec(Pt(17, 10.5), 3.4, 2.6),
        ChamberSpec(Pt(25, 15), 1.7),
        ChamberSpec(Pt(31, 8), 2.4),
      ],
      obstacles: [
        TurretSpec(Pt(17, 13.1), facing: kFaceUp, range: 7),
      ],
      pickups: [
        FuelCellSpec(Pt(17, 9)),
      ],
      shipSpawn: Pt(5, 8),
      cargoSpawn: Pt(25, 15.4),
      goal: GoalSpec(Pt(31, 9.2)),
    ),
  ),
  // Two guns covering a gallery: pick them off or slip past under fire.
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.3, star3Time: 70),
    spec: const LevelSpec(
      id: 'redoubt_01',
      seed: 611,
      name: 'Gun Line',
      themeId: 'redoubt',
      worldW: 42,
      worldH: 24,
      tunnels: [
        TunnelSpec([Pt(5, 9), Pt(11, 10), Pt(17, 12), Pt(24, 12), Pt(30, 10)], width: 1.9),
        TunnelSpec([Pt(30, 10), Pt(36, 9)], width: 1.8),
        TunnelSpec([Pt(21, 12), Pt(21, 17)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 9), 2.4),
        ChamberSpec(Pt(20.5, 12), 4.5, 2.6),
        ChamberSpec(Pt(21, 18), 1.7),
        ChamberSpec(Pt(36, 9), 2.4),
      ],
      obstacles: [
        TurretSpec(Pt(17, 9.3), facing: kFaceDown, range: 8),
        TurretSpec(Pt(25, 9.0), facing: kFaceDown, range: 8, phase: 1.1),
      ],
      pickups: [
        FuelCellSpec(Pt(17.2, 12), amount: 35),
      ],
      shipSpawn: Pt(5, 9),
      cargoSpawn: Pt(21, 18.4),
      goal: GoalSpec(Pt(36, 10.2)),
    ),
  ),
  // A long haul that only pays with the canisters in the side pockets.
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.3, star3Time: 85),
    spec: const LevelSpec(
      id: 'redoubt_02',
      seed: 621,
      name: 'Supply Line',
      themeId: 'redoubt',
      worldW: 50,
      worldH: 26,
      modifiers: LevelModifiers(fuelDrainMul: 1.5),
      tunnels: [
        TunnelSpec([Pt(5, 9), Pt(12, 11), Pt(19, 10), Pt(26, 12), Pt(33, 11), Pt(40, 13)],
            width: 1.8),
        TunnelSpec([Pt(40, 13), Pt(44, 10)], width: 1.7),
        TunnelSpec([Pt(19, 10), Pt(19, 6)], width: 1.2),
        TunnelSpec([Pt(33, 11), Pt(33, 16)], width: 1.2),
        TunnelSpec([Pt(26, 12), Pt(26, 18)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 9), 2.4),
        ChamberSpec(Pt(19, 5.5), 1.6),
        ChamberSpec(Pt(26, 19), 1.7),
        ChamberSpec(Pt(33, 16.5), 1.6),
        ChamberSpec(Pt(44, 10), 2.4),
      ],
      obstacles: [
        TurretSpec(Pt(29.5, 8.9), facing: kFaceDown, range: 8),
        TurretSpec(Pt(36, 14.0), facing: kFaceUp, range: 6, aimArc: 0.9, phase: 0.8),
      ],
      pickups: [
        FuelCellSpec(Pt(19, 5.5)),
        FuelCellSpec(Pt(33, 16.5)),
        FuelCellSpec(Pt(26.3, 16.8), amount: 30),
        FuelCellSpec(Pt(30.8, 12.1), amount: 30),
      ],
      shipSpawn: Pt(5, 9),
      cargoSpawn: Pt(26, 19.4),
      goal: GoalSpec(Pt(44, 11.2)),
    ),
  ),
  // The first reactor: three hits buy ten quiet seconds; eight start the
  // countdown. Either way, the guns stop.
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.5, star2Fuel: 0.25, star3Time: 85),
    spec: const LevelSpec(
      id: 'redoubt_03',
      seed: 631,
      name: 'Power Plant',
      themeId: 'redoubt',
      worldW: 46,
      worldH: 28,
      tunnels: [
        TunnelSpec([Pt(5, 9), Pt(11, 10), Pt(17, 13)], width: 1.8),
        TunnelSpec([Pt(28, 13), Pt(34, 10), Pt(40, 9)], width: 1.8),
        TunnelSpec([Pt(22.5, 17), Pt(22.5, 21)], width: 1.3),
      ],
      chambers: [
        ChamberSpec(Pt(5, 9), 2.4),
        ChamberSpec(Pt(22.5, 13.5), 6.0, 3.6),
        ChamberSpec(Pt(22.5, 22), 1.7),
        ChamberSpec(Pt(40, 9), 2.4),
      ],
      obstacles: [
        ReactorSpec(Pt(22.5, 12.5), escapeSeconds: 35),
        TurretSpec(Pt(19, 10.6), facing: kFaceDown, range: 8),
        TurretSpec(Pt(26, 10.5), facing: kFaceDown, range: 8, phase: 0.9),
        TurretSpec(Pt(19.5, 16.8), facing: kFaceUp, range: 7, phase: 0.4),
      ],
      pickups: [
        FuelCellSpec(Pt(18, 13.5)),
        FuelCellSpec(Pt(14.3, 11), amount: 20),
        FuelCellSpec(Pt(12.6, 10.6), amount: 15),
        FuelCellSpec(Pt(22.9, 19.8), amount: 10),
        FuelCellSpec(Pt(23, 16.8), amount: 5),
      ],
      shipSpawn: Pt(5, 9),
      cargoSpawn: Pt(22.5, 22.4),
      goal: GoalSpec(Pt(40, 10.2)),
    ),
  ),
  // Guns on both walls of a shaft, a pendulum in the gap.
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.5, star2Fuel: 0.25, star3Time: 90),
    spec: const LevelSpec(
      id: 'redoubt_04',
      seed: 641,
      name: 'Crossfire',
      themeId: 'redoubt',
      worldW: 44,
      worldH: 32,
      tunnels: [
        TunnelSpec([Pt(5, 8), Pt(12, 9), Pt(18, 8)], width: 1.8),
        TunnelSpec([Pt(18, 8), Pt(21, 14), Pt(21, 21)], width: 2.0),
        TunnelSpec([Pt(21, 21), Pt(28, 23), Pt(34, 21)], width: 1.8),
        TunnelSpec([Pt(34, 21), Pt(38, 16), Pt(38, 11)], width: 1.8),
        TunnelSpec([Pt(28, 23), Pt(28, 27)], width: 1.2),
      ],
      chambers: [
        ChamberSpec(Pt(5, 8), 2.4),
        ChamberSpec(Pt(28, 27.5), 1.6),
        ChamberSpec(Pt(38, 10), 2.4),
      ],
      obstacles: [
        TurretSpec(Pt(18.7, 16), facing: kFaceRight, range: 7),
        TurretSpec(Pt(23.8, 19), facing: kFaceLeft, range: 7, phase: 1.0),
        TurretSpec(Pt(33.2, 18), facing: kFaceRight, range: 7, aimArc: 0.7, phase: 0.5),
        PendulumSpec(Pt(28, 20), length: 1.6, amplitudeRad: 0.9, periodSec: 3.4),
      ],
      pickups: [
        FuelCellSpec(Pt(21, 12)),
        FuelCellSpec(Pt(21.5, 20.3), amount: 15),
        FuelCellSpec(Pt(23.1, 16.2), amount: 10),
        FuelCellSpec(Pt(28.4, 25.4), amount: 10),
      ],
      shipSpawn: Pt(5, 8),
      cargoSpawn: Pt(28, 27.9),
      goal: GoalSpec(Pt(38, 11.2)),
    ),
  ),
  // Finale: the reactor sits past the cargo. Grab the pod, blow the core,
  // and outrun the meltdown all the way home.
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.45, star2Fuel: 0.2, star3Time: 100),
    spec: const LevelSpec(
      id: 'redoubt_05',
      seed: 651,
      name: 'Meltdown',
      themeId: 'redoubt',
      worldW: 54,
      worldH: 30,
      tunnels: [
        TunnelSpec([Pt(5, 9), Pt(12, 10), Pt(19, 13), Pt(26, 13)], width: 1.8),
        TunnelSpec([Pt(26, 13), Pt(33, 15), Pt(40, 14), Pt(45, 16)], width: 1.8),
        TunnelSpec([Pt(26, 13), Pt(26, 19)], width: 1.3),
        TunnelSpec([Pt(12, 10), Pt(12, 6)], width: 1.4),
      ],
      chambers: [
        ChamberSpec(Pt(5, 9), 2.4),
        ChamberSpec(Pt(12, 5.5), 2.6, 2.0),
        ChamberSpec(Pt(26, 20), 1.7),
        ChamberSpec(Pt(47, 16), 4.0, 3.2),
      ],
      obstacles: [
        ReactorSpec(Pt(48.5, 15.5), hp: 10, escapeSeconds: 40),
        TurretSpec(Pt(19, 10.4), facing: kFaceDown, range: 8),
        TurretSpec(Pt(33, 17.4), facing: kFaceUp, range: 8, phase: 0.7),
        TurretSpec(Pt(40, 11.5), facing: kFaceDown, range: 8, phase: 1.3),
        TurretSpec(Pt(47, 19.2), facing: kFaceUp, range: 7, phase: 0.3),
      ],
      pickups: [
        FuelCellSpec(Pt(36.5, 14.5)),
        FuelCellSpec(Pt(24.6, 14.3), amount: 45),
        FuelCellSpec(Pt(13.7, 11.4), amount: 10),
        FuelCellSpec(Pt(25.5, 17.2), amount: 5),
      ],
      shipSpawn: Pt(5, 9),
      cargoSpawn: Pt(26, 20.4),
      goal: GoalSpec(Pt(12, 6.5)),
    ),
  ),
];
