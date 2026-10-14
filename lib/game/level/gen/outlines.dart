// The Act II Expeditions the generator lays out (docs/STORY.md §3). Change
// an outline, then `dart run tool/generate_expedition.dart <id>` and
// re-run the autopilot for it (`LEVELS=<id> EXPORT_ROUTES=true`).

import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/gen/expedition_generator.dart';

const _p = Room.plain;
const _sq = Room.squeeze;
const _up = Room.climb;
const _dn = Room.drop;
const _bar = Room.bar;
const _pen = Room.pendulum;
const _blk = Room.block;
const _zg = Room.zeroG;
const _draft = Room.updraft;
const _wind = Room.crosswind;
const _well = Room.well;
const _gun = Room.turret;
const _fuel = Room.canister;

const List<ExpeditionOutline> kExpeditionOutlines = [
  // E1: the Tide's first tremor collapses a shaft. MEDEVAC four capsules.
  ExpeditionOutline(
    id: 'exp_01',
    name: 'Cave-in',
    themeId: 'mine',
    seed: 1104,
    shipId: 'mule',
    modifiers: LevelModifiers(gravityMul: 1.1, cargoDensityMul: 1.2),
    legs: [
      [_p, _bar],
      [_dn, _p],
      [_p, _up],
      [_p, _dn],
    ],
  ),
  // E2: vaccine to three outposts before the batch warms.
  ExpeditionOutline(
    id: 'exp_02',
    name: 'Cold Chain',
    themeId: 'ice',
    seed: 1201,
    shipId: 'skate',
    modifiers: LevelModifiers(wallFriction: 0.03),
    legs: [
      [_wind, _p],
      [_draft, _p],
      [_pen, _wind],
    ],
  ),
  // E3: evacuate the Crucible before the eruption.
  ExpeditionOutline(
    id: 'exp_03',
    name: 'Exodus',
    themeId: 'lava',
    seed: 1301,
    shipId: 'mule',
    modifiers: LevelModifiers(gravityMul: 1.3, cargoDensityMul: 1.2),
    legs: [
      [_draft, _p],
      [_p, _up],
      [_p, _draft],
      [_bar, _fuel, _p],
    ],
  ),
  // E4: shield emitter segments round the Ring.
  ExpeditionOutline(
    id: 'exp_04',
    name: 'Shield Ring',
    themeId: 'orbit',
    seed: 1402,
    shipId: 'vector',
    modifiers: LevelModifiers(gravityMul: 0.7),
    legs: [
      [_zg, _well],
      [_wind, _zg],
      [_well, _sq, _blk],
      [_zg, _well],
    ],
  ),
  // E5: the Warden asks for help. Its own guns don't know that yet.
  ExpeditionOutline(
    id: 'exp_05',
    name: "The Warden's Peace",
    themeId: 'redoubt',
    seed: 1501,
    shipId: 'talon',
    legs: [
      [_gun, _sq],
      [_gun, _up, _bar],
      [_pen, _gun],
    ],
  ),
  // E6: relic pods into the Heart.
  ExpeditionOutline(
    id: 'exp_06',
    name: 'Into the Heart',
    themeId: 'alien',
    seed: 1605,
    shipId: 'hopper',
    modifiers: LevelModifiers(gravityMul: 0.9),
    legs: [
      [_zg, _sq, _bar],
      [_draft, _dn, _pen],
      [_wind, _up, _sq],
      [_sq, _zg, _blk],
    ],
  ),
  // E7: the Warden's core into the Heart as the Tide hits.
  ExpeditionOutline(
    id: 'exp_07',
    name: 'The Long Night',
    themeId: 'orbit',
    seed: 1701,
    shipId: 'vector',
    modifiers: LevelModifiers(gravityMul: 0.8),
    legs: [
      [_well, _zg],
      [_wind, _blk],
      [_zg, _sq],
      [_well, _pen],
      [_draft, _p, _bar],
    ],
  ),
];
