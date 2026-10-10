import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';

/// Ship flown on an Expedition unless it names one.
const expeditionShipId = 'hopper';

/// Act II, "The Long Night" (docs/STORY.md §3): long multi-leg hauls. Each
/// leg lands its pod on a staging pad, which refuels and saves a checkpoint.
final List<LevelDef> expeditionLevels = [
  // E0, the free taster: a seed vault to each of three Grove farms. Hand
  // built (the prototype the generator is measured against).
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.3, star3Time: 150),
    spec: LevelSpec.expedition(
      id: 'exp_00',
      seed: 900,
      name: 'Lifeline Convoy',
      themeId: 'alien',
      worldW: 128,
      worldH: 30,
      modifiers: const LevelModifiers(gravityMul: 0.85),
      tunnels: const [
        // Leg 1: the spawn cave to the first farm, the pod in a dip.
        TunnelSpec(
          [Pt(6, 12), Pt(12, 10), Pt(18, 12), Pt(22, 16), Pt(27, 12), Pt(33, 11), Pt(38, 12)],
          widths: [2.0, 1.8, 1.7, 1.8, 1.7, 1.8, 2.0],
        ),
        // Leg 2: over a zero-g hollow and down to a deep pocket.
        TunnelSpec(
          [Pt(38, 12), Pt(44, 10), Pt(50, 10), Pt(56, 11), Pt(60, 15), Pt(64, 11), Pt(71, 10), Pt(78, 11)],
          widths: [2.0, 1.8, 2.2, 1.8, 1.7, 1.8, 1.7, 2.0],
        ),
        // Leg 3: a long climb with a squeeze, the pod low under a ledge.
        TunnelSpec(
          [Pt(78, 11), Pt(85, 13), Pt(90, 17), Pt(95, 20), Pt(100, 17), Pt(106, 13), Pt(112, 12), Pt(120, 12)],
          widths: [2.0, 1.6, 1.5, 1.8, 1.4, 1.6, 1.8, 2.0],
        ),
      ],
      chambers: const [
        ChamberSpec(Pt(6, 12), 2.6),
        ChamberSpec(Pt(22, 17), 1.8),
        ChamberSpec(Pt(38, 12), 3.0, 2.4),
        ChamberSpec(Pt(50, 10), 3.5, 2.6),
        ChamberSpec(Pt(60, 16), 1.8),
        ChamberSpec(Pt(78, 11), 3.0, 2.4),
        ChamberSpec(Pt(95, 21), 1.8),
        ChamberSpec(Pt(120, 12), 2.8, 2.4),
      ],
      fields: const [
        // The hollow where the caves stopped pulling the day the gate died.
        GravityZoneSpec(Pt(50, 10), halfW: 3, halfH: 2, gx: 0, gy: 0, feather: 1.2),
      ],
      shipSpawn: const Pt(6, 12),
      legs: const [
        LegSpec(Pt(22, 17), GoalSpec(Pt(38, 13.2))),
        LegSpec(Pt(60, 16), GoalSpec(Pt(78, 12.2))),
        LegSpec(Pt(95, 21), GoalSpec(Pt(120, 13.2))),
      ],
    ),
  ),
];
