# Narrow Haul — Development Plan & Current State

> Living reference document. Update after each work session.
> Last updated: March 2026 (v1.2.0)

---

## Project at a Glance

| Item | Value |
|---|---|
| Engine | Flame v1.36.0 + Forge2D v0.19.2 |
| Language | Dart / Flutter |
| Orientation | Landscape only |
| Levels | 20 (levels 01–20 in `assets/tiles/`) |
| Zoom | 28 px/meter (`_baseZoom = 28`) |
| Physics | `pixelsPerMeter = 32`, gravity `kGravityY = 1.375` |
| Asset prefix | `Flame.images.prefix = 'assets/'` (set in `main()`) |

---

## Asset Status

### ✅ Wired and Active

| File | Size | Where used | Notes |
|---|---|---|---|
| `ship.png` | 128×128 | `ship_body.dart` | Drawn at 3× physics size (~39×55 px on screen) |
| `cargo.png` | 64×64 | `cargo_body.dart` | Drawn at 3× physics radius (~34 px diameter) |
| `exhaust.png` | 256×128 (4 frames) | `thrust_plume.dart` | 12 fps animation, Y-flipped in code |
| `joystick_base.png` | 256×256 | `hud_touch_controls.dart` | Always visible at resting position |
| `joystick_knob.png` | 128×128 | `hud_touch_controls.dart` | Centred on base at rest; tracks finger while dragging |
| `thrust_idle.png` | 256×256 | `hud_touch_controls.dart` | Shown when button not pressed |
| `thrust_press.png` | 256×256 | `hud_touch_controls.dart` | Shown while held |
| `fuel_bar.png` | 320×48 | `hud_touch_controls.dart` | Frame sprite; dynamic fill drawn on top |
| `landing.png` | 256×64 | `world_dromes.dart` | Background of `LandingStripVisual`; animated overlays on top |
| `far.png` | 1920×1080 | `parallax_background.dart` | Layer 0 — 4%/2% camera speed |
| `mid.png` | 1920×1080 | `parallax_background.dart` | Layer 1 — 15%/7% camera speed |
| `near.png` | 1920×1080 | `parallax_background.dart` | Layer 2 — 38%/18% camera speed |
| `tiles.png` | 512×512 | Tiled map loader | Cave wall tile set |

### ⚠️ Wired but needs re-export

| File | Issue | Fix |
|---|---|---|
| `exhaust.png` | Possibly black background (not transparent) | Re-export as PNG with alpha channel |

### ❌ Not yet created

| File | Size | Purpose | Prompt hint |
|---|---|---|---|
| `thrust_plume_fixed.png` | 256×128 (4 fr) | Flame pointing downward (no code flip needed) | See exhaust prompt, add "flame tips point DOWN" |
| `fuel_bar_frame.png` | 320×48 | Just the border frame, transparent interior | Already partially covered by `fuel_bar.png` |
| App icon | 1024×1024 | iOS / Android launcher | Rocket carrying cargo, dark cave background |
| Launch screen | 1242×2688 | iOS splash | Same branding |

---

## Code Architecture

```
lib/
├── main.dart                          # App entry, sets Flame.images.prefix,
│                                      # initialises ProgressService, wires overlays
├── game/
│   ├── narrow_haul_game.dart          # Master controller (RunState, level lifecycle,
│   │                                  # star calc, achievement checks, daily challenge)
│   ├── physics_constants.dart         # pixelsPerMeter, gravity, collision filters
│   ├── tags.dart                      # ShipTag, CargoTag, WallTag, HookTag
│   ├── components/
│   │   ├── ship_body.dart             # BodyComponent + ship.png sprite (3× scale)
│   │   ├── cargo_body.dart            # BodyComponent + cargo.png sprite (3× scale)
│   │   ├── cargo_attachment.dart      # Rope reveal FSM → RopePhysicsCoupling
│   │   ├── rope_line.dart             # Bézier rope visual (code-drawn, no sprite needed)
│   │   ├── rope_physics_coupling.dart # Forge2D RopeJoint tether
│   │   ├── rope_segment_body.dart     # Physics rope segments (if multi-segment used)
│   │   ├── thrust_plume.dart          # exhaust.png 4-frame anim; canvas fallback
│   │   ├── wall_box.dart              # Physics + visual cave walls
│   │   ├── world_dromes.dart          # HelipadVisual + LandingStripVisual (landing.png)
│   │   ├── dual_landing_zone.dart     # Goal trigger sensor
│   │   ├── hud_touch_controls.dart    # Floating joystick + thrust button + fuel/level HUD
│   │   └── parallax_background.dart  # 3-layer far/mid/near scroll (game-level priority −9999)
│   ├── level/
│   │   ├── level_data.dart            # LevelData struct (walls, spawns, rope length)
│   │   └── tiled_level_loader.dart    # TMX → LevelData via rootBundle
│   └── services/
│       ├── progress_service.dart      # shared_preferences: stars, times, unlocks
│       ├── achievement_service.dart   # AchievementIds + metadata + unlock()
│       ├── audio_service.dart         # flame_audio wrapper (silent fallback)
│       ├── daily_challenge.dart       # Deterministic daily config (gravity/fuel mods)
│       └── monetization_service.dart  # Rewarded ads / IAP stubs (ready for SDK)

assets/
├── *.png                              # All sprites at assets/ root
├── tiles/
│   ├── level_01.tmx … level_20.tmx   # 20 Tiled level maps
└── audio/                             # Create when adding sound files
    ├── thrust_loop.mp3
    ├── attach.mp3
    ├── crash.mp3
    ├── land.mp3
    └── star.mp3
```

---

## Key Constants (tuning guide)

| Constant | File | Current | Effect |
|---|---|---|---|
| `_baseZoom` | `narrow_haul_game.dart` | 28 | px per world meter; larger = more zoomed in |
| `pixelsPerMeter` | `physics_constants.dart` | 32 | Tiled tile scale |
| `kGravityY` | `physics_constants.dart` | 1.375 | World gravity (m/s²) |
| `thrustForce` | `ship_body.dart` | 5.1 N | Engine power |
| `fuelDrainPerSecond` | `ship_body.dart` | 12 | Fuel units/s while thrusting |
| `secondsPerFullRotation` | `ship_body.dart` | 4.0 s | Turn speed |
| `_visualScale` (ship) | `ship_body.dart` | 3.0 | Visual vs physics size ratio |
| `_spriteHalf` (cargo) | `cargo_body.dart` | 0.60 m | Visual radius (physics = 0.14 m) |
| Parallax X speeds | `parallax_background.dart` | 0.04 / 0.15 / 0.38 | Per-layer scroll fraction |
| Parallax Y speeds | `parallax_background.dart` | 0.02 / 0.07 / 0.18 | Per-layer vertical scroll |
| Parallax alphas | `parallax_background.dart` | 0.50 / 0.72 / 0.92 | Per-layer opacity |

---

## Overlay / Screen Map

| Overlay key | Class | Trigger |
|---|---|---|
| `'menu'` | `_MenuOverlay` | Game start; after game over / win |
| `'levelSelect'` | `_LevelSelectOverlay` | "Play" button on menu |
| `'gameOver'` | `_EndOverlay` | Ship hits wall (RunState.gameOver) |
| `'levelComplete'` | `_LevelCompleteOverlay` | Cargo + ship on pad (RunState.won) |
| `'achievements'` | `_AchievementsOverlay` | "Achievements" button on menu |

---

## Gamification State

### Stars per level
| Stars | Condition |
|---|---|
| ⭐ | Reached goal at all |
| ⭐⭐ | Reached goal with > 25% fuel remaining |
| ⭐⭐⭐ | Reached goal with > 60% fuel remaining (threshold varies per level) |

### Achievements
| ID | Trigger |
|---|---|
| `first_haul` | Complete level 1 |
| `fuel_miser` | Finish any level with > 80% fuel |
| `speed_hauler` | Finish any level in < 30 s |
| `no_scratch` | First no-retry completion |
| `perfect_pilot` | 3-star any level |
| `level_10` | Reach level 10 |
| `level_20` | Reach level 20 |
| `daily_pilot` | Complete a daily challenge |

### Daily Challenge
Deterministic config generated from today's date. Modifiers: gravity multiplier
(0.5×–1.8×) and fuel drain multiplier (0.5×–2×). `DailyChallengeConfig.forToday(totalLevels)`.

---

## Audio Files Needed

Drop these into `assets/audio/` — `AudioService` loads them automatically
with a silent fallback if missing.

| File | Description |
|---|---|
| `thrust_loop.mp3` | Engine hum, loops while thrusting |
| `attach.mp3` | Short click/clunk when rope attaches to cargo |
| `crash.mp3` | Impact sound on wall hit |
| `land.mp3` | Landing chime on goal reached |
| `star.mp3` | Star earn sound (2- or 3-star completions) |

---

## AI Asset Prompts

### Joystick knob
```
Game UI joystick knob (thumb pad), isolated element, transparent background PNG.
Dark charcoal/gunmetal circular disc, slightly convex/domed surface with subtle
radial panel lines. Cyan (#00B4D8) inner ring highlight around the edge.
Small crosshair (+) engraved in the center, filled with dim cyan glow.
Soft drop shadow below. Same sci-fi / HUD aesthetic as the joystick base ring.
Size: 128 × 128 px. No text, no labels. Cartoon flat-vector style.
```

### Thrust button (idle)
```
Game UI thrust/fire button, isolated element, transparent background PNG.
Circular button, dark gunmetal base. Outer ring in cyan (#00B4D8) with
a subtle metallic bevel. Center: white flame icon (solid silhouette).
Below the flame: "THRUST" text in a bold sci-fi stencil font, cyan color.
Flat vector / cartoon style. Size: 256 × 256 px.
```

### Thrust button (pressed)
```
Same as idle thrust button but activated:
- Outer ring bright cyan with strong outer glow bloom
- Background slightly lighter (dark teal)
- Flame icon bright white with warm orange (#FF6B35) inner core dot
- "THRUST" text bright white
- Radial pulse highlight ring just inside the outer edge
Size: 256 × 256 px. Transparent background.
```

### Exhaust flame sprite sheet (corrected orientation)
```
Rocket engine exhaust flame sprite sheet, 4 frames, animated fire plume,
orange-to-white gradient core, transparent background.
Flame tips point DOWNWARD — bright white core at TOP, flame tapers toward bottom.
Cartoon / flat vector style.
Export: single PNG, 4 frames horizontal. Total size: 256 × 128 px (each frame 64 × 128 px).
```

### Fuel bar frame
```
Game UI horizontal fuel gauge bar frame, isolated element, transparent background PNG.
Dark semi-transparent pill/rectangle with rounded corners (radius ~8px).
Outer border: cyan (#00B4D8) metallic rim, 3px thick, slight inner bevel.
Interior: EMPTY/TRANSPARENT so game can draw fill color dynamically.
Small tick marks at 25%, 50%, 75% along the top edge.
Size: 320 × 48 px total (inner fill area ~280 × 24 px centered).
Flat vector / cartoon style. No fill color — just the frame.
```

---

## Remaining Work

### Must-do before release
- [ ] Re-export `exhaust.png` with **transparent background** (currently may be black)
- [ ] Add audio files to `assets/audio/`
- [ ] App icon (1024×1024) and iOS launch screen
- [ ] Test all 20 levels for playability

### Polish
- [ ] Tune `_visualScale` constants if ship/cargo look too big or small at target device sizes
- [ ] Tune parallax speed/opacity constants for feel
- [ ] Add a `fuel_bar_frame.png` with transparent interior (currently the frame has fill baked in)
- [ ] Helipad sprite (`helipad.png`) to replace canvas-drawn 'H' marker

### Platform (requires native config)
- [ ] Configure `google_mobile_ads` with AdMob app IDs (Android + iOS plist/manifest)
- [ ] Configure `in_app_purchase` SKUs in App Store Connect and Google Play Console
- [ ] Replace stubs in `lib/game/services/monetization_service.dart`

### Future features
- [ ] Online leaderboard for daily challenge (Firebase / Supabase)
- [ ] Game Center (iOS) / Play Games (Android) for cloud achievements
- [ ] Push notifications for daily challenge reminder
- [ ] Level editor integration or in-app level browser
