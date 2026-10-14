import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/physics_core.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/fleet_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/ui/space_ui.dart';

// What a mission holds, as the briefing lists it. Plain data and rules, no
// widgets, so tests can check it without a game.

/// One line of a mission briefing: what the pilot will face (or get).
class BriefingFact {
  const BriefingFact(this.icon, this.label, {this.kind = FactKind.info});
  final IconData icon;
  final String label;
  final FactKind kind;

  @override
  String toString() => label;
}

/// [warn]: makes the flight harder. [help]: makes it easier. [info]: neither.
enum FactKind { info, warn, help }

/// What's special about flat level [index]: ship, physics, force fields,
/// hazards and pickups. [daily] layers today's challenge modifiers on top;
/// [testFlight] means the ship is swapped for another one at launch.
List<BriefingFact> briefingFacts(
  int index, {
  DailyChallengeConfig? daily,
  bool testFlight = false,
}) {
  final def = LevelRegistry.defAt(index);
  // A daily flies the level's own ship (or the Test Flight's).
  final ship = daily != null || testFlight
      ? LevelRegistry.shipFor(index)
      : FleetService.flownShipFor(index);
  final m = def.modifiers;
  final facts = <BriefingFact>[
    if (testFlight)
      const BriefingFact(
        Icons.swap_horiz_rounded,
        'Test Flight: another ship',
        kind: FactKind.warn,
      )
    else
      BriefingFact(
        Icons.rocket_rounded,
        isNewShip(ship) ? '${ship.name} · new ship' : ship.name,
        kind: isNewShip(ship) ? FactKind.warn : FactKind.info,
      ),
  ];

  final g = combinedGravityMul(m.gravityMul, daily?.gravityMultiplier ?? 1);
  if (g == 0) {
    facts.add(const BriefingFact(Icons.blur_on_rounded, 'Zero-g'));
  } else if ((g - 1).abs() > 0.01) {
    facts.add(
      BriefingFact(
        g > 1 ? Icons.south_rounded : Icons.north_rounded,
        '${g > 1 ? 'Heavy' : 'Light'} gravity ${_trim(g)} g',
        kind: g > 1 ? FactKind.warn : FactKind.help,
      ),
    );
  }

  final burn = m.fuelDrainMul * (daily?.fuelDrainMultiplier ?? 1);
  if ((burn - 1).abs() > 0.01) {
    facts.add(
      BriefingFact(
        Icons.local_gas_station_rounded,
        burn > 1
            ? 'Fuel burn ×${_mul(burn)}'
            : 'Fuel lasts ×${_mul(1 / burn)}',
        kind: burn > 1 ? FactKind.warn : FactKind.help,
      ),
    );
  }
  if (m.cargoDensityMul > 1) {
    facts.add(
      BriefingFact(
        Icons.anchor_rounded,
        'Heavy cargo ×${_mul(m.cargoDensityMul)}',
        kind: FactKind.warn,
      ),
    );
  }
  if (m.wallFriction != null) {
    facts.add(
      const BriefingFact(
        Icons.ac_unit_rounded,
        'Icy walls',
        kind: FactKind.warn,
      ),
    );
  }

  if (def is CaveLevelDef) {
    final spec = def.spec;
    final winds = spec.fields.whereType<WindZoneSpec>();
    if (winds.isNotEmpty) {
      facts.add(
        BriefingFact(
          Icons.air_rounded,
          winds.any((w) => w.gustAmp > 0) ? 'Gusting wind' : 'Wind',
          kind: FactKind.warn,
        ),
      );
    }
    final zones = spec.fields.whereType<GravityZoneSpec>();
    if (zones.any((z) => z.gx == 0 && z.gy == 0)) {
      facts.add(const BriefingFact(Icons.blur_circular_rounded, 'Zero-g pocket'));
    }
    if (zones.any((z) => z.gx != 0 || z.gy != 0)) {
      facts.add(
        const BriefingFact(
          Icons.turn_right_rounded,
          'Sideways gravity',
          kind: FactKind.warn,
        ),
      );
    }
    final wells = spec.fields.whereType<GravityWellSpec>().length;
    if (wells > 0) {
      facts.add(
        BriefingFact(
          Icons.radio_button_checked_rounded,
          wells == 1 ? 'Gravity well' : '$wells gravity wells',
          kind: FactKind.warn,
        ),
      );
    }

    final obstacles = spec.obstacles;
    final moving = obstacles
        .where(
          (o) =>
              o is RotatingBarSpec || o is PendulumSpec || o is SlidingBlockSpec,
        )
        .length;
    if (moving > 0) {
      facts.add(
        BriefingFact(
          Icons.settings_rounded,
          moving == 1 ? 'Moving hazard' : '$moving moving hazards',
          kind: FactKind.warn,
        ),
      );
    }
    final turrets = obstacles.whereType<TurretSpec>().length;
    if (turrets > 0) {
      facts.add(
        BriefingFact(
          Icons.gps_fixed_rounded,
          turrets == 1 ? 'Turret' : '$turrets turrets',
          kind: FactKind.warn,
        ),
      );
    }
    if (obstacles.any((o) => o is ReactorSpec)) {
      facts.add(
        const BriefingFact(
          Icons.bolt_rounded,
          'Reactor',
          kind: FactKind.warn,
        ),
      );
    }
    final cells = spec.pickups.whereType<FuelCellSpec>().length;
    if (cells > 0) {
      facts.add(
        BriefingFact(
          Icons.battery_charging_full_rounded,
          cells == 1 ? 'Fuel canister' : '$cells fuel canisters',
          kind: FactKind.help,
        ),
      );
    }
  }
  return facts;
}

/// A ship not flown yet (`LevelRegistry.isShipNew`), like the in-flight
/// ship hint.
bool isNewShip(ShipSpec ship) => LevelRegistry.isShipNew(ship.id);

/// `1.5`, `2`.
String _mul(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// `1.35`, `1.4`, `2` (two decimals at most, no trailing zeros).
String _trim(double v) =>
    v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// Star rules as the game scores them (`_calculateStars`): 3★ needs the fuel
/// *and* the time, 2★ the fuel, 1★ just the delivery.
(String three, String two) starTargets(StarSpec s) => (
  '≥ ${(s.star3Fuel * 100).round()}% fuel · ≤ ${formatFlightTime(s.star3Time)}',
  '≥ ${(s.star2Fuel * 100).round()}% fuel',
);

/// XP for clearing today's daily now (the streak includes today).
({int xp, int bonus, int streak}) dailyReward() {
  final streak = ProgressService.instance.getDailyStreak() + 1;
  return (xp: kDailyXp, bonus: dailyStreakBonusXp(streak), streak: streak);
}
