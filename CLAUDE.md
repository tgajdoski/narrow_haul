# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get          # Install dependencies
flutter run              # Run the game (use a landscape-capable device/simulator)
flutter test             # Run tests
flutter analyze          # Static analysis / linting
```

There is no Makefile or custom build script — all operations go through `flutter`.

## Architecture Overview

**Narrow Haul** is a 2D physics-based Flutter game. The tech stack is:
- **Flame v1.36.0** — game engine (component/system model)
- **Forge2D v0.19.2** — Box2D physics (via `flame_forge2d`)
- **Flame Tiled v3.1.0** — level loading from `.tmx` map files
- **shared_preferences** — persistence for progress, cosmetics, achievements

`Flame.images.prefix` is set to `'assets/'` in `main()`, so all image paths are relative to `assets/` (not the default `assets/images/`).

### Game Class (`lib/game/narrow_haul_game.dart`)

`NarrowHaulGame` extends `Forge2DGame`. It is the single master controller:
- Owns the `RunState` enum (`menu | playing | gameOver | won`) and drives all state transitions
- Holds references to the active `ShipBody`, `CargoBody`, `CargoAttachment`
- Manages level lifecycle: load → play → teardown (all level entities tracked in `_levelEntities` for bulk removal)
- Reads `rotateAxis` (−1.0 to 1.0) and `thrustHeld` (bool) from `HudTouchControls` each frame, then calls `ship.setInput(...)`
- Calculates stars (1/2/3 based on remaining fuel %), saves progress, fires achievement checks after win
- Hosts the daily challenge mode (`isChallengeMode`, `activeChallengeConfig`)

### Physics System (`lib/game/physics_constants.dart`)

- **Scale:** 32 px = 1 meter (`pixelsPerMeter`). Tiled tiles are 32 px.
- **Gravity:** `kGravityY = 1.375 m/s²` (debug builds use 70% of this via `kDebugReduceGravity`)
- **Collision bitmasks:** `categoryWall=0x0001`, `categoryShip=0x0002`, `categoryCargo=0x0004`, `categoryGoalCargo=0x0008`, `categoryGoalShip=0x0010`, `categoryHook=0x0020`. Hook sensor only collides with cargo; ship/cargo do not collide with each other directly (rope joint handles connection).
- **Tags** in `lib/game/tags.dart` are used in `beginContact` callbacks to identify collision partners.

### Rope/Tow System

Three collaborating files:
1. **`cargo_attachment.dart`** — FSM that monitors ship-cargo distance. Starts fading in rope visual at 2.5 m; auto-attaches when hook is within 0.63 m or ship center is within 1.2 m.
2. **`rope_physics_coupling.dart`** — Creates the Forge2D joint. Uses `RopeJoint` for normal distances (≥ 0.12 m) or `DistanceJoint` for very short distances. Ship anchor = `(0, 0.26)` (rear); cargo anchor = cargo world center. `maxLength` = distance at attach clamped to `levelData.ropeMaxLength`.
3. **`rope_line.dart`** — Bézier visual only (no physics). Opacity driven by `ropeRevealProgress`.

### Level System

`LevelRegistry` (`lib/game/level/level_registry.dart`) is the authoritative list: 5 `WorldDef`s → 42 `LevelDef`s (flat index = play order). Two level kinds (sealed `LevelDef` in `level_def.dart`):

1. **`TmxLevelDef`** — the 10-level Tutorial world. `.tmx` files in `assets/tiles/` (level_01…level_10; files 11-20 exist but are retired). `TiledLevelLoader` parses object layer "walls" (rectangles → static bodies) and "markers" (`ship`, `goal`, `cargo_zone`).
2. **`CaveLevelDef`** — 32 organic cave levels in 4 themed worlds (Alien/Mine/Ice/Lava), 8 each, defined as const `LevelSpec` data in `lib/game/level/specs/world_*.dart`. **No external editor** — hand-authored Dart data.

**Cave pipeline** (`lib/game/level/cave/`): `LevelSpec` (tunnels = Catmull-Rom splines with per-point half-widths, chambers = ellipses, anchors, obstacles, modifiers) → `cave_builder.dart` samples a signed distance field (smooth-min union, seeded fbm noise for the ant-nest look, noise fades near anchors) on a 0.1 m grid → marching squares → Chaikin + Douglas-Peucker → contour loops. Loops become one static body with `ChainShape.createLoop` fixtures (`CaveTerrain` component) and an even-odd filled `Path` for rendering. Deterministic: noise seed is the spec's explicit `seed` int — levels are fixed, never random. Builder is pure Dart (headless-testable) and memoized per level id (cache cleared each load in debug for hot-reload authoring).

**Validation:** `test/cave_level_validation_test.dart` proves every cave level completable (anchor openness, BFS reachability with ship clearance, cargo rest-point approachability, obstacle sweeps clear of anchors, determinism, build-time budget). Authoring aid: `dart run tool/preview_levels.dart [id]` prints ASCII maps + issues. **Run this after any spec edit.** Common authoring gotcha: a cargo pocket must be a bowl — connect its tunnel at/above the pocket center, never as a slope under the cargo, or the cargo rolls out.

**Theming:** `ThemeSpec` per world (`lib/game/level/theme_spec.dart`) — backdrop, rock palette, parallax tint/alphas, pad + UI accent colors. Applied in `_spawnLevel`; parallax layers are the shared 3 PNGs modulate-tinted per theme.

**Modifiers:** `LevelModifiers` per level — `gravityMul`, `fuelDrainMul`, `cargoDensityMul`, `wallFriction` (ice ≈ 0.03). They compose multiplicatively with daily-challenge multipliers.

**Obstacles** (`lib/game/components/obstacles.dart`): `RotatingBar` (constant angular velocity), `Pendulum` and `SlidingBlock` (kinematic velocity-tracking on analytic paths — never teleported). All carry `WallTag`, so ship contact = crash via existing handling; cargo gets batted physically.

**Progression:** worlds unlock by total-star gates (`WorldDef.starsRequired`: 0/8/22/40/60); within a world, completing a level (≥1★) unlocks the next. Unlock state is *computed* from stars, not stored. Newly earned stars pay cosmetic currency × `WorldDef.rewardPerStar`. Per-level star thresholds live on `LevelDef.stars` (`StarSpec`: fuel fractions + time limit).

`ropeMaxLength` is auto-calculated as `(shipToCargoDistance + 6.0 m) × 2` at load time for both level kinds.

### Services (`lib/game/services/`)

| Service | Responsibility |
|---|---|
| `ProgressService` | Singleton backed by `shared_preferences`. Stars/best times are keyed by **string `LevelDef.saveId`** (`stars2_<id>` / `time2_<id>`) so reordering levels never corrupts saves; `init()` runs a one-time `save_v2` migration from the old index keys. Also: daily challenge completion, cosmetic currency. Call `ProgressService.init()` before `runApp`. |
| `CareerService` / `rank_service.dart` | Pilot ranks & XP. Pure rank math (`kRanks`, `rankFor`, `computeRunXp`) + persistence glue. XP stored in `xp_total`; `save_v3` migration backfills XP from existing stars/achievements. |
| `AchievementService` | Static class. `AchievementService.all` = full list; `unlocked` = Set of earned IDs. Call `unlock(id)` after win checks. |
| `AudioService` | Wraps `flame_audio`. Silent fallback if audio files are missing. Audio files go in `assets/audio/`. |
| `CosmeticsService` | Categories: `catShip`, `catRope`, `catPlume`. `isUnlocked`, `equip`, `unlock` (costs cosmetic currency). |
| `DailyChallengeService` | `DailyChallengeConfig.forToday(totalLevels)` — deterministic gravity/fuel modifiers from date. |
| `MonetizationService` | Stub only — rewarded ads / IAP not yet wired. |

### Pilot Career (Ranks & XP)

10 realistic civil-aviation ranks (`kRanks` in `rank_service.dart`): Student → Private → Commercial Pilot → Second Officer → First Officer → Senior First Officer → Captain → Senior Captain → Training Captain → Chief Pilot (+ prestige ★ every 3000 XP). XP is awarded in `_onGoalReached`: first clear 60×tier, new stars 30×tier each, clean flight +15, PB +20, daily 150 + streak, achievements +100; tier = 1 + 0.5×world index. Runs that earn nothing new share a 300 XP/day cap. Ranks grant a currency multiplier on payouts, a one-off promotion bonus, and unlock rank-locked cosmetics (`CosmeticItem.rankRequired`). Insignia (wings / epaulette bars) is drawn by `paintInsignia` in `components/rank_insignia.dart`. The win result is exposed as `NarrowHaulGame.lastRunReward`. Lifetime stats: `ProgressService.getStat(stat*)`.

**Contracts** (`contracts_service.dart`, unlocked at Commercial Pilot): 3 daily tasks generated deterministically from the date (only feasible ones: unlocked worlds, stars left, daily not done), stored per day in `contracts_<date>` so they don't reshuffle; progress applied in `_onGoalReached` via `ContractsService.recordDelivery`, completed contracts + all-done bonus appear as XP lines. **Achievement toast:** `AchievementService.unlock(id, announce: true)` pushes to `AchievementService.announced`, shown by `_AchievementToastHost` (use only for mid-flight unlocks; win-time unlocks are listed on the level-complete screen). Mid-flight unlocks pay their XP with the delivery, or immediately on crash.

### Overlays (Flutter widgets, defined in `lib/main.dart`)

| Key | Shown when |
|---|---|
| `'menu'` | App start; after game-over or win → menu |
| `'levelSelect'` | "Missions" button on menu |
| `'achievements'` | "Achievements" button on menu |
| `'cosmetics'` | "Garage" button on menu |
| `'gameOver'` | Ship hits wall (`RunState.gameOver`) |
| `'levelComplete'` | Both ship + cargo on pad (`RunState.won`); shows XP breakdown + animated rank bar |
| `'rankUp'` | Pushed on top of levelComplete when the run crossed a rank |
| `'pilotProfile'` | Pilot Logbook (rank ladder + lifetime stats), from the menu rank card |

All overlays are plain Flutter `StatelessWidget`s registered in `GameWidget.overlayBuilderMap`. They call back into `NarrowHaulGame` methods (`restartLevel`, `backToMenu`, `nextLevel`, `startLevel(i)`).

### Camera

Base zoom `_baseZoom = 28` (px/meter). Follows ship with 18% lerp per frame. Clamped to world bounds so the camera never shows outside the level. Auto-scales down if world fits inside viewport.

### Visual Layer Priorities

| Layer | Priority |
|---|---|
| Parallax background | −9999 |
| Solid backdrop rect | −2000 |
| Terrain/objects | 0 (default) |
| Rope line | 1000 |
| HUD controls & text | 5000 |

### Key Tuning Constants

| Constant | File | Value |
|---|---|---|
| `_baseZoom` | `narrow_haul_game.dart` | 28 px/m |
| `pixelsPerMeter` | `physics_constants.dart` | 32 |
| `kGravityY` | `physics_constants.dart` | 1.375 m/s² |
| `thrustForce` | `ship_body.dart` | 5.1 N |
| `fuelDrainPerSecond` | `ship_body.dart` | 12 units/s |
| `secondsPerFullRotation` | `ship_body.dart` | 4.0 s |

### Debug Mode

In `kDebugMode` (Flutter debug builds), gravity is reduced to 70% and the HUD shows `rot?` / `thrust?` stall warnings when physics joints are fighting input.

## Asset Notes

- All sprites live at `assets/` root (not `assets/images/`). The path prefix is set once in `main()`.
- `exhaust.png` may have a black background (not transparent) — flag this if visual artifacts appear.
- Audio files (`thrust_loop.mp3`, `attach.mp3`, `crash.mp3`, `land.mp3`, `star.mp3`) belong in `assets/audio/`; `AudioService` silently skips missing files.
- `rope_segment_body.dart` exists but is unused (multi-segment rope system, not active).
