# Narrow Haul

A 2D physics-based spacecraft cargo transport game built with Flutter, Flame, and Forge2D.

## Game Overview

Pilot a rocket through narrow terrain, pick up cargo using an automatic rope/tow system, and land both your ship and the cargo on the landing pad to complete each level.

**Controls:**
- **Left side:** Rotation pad (turn left/right)
- **Right side:** Thrust button (hold to fire engine)
- **Landscape orientation required**

## Tech Stack

- **Flutter** - Cross-platform framework
- **Flame v1.36.0** - Game engine
- **Forge2D v0.14.2** - Physics engine (Box2D port)
- **Flame Tiled v3.1.0** - Level loading from Tiled maps

## Documentation

See **[GAME_LOGIC_REFERENCE.md](GAME_LOGIC_REFERENCE.md)** for comprehensive documentation including:
- Complete architecture and code structure
- Physics system and constants
- Rope/tow mechanics
- Level system and data format
- Win/lose conditions
- Extension points for future development

## Quick Start

```bash
# Get dependencies
flutter pub get

# Run the game (landscape mode recommended)
flutter run
```

## Project Structure

```
lib/
├── main.dart                          # App entry point
├── game/
│   ├── narrow_haul_game.dart          # Main game controller
│   ├── physics_constants.dart         # Physics configuration
│   ├── components/                     # Game entities (ship, cargo, rope, etc.)
│   └── level/                          # Level loading and data structures

assets/
└── tiles/                              # Tiled .tmx level files
    ├── level_01.tmx
    ├── level_02.tmx
    └── level_03.tmx
```

## Game Mechanics

- **Gravity-based physics** with realistic momentum
- **Automatic rope attachment** when approaching cargo
- **Fuel system** - manage your fuel to complete levels
- **Precision landing** - both ship and cargo must be on the pad
- **Progressive difficulty** - 3 levels with increasing complexity

## Development

This game is designed for extension. The reference document includes:
- Tuning constants for difficulty adjustment
- Extension points for new features
- Physics modification guidelines
- Level creation instructions using Tiled

## License

Private project - all rights reserved.
