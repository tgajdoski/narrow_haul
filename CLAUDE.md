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

`LevelRegistry` (`lib/game/level/level_registry.dart`) is the authoritative list: 6 `WorldDef`s → 54 `LevelDef`s (flat index = play order). Two level kinds (sealed `LevelDef` in `level_def.dart`):

1. **`TmxLevelDef`** — the 10-level Tutorial world. `.tmx` files in `assets/tiles/` (level_01…level_10; files 11-20 exist but are retired). `TiledLevelLoader` parses object layer "walls" (rectangles → static bodies) and "markers" (`ship`, `goal`, `cargo_zone`).
2. **`CaveLevelDef`** — 44 organic cave levels in 5 themed worlds (Alien/Mine/Ice/Lava/Orbit), 8 each plus a `rating_<ship>` type-rating level opening the Alien, Mine, Ice and Orbit worlds, defined as const `LevelSpec` data in `lib/game/level/specs/world_*.dart`. **No external editor** — hand-authored Dart data.

**Cave pipeline** (`lib/game/level/cave/`): `LevelSpec` (tunnels = Catmull-Rom splines with per-point half-widths, chambers = ellipses, anchors, obstacles, modifiers) → `cave_builder.dart` samples a signed distance field (smooth-min union, seeded fbm noise for the ant-nest look, noise fades near anchors) on a 0.1 m grid → marching squares → Chaikin + Douglas-Peucker → contour loops. Loops become one static body with `ChainShape.createLoop` fixtures (`CaveTerrain` component) and an even-odd filled `Path` for rendering. Deterministic: noise seed is the spec's explicit `seed` int — levels are fixed, never random. Builder is pure Dart (headless-testable) and memoized per level id (cache cleared each load in debug for hot-reload authoring).

**Validation:** `test/cave_level_validation_test.dart` proves every cave level completable (anchor openness, BFS reachability with ship clearance, cargo rest-point approachability, obstacle sweeps clear of anchors, determinism, build-time budget). Authoring aid: `dart run tool/preview_levels.dart [id]` prints ASCII maps + issues. **Run this after any spec edit.** Common authoring gotcha: a cargo pocket must be a bowl — connect its tunnel at/above the pocket center, never as a slope under the cargo, or the cargo rolls out.

**Flight checks** (`analyzeFlight` in `level_validator.dart`): along the shortest 8-connected route spawn → cargo → goal, *lift* = loaded thrust accel ÷ strongest pull at the heaviest daily gravity (must be ≥ 2.0), and *fuel* = impulse floor ∫|pull + hull drag·v|/a_thrust dt at 2.5 m/s cruise × 1.3 overhead (must be ≤ 60% of tank). Clearance and both checks use the level's ship. The preview tool prints these per level and warns `⚠ 3★ tight` when the estimate exceeds the 3★ fuel budget.

**Theming:** `ThemeSpec` per world (`lib/game/level/theme_spec.dart`) — backdrop, rock palette, parallax tint/alphas, pad + UI accent colors, edge glow, decor tip color/density, `AmbientKind` particles. Applied in `_spawnLevel`. Optional art in `assets/themes/<id>/` (`rock.png`, `far/mid/near.png`, `decor.png` — spec in `assets/themes/README.md`) is loaded by `ThemeAssets`; every file falls back to the flat look (shared tinted parallax, solid rock, procedural spikes). `CaveDecor` places visual-only stalactites/stalagmites on cave floors/ceilings (seeded, clear of anchors and narrow passages — `test/cave_decor_test.dart`).

**Modifiers:** `LevelModifiers` per level — `gravityMul`, `fuelDrainMul`, `cargoDensityMul`, `wallFriction` (ice ≈ 0.03). They compose multiplicatively with daily-challenge multipliers; combined gravity is clamped to `kMaxGravityMul` (2.5). Worlds ramp gravity: Alien 0.85→0.5, Mine 1.1→1.3, Lava 1.4→1.7. The HUD shows a local-gravity arrow (`GravityIndicatorHud`) whenever gravity isn't 1 g.

**Ships** (`lib/game/ship/ship_spec.dart`): `ShipSpec` const data (hull scale, density, thrust, turn rate, tank, drain, damping, winch length, tint, passive-assist flags). The level picks the ship — `LevelSpec.shipId` overrides `WorldDef.defaultShipId`, which comes from a pure-Dart `<world>ShipId` const in each `specs/world_*.dart` file so `dart run` tools can see it. Kestrel (baseline, tutorial), Hopper (light, low-g Alien), Mule (heavy lifter, Mine/Lava), Skate (auto-levels against local gravity when both controls are released, Ice), Vector (hover assist: while thrusting, cancels 75% of the local pull, Orbit). Ship art: `ShipSpec.sprite` (`ship_<id>.png`, 256×256, framed like `ship.png`); if missing, the Kestrel sprite is drawn with `ShipSpec.tint`. Each new ship gets a `rating_<ship>` type-rating level at the start of its world; `LevelRegistry.hasTypeRating(id)` (Kestrel = Training Grounds complete) drives the Pilot Logbook's Type Ratings list and the `fleet_qualified` achievement. Ship/field achievements: `storm_rider` (3★ with wind), `orbital_mechanic` (3★ with a well), `heavy_lifter` (deliver at ≥ 1.5 g), `test_pilot` (Test Flight daily). A level that already has stars stays unlocked even if a level is inserted before it.

**Force fields** (`FieldSpec` in `level_spec.dart`, strengths in g): `GravityZoneSpec` (replaces gravity in a feathered rect/ellipse — zero-g or sideways), `WindZoneSpec` (additive, optional gusts), `GravityWellSpec` (softened, capped point attractor). `FieldSampler` (pure Dart) is shared by runtime and validator; `ForceFieldSystem` applies only `mass × (local − base)` to ship (after launch) and cargo, so levels without fields are untouched; it also draws the fields from the same sampler (wind streaks, gravity-zone tint + chevrons, zero-g motes, contracting well rings) below the rock. Validator guardrails: wind peak ≤ 1 g and ≤ 45% of loaded thrust; spawn/cargo/goal must feel ≥ 0.3 g within 25° of straight down through a full gust cycle, or ≤ 0.2 g (drift); a cargo pod near a well or in a strong zone needs `LevelSpec.cargoClamped` (kinematic until hooked, `CargoBody.release()` on attach). Well cores are solid `WellCore` bodies (WallTag = crash), treated as rock by the validator, and must stay ≥ 1.5 m from spawn/cargo/goal. `gravityMul: 0` = zero-g level. Preview map marks `~` wind, `z` gravity zone, `0` zero-g, `o` well. Physics constants needed by pure-Dart code live in `physics_core.dart`.

**Obstacles** (`lib/game/components/obstacles.dart`): `RotatingBar` (constant angular velocity), `Pendulum` and `SlidingBlock` (kinematic velocity-tracking on analytic paths — never teleported). All carry `WallTag`, so ship contact = crash via existing handling; cargo gets batted physically.

**Progression:** worlds unlock by total-star gates (`WorldDef.starsRequired`: 0/8/22/40/60/80); within a world, completing a level (≥1★) unlocks the next. Unlock state is *computed* from stars, not stored. Newly earned stars pay cosmetic currency × `WorldDef.rewardPerStar`. Per-level star thresholds live on `LevelDef.stars` (`StarSpec`: fuel fractions + time limit).

`ropeMaxLength` is auto-calculated as `(shipToCargoDistance + 6.0 m) × 2` at load time for both level kinds.

### Services (`lib/game/services/`)

| Service | Responsibility |
|---|---|
| `ProgressService` | Singleton backed by `shared_preferences`. Stars/best times are keyed by **string `LevelDef.saveId`** (`stars2_<id>` / `time2_<id>`) so reordering levels never corrupts saves; `init()` runs a one-time `save_v2` migration from the old index keys. Also: daily challenge completion, cosmetic currency. Call `ProgressService.init()` before `runApp`. |
| `CareerService` / `rank_service.dart` | Pilot ranks & XP. Pure rank math (`kRanks`, `rankFor`, `computeRunXp`) + persistence glue. XP stored in `xp_total`; `save_v3` migration backfills XP from existing stars/achievements. |
| `AchievementService` | Static class. `AchievementService.all` = full list; `unlocked` = Set of earned IDs. Call `unlock(id)` after win checks. |
| `AudioService` | Wraps `flame_audio`. Silent fallback if audio files are missing. Audio files go in `assets/audio/`. |
| `CosmeticsService` | Categories: `catShip`, `catRope`, `catPlume`. `isUnlocked`, `equip`, `unlock` (costs cosmetic currency). |
| `DailyChallengeService` | `DailyChallengeConfig.forToday(totalLevels, shipOptions:)` — deterministic gravity/fuel modifiers from date, or a "Test Flight" day flying another ship (`shipId`). Candidates come from `LevelRegistry.testFlightOptions`: smaller-or-equal hull, and on cave levels each must pass the full validator (TMX: ≥ 90% of the native ship's `deltaV`); none → standard run. |
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
| `'pause'` | HUD pause button (top-center) or app backgrounded mid-flight (`pauseGame`/`resumeGame`; `isPaused`, runState stays `playing`) |
| `'settings'` | From menu or pause; sound / vibration / left-handed / minimap, persisted in `ProgressService`, applied via `applySettings()` |

`pause`/`settings` live in `lib/ui/pause_settings_overlays.dart`. Crashes play `ExplosionBurst` + camera shake for 0.9 s before `'gameOver'` appears. Level time is `elapsedSeconds` (accumulated game time — pauses don't count). Vibration goes through `Haptics` (`services/haptics.dart`). The ship hovers on its start pad (`gravityScale` zero) until the first input (`ShipBody.launched`), and the level clock starts then. On delivery a `CelebrationBurst` plays ~1.1 s before `'levelComplete'`. `HintHud` shows the landing status (only one of ship/cargo on the pad) and, on tut_01–03 until first clear, onboarding steps. Titles use the bundled `RussoOne` font (`kDisplayFont`, `lib/ui/fonts.dart`) via the theme's display/headline/title styles.

**Visual smoke test:** `flutter test integration_test/visual_smoke_test.dart -d macos` drives menus, levels, pause, crash and the result screen, saving screenshots to the app's sandbox temp dir (printed as `SHOTS_DIR=`). Uses mocked prefs, so it never touches real saves.

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
| Minimap (`MinimapHud`, top-right, tap to collapse; persisted as `minimap_enabled`) | 4900 |

### Key Tuning Constants

| Constant | File | Value |
|---|---|---|
| `_baseZoom` | `narrow_haul_game.dart` | 28 px/m |
| `pixelsPerMeter` | `physics_constants.dart` | 32 |
| `kGravityY` | `physics_constants.dart` | 1.375 m/s² |
| `thrustForce` | `ship_spec.dart` (Kestrel) | 5.1 N |
| `fuelDrainPerSecond` | `ship_spec.dart` (Kestrel) | 12 units/s |
| `secondsPerFullRotation` | `ship_spec.dart` (Kestrel) | 4.0 s |

### Debug Mode

In `kDebugMode` (Flutter debug builds), gravity is reduced to 70% and the HUD shows `rot?` / `thrust?` stall warnings when physics joints are fighting input.

## Asset Notes

- All sprites live at `assets/` root (not `assets/images/`). The path prefix is set once in `main()`.
- Ship sprites `ship_<id>.png` must be 256×256 RGBA framed like `ship.png` (hull inside x 58–198, bottom-aligned to the nozzle line at y 181 — the plume starts there). AI-generated art often has a *painted* checkerboard instead of transparency: run `python art_src/ships/fix_ships.py <src.png> <out.png> assets/ship.png` (needs Pillow) to strip it, crop and frame. 1024 px sources live in `art_src/ships/` (not bundled).
- `exhaust.png` may have a black background (not transparent) — flag this if visual artifacts appear.
- Audio files (`thrust_loop.mp3`, `attach.mp3`, `crash.mp3`, `land.mp3`, `star.mp3`) belong in `assets/audio/`; `AudioService` silently skips missing files.
- `rope_segment_body.dart` exists but is unused (multi-segment rope system, not active).
