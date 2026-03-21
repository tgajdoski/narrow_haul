/// Fixture [userData] for static terrain — ship contact ends the run.
class WallTag {
  const WallTag();
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
