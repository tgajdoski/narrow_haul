# Narrow Haul - Game Logic Reference

## Overview
**Narrow Haul** is a 2D physics-based spacecraft cargo transport game built with Flutter, Flame, and Forge2D (Box2D). The player controls a rocket that must pick up cargo using a rope/tow system and land both the ship and cargo on a landing pad.

**Tech Stack:**
- Flutter + Dart
- Flame Game Engine v1.36.0
- Forge2D (Box2D) v0.14.2+1 for physics
- Flame Forge2D v0.19.2+5 (Flame + Forge2D integration)
- Flame Tiled v3.1.0 for level loading
- Tiled v0.11.1 for TMX map format

**Core Game Loop:** Navigate terrain → Approach cargo → Auto-attach rope → Tow cargo to landing zone → Win when both ship and cargo are on the pad

---

## 1. Core Game Architecture

### 1.1 Main Game Class: `NarrowHaulGame`
**File:** `lib/game/narrow_haul_game.dart`

Extends `Forge2DGame` (Flame + Forge2D integration).

**Key Responsibilities:**
- Game state management (menu, playing, gameOver, won)
- Level loading and progression
- Player input handling (rotate, thrust)
- Camera control and bounds
- Entity lifecycle management

**Game States (RunState enum):**
```dart
enum RunState { menu, playing, gameOver, won }
```

**Core Properties:**
- `runState`: Current game state
- `levelIndex`: Current level (0-based)
- `ship`: Reference to ShipBody component
- `cargo`: Reference to CargoBody component
- `cargoAttachment`: Reference to CargoAttachment (rope system)
- `rotateAxis`: -1.0 to 1.0 (left/right rotation input)
- `thrustHeld`: boolean (thrust button state)

**Level Management:**
- 3 levels defined in `levelPaths` array
- Levels stored as Tiled `.tmx` files in `assets/tiles/`
- Level progression: level_01 → level_02 → level_03 → wraps back to level_01

**Camera System:**
- Base zoom: 28x
- Follows ship position with smooth interpolation (18% lerp per frame)
- Camera bounds clamped to world size
- Auto-zooms to contain entire world if world is smaller than viewport
- Prevents "world bleed" (showing outside game area)

---

## 2. Physics System

### 2.1 Physics Constants
**File:** `lib/game/physics_constants.dart`

**Unit System:**
- 1 Forge2D world unit = 1 meter
- Tiled maps: 32 pixels = 1 meter (`pixelsPerMeter = 32`)

**Gravity:**
- Base gravity: `1.375 m/s²` downward (Y-axis)
- Debug mode: `0.7x` multiplier (30% reduction) for easier testing
- Can be toggled via `kDebugReduceGravity` flag

**Collision Layers (Bitmask System):**
```
categoryWall      = 0x0001  (walls/terrain)
categoryShip      = 0x0002  (player ship)
categoryCargo     = 0x0004  (cargo object)
categoryGoalCargo = 0x0008  (cargo landing sensor)
categoryGoalShip  = 0x0010  (ship landing sensor)
categoryHook      = 0x0020  (ship's nose hook sensor)
categoryRope      = 0x0040  (rope segments - unused in current implementation)
```

**Collision Matrix:**
- **Wall:** Collides with ship, cargo, rope segments
- **Ship:** Collides with walls, cargo (for hook), ship goal sensor
- **Cargo:** Collides with walls, ship (via hook), cargo goal sensor, hook sensor
- **Hook:** Collides with cargo only (sensor for attachment)
- **Rope segments:** Collides with walls only (physics joints handle ship-cargo connection)
- **Goal sensors:** Inanimate triggers, detect ship/cargo overlap

---

### 2.2 Ship Physics
**File:** `lib/game/components/ship_body.dart`

**Visual Design:**
- Triangle shape (rocket-like)
- Nose points up (local -Y direction)
- Engine at bottom (local +Y at `rearLocalY = 0.26`)
- Color: Cyan (`0xFF00B4D8`)

**Physical Properties:**
```dart
Shape: Polygon (triangle)
  Vertices: [(0, -0.34), (-0.21, 0.26), (0.21, 0.26)]
Density: 1.15
Friction: 0.2
Restitution: 0.05 (low bounciness)
Linear damping: 0.22 (air resistance)
Angular damping: 0 (rotation controlled directly)
```

**Nose Hook Sensor:**
- Position: `(0, -0.24)` in local space (at nose)
- Radius: `0.14 m`
- Sensor fixture (no collision, only overlap detection)
- Used to detect cargo proximity for rope attachment

**Rotation Control:**
- **Input:** Normalized axis -1.0 (CCW) to +1.0 (CW)
- **Speed:** 360° in `4.0 seconds` at full input = `π/2 rad/s` (90°/sec)
- **Implementation:** Direct angular velocity setting (not torque-based)
- **Deadzone:** `0.01` (ignores tiny inputs)
- **Release behavior:** When input released, angular velocity decays by `22 rad/s²` per second (stops quickly)

**Thrust Control:**
- **Force:** `5.1 N` (Newtons) applied along local -Y (nose direction)
- **Fuel system:**
  - Max fuel: `100 units`
  - Drain rate: `12 units/second` while thrusting
  - No fuel = no thrust (hard cutoff)
- **Implementation:** `applyForce()` at ship center of mass

**Collision Behavior:**
- Ship touching any wall → Instant game over
- Handled via `ContactCallbacks.beginContact()` detecting `WallTag`

---

### 2.3 Cargo Physics
**File:** `lib/game/components/cargo_body.dart`

**Visual Design:**
- Circle/sphere shape
- Radius: `0.14 m`
- Color: Orange-red (`0xFFE07A5F`) with brown outline

**Physical Properties:**
```dart
Shape: Circle (radius 0.14)
Density: 2.0 (heavier than ship)
Friction: 0.45 (slides less than ship)
Restitution: 0.08 (low bounce)
Linear damping: 0.05
Angular damping: 0.6
```

**Notes:**
- Heavier density makes towing more challenging
- Higher friction prevents excessive sliding on landing
- Simpler collision shape for stable rope physics

---

## 3. Rope/Tow System

### 3.1 Cargo Attachment Logic
**File:** `lib/game/components/cargo_attachment.dart`

**Three-Phase Attachment System:**

#### Phase 1: Approach Detection
- Monitors distance between ship center and cargo center
- **Activation range:** `2.5 meters` (`approachDistanceMeters`)
- Within range → Rope visual begins fading in
- Outside range → Rope visual fades out

#### Phase 2: Rope Reveal Animation
- **Duration:** `1.15 seconds` (`ropeRevealDuration`) to fully appear
- **Progress:** 0.0 (invisible) to 1.0 (fully visible)
- Fades in when approaching, fades out at `55%` speed when leaving
- **Minimum reveal to attach:** `0.05` (5% visible) - prevents instant attachment

#### Phase 3: Auto-Attachment
**Two attachment conditions (either triggers attachment):**

1. **Hook proximity:**
   - Hook world position calculated from ship's nose sensor
   - Distance from hook to cargo center ≤ `hookRadius + cargoRadius + 0.35m`
   - Catch radius: `0.14 + 0.14 + 0.35 = 0.63 meters`

2. **Center proximity (gameplay-friendly fallback):**
   - Ship center to cargo center ≤ `1.2 meters`
   - Ensures attachment even if hook sensor misses

**Attachment Process:**
- Creates `RopePhysicsCoupling` component
- Adds physics joint between ship and cargo
- Sets `attached = true`
- Rope reveal progress locked to 1.0 (fully visible)

**Contact-based attachment:**
- If nose hook sensor makes contact with cargo (via Forge2D collision)
- `onHookTouchesCargo()` callback triggers immediate attachment attempt

---

### 3.2 Rope Physics Implementation
**File:** `lib/game/components/rope_physics_coupling.dart`

**Joint Selection (distance-based):**

1. **Very short distance (< 0.04m):** No joint created (too close, unstable)

2. **Short distance (< 0.12m):** Uses `DistanceJoint`
   - Fixed-length rigid connection
   - Prevents instability with very short ropes
   - `collideConnected = false` (ship and cargo pass through each other)

3. **Normal distance (≥ 0.12m):** Uses `RopeJoint`
   - Flexible rope with maximum length constraint
   - `maxLength` = actual distance at attachment, clamped to level's `ropeMaxLength`
   - `collideConnected = false`
   - Minimum maxLength: `0.0125m` (above Forge2D's `linearSlop` of ~0.005)

**Anchor Points:**
- **Ship anchor:** Rear of ship at `(0, ShipBody.rearLocalY)` = `(0, 0.26)` in local space
- **Cargo anchor:** Cargo body's world center

**Rope Length Calculation:**
```dart
distance_at_attach = distance(shipAnchor, cargoAnchor)
maxLength = clamp(distance_at_attach, 0.0125, levelData.ropeMaxLength)
```

**Level rope max length formula:**
```dart
ropeMaxLength = initialShipToCargoDistance + 6.0 meters
```

**Joint Cleanup:**
- Joints destroyed when component removed (level restart, game over)
- Prevents memory leaks and orphaned physics constraints

---

### 3.3 Rope Visual Rendering
**File:** `lib/game/components/rope_line.dart`

**Rendering stages:**
1. **Pre-attachment:** Dashed/faded line preview
2. **Post-attachment:** Solid line showing active tow

**Line properties:**
- Draws from ship rear anchor to cargo center
- Opacity controlled by `ropeRevealProgress` (0.0 to 1.0)
- Color changes based on attachment state

---

## 4. Level System

### 4.1 Level Data Structure
**File:** `lib/game/level/level_data.dart`

```dart
class LevelData {
  List<WallRect> walls;           // Static terrain boxes
  Vector2 shipSpawn;              // Ship starting position
  Vector2 cargoSpawn;             // Cargo starting position (randomized)
  Vector2 goalCenter;             // Landing pad center
  double goalHalfWidth;           // Landing pad half-width
  double goalHalfHeight;          // Landing pad half-height
  Vector2 worldSize;              // Total world bounds (for camera)
  double ropeMaxLength;           // Max tow cable length
  Vector2 cargoZoneCenter;        // Cargo spawn region center
  Vector2 cargoZoneSize;          // Cargo spawn region size
}
```

**Wall Definition:**
- Each wall is an axis-aligned box
- Defined by center position, half-width, half-height
- Static bodies (infinite mass, no movement)

---

### 4.2 Tiled Level Loader
**File:** `lib/game/level/tiled_level_loader.dart`

**TMX Format Requirements:**

1. **Object Layer: "walls"**
   - Each rectangle object becomes a wall
   - Converted from pixels to meters using `pixelsPerMeter = 32`

2. **Object Layer: "markers"**
   - **"ship" object:** Ship spawn point (center of object)
   - **"goal" object:** Landing pad (rectangle, center + size)
   - **"cargo_zone" object:** Rectangle defining valid cargo spawn area

**Cargo Spawn Randomization:**
```dart
Random seed: levelIndex * 10007 + assetPath.hashCode
Spawn area: cargo_zone rectangle, shrunk by 0.55m margin on all sides
Position: Random point within inner area
```
- Ensures consistent randomization per level
- Different each level load (restart = new position)
- Prevents cargo spawning too close to zone edges

**World Size:**
- Calculated from Tiled map dimensions
- `width = mapWidth * tileWidth / 32`
- `height = mapHeight * tileHeight / 32`

**Rope Max Length Formula:**
```dart
distance = distance(shipSpawn, cargoSpawn)
ropeMaxLength = distance + 6.0 meters
```
- Rope always long enough to reach cargo + 6m slack
- Prevents impossible levels where rope can't reach

---

## 5. Win/Lose Conditions

### 5.1 Game Over (Loss)
**Trigger:** Ship hull touches any wall
**Implementation:** `ShipBody.beginContact()` detects `WallTag`
**Immediate effects:**
- Sets `runState = RunState.gameOver`
- Pauses game engine
- Displays "Hull breach" overlay
- Resets input state (clears thrust/rotation)

**Player options:**
- **Retry:** Restart current level (cargo respawns in new random position)
- **Menu:** Return to main menu

---

### 5.2 Level Complete (Win)
**File:** `lib/game/components/dual_landing_zone.dart`

**Dual-sensor system:**
1. **Cargo sensor:** Rectangular trigger volume at landing pad
   - Filter: Only detects `categoryCargo` objects
   - Contact: Sets `_cargoInside = true`
   
2. **Ship sensor:** Same rectangle, separate sensor
   - Filter: Only detects `categoryShip` objects
   - Contact: Sets `_shipInside = true`

**Win condition:**
```dart
if (_cargoInside && _shipInside && !_fired) {
  _fired = true;
  onBothLanded();
}
```

**Requirements:**
- Both ship and cargo must be inside pad simultaneously
- One-time trigger (`_fired` flag prevents re-triggering)
- Order doesn't matter (can land cargo first or ship first)

**Immediate effects:**
- Sets `runState = RunState.won`
- Pauses game engine
- Displays "Mission complete" overlay
- Shows level completion message

**Player options:**
- **Next level:** Progress to next level (or wrap to level 1 if on last level)
- **Menu:** Return to main menu

---

## 6. Input System

### 6.1 Touch Controls
**File:** `lib/game/components/hud_touch_controls.dart`

**Layout (Landscape orientation only):**
- **Left side:** Rotate pad (dual button/continuous axis)
- **Right side:** Thrust button (hold to thrust)

#### Rotate Pad
- **Size:** 72px height, 156px width (2 buttons + gap)
- **Type:** Continuous axis control
- **Output:** -1.0 (rotate CCW/left) to +1.0 (rotate CW/right)
- **Deadzone:** 0.08 (8% of range, prevents drift)
- **Visual:** Knob indicator shows current rotation axis
- **Behavior:**
  - Tap: Jump to rotation value
  - Drag: Follow finger position
  - Release: Return to 0 (no rotation)

#### Thrust Button
- **Size:** 100px × 72px
- **Type:** Binary on/off button
- **Label:** "THRUST"
- **Behavior:**
  - Press: `thrustHeld = true`
  - Release: `thrustHeld = false`

**Positioning:**
- Both controls: 24px from bottom edge
- Rotate pad: 20px from left edge
- Thrust button: 24px from right edge

---

### 6.2 Input Processing
**File:** `lib/game/narrow_haul_game.dart` (`update()` method)

**Per-frame input handling:**
```dart
ship.setInput(rotate: rotateAxis, thrust: thrustHeld);
```

**Ship processes inputs:**
- Rotation: Sets `angularVelocity` directly
- Thrust: Applies force if fuel > 0

**Input reset on state changes:**
- Game over → Clear all inputs
- Level complete → Clear all inputs
- Back to menu → Clear all inputs
- Prevents "sticky" inputs carrying over

---

## 7. HUD and UI

### 7.1 In-Game HUD
**Display elements:**

**Top-left text display:**
```
Without cargo attached:
"Level 2/3  Fuel 87  Approach: faded line = range hint only — get close to engage tow"

With cargo attached:
"Level 2/3  Fuel 87  TOWING — RopeJoint — land ship + cargo on green"
```

**Debug mode additions (when towing):**
- Rotation stall detection: `rot?` if angular velocity stalled for 22+ frames
- Thrust stall detection: `thrust?` if linear velocity not increasing for 40+ frames
- Helps detect physics issues during development

**Visual elements:**
- Helipad graphic at ship spawn (blue/cyan pad)
- Landing strip at goal zone (green pad)
- Cargo zone outline (orange/faded)
- Rope line connecting ship to cargo (when in range)

---

### 7.2 Menu Overlays

#### Main Menu
**Displayed when:** Game starts, or "Back to Menu" pressed
**Content:**
- Title: "Narrow Haul"
- Instructions: Controls and objective explanation
- Play button → Starts level 1

#### Game Over Overlay
**Displayed when:** Ship hits wall
**Content:**
- Title: "Hull breach"
- Subtitle: "The ship touched the terrain."
- **Retry button** → Restart current level
- **Menu button** → Return to main menu

#### Level Complete Overlay
**Displayed when:** Both ship and cargo land on pad
**Content:**
- Title: "Mission complete"
- Subtitle: "Cargo and ship on the landing pad. Level {N} cleared."
- **Next level button** (or "Replay" if last level) → Load next level
- **Menu button** → Return to main menu

---

## 8. Visual Rendering

### 8.1 Visual Hierarchy (Priorities)
```
Background:    -2000  (world backdrop solid color)
Walls:         0      (default, terrain)
Ship/Cargo:    0      (default, game objects)
Landing zones: 0      (default, goal markers)
Rope line:     1000   (in front of objects)
HUD controls:  5000   (topmost, always visible)
HUD text:      5000   (topmost)
```

### 8.2 Color Palette
```dart
Background:         0xFF050816  (very dark blue-black)
Game backdrop:      0xFF0B132B  (dark blue)
Ship:               0xFF00B4D8  (cyan/light blue)
Cargo:              0xFFE07A5F  (orange-red)
Cargo outline:      0xFF5C3D2E  (brown)
Walls:              0xFF1B263B  (dark gray-blue)
Landing pad (ship): 0xFF0A9396  (cyan-green)
Landing pad (cargo):0xFFE76F51  (orange)
Helipad:            0xFF005F73  (dark cyan)
Thrust plume:       0xFFFFAA00  (orange-yellow gradient)
HUD controls:       0x551B263B  (semi-transparent dark)
HUD borders:        0xCC00B4D8  (semi-transparent cyan)
```

### 8.3 Camera and Viewport
- **Viewport anchor:** Center (camera focuses on center of screen)
- **Zoom:** 28x base zoom, auto-adjusts to contain world if needed
- **Bounds:** Camera can't show outside world rectangle
- **Following:** Smoothly follows ship position (18% interpolation per frame)
- **Snap:** Instantly centers on ship when level loads

---

## 9. Performance and Optimization

### 9.1 Physics Settings
- **Time step:** Forge2D default (fixed timestep, typically 1/60s)
- **Velocity iterations:** Default (Forge2D uses 8)
- **Position iterations:** Default (Forge2D uses 3)
- **Sleeping:** Enabled (bodies at rest stop simulating)

### 9.2 Entity Management
- All level entities tracked in `_levelEntities` list
- Bulk removal on level clear/restart
- Prevents memory leaks from orphaned components
- Joints explicitly destroyed before bodies

### 9.3 Rendering Optimizations
- Static backdrop (one rectangle, priority -2000)
- Simple primitive shapes (no complex meshes)
- Minimal overdraw (layered transparency kept to minimum)
- HUD rendered to viewport (not world, no zoom/pan overhead)

---

## 10. Game Balance and Tuning

### 10.1 Key Constants Reference

**Ship:**
```dart
Thrust force:            5.1 N
Rotation speed:          90°/sec (π/2 rad/s)
Max fuel:                100 units
Fuel drain:              12 units/sec
Rotation release decay:  22 rad/s²
```

**Cargo:**
```dart
Radius:                  0.14 m
Density:                 2.0 (heavier than ship)
```

**Rope:**
```dart
Approach reveal range:   2.5 m
Hook catch extra radius: 0.35 m
Center attach max dist:  1.2 m
Reveal animation time:   1.15 seconds
Min reveal to attach:    5%
```

**Physics:**
```dart
Gravity:                 1.375 m/s² (debug: 0.96 m/s²)
Pixels per meter:        32 px = 1 m
```

### 10.2 Difficulty Tuning Knobs

**To make easier:**
- Increase ship thrust force
- Decrease fuel drain rate
- Increase rope catch radius
- Decrease gravity
- Increase max fuel

**To make harder:**
- Decrease ship thrust force
- Increase cargo density (heavier to tow)
- Decrease rope catch radius
- Increase gravity
- Decrease max fuel or increase fuel drain

**To adjust controls feel:**
- Rotation speed: Change `secondsPerFullRotation` (lower = faster turns)
- Rotation stop: Change `releaseSpinDecay` (higher = stops quicker)
- Ship air resistance: Change `linearDamping` (higher = slower top speed)

---

## 11. Game Flow Diagram

```
┌─────────────┐
│  App Start  │
└──────┬──────┘
       │
       v
┌─────────────┐
│  Main Menu  │◄─────────────┐
│  (Overlay)  │              │
└──────┬──────┘              │
       │                     │
       │ [Play]             │
       v                     │
┌─────────────┐              │
│ Load Level  │              │
│   (TMX)     │              │
└──────┬──────┘              │
       │                     │
       v                     │
┌─────────────┐              │
│   Playing   │              │
│  RunState   │              │
└──────┬──────┘              │
       │                     │
       ├─────[Ship hits wall]────>┌──────────┐
       │                          │Game Over │
       │                          │(Overlay) │
       │                          └────┬─────┘
       │                               │
       │                               ├─[Retry]─>Load Level
       │                               └─[Menu]───┐
       │                                          │
       └─────[Both landed on pad]─────>┌──────────┐
                                        │ Level    │
                                        │Complete  │
                                        │(Overlay) │
                                        └────┬─────┘
                                             │
                                             ├─[Next]──>Load Next Level
                                             └─[Menu]──>────────────────┘
```

---

## 12. File Structure Summary

```
lib/
├── main.dart                          # App entry, Flutter widget tree
├── game/
│   ├── narrow_haul_game.dart          # Main game class, state management
│   ├── physics_constants.dart         # Physics config, collision layers
│   ├── tags.dart                      # Collision detection tags
│   ├── components/
│   │   ├── ship_body.dart             # Player ship physics & control
│   │   ├── cargo_body.dart            # Cargo object physics
│   │   ├── cargo_attachment.dart      # Rope approach/attach logic
│   │   ├── rope_physics_coupling.dart # Forge2D joint creation
│   │   ├── rope_line.dart             # Rope visual rendering
│   │   ├── dual_landing_zone.dart     # Win condition sensors
│   │   ├── wall_box.dart              # Static terrain walls
│   │   ├── world_dromes.dart          # Helipad/landing strip visuals
│   │   ├── thrust_plume.dart          # Engine fire visual effect
│   │   ├── hud_touch_controls.dart    # On-screen input controls
│   │   └── rope_segment_body.dart     # (Unused multi-segment system)
│   └── level/
│       ├── level_data.dart            # Level data structure
│       └── tiled_level_loader.dart    # TMX parser and loader
└── test/
    └── widget_test.dart               # Flutter widget tests

assets/
└── tiles/
    ├── level_01.tmx                   # Level 1 Tiled map
    ├── level_02.tmx                   # Level 2 Tiled map
    └── level_03.tmx                   # Level 3 Tiled map
```

---

## 13. Extension Points for Development

### 13.1 New Features to Add
- **Multi-segment rope rendering:** Use `rope_segment_body.dart` for visual fidelity
- **Fuel pickups:** Extend ship to detect fuel orbs
- **Obstacles:** Moving platforms, rotating hazards
- **Wind/drift:** Environmental forces affecting ship
- **Cargo types:** Different masses, shapes, behaviors
- **Scoring system:** Time, fuel efficiency, damage
- **Level editor:** In-game or external tool for TMX creation
- **Sounds:** Engine thrust, rope attach, collision, landing

### 13.2 Game Modes
- **Time trial:** Complete level under time limit
- **Fuel limit:** Fixed fuel pool, no refills
- **Precision landing:** Smaller landing pad, bonus points
- **Multi-cargo:** Tow multiple cargo pieces
- **Cargo delivery chain:** Specific drop-off points

### 13.3 Physics Experiments
- **Elastic rope:** Replace RopeJoint with chain of DistanceJoints
- **Cable breaking:** Rope snaps under high tension
- **Thruster vectors:** Directional thrust instead of rear-only
- **Cargo momentum:** Swinging cargo affects ship stability
- **Gravity wells:** Local gravity fields (planets, asteroids)

---

## 14. Known Issues and Limitations

### 14.1 Current Limitations
- **No level persistence:** Progress not saved between sessions
- **No sound/music:** Silent gameplay
- **Fixed level count:** Only 3 levels
- **No difficulty settings:** One balance for all players
- **Landscape only:** Portrait orientation not supported
- **No accessibility features:** Touch-only input

### 14.2 Potential Physics Issues
- **Rope stalling:** Towing heavy cargo can cause rotation/thrust to feel unresponsive
  - Detection: Debug HUD shows `rot?` and `thrust?` indicators
  - Mitigation: Reduce cargo density or increase ship thrust
- **Joint instability:** Very short ropes (< 0.12m) use DistanceJoint to prevent jitter
- **Camera jitter:** Smoothing (18% lerp) minimizes but doesn't eliminate

---

## 15. Testing and Debugging

### 15.1 Debug Features
**In `kDebugMode` (Flutter debug builds):**
- Reduced gravity (70% of normal) for easier testing
- Rope stall detection (rotation and thrust)
- Debug HUD text shows stall warnings

**To test specific scenarios:**
- Modify `levelIndex` initial value to skip to specific levels
- Adjust `maxFuel` to test fuel scarcity
- Change `ropeMaxLength` formula to test attachment limits
- Modify `shipSpawn` in level data for different starting positions

### 15.2 Common Testing Tasks
- **Test attachment:** Approach cargo from different angles, speeds
- **Test rope physics:** Swing cargo, fly in circles, sudden stops
- **Test landing:** Land ship first vs cargo first, test sensor overlap
- **Test collisions:** Graze walls, test sensor vs fixture contacts
- **Test fuel:** Run out mid-flight, test thrust cutoff
- **Test levels:** Verify all 3 levels load and complete properly

---

## 16. Dependencies and Setup

### 16.1 Key Dependencies
```yaml
flutter: sdk: flutter
flame: ^1.36.0              # Game engine
flame_forge2d: ^0.19.2+5    # Physics integration
flame_tiled: ^3.1.0         # Level loading
forge2d: ^0.14.2+1          # Physics engine (Box2D port)
tiled: ^0.11.1              # TMX format support
```

### 16.2 Asset Requirements
- **TMX levels:** Must be in `assets/tiles/` directory
- **TMX object layers:** "walls" and "markers" required
- **Marker objects:** "ship", "goal", "cargo_zone" required
- **Pixel-to-meter ratio:** TMX must use 32px = 1 tile/meter scale

### 16.3 Platform Support
- **Landscape orientation enforced:** `main.dart` sets preferred orientations
- **Dark theme:** App uses dark color scheme throughout
- **Touch input required:** No keyboard/gamepad support currently

---

## End of Reference Document

This document captures the complete game logic as implemented in the codebase. Use this as a reference for:
- Understanding existing systems
- Planning new features
- Debugging issues
- Onboarding new developers
- Porting to different engines/platforms

**Last Updated:** Based on codebase snapshot as of review session
**Version:** 1.0.0+1 (from pubspec.yaml)
