# Performance baseline

How fast the game runs, how it's measured, and what's left to do. Measured on 2026-10-09.

## Tools

| Tool | What it measures | Command |
|---|---|---|
| `PerfMonitor` (`lib/game/perf/`) | Engine frame timings (UI build, raster), `update` total, game-logic sections, `render` recording, level load, startup marks. Prints one `PERF <level> <outcome> …` line per flight. A small FPS readout appears top-left. | `flutter run --profile --dart-define=PERF=true` |
| Headless bench (`test/autopilot/perf_bench_test.dart`) | Flies every level once with the autopilot. Records load time, update and render recording per frame, render cost per component type, and logic sections. Writes `build/perf_report.md`. | `flutter test test/autopilot/perf_bench_test.dart --run-skipped --dart-define=PERF=true --dart-define=STORE_CAPTURE=true [--dart-define=LEVELS=a,b]` |
| Device demo test (`integration_test/perf_flight_test.dart`) | Replays the bundled demo flight of 7 heavy levels with the real visuals. Writes `build/perf_device_<level>.json`. | `flutter drive --profile --dart-define=PERF=true --driver=test_driver/perf_driver.dart --target=integration_test/perf_flight_test.dart -d <device>` |

Without `PERF` every hook is a `const` false check, so release builds carry no probe.

## Results

### Headless bench (Mac, JIT, all 60 levels)

- **`update` is cheap.** Every level stays at p95 ≤ 0.9 ms. The game-logic part is at most 0.34 ms p95. The 12-raycast rock probe averages 0.017 ms. Shell interception, guidance and camera each stay at or below 0.003 ms.
- **`render` recording stays at p95 ≤ 2.2 ms.** The biggest costs are `HudTouchControls` (0.08 ms mean), `AmbientParticles` (0.075 ms) and `CaveDecor` (0.06 ms). `CaveTerrain` records in 0.005 ms, because its cost is raster work, not recording.
- **Level load takes 10–220 ms.** Debug builds rebuild the cave on every load, so release is faster.
- **`crateSpots` (main thread, only when a crate rolls) takes 2–4 ms.** That's too little to be worth an isolate.
- **After this pass** (mean over the 60 levels, same Mac): render p95 went from 0.60 to 0.42 ms (−30%), render p50 from 0.24 to 0.22 ms, and update p95 from 0.17 to 0.11 ms. The update figure is partly JIT noise.
- **The autopilot regression is identical to `HEAD`**, with a byte-equal `build/autopilot_report.json`, so flight behaviour is unchanged. `mine_08` failed the hazards-on run at `HEAD` too: after the ship ×1.6 / pod ×3 commit `2e9db0e`, a towing Mule no longer fit round the rotating bar. The bar chamber is now 3.5 m (was 3.0); the bot delivers 3★ (tight) and the route is re-exported.
- **The update max spikes (30–218 ms)** happen on a level's first frames: JIT warm-up and GC. They don't show up in profile/AOT builds.

### Device demo test, macOS profile build (Apple silicon)

Before the HUD text and `saveLayer` changes below.

| level | frames | UI build ms p50 / p95 / p99 | raster ms p50 / p95 / p99 | frames > 16.7 ms |
|---|---:|---|---|---:|
| alien_08 | 4024 | 0.6 / 0.8 / 1.3 | 2.5 / 3.6 / 4.1 | 2 |
| ice_07 | 4017 | 0.7 / 0.9 / 1.5 | 2.5 / 2.9 / 3.1 | 0 |
| lava_07 | 4018 | 0.7 / 0.9 / 1.5 | 2.5 / 2.9 / 3.4 | 0 |
| mine_08 | 3980 | 0.5 / 0.8 / 1.0 | 1.8 / 2.6 / 3.0 | 2 |
| orbit_06 | 3997 | 0.4 / 0.8 / 1.0 | 1.8 / 2.5 / 3.0 | 2 |
| redoubt_04 | 3972 | 0.7 / 0.9 / 1.5 | 2.2 / 2.6 / 2.7 | 0 |
| tut_08 | 4007 | 0.5 / 1.1 / 1.6 | 1.6 / 2.4 / 3.0 | 2 |

The few late frames are level start and shader warm-up. A Mac GPU is far faster than a phone's, so the iPhone run below is the number that matters.

### Device demo test, iPhone (iOS 26.6, profile build)

Measured after the HUD text and `saveLayer` changes. 1,930–2,160 frames of demo replay per level.

| level | UI build ms p50 / p95 / p99 | raster ms p50 / p95 / p99 / max | frames > 16.7 ms |
|---|---|---|---:|
| tut_08 | 1.3 / 1.8 / 3.0 | 3.3 / 3.9 / 4.1 / 5.5 | 0 |
| alien_08 | 1.6 / 1.9 / 3.0 | 3.6 / 4.1 / 4.3 / 8.0 | 0 |
| mine_08 | 1.7 / 2.1 / 3.0 | 3.5 / 4.0 / 4.2 / 5.1 | 0 |
| ice_07 | 1.8 / 2.2 / 3.0 | 3.5 / 4.1 / 4.3 / 5.1 | 0 |
| lava_07 | 1.8 / 2.2 / 3.1 | 3.4 / 4.1 / 4.3 / 5.1 | 0 |
| orbit_06 | 1.6 / 1.9 / 2.8 | 3.5 / 4.0 / 4.3 / 5.4 | 0 |
| redoubt_04 | 1.7 / 2.1 / 3.0 | 3.4 / 4.2 / 4.6 / 5.6 | 0 |

**Verdict:** raster p95 stays at or under 4.2 ms and no frame was late. That's a quarter of the 16.7 ms a 60 fps frame allows. The GPU items below are not needed on this phone. Keep them for a low-end Android check.

**Startup on the iPhone:** `main` to `runApp` took 28 ms. `AudioService.init` then took about 6 s, because building ~40 pooled players is slow on iOS, and the game's `onLoad` waited for it. Now `init` only loads the files and builds the pools in the background (`AudioService.warmedUp`). Until a sound's pool is ready, it plays on a one-off player. Re-measured on the iPhone: files ready at +0.66 s, game loaded at +0.66 s (was +6.1 s), pools ready in the background at +8.9 s.

**Startup:** `AudioService.init` took about 800 ms on the Mac, loading 23 files one at a time. It now loads them concurrently.

## Changes made in this pass

**Bug fixes:**
- **A delivery that fails to save no longer freezes on the pad.** The result screen shows without the XP panel instead (`_onGoalReached` → `_bookDelivery`, `test/level_lifecycle_test.dart`).
- **Leaving mid-load no longer leaves a live level behind.** `_spawnLevel` takes a generation token, and every entity is tracked before it's added (`_addToLevel`, `_checkLoad`).
- **The daily's Test Flight isolate failing** now falls back to a standard run.

**Code quality:**
- The `unawaited_futures` lint is on, and every fire-and-forget call is explicit.

**Performance:**
- Audio files and pools, and the theme images, load concurrently.
- Firebase starts alongside the save load.
- Countdown and level-intro text no longer build a `TextPainter` every frame.
- Fading HUD labels snap their alpha to 1/32 steps (`quantizeAlpha`), so `HudText` re-lays them out about 32 times per fade instead of every frame.
- The guidance plates skip `saveLayer` when fully opaque.

**Structure:**
- One star rule, `StarSpec.rate`, now serves the game and the HUD.
- `LevelRegistry.starsIn` / `trainingFinale` / `trainingComplete` replace the scattered star totals.
- `OverlayIds` holds the overlay keys.
- UI screens open and close Settings and the rank-up card through game methods instead of editing `game.overlays` directly.

## GPU items (not needed on the iPhone; revisit if a low-end Android shows late frames)

Only do these if a device's raster p95 is above about 8 ms, or there are late frames mid-flight:
1. **HUD glows.** About 10 `MaskFilter.blur` draws per frame (`drawGlow` in `hud_holo.dart`) plus a blurred shadow on every HUD label. Fix: pre-render the static plates and glows into images per state, and drop the text-shadow blur.
2. **`CaveTerrain.render`.** It fills the whole world's even-odd rock path with an image shader and strokes every edge twice, with no culling. Fix: rasterise it into world tiles (like the glow bitmap) and draw only the visible ones.
3. **Off-screen culling.** Ambient particles (up to 260 circles), route dots and force-field streaks.

The bench says these aren't worth doing (CPU cost under 0.02 ms each): entity registries for shells and turrets, the rock-probe AABB early-out, and an isolate for `crateSpots`.

Larger refactors, deliberately not done yet:
- Split `NarrowHaulGame` (3,200 lines) into `LevelSession`/`LevelLoader` and `WeaponsController`.
- Put the static services behind interfaces.
- A `CameraRig` that composes follow, shake, rumble and meltdown.
