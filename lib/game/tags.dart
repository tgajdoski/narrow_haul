/// Fixture [userData] for anything solid the ship must not hit — ship
/// contact ends the run (moving obstacles, turrets, reactors, well cores).
class WallTag {
  const WallTag();
}

/// Static rock (cave walls, tutorial walls): a slow touch only scrapes or
/// lands the ship, a fast one crashes (`classifyHullContact`).
class RockTag extends WallTag {
  const RockTag();
}

/// Body [userData] for the cargo — landing pad cargo sensor detects this.
class CargoTag {
  const CargoTag();
}

/// Ship fixture [userData] — landing pad ship sensor detects this.
class ShipTag {
  const ShipTag();
}

/// Winch hook sensor on the ship — must overlap cargo to attach the chain.
class HookTag {
  const HookTag();
}
