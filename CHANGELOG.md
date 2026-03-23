# Narrow Haul — Changelog

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
- Generate ship/cargo/HUD sprites using the prompts above, then load with `Sprite.load()`
- Add parallax star background using Flame's `ParallaxComponent`

### Short-term — requires native platform configuration
- Configure `google_mobile_ads` with app IDs from AdMob (Android + iOS)
- Configure `in_app_purchase` product IDs in App Store Connect and Google Play
- Replace stubs in `MonetizationService` with real SDK calls

### Medium-term
- Tile-based terrain rendering (swap rectangles for textured tiles via `FlameForge2D`)
- Online leaderboard for daily challenges (Firebase or Supabase)
- Game Center / Play Games Services for cloud achievements
- Push notifications for daily challenge reminders
