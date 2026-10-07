import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';

/// Ship flown in this world unless a level overrides it: the fly-by-wire
/// Vector, whose hover assist cancels the pull of wells while thrusting.
const orbitShipId = 'vector';

/// World 5 — Outer Ring. Asteroid caverns in near-weightlessness: inertia,
/// planetoid wells, sideways and inverted pulls. Pods near wells are locked
/// in place (cargoClamped) until hooked.
final List<LevelDef> orbitLevels = [
  // Type rating: first flight in the Vector — hold thrust, it goes where it points.
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.6, star2Fuel: 0.3, star3Time: 55),
    spec: const LevelSpec(
      id: 'rating_vector',
      seed: 590,
      name: 'Vector Type Rating',
      themeId: 'orbit',
      worldW: 34,
      worldH: 22,
      modifiers: LevelModifiers(gravityMul: 0.6),
      tunnels: [
        TunnelSpec([Pt(5, 10), Pt(11, 8), Pt(17, 10), Pt(23, 8), Pt(29, 10)], width: 2.0),
        TunnelSpec([Pt(17, 10), Pt(17, 13.5)], width: 1.5),
      ],
      chambers: [
        ChamberSpec(Pt(5, 10), 2.4),
        ChamberSpec(Pt(17, 14), 1.8),
        ChamberSpec(Pt(29, 10), 2.4),
      ],
      shipSpawn: Pt(5, 10),
      cargoSpawn: Pt(17, 14),
      goal: GoalSpec(Pt(29, 11.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.7, star2Fuel: 0.4, star3Time: 60),
    spec: const LevelSpec(
      id: 'orbit_01',
      seed: 501,
      name: 'Weightless',
      themeId: 'orbit',
      worldW: 36,
      worldH: 22,
      modifiers: LevelModifiers(gravityMul: 0),
      tunnels: [
        TunnelSpec([Pt(5, 11), Pt(11, 8), Pt(18, 12), Pt(25, 8), Pt(31, 11)], width: 1.8),
        TunnelSpec([Pt(18, 12), Pt(18, 16)], width: 1.4),
      ],
      chambers: [
        ChamberSpec(Pt(5, 11), 2.4),
        ChamberSpec(Pt(18, 16.5), 1.7),
        ChamberSpec(Pt(31, 11), 2.4),
      ],
      shipSpawn: Pt(5, 11),
      cargoSpawn: Pt(18, 16.5),
      goal: GoalSpec(Pt(31, 12.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.7, star2Fuel: 0.4, star3Time: 65),
    spec: const LevelSpec(
      id: 'orbit_02',
      seed: 502,
      name: 'First Moon',
      themeId: 'orbit',
      worldW: 38,
      worldH: 28,
      modifiers: LevelModifiers(gravityMul: 0),
      tunnels: [
        TunnelSpec([Pt(5, 13), Pt(12, 13)], width: 1.8),
        TunnelSpec([Pt(19, 18), Pt(19, 22)], width: 1.4),
        TunnelSpec([Pt(26, 13), Pt(33, 13)], width: 1.8),
      ],
      chambers: [
        ChamberSpec(Pt(5, 13), 2.4),
        ChamberSpec(Pt(19, 13), 7, 6),
        ChamberSpec(Pt(19, 22.5), 1.7),
        ChamberSpec(Pt(33, 13), 2.4),
      ],
      fields: [
        GravityWellSpec(Pt(19, 13), strength: 2.5, coreRadius: 1.2, maxG: 1.5),
      ],
      shipSpawn: Pt(5, 13),
      cargoSpawn: Pt(19, 22.5),
      goal: GoalSpec(Pt(33, 14.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.65, star2Fuel: 0.35, star3Time: 70),
    spec: const LevelSpec(
      id: 'orbit_03',
      seed: 503,
      name: 'Slingshot',
      themeId: 'orbit',
      worldW: 40,
      worldH: 26,
      modifiers: LevelModifiers(gravityMul: 0.35),
      cargoClamped: true,
      tunnels: [
        TunnelSpec([Pt(5, 8), Pt(12, 9), Pt(17, 12)], width: 1.7),
        TunnelSpec([Pt(25, 17), Pt(30, 19), Pt(35, 18)], width: 1.7),
      ],
      chambers: [
        ChamberSpec(Pt(5, 8), 2.4),
        ChamberSpec(Pt(21, 14), 6, 5),
        ChamberSpec(Pt(35, 18), 2.4),
      ],
      fields: [
        GravityWellSpec(Pt(21, 14.5), strength: 4, coreRadius: 1.0, maxG: 1.8),
      ],
      shipSpawn: Pt(5, 8),
      cargoSpawn: Pt(21, 11),
      goal: GoalSpec(Pt(35, 19.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.6, star2Fuel: 0.3, star3Time: 70),
    spec: const LevelSpec(
      id: 'orbit_04',
      seed: 504,
      name: 'Undertow',
      themeId: 'orbit',
      worldW: 40,
      worldH: 22,
      modifiers: LevelModifiers(gravityMul: 0.5),
      tunnels: [
        TunnelSpec([Pt(5, 11), Pt(12, 9), Pt(20, 11), Pt(28, 9), Pt(35, 11)], width: 1.8),
        TunnelSpec([Pt(28, 9), Pt(28, 14.5)], width: 1.4),
      ],
      chambers: [
        ChamberSpec(Pt(5, 11), 2.4),
        ChamberSpec(Pt(28, 15), 1.7),
        ChamberSpec(Pt(35, 11), 2.4),
      ],
      fields: [
        // A sideways undertow drags you back toward the start.
        GravityZoneSpec(Pt(16, 10), halfW: 4, halfH: 4, gx: -0.6, gy: 0.3, feather: 1.2),
      ],
      shipSpawn: Pt(5, 11),
      cargoSpawn: Pt(28, 15),
      goal: GoalSpec(Pt(35, 12.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.6, star2Fuel: 0.3, star3Time: 75),
    spec: const LevelSpec(
      id: 'orbit_05',
      seed: 505,
      name: 'Binary',
      themeId: 'orbit',
      worldW: 44,
      worldH: 26,
      modifiers: LevelModifiers(gravityMul: 0),
      cargoClamped: true,
      tunnels: [
        TunnelSpec([Pt(4, 13), Pt(10, 13)], width: 1.8),
        TunnelSpec([Pt(34, 13), Pt(40, 13)], width: 1.8),
      ],
      chambers: [
        ChamberSpec(Pt(4, 13), 2.4),
        ChamberSpec(Pt(22, 13), 12, 7),
        ChamberSpec(Pt(40, 13), 2.4),
      ],
      fields: [
        GravityWellSpec(Pt(16, 10), strength: 3, coreRadius: 1.1, maxG: 1.5),
        GravityWellSpec(Pt(28, 16), strength: 3, coreRadius: 1.1, maxG: 1.5),
      ],
      shipSpawn: Pt(4, 13),
      cargoSpawn: Pt(22, 13),
      goal: GoalSpec(Pt(40, 14.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.3, star3Time: 80),
    spec: const LevelSpec(
      id: 'orbit_06',
      seed: 506,
      name: 'Tidal Lock',
      themeId: 'orbit',
      worldW: 40,
      worldH: 28,
      modifiers: LevelModifiers(gravityMul: 0.4),
      cargoClamped: true,
      tunnels: [
        TunnelSpec([Pt(5, 22), Pt(10, 18), Pt(14, 13), Pt(20, 10)], width: 1.7),
        TunnelSpec([Pt(28, 12), Pt(32, 18), Pt(35, 22)], width: 1.7),
      ],
      chambers: [
        ChamberSpec(Pt(5, 22), 2.4),
        ChamberSpec(Pt(24, 10.5), 5, 4.5),
        ChamberSpec(Pt(35, 22), 2.4),
      ],
      fields: [
        GravityWellSpec(Pt(25, 11), strength: 3, coreRadius: 1.0, maxG: 1.5),
        WindZoneSpec(Pt(31.5, 16.5), halfW: 2.5, halfH: 3, ax: -0.3, ay: 0, gustAmp: 0.5, gustPeriod: 3.5),
      ],
      shipSpawn: Pt(5, 22),
      cargoSpawn: Pt(25, 7.3),
      goal: GoalSpec(Pt(35, 23.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.55, star2Fuel: 0.28, star3Time: 80),
    spec: const LevelSpec(
      id: 'orbit_07',
      seed: 507,
      name: 'Inversion',
      themeId: 'orbit',
      worldW: 42,
      worldH: 24,
      modifiers: LevelModifiers(gravityMul: 0.6),
      tunnels: [
        TunnelSpec([Pt(5, 12), Pt(12, 10), Pt(20, 12), Pt(28, 10), Pt(36, 12)], width: 1.8),
        TunnelSpec([Pt(20, 12), Pt(20, 17.5)], width: 1.4),
      ],
      chambers: [
        ChamberSpec(Pt(5, 12), 2.4),
        ChamberSpec(Pt(20, 18), 1.7),
        ChamberSpec(Pt(36, 12), 2.4),
      ],
      fields: [
        // Two pockets where "down" is up.
        GravityZoneSpec(Pt(12, 11), halfW: 3.5, halfH: 4, gx: 0, gy: -0.6, feather: 1.2),
        GravityZoneSpec(Pt(28, 11), halfW: 3.5, halfH: 4, gx: 0, gy: -0.6, feather: 1.2),
      ],
      shipSpawn: Pt(5, 12),
      cargoSpawn: Pt(20, 18),
      goal: GoalSpec(Pt(36, 13.2)),
    ),
  ),
  CaveLevelDef(
    stars: const StarSpec(star3Fuel: 0.5, star2Fuel: 0.25, star3Time: 90),
    spec: const LevelSpec(
      id: 'orbit_08',
      seed: 508,
      name: 'Event Horizon',
      themeId: 'orbit',
      worldW: 46,
      worldH: 30,
      modifiers: LevelModifiers(gravityMul: 0),
      cargoClamped: true,
      tunnels: [
        TunnelSpec([Pt(4, 15), Pt(12, 15)], width: 1.8),
        TunnelSpec([Pt(29, 15), Pt(36, 12), Pt(42, 15)], width: 1.7),
      ],
      chambers: [
        ChamberSpec(Pt(4, 15), 2.4),
        ChamberSpec(Pt(21, 15), 9, 8),
        ChamberSpec(Pt(42, 15), 2.4),
      ],
      fields: [
        GravityWellSpec(Pt(21, 15), strength: 6, coreRadius: 1.6, maxG: 2.0),
        GravityWellSpec(Pt(36, 18), strength: 2, coreRadius: 0.9, maxG: 1.2),
        WindZoneSpec(Pt(33, 13.5), halfW: 2.5, halfH: 2.5, ax: 0, ay: 0.3, gustAmp: 0.5, gustPeriod: 3),
      ],
      shipSpawn: Pt(4, 15),
      cargoSpawn: Pt(21, 9),
      goal: GoalSpec(Pt(42, 16.2)),
    ),
  ),
];
