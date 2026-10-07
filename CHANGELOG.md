# Narrow Haul — Changelog

## v2.3.0 — Defences Update (Thrust layer)

Borrowed from Thrust and Gravitar: caves that shoot back, fuel worth the detour, and a reactor to outrun.

### New world: The Redoubt
- 6 missions (Talon type rating + 5), unlocked at 100 stars, flown in the new **Talon** armed escort hauler (Kestrel handling, 115 tank, nose cannon). Own sprite (`ship_talon.png`, source in `art_src/ships/`).
- **FIRE button** appears only for armed ships (tap = one shot, hold = auto-fire; every shot costs fuel). Mirrored in left-handed mode.

### Defences & pickups
- **Wall turrets**: lead their aim, need line of sight (the cargo pod is cover), telegraph each shot with a muzzle glow, hold fire until you launch. Shells destroy the ship and shove the cargo. Two hits destroy a turret.
- **Reactor core**: 3 hits knock all turrets offline for 10 s; destroying it starts a meltdown countdown — deliver before it hits zero. First escape per mission pays +150 XP and a currency bonus.
- **Fuel canisters**: fly through to top up the tank.
- Dodge-only turrets added to The Grinder (mine) and Molten Run (lava).
- Mission Select badges: ✛ turrets, ☢ reactor.

### Progression
- Achievements: Weapons Hot, Meltdown Escape, Hold Fire, Hot Refuel.
- Contract: "Destroy N turrets and deliver" (offered once an armed world is unlocked).
- Lifetime stats: turrets destroyed, reactor escapes, fuel canisters.

### Dev
- `TurretSpec` / `ReactorSpec` obstacles and `LevelSpec.pickups` (`FuelCellSpec`); `ShipSpec.armed`.
- Validator: turrets must sit on a wall facing open space and must never see the spawn pad, cargo or goal; reactors require an armed ship; pickups must be open and reachable. ASCII preview marks `T`, `R`, `F`.
- Optional sounds `shot.mp3` / `boom.mp3` (silently skipped when missing).
- New tests: lead-aim math, line of sight, reactor/turret state, validator combat rules, turret contract.

## v2.2.0 — Look & Feel Update

Worlds finally look like where they are, and flying feels better.

### World visuals
- Per-world art pipeline: optional `rock.png` (tileable rock texture), `far/mid/near.png` (dedicated parallax) and `decor.png` (edge props) in `assets/themes/<world>/`; every file falls back to the existing look. Prompts and specs in DEVELOPMENT_PLAN.md and `assets/themes/README.md`.
- Stalactites & stalagmites on cave floors and ceilings (procedural spikes until art lands) — deterministic, kept clear of pads, cargo and narrow passages.
- Edge glow per world (lava heat, ice frost, alien bioluminescence) and ambient particles (embers, snow, spores, dust).
- Bundled display font (Russo One, OFL) for titles.

### Flight & HUD
- Pause button + pause menu (Resume / Restart / Settings / Menu); auto-pause when the app is backgrounded.
- Settings: sound, vibration, left-handed controls, minimap.
- Live timer and best-reachable star target in the HUD; star-threshold ticks on the fuel bar; blinking LOW FUEL warning.
- Level intro card; onboarding hints on the first three tutorial levels; landing hint when only ship or cargo is on the pad.
- Crash explosion with camera shake; confetti on delivery; haptics on hook, landing and crash.
- The ship waits on its start pad until the first input, and the level clock starts then.

### Screens
- Mission Complete: stars pop in, fuel left shown, and what the next star needed.
- Mission Select: auto-scrolls to and highlights the next mission, shows level names, explains modifier icons.

### Fixes
- Level time no longer counts paused or backgrounded time.
- The solid level backdrop hid the parallax layers entirely (now a haze when a world has its own parallax art).
- Rock speckles were re-computed (60 path hit-tests) every frame.
- Starting a level now closes any lingering in-game overlay.

### Dev
- `integration_test/visual_smoke_test.dart`: drives the real app on macOS and saves screenshots (mocked save data).
- New tests: cave decor placement, pause/settings layout on a small landscape phone.

## v2.1.0 — Pilot Career Update

A long-term progression layer on top of stars: earn XP, climb a realistic civil-aviation career ladder, and take daily contracts.

### Pilot Ranks & XP
- 10 ranks modelled on real licences and airline seniority: Student Pilot → Private Pilot → Commercial Pilot → Second Officer → First Officer → Senior First Officer → Captain → Senior Captain → Training Captain → Chief Pilot, plus prestige ★ every 3000 XP beyond the top.
- XP per delivery: first clear 60×tier, each new star 30×tier (tier = 1.0 Training → 3.0 Ember Core), clean flight +15, personal best +20, daily challenge 150 + streak bonus, achievements +100. Repeat runs that earn nothing new share a 300 XP/day cap.
- Rank perks: currency multiplier on payouts (+5% → +20%), one-off promotion bonus (25 × rank), and five rank-locked cosmetics (Braided Gold rope, Carbon ship, Afterburner plume, Captain's Gold Trim ship, Aurora plume).
- Insignia drawn procedurally: pilot wings for licence ranks, airline epaulettes with 1–4 gold bars, star and laurel for senior roles.
- Save format v3: one-time migration backfills XP from existing stars and achievements so upgrading players start at a fair rank.

### Daily Contracts
- Unlocked at Commercial Pilot: 3 deterministic tasks per day (deliver in a world, land with high fuel, clean flights, beat a PB, earn stars, fast delivery, finish the daily), 75–150 XP each + 100 XP for completing all three. Only feasible contracts are offered; the day's set is stored so it never reshuffles.
- Daily challenge streak (🔥) shown on the menu; streak raises daily XP (capped at 7 days).

### UI
- Menu rank card (insignia, title, XP bar) → new **Pilot Logbook** screen: rank ladder with perks and lifetime stats (flight hours, flights, deliveries, crashes, fuel burned).
- Mission Complete shows an animated XP breakdown, the rank bar filling, currency earned and newly unlocked achievements; a full-screen **Promoted** overlay celebrates rank-ups.
- Achievement toast for mid-flight unlocks (Cargo Swinger now also pays XP).
- Garage shows "🔒 <rank>" on rank-locked items.

### Achievements
- New: Fly for Hire, Left Seat, Chief Pilot, Full Manifest, Week on Duty, Century Hauler.
- Master Hauler now requires all missions (description was stuck at "20").

### Fixes
- The retried flag was reset on every reload, so a crash-then-retry still counted as a no-retry flight (No Scratch streak). Retries are now tracked correctly.

---

## v2.0.0 — Worlds Update: Organic Caves

The rectangle era is over. 32 hand-crafted organic cave levels across 4 themed worlds, on top of a trimmed 10-level tutorial — 42 missions total.

---

### Cave Terrain Engine (no external level editor)
- New `lib/game/level/cave/` pipeline: levels are const Dart data (`LevelSpec`) — tunnel splines with per-point widths, ellipse chambers, spawn/goal/cargo anchors.
- Terrain is carved from a signed distance field (smooth-min unions for organic fillets), roughened with seeded fbm noise for the "ant nest cut vertically" look, traced with marching squares, and smoothed (Chaikin + Douglas-Peucker).
- **Fully deterministic:** every level's shape is a pure function of its spec and its explicit `seed` — identical on every run and device. Nothing is randomized at spawn.
- Physics: one static body with `ChainShape.createLoop` fixtures per contour (`CaveTerrain`); rendering: even-odd filled path with themed rock palette, edge strokes, and seeded mineral speckles.
- Hot-reload authoring: builder cache clears each load in debug; `dart run tool/preview_levels.dart [id]` prints ASCII cave maps + playability issues.

### Four Themed Worlds (8 levels each)
- **Xenar Caverns** (alien; violet rock, teal accents) — pure flying: curves, chambers, squeezes, a loop, chimneys.
- **Rustshaft Mines** (mine; warm browns) — machinery: rotating bars, pendulums, sliding crushers.
- **Glacier Deep** (ice; pale blues) — wall friction ≈ 0.03 everywhere, plus icicle pendulums and ice blocks.
- **Ember Core** (lava; dark reds) — modifier gauntlet: heavy gravity, fuel scarcity, dead-weight cargo, everything combined in the 56 m finale.
- `ThemeSpec` drives backdrop color, rock palette, parallax tint/alpha (shared PNGs, modulate-blended), helipad colors, and level-select accents.

### Moving Obstacles
- `RotatingBar` (constant angular velocity), `Pendulum` and `SlidingBlock` (kinematic, velocity-tracked along analytic paths — frame-rate-proof and deterministic).
- All kill the ship on contact like terrain; cargo gets physically batted.

### Per-Level Physics Modifiers
- `LevelModifiers`: `gravityMul`, `fuelDrainMul`, `cargoDensityMul`, `wallFriction` — compose multiplicatively with daily-challenge modifiers.
- `CargoBody` gained `densityMul` (heavy-cargo levels up to 2.5×).

### Worlds Progression & Economy
- `LevelRegistry` replaces `levelPaths`: 5 worlds, star-gated (0/8/22/40/60 total stars); within a world, each completion unlocks the next level. Unlocks are computed from stars, not stored.
- Newly earned stars pay cosmetic coins scaled by world (5→20 per star), feeding the Garage.
- Level select regrouped by world: themed header chips with lock/star-gate status, per-world path colors, and modifier badge glyphs (▼ gravity, ⛽ fuel, ⚓ heavy cargo, ❄ ice) on nodes.
- Per-level star thresholds moved onto `LevelDef.stars` (fuel fractions + time limit).

### Save Format v2
- Progress keyed by stable string `saveId` (`stars2_tut_01`, `time2_alien_03`, …) instead of level index; one-time automatic migration preserves tutorial progress. Tutorial trimmed from 20 TMX levels to the 10 best.

### Playability Proven by CI
- `test/cave_level_validation_test.dart`: every cave level is validated — spawn/goal/cargo in open pockets, ship-clearance flood-fill reachability spawn→cargo→goal, cargo rest-point within attach range, obstacle sweeps clear of anchors, build determinism, and a per-level build-time budget.

---

## v1.3.0 — Gamification Update

A major update to persistence, progression, and player expression.

---

### Strict Star Logic & Fuel Tracking
- **Lifetime Stat:** `total_fuel_spent` added to `ProgressService`. Fuel used in every run (including deaths) is recorded to local storage.
- **Star Math Overhaul:** `NarrowHaulGame._calculateStars()` now uses percentage of max fuel and base time limits.
  - 1 Star: Reached the goal (any fuel).
  - 2 Stars: >40% fuel remaining.
  - 3 Stars: >70% fuel remaining **and** under the level's specific time limit.

### World Map Level Select
- Replaced the basic GridView with a custom-painted `_WorldMap` in `lib/main.dart`.
- The 20 levels are now drawn as circular nodes across a sine-wave path using a `CustomPainter` (`_MapPathPainter`).
- Fully horizontal scrolling using `SingleChildScrollView` and `Stack`.

### Daily Challenge Upgrades
- Added `saveDailyBestTime` to track the fastest daily clear.
- Completing the challenge for the first time each day rewards **50 Cosmetic Coins**.
- The main menu "Daily ✓" button now shows your local best completion time underneath it.

### "Cargo Swinger" Achievement
- Added to `AchievementIds`.
- Logic implemented in `lib/game/components/cargo_attachment.dart` using `math.atan2` to track continuous relative angle delta between the ship and cargo.
- Unlocks when the player swings the cargo 360 degrees without dropping it.

### Cosmetics System & Garage UI
- Added `lib/game/services/cosmetics_service.dart`.
- Three customization categories: Ships, Ropes, Plumes.
- **Dynamic In-Engine Rendering:** No new asset sheets were needed.
  - `ShipBody`: Uses `BlendMode.srcATop` on the base sprite to tint neon magenta, stealth black, or gold.
  - `ThrustPlume`: Uses `BlendMode.hue` or `HSVColor` swaps to render red, green, or animated rainbow engine fire.
  - `RopeLine`: Uses multiple overlapping `Canvas.drawPath` strokes with blur masks to draw segmented "chains" and glowing "energy beams".
- Added a **Garage (Skins)** menu to spend the coins earned in Daily Challenges.

---

## v1.2.0 — Sprite Integration & Parallax Background

All game-object and HUD sprites are now wired in, replacing the placeholder
Canvas-drawn primitives. A three-layer parallax background system is live.

---

### Asset Infrastructure

**`pubspec.yaml`**
- Added `- assets/` to the `flutter.assets` list so all PNG files in the root
  assets folder are bundled (previously only `assets/tiles/` was registered).

**`lib/main.dart`** + **`lib/game/narrow_haul_game.dart`**
- `Flame.images.prefix = 'assets/'` set in `main()` (global Flame cache).
- `images.prefix = 'assets/'` set in `NarrowHaulGame.onLoad()` (game-local cache).
- Both are required because `Sprite.load()` uses the global cache and
  `gameRef.images` uses the game-local cache.

---

### HUD Sprites — `lib/game/components/hud_touch_controls.dart`

| Asset | Size | How used |
|---|---|---|
| `joystick_base.png` | 256×256 px | Base ring drawn at touch-down point; **also shown at fixed resting position** when idle |
| `joystick_knob.png` | 128×128 px | Moving thumb pad; shown centred on base when idle |
| `thrust_idle.png` | 256×256 px | Full thrust button sprite when not pressed |
| `thrust_press.png` | 256×256 px | Swaps in on hold |
| `fuel_bar.png` | 320×48 px | Rendered as the outer frame; dynamic fill drawn on top with 5 px inset |

**Joystick idle state changed**: `_drawHint()` now renders `joystick_base.png` +
centred `joystick_knob.png` at a fixed bottom-left position so the control is
always visible, not just during a drag. Canvas arrows/circles are the fallback.

**Fuel bar enlarged**: bar dimensions updated to 220×26 px (was 120×8 px) to
match the sprite's proportions and be legible on device.

All sprite loads are wrapped in `try/catch`; the original Canvas drawing is kept
as a silent fallback if an asset is missing.

---

### Engine Exhaust Animation — `lib/game/components/thrust_plume.dart`

- Loads `exhaust.png` (256×128 px, 4 frames of 64×128 px each) via
  `Flame.images.load()`.
- Animates at **12 fps** (stepTime = 0.08 s), cycling through all 4 frames.
- **Y-flip applied in render**: the source sprite has the bright core at the
  bottom (flames pointing upward). A `canvas.translate / canvas.scale(1, -1)`
  transform flips the image so the core sits at the engine bell and the flame
  tips extend away from the ship.
- Falls back silently to the procedural 3-layer cone + particle-spark rendering
  if the asset is unavailable.

---

### Ship Sprite — `lib/game/components/ship_body.dart`

- Loads `ship.png` (128×128 px) in `onLoad()`.
- `renderBody = false` on successful load (hides physics triangle).
- Sprite is drawn at **3× the physics hull dimensions** (`_visualScale = 3.0`):
  - Visual rect: `±0.69 m` wide × `1.11 + 0.87 m` tall (≈ 38×55 px at zoom 28)
  - Physics hitbox unchanged at `±0.21 m` wide × `0.60 m` tall
- Falls back to the physics triangle if the asset fails to load.

---

### Cargo Sprite — `lib/game/components/cargo_body.dart`

- Loads `cargo.png` (64×64 px) in `onLoad()`.
- `renderBody = false` on successful load.
- Sprite drawn at **3× the physics radius**: `_spriteHalf = 0.60 m` (≈ 34 px
  diameter at zoom 28); physics circle stays at `radius = 0.14 m`.
- `renderCircle` override kept for the fallback path (`renderBody = true`).

---

### Landing Pad Sprite — `lib/game/components/world_dromes.dart`

- `LandingStripVisual` loads `landing.png` (256×64 px) in `onLoad()`.
- When loaded, replaces the solid dark-green `RectangleComponent` background
  with the sprite texture (stretched to the pad's world-space dimensions).
- Animated pulsing fill, chevron stripes, and corner blinking lights are still
  drawn on top of the sprite each frame.
- Falls back to the solid fill if the asset is missing.

---

### Parallax Background — `lib/game/components/parallax_background.dart` (NEW)

Three-layer scrolling background driven by the camera's world position.

| Layer | File | X speed | Y speed | Opacity |
|---|---|---|---|---|
| Far | `far.png` (1920×1080) | 4 % of cam | 2 % of cam | 50 % |
| Mid | `mid.png` (1920×1080) | 15 % of cam | 7 % of cam | 72 % |
| Near | `near.png` (1920×1080) | 38 % of cam | 18 % of cam | 92 % |

**Technical notes:**
- Component added to the game directly (`game.add()`) at `priority = −9999`,
  **not** to `camera.viewport`. This ensures it renders before the
  `CameraComponent` and therefore behind the game world and all HUD elements.
- Images are tiled in both X and Y to cover any level size.
- Each tile is drawn **+1 px** wider/taller than its slot to eliminate hairline
  seams caused by sub-pixel rounding during scroll.
- `size = game.size` is set eagerly in `onLoad()` (not waiting for
  `onGameResize`) so `PositionComponent`'s bounding-box clip doesn't suppress
  rendering on the first frame.
- Speed constants at the top of the file can be tuned without recompiling.

---

### Bug Fixes

| Issue | Fix |
|---|---|
| Background rendered over ship/cargo | Moved from `camera.viewport.add()` to `game.add()` |
| Background invisible on first frame | Set `size = game.size` in `onLoad()` before image loading |
| Visible tiling grid seams | 1 px tile overlap + `FilterQuality.low` |
| Ship/cargo barely visible | 3× visual scale (hitbox unchanged) |
| Joystick only shown while dragging | `_drawHint()` shows full joystick sprite at fixed resting position |

---

## v1.1.0 — Roadmap Implementation

All 12 planned items from the Narrow Haul roadmap have been implemented.

---

## New Dependencies

| Package | Version | Purpose |
|---|---|---|
| `shared_preferences` | ^2.5.4 | Persist stars, best times, unlocks, achievements |
| `flame_audio` | ^2.12.0 | Sound effects (graceful silent fallback when files absent) |

---

## 1. Controls — Floating Joystick + Redesigned Thrust Button

**File:** `lib/game/components/hud_touch_controls.dart` (complete rewrite)

### Left half of screen — `_FloatingJoystick`
- Joystick appears exactly where the thumb lands (not fixed position)
- Idle state: subtle dual-arrow hint + faint circle at bottom-left
- Active state: outer ring base + inner knob tracks finger within 56 px radius
- Horizontal knob offset normalized to `[-1.0, 1.0]` → `game.rotateAxis`
- Multi-touch safe: tracks `pointerId` so thrust and joystick never interfere

### Right corner — `_ThrustButton`
- 104 px diameter circle
- Animated flame icon drawn with Canvas
- Pulsing orange glow ring while held
- Uses `DragCallbacks` for reliable hold detection

### New HUD components
- **`FuelGaugeHud`** — bar at top-left: cyan → yellow → red as fuel drops; green dot when towing
- **`LevelInfoHud`** — mission number + current best star rating

---

## 2. Persistence — ProgressService

**File:** `lib/game/services/progress_service.dart` (new)

Backed by `shared_preferences`. All data survives app restarts.

| Method | What it stores |
|---|---|
| `saveStars(levelIndex, stars)` | Best star count per level (never decreases) |
| `getStars(levelIndex)` | Current best for that level |
| `getTotalStars(n)` | Sum across all n levels |
| `unlockLevel(index)` | Sequential level gate |
| `isUnlocked(index)` | Gate check |
| `saveBestTime(index, seconds)` | Fastest completion |
| `getBestTime(index)` | Read fastest |
| `getNoRetryStreak()` / `setNoRetryStreak(v)` | Consecutive no-retry completions |
| `unlockAchievement(id)` | Persists achievement IDs |
| `isDailyChallengeComplete()` | Per-day challenge flag |
| `markDailyChallengeComplete()` | Sets today's flag |

`ProgressService.init()` is awaited in `main()` before `runApp()`.

---

## 3. Star Rating System

**File:** `lib/game/narrow_haul_game.dart`

Calculated at level completion based on fuel remaining:

| Stars | Condition |
|---|---|
| 1 star | Level complete (any fuel) |
| 2 stars | Fuel remaining ≥ 40 units |
| 3 stars | Fuel remaining ≥ zone threshold |

**3-star fuel thresholds by zone:**

| Zone | Levels | Threshold |
|---|---|---|
| Tutorial | 1–3 | 70 units |
| Beginner | 4–7 | 65 units |
| Intermediate | 8–12 | 55 units |
| Advanced | 13–16 | 45 units |
| Expert | 17–20 | 38 units |

- Best score only ever improves on retry
- `game.lastLevelStars` and `game.lastLevelTimeSeconds` exposed to overlays

---

## 4. Level Select Screen

**File:** `lib/main.dart` — `_LevelSelectOverlay`

- 5-column grid of 20 mission cells
- Each cell: mission number (zone-colored), 3 star slots, best time
- Locked missions dimmed with a lock icon
- Tapping an unlocked mission calls `game.startLevel(index)`
- Accessed via **Missions** button on the main menu

**Zone color coding:**

| Zone | Levels | Color |
|---|---|---|
| Tutorial | 1–3 | Cyan |
| Beginner | 4–7 | Green |
| Intermediate | 8–12 | Yellow |
| Advanced | 13–16 | Orange |
| Expert | 17–20 | Coral/Red |

---

## 5. Twenty Levels (17 new TMX files)

**Files:** `assets/tiles/level_04.tmx` through `assets/tiles/level_20.tmx`

All use Tiled `.tmx` format (32 px = 1 meter), compatible with existing `tiled_level_loader.dart`.

| Level | Name | Map Size | Key Challenge |
|---|---|---|---|
| 04 | Hanging Wall | 56×14 | Vertical wall from ceiling, gap at bottom; navigate under then fly up |
| 05 | Rising Wall | 56×14 | Vertical wall from floor, gap at top; arc over it, land low right |
| 06 | Double Turn | 56×14 | Two alternating walls — first S-path |
| 07 | The Gate | 56×14 | 3 m horizontal gate opening |
| 08 | Low Ceiling | 56×14 | Long slab from above; navigate under it, exit right, then fly up |
| 09 | The Chimney | 40×20 | Taller map; two horizontal shelves force a zigzag ascent |
| 10 | Zigzag | 56×14 | Three alternating pillars — top → bottom → top path |
| 11 | The Corridor | 56×14 | 4 m tall horizontal channel spanning most of the map |
| 12 | W-Path | 56×14 | Three pillars, start top, goal bottom — W-shape route |
| 13 | Double Gate | 56×14 | Two 3 m gates in series |
| 14 | Cave System | 56×14 | Four alternating ceiling/floor protrusions — wave navigation |
| 15 | Bottleneck | 56×14 | 2.75 m opening after long open approach |
| 16 | Triple Gate | 56×14 | Three 3 m gates in quick succession |
| 17 | The Marathon | 64×14 | Wider map: gate + low ceiling + pillars + final gate |
| 18 | Slalom | 56×14 | Five rapid alternating pillars — high-speed weaving |
| 19 | The Squeeze | 56×14 | 3 m corridor spanning most of the map |
| 20 | Final Haul | 72×14 | Widest map: gate + slab + pillars + tight gate + narrow finale + tiny goal |

### Adding More Levels

1. Open [Tiled Map Editor](https://www.mapeditor.org) (free, v1.12+)
2. New map → Orthogonal, **32×32 px tiles**
3. Object layer `walls` — rectangles become terrain
4. Object layer `markers` — objects named `ship`, `goal`, `cargo_zone`
5. Save `.tmx` to `assets/tiles/`
6. Add path to `levelPaths` array in `lib/game/narrow_haul_game.dart`

### AI Level Design Prompt

Paste this into Gemini, ChatGPT, or Claude to generate level layouts:

```
I am designing levels for a 2D physics spacecraft game called Narrow Haul.
The player flies a rocket through cave terrain, attaches a cargo pod via a
tow rope, and must land both on a landing pad simultaneously.

Level format: rectangle grid, 32 px = 1 meter in physics.
Please describe level [NUMBER], difficulty [BEGINNER/INTERMEDIATE/ADVANCED/EXPERT].

For each level provide:
1. Map size in tiles (e.g. 56 wide × 14 tall)
2. Ship spawn position (pixels, top-left = 0,0)
3. Cargo zone position and size (pixels)
4. Landing pad position and size (pixels)
5. Each wall as: x, y, width, height in pixels
6. What makes it challenging and what skill it teaches

Physics reference:
- Rope slack: 6 m beyond initial ship-to-cargo distance
- Ship rotation: 90°/sec  |  Gravity: ~1.4 m/s²
- Fuel: 100 units, drains 12 units/sec while thrusting
- Comfortable passage: 3–4 m  |  Tight passage: 2.5–3 m
- Ship triangle height: ~0.6 m  |  Cargo diameter: ~0.28 m
```

---

## 6. Audio Framework

**File:** `lib/game/services/audio_service.dart` (new)

Wraps `flame_audio` with silent fallback — the game runs fine with no audio files present.

| Sound | Trigger | File |
|---|---|---|
| Engine loop | Thrust button held | `assets/audio/thrust_loop.mp3` |
| Rope attach | Cargo tow connects | `assets/audio/attach.mp3` |
| Crash | Ship hits wall | `assets/audio/crash.mp3` |
| Landing chime | Both on pad | `assets/audio/land.mp3` |
| Star jingle | 2+ stars earned | `assets/audio/star.mp3` |

### To Enable Audio

1. Create the `assets/audio/` directory
2. Add the five MP3/OGG files listed above
3. Register in `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/tiles/
       - assets/audio/
   ```

### Audio Asset Prompt for Designers

```
Create a 5-piece sound effect pack for a 2D space cargo game:

1. thrust_loop.mp3 — looping rocket engine, 1–2 sec seamless loop,
   low rumble + high-pitched exhaust whine, sci-fi tone

2. attach.mp3 — rope/tether snap, 0.3 sec,
   metallic click + brief magnetic hum, satisfying

3. crash.mp3 — hull impact, 0.5 sec,
   crunching metal + thud, short reverb tail

4. land.mp3 — successful landing chime, 0.8 sec,
   ascending synth arpeggio, gentle and rewarding

5. star.mp3 — star earned jingle, 0.5 sec,
   bright ascending notes, celebratory but not annoying
```

---

## 7. Daily Challenge

**File:** `lib/game/services/daily_challenge.dart` (new)

- Deterministic from today's date — same challenge for all players on the same day
- Picks a random level index + one of five physics modifiers:

| Modifier | Effect |
|---|---|
| Standard Run | Normal physics |
| Low Gravity | 0.5× gravity — floatier, harder to land precisely |
| Heavy Haul | 1.8× gravity — sinks fast, requires constant thrust |
| Fuel Crisis | 2× fuel drain rate |
| Fuel Rich | 0.5× fuel drain rate |

- Gravity applied live via `world.gravity = Vector2(0, kGravityY * multiplier)`
- Fuel drain via `ShipBody.fuelDrainMultiplier` parameter
- Main menu shows **Daily Challenge** button; grayed out with ✓ badge once complete
- Completion recorded per calendar day in `ProgressService`

---

## 8. Achievements

**Files:** `lib/game/services/achievement_service.dart` (new), `lib/main.dart` (`_AchievementsOverlay`)

| ID | Title | Condition |
|---|---|---|
| `first_haul` | First Haul | Complete any mission |
| `fuel_miser` | Fuel Miser | Complete with > 90 fuel remaining |
| `speed_hauler` | Speed Hauler | Complete any level in under 30 seconds |
| `no_scratch` | No Scratch | Complete 5 levels in a row without retrying |
| `perfect_pilot` | Perfect Pilot | Earn 3 stars on every level |
| `level_10` | Deep Space | Reach Mission 10 |
| `level_20` | Master Hauler | Complete all 20 missions |
| `daily_pilot` | Daily Pilot | Complete a daily challenge |

Achievements are checked automatically after every level completion in `_checkAchievements()`.
Accessible from main menu → **Achievements**.

---

## 9. Monetization Framework

**File:** `lib/game/services/monetization_service.dart` (new)

Fully structured stubs ready to swap in real SDK calls when native configuration is done.

### Revenue Streams

| Stream | Placement | Player Action |
|---|---|---|
| Rewarded ad | `fuel_refill` | Watch ad → refill 50% fuel |
| Rewarded ad | `cargo_attach` | Watch ad → retry with cargo pre-attached |
| Interstitial | Auto | Every 3rd level end (skipped if ads removed) |
| IAP | `nh_remove_ads` | $2.99 one-time removes all interstitials |
| IAP | `nh_skin_pack_1` | $1.99 Nebula skin pack |
| IAP | `nh_cosmetic_bundle` | $4.99 full cosmetics |
| IAP | `nh_supporter_pack` | $7.99 all cosmetics + remove ads |
| IAP | `nh_level_pack_deep_space` | $2.99 unlocks missions 11–20 |

In debug mode, rewarded ads immediately grant the reward without an SDK.

### Cosmetic System (stars or IAP)

| Skin | Color | Unlock |
|---|---|---|
| Standard | Cyan `#00B4D8` | Free (default) |
| Gold Rush | `#FFD166` | 30 total stars |
| Crimson | `#E07A5F` | 45 total stars |
| Emerald | `#4ADE80` | 60 total stars |
| Nebula | `#9B5DE5` | IAP `nh_skin_pack_1` |

Rope styles: Cable (free) · Energy Beam (20 stars) · Chain (40 stars)

### To Enable Native Ads (google_mobile_ads)

1. `flutter pub add google_mobile_ads`
2. Android — add to `AndroidManifest.xml`:
   ```xml
   <meta-data
     android:name="com.google.android.gms.ads.APPLICATION_ID"
     android:value="ca-app-pub-XXXXXX~XXXXXX"/>
   ```
3. iOS — add to `Info.plist`:
   ```xml
   <key>GADApplicationIdentifier</key>
   <string>ca-app-pub-XXXXXX~XXXXXX</string>
   ```
4. Replace stub methods in `MonetizationService` with real `AdManager` calls

### To Enable IAP (in_app_purchase)

1. `flutter pub add in_app_purchase`
2. Configure product IDs in App Store Connect and Google Play Console
3. Replace stub `purchase()` with `InAppPurchase.instance.buyNonConsumable()`

---

## 10. Visual Improvements (Vector Rendering)

No external art files required — all improvements are code-only.

### ThrustPlume (`lib/game/components/thrust_plume.dart`)
- Animated 3-layer flame cone: outer (orange-red) → mid (amber) → core (white-yellow)
- Flicker via `sin(_time * 28)` modulation each frame
- 5 random particle sparks per frame with natural fade-out
- Outer glow bloom behind the nozzle

### WallBox (`lib/game/components/wall_box.dart`)
- Seeded `Random` per tile generates 4 unique crack/detail lines
- Top-left highlight edge + bottom-right shadow edge for depth

### LandingStripVisual (`lib/game/components/world_dromes.dart`)
- Pulsing green fill overlay
- Animated chevron stripe pattern
- Four blinking corner lights at 4 Hz

### HelipadVisual (`lib/game/components/world_dromes.dart`)
- Bold H marking
- Four corner marker dots

---

## 11. Updated Main Menu & Overlays

### Main Menu
| Button | Action |
|---|---|
| PLAY | Start from Mission 1 |
| Missions | Open level select grid |
| Daily Challenge | Start today's challenge (shows ✓ when done) |
| Achievements | Open achievements list |

Header displays total stars (e.g. `★ 34 / 60 stars`).

### Level Complete Overlay
Shows earned stars (animated), completion time, and mission number.
"Next Mission" advances. "Done" returns from daily challenge.

### Game Over Overlay
Orange-tinted "Hull Breach" card. Retry or return to menu.

---

## Art Asset Prompts

Use these prompts with Gemini Imagen, Midjourney, or a designer.

### Ship Sprite — 128×128 px PNG, transparent background
```
Top-down 2D spacecraft, triangular rocket body pointing upward, glowing cyan
exhaust nozzle at the rear, minimalist flat vector style, dark space aesthetic,
transparent background, 128×128px.
Colors: cyan #00B4D8 hull, dark gray #1B263B panels, orange #FFAA00 engine glow.
```

### Cargo Pod — 64×64 px PNG, transparent background
```
2D cargo pod sphere for a space game, orange-red metallic surface, riveted
panels, subtle glow outline, transparent background, 64×64px.
Flat vector style. Colors: #E07A5F main body, #5C3D2E trim.
```

### Thrust Plume Sprite Sheet — 4 frames, 32×64 px each (128×64 px total)
```
Rocket engine exhaust flame sprite sheet, 4 animation frames in a row,
animated fire plume, orange-to-white gradient core, transparent background,
32×64px per frame (128×64px total). Cartoon / flat vector style.
```

### Cave Wall Tile Set — 32×32 px tiles, transparent background
```
2D platformer cave wall tile set, multiple 32×32px tiles on one sheet,
dark rocky asteroid surface, jagged edges, blue-grey tint (#1B263B base),
subtle rock crack lines, tileable on all four sides.
Flat vector with light hand-drawn detail. Transparent background.
```

### Landing Pad — 128×32 px, transparent background
```
2D top-down landing pad for a space game, rectangular platform,
green (#2ECC71) chevron landing markers, blinking edge lights,
flat vector style, 128×32px, transparent background.
```

### Parallax Background — 3 separate 1920×1080 px images
```
Deep space parallax background, 3 separate PNG images:

Layer 1 (far): dense star field dots on very dark blue-black (#050816) only.

Layer 2 (mid): faint nebula wisps, dark purple and teal tones,
max 20% opacity, atmospheric.

Layer 3 (near): large blurred asteroid silhouettes, very dark grey,
parallax foreground only.
```

### HUD / UI Kit — transparent PNGs
```
Sci-fi mobile game HUD kit, all elements transparent background,
flat vector style:
- Joystick base circle: dark semi-transparent fill, cyan #00B4D8 rim, 128×128px
- Joystick knob circle: solid cyan fill, white inner highlight, 64×64px
- Thrust button circle: dark fill, orange flame icon, cyan rim, 120×120px
- Fuel gauge bar: 200×24px, cyan fill on dark background, rounded ends
```

---

## File Structure (Updated)

```
lib/
├── main.dart                              # App entry, all Flutter overlays, UI
├── game/
│   ├── narrow_haul_game.dart              # Main game class, 20 level paths, star logic
│   ├── physics_constants.dart             # Physics config, collision filters
│   ├── tags.dart                          # Collision tag markers
│   ├── components/
│   │   ├── ship_body.dart                 # Ship physics (+ fuelDrainMultiplier)
│   │   ├── cargo_body.dart                # Cargo physics
│   │   ├── cargo_attachment.dart          # Rope attach logic (+ onAttached callback)
│   │   ├── rope_physics_coupling.dart     # Forge2D joints
│   │   ├── rope_line.dart                 # Rope visual (Bézier catenary)
│   │   ├── dual_landing_zone.dart         # Win condition sensors
│   │   ├── wall_box.dart                  # Terrain walls (rock texture rendering)
│   │   ├── world_dromes.dart              # Helipad + landing strip (animated)
│   │   ├── thrust_plume.dart              # Engine flame (animated 3-layer cone)
│   │   └── hud_touch_controls.dart        # Floating joystick, fuel gauge, level info
│   ├── level/
│   │   ├── level_data.dart                # Level data structure
│   │   └── tiled_level_loader.dart        # TMX parser
│   └── services/
│       ├── progress_service.dart          # shared_preferences persistence layer
│       ├── achievement_service.dart       # Achievement definitions + unlock logic
│       ├── audio_service.dart             # flame_audio wrapper (silent fallback)
│       ├── daily_challenge.dart           # Daily challenge config generator
│       └── monetization_service.dart      # Ads/IAP stubs (ready for SDK swap-in)

assets/
├── tiles/
│   ├── level_01.tmx – level_20.tmx        # 20 Tiled level maps
└── audio/                                  # Create this folder when adding sounds
    ├── thrust_loop.mp3
    ├── attach.mp3
    ├── crash.mp3
    ├── land.mp3
    └── star.mp3
```

---

## Next Steps

### Immediate — no native platform setup required
- Drop audio files into `assets/audio/` → sound activates automatically
- ~~Generate ship/cargo/HUD sprites~~ ✅ **Done in v1.2.0**
- ~~Add parallax background~~ ✅ **Done in v1.2.0**
- Fix `exhaust.png` black background → re-export with transparent PNG alpha channel
- Tune `_visualScale` in `ship_body.dart` / `cargo_body.dart` if sizes need adjustment
- Tune parallax speed constants in `parallax_background.dart` for feel

### Short-term — requires native platform configuration
- Configure `google_mobile_ads` with app IDs from AdMob (Android + iOS)
- Configure `in_app_purchase` product IDs in App Store Connect and Google Play
- Replace stubs in `MonetizationService` with real SDK calls

### Medium-term
- Online leaderboard for daily challenges (Firebase or Supabase)
- Game Center / Play Games Services for cloud achievements
- Push notifications for daily challenge reminders
- App icon and launch screen with game branding
