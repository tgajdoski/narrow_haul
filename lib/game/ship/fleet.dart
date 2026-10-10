import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/ship_fit_table.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

/// The fleet: which ship flies a level. Pure Dart (tools and tests use it).
///
/// Every level keeps its *par ship* (`LevelRegistry.shipFor`), the one it is
/// balanced, validated, routed and autopiloted for. Any other ship the pilot
/// owns may fly it when it passes that level's validator ([shipFitOn]).

/// Why a ship can or can't fly a level.
enum ShipFit {
  ok,
  tooBig,
  lowLift,
  lowFuel,
  needsCannon,
  parOnly;

  bool get flies => this == ok;

  /// Briefing reason for a greyed-out ship.
  String get reason => switch (this) {
        ok => '',
        tooBig => 'Too wide for these tunnels',
        lowLift => 'Not enough lift here',
        lowFuel => 'Tank too small for this run',
        needsCannon => 'Needs a cannon for the turrets',
        parOnly => 'Type rating: fly the rated ship',
      };
}

/// Sorts validator issues (strings) into one [ShipFit]: armament first, then
/// lift and fuel, and anything geometric means the hull doesn't fit.
ShipFit classifyFitIssues(List<String> issues) {
  if (issues.isEmpty) return ShipFit.ok;
  bool has(String p) => issues.any((i) => i.startsWith(p));
  if (issues.any((i) => i.contains('unarmed'))) return ShipFit.needsCannon;
  if (has('LIFT') || has('WIND')) return ShipFit.lowLift;
  if (has('FUEL')) return ShipFit.lowFuel;
  return ShipFit.tooBig;
}

/// TMX tutorial maps have no validator: a hull no larger than the par ship's
/// and ≥ 90% of its range (as the daily Test Flight requires).
ShipFit tmxShipFit(ShipSpec ship, ShipSpec par) {
  if (!shipFits(ship, par)) return ShipFit.tooBig;
  if (ship.deltaV < par.deltaV * 0.9) return ShipFit.lowFuel;
  return ShipFit.ok;
}

/// Type-rating missions are flown in the ship they rate.
bool isParOnly(LevelDef def) => def.saveId.startsWith('rating_');

/// Can [ship] fly [def], whose par ship is [par]?
ShipFit shipFitOn(LevelDef def, ShipSpec par, ShipSpec ship) {
  if (ship.id == par.id) return ShipFit.ok;
  if (isParOnly(def)) return ShipFit.parOnly;
  return switch (def) {
    TmxLevelDef() => tmxShipFit(ship, par),
    // Missing from the table (a new level before regenerating): par only.
    CaveLevelDef() => kShipFitTable[def.saveId]?[ship.id] ?? ShipFit.parOnly,
  };
}

/// The ship actually flown: the briefing [choice] for this level, else the
/// Garage [preferred] ship, else par — each only if owned and fit.
ShipSpec resolveFlownShip({
  required LevelDef def,
  required ShipSpec par,
  required bool Function(String id) owns,
  String? choice,
  String? preferred,
}) {
  for (final id in [choice, preferred]) {
    final ship = id == null ? null : kShips[id];
    if (ship != null && owns(ship.id) && shipFitOn(def, par, ship).flies) {
      return ship;
    }
  }
  return par;
}

/// Star fuel fraction left, made fair across ships: the share of the tank
/// burned is scaled by the flown ship's range over the par ship's, so a big
/// tank doesn't make 3★ trivial and a small one doesn't make it impossible.
/// (A kit's tank multiplier applies to both and cancels.)
double normalisedFuelLeft(double fuelLeftFrac, ShipSpec flown, ShipSpec par) {
  if (flown.id == par.id) return fuelLeftFrac;
  return 1 - (1 - fuelLeftFrac) * (flown.deltaV / par.deltaV);
}

/// Coins to buy a ship before its type rating. The Kestrel is everyone's.
const Map<String, int> kShipCoinPrice = {
  'hopper': 400,
  'skate': 600,
  'mule': 700,
  'vector': 800,
  'talon': 1200,
};

/// The world whose type rating earns each ship, for "Earn: …" captions.
const Map<String, String> kShipEarnedIn = {
  'kestrel': 'Training Grounds',
  'hopper': 'Alien',
  'mule': 'Mine',
  'skate': 'Ice',
  'vector': 'Orbit',
  'talon': 'The Redoubt',
};

/// Ships in Garage order.
const List<String> kFleetOrder = ['kestrel', 'hopper', 'skate', 'mule', 'vector', 'talon'];

/// Trait chip for the Garage.
String shipTrait(ShipSpec s) {
  if (s.armed) return 'Cannon';
  if (s.hoverAssist) return 'Hover assist';
  if (s.autoLevel) return 'Auto-levels';
  if (s.ropeLengthMul > 1) return 'Long winch';
  if (s.hullScale < 1) return 'Compact hull';
  return 'All-rounder';
}

/// Garage stat bars for a ship, each 0..1, scaled across the fleet.
class ShipStats {
  const ShipStats({
    required this.lift,
    required this.turn,
    required this.range,
    required this.steady,
    required this.compact,
  });
  final double lift;
  final double turn;
  final double range;
  final double steady;
  final double compact;

  static ShipStats of(ShipSpec s) {
    double c(double v) => v.clamp(0.05, 1.0);
    final accel = s.thrustForce / s.mass; // Kestrel ≈ 15.6 m/s², Mule ≈ 17.9
    return ShipStats(
      lift: c((accel - 10) / 10),
      turn: c((6.5 - s.secondsPerFullRotation) / 4 + (s.turnBoost - 1.6) * 0.3),
      range: c(s.deltaV / 240),
      steady: c(s.linearDamping * 1.6 +
          (s.autoLevel ? 0.3 : 0) +
          (s.hoverAssist ? 0.3 : 0)),
      compact: c(1.6 - s.circumradius),
    );
  }
}
