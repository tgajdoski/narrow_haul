import 'dart:math' as math;

/// How a weapon leaves the ship.
enum WeaponKind {
  /// The Talon's nose gun: fuel per shot, turrets only.
  cannon,

  /// Shockwave around the ship itself.
  charge,

  /// Dropped from the belly, falls under local gravity, bursts on contact.
  bomb,

  /// Held beam from the nose (ammo = seconds).
  laser,

  /// Steers to the nearest live target in line of sight.
  seeker,

  /// A spread of pellets.
  flak,
}

/// One weapon's numbers. Pure data (no Flame), shared by the game, the
/// Garage Armory and the tests.
class WeaponSpec {
  const WeaponSpec({
    required this.id,
    required this.name,
    required this.blurb,
    required this.kind,
    required this.unit,
    this.damage = 1,
    this.blastRadius = 0,
    this.carveRadius = 0,
    this.cooldown = 0.4,
    this.speed = 0,
    this.pellets = 1,
    this.spread = 0,
    this.range = 0,
    this.tick = 0,
    this.crateMin = 1,
    this.crateMax = 2,
    this.coinPack = 3,
    this.coinCost = 0,
  });

  final String id;
  final String name;
  final String blurb;
  final WeaponKind kind;

  /// Ammo unit as shown in the HUD/Garage ("charges", "s").
  final String unit;

  /// Hits dealt per impact (per pellet, per laser tick). Turrets have 2–4 hp.
  final int damage;

  /// Everything shootable within this radius takes [damage] (0: direct hit).
  final double blastRadius;

  /// Rock opened by an impact (cave levels; 0: none).
  final double carveRadius;

  /// Seconds between shots (laser: unused, it fires every frame).
  final double cooldown;

  /// Muzzle speed relative to the ship (m/s).
  final double speed;

  final int pellets;

  /// Total fan angle of the pellets (rad).
  final double spread;

  /// Laser reach (m).
  final double range;

  /// Laser: seconds between damage / carve ticks.
  final double tick;

  /// A supply crate holds this many units (inclusive range).
  final int crateMin;
  final int crateMax;

  /// Garage: units per coin purchase, and its price (0: not sold for coins).
  final int coinPack;
  final int coinCost;

  /// Laser ammo is seconds of beam; everything else counts shots.
  bool get continuous => kind == WeaponKind.laser;

  /// Breaks obstacles (bars, pendulums, blocks). The Talon's cannon can't, so
  /// The Redoubt's recorded routes and the autopilot stay valid.
  bool get heavy => kind != WeaponKind.cannon;

  bool get carvesRock => carveRadius > 0;
}

const kCannon = WeaponSpec(
  id: 'cannon',
  name: 'Autocannon',
  blurb: 'The Talon\'s nose gun. Each round costs fuel; it knocks out turrets '
      'and shoots down their shells, but bounces off rock and machinery.',
  kind: WeaponKind.cannon,
  unit: 'fuel',
);

const kDemoCharge = WeaponSpec(
  id: 'demo_charge',
  name: 'Demolition Charge',
  blurb: 'A shockwave around the ship: wrecks every obstacle and turret in '
      'reach, swats incoming fire and blows a hole in the rock. Your hull is '
      'shielded; the pod gets shoved.',
  kind: WeaponKind.charge,
  unit: 'charges',
  damage: 6,
  blastRadius: 2.6,
  carveRadius: 2.2,
  cooldown: 1.0,
  crateMin: 1,
  crateMax: 2,
  coinPack: 2,
  coinCost: 160,
);

const kGravityBomb = WeaponSpec(
  id: 'gravity_bomb',
  name: 'Gravity Bomb',
  blurb: 'Released from the belly and left to fall: it follows the local '
      'pull (wind and wells bend it) and bursts on contact.',
  kind: WeaponKind.bomb,
  unit: 'bombs',
  damage: 4,
  blastRadius: 1.8,
  carveRadius: 1.5,
  cooldown: 0.6,
  speed: 0.6,
  crateMin: 2,
  crateMax: 3,
  coinPack: 3,
  coinCost: 120,
);

const kMiningLaser = WeaponSpec(
  id: 'mining_laser',
  name: 'Mining Laser',
  blurb: 'Hold to cut. A short beam from the nose that tunnels through rock, '
      'slices machinery and burns shells that cross it. Ammo is seconds of beam.',
  kind: WeaponKind.laser,
  unit: 's',
  damage: 1,
  carveRadius: 0.55,
  range: 4,
  tick: 0.2,
  crateMin: 6,
  crateMax: 10,
  coinPack: 10,
  coinCost: 140,
);

const kSeeker = WeaponSpec(
  id: 'seeker',
  name: 'Seeker Missile',
  blurb: 'Locks on to the nearest turret, reactor or obstacle in sight and '
      'steers itself there.',
  kind: WeaponKind.seeker,
  unit: 'missiles',
  damage: 3,
  blastRadius: 0.8,
  cooldown: 0.7,
  speed: 5,
  crateMin: 1,
  crateMax: 3,
  coinPack: 3,
  coinCost: 110,
);

const kFlak = WeaponSpec(
  id: 'flak',
  name: 'Flak Burst',
  blurb: 'Five pellets in a fan. Short work of pendulums and limpet guns, '
      'no use against rock.',
  kind: WeaponKind.flak,
  unit: 'bursts',
  damage: 1,
  cooldown: 0.5,
  speed: 10,
  pellets: 5,
  spread: 0.5,
  crateMin: 2,
  crateMax: 4,
  coinPack: 4,
  coinCost: 90,
);

/// Special weapons, in Armory / HUD order (the cannon is the Talon's own).
const List<WeaponSpec> kWeapons = [
  kDemoCharge,
  kGravityBomb,
  kMiningLaser,
  kSeeker,
  kFlak,
];

WeaponSpec? weaponById(String id) {
  if (id == kCannon.id) return kCannon;
  for (final w in kWeapons) {
    if (w.id == id) return w;
  }
  return null;
}

/// Garage stat bars (0–1), like `RopeStats`.
class WeaponStats {
  const WeaponStats({
    required this.power,
    required this.reach,
    required this.mining,
    required this.precision,
  });

  final double power;
  final double reach;
  final double mining;
  final double precision;

  static WeaponStats of(WeaponSpec w) => WeaponStats(
        power: (w.damage * w.pellets / 6).clamp(0.1, 1.0),
        reach: switch (w.kind) {
          WeaponKind.charge => 0.35,
          WeaponKind.bomb => 0.5,
          WeaponKind.laser => 0.45,
          WeaponKind.seeker => 1.0,
          WeaponKind.flak => 0.6,
          WeaponKind.cannon => 0.8,
        },
        mining: (w.carveRadius / 2.2).clamp(0.0, 1.0),
        precision: switch (w.kind) {
          WeaponKind.charge => 0.2,
          WeaponKind.bomb => 0.45,
          WeaponKind.laser => 0.9,
          WeaponKind.seeker => 1.0,
          WeaponKind.flak => 0.5,
          WeaponKind.cannon => 0.8,
        },
      );
}

/// A flight's weapons: the ship's own cannon (armed ships) plus special
/// ammo in two pools. *Found* ammo comes from supply crates and lasts this
/// flight only; *carried* ammo is the player's stock (Garage coins, ads,
/// purchases). Found ammo is spent first. Carried ammo costs the run its
/// third star ([usedCarried]), so stars can't be bought.
class WeaponRack {
  WeaponRack({this.hasCannon = false, Map<String, double> carried = const {}})
      : _carried = {
          for (final e in carried.entries)
            if (e.value > 0) e.key: e.value,
        } {
    selectedId = available.isEmpty ? null : available.first;
  }

  final bool hasCannon;
  final Map<String, double> _found = {};
  final Map<String, double> _carried;

  /// Carried units spent and not yet written back to the save.
  final Map<String, double> _unsaved = {};

  /// Some carried ammo was used this flight.
  bool get usedCarried => _usedCarried;
  bool _usedCarried = false;

  /// Carried units spent since the last call, per weapon (the game deducts
  /// them from the save).
  Map<String, double> takeCarriedSpent() {
    final out = Map<String, double>.of(_unsaved);
    _unsaved.clear();
    return out;
  }

  String? selectedId;

  WeaponSpec? get selected => selectedId == null ? null : weaponById(selectedId!);

  double found(String id) => _found[id] ?? 0;
  double carried(String id) => _carried[id] ?? 0;
  double ammo(String id) => found(id) + carried(id);

  /// What the HUD can cycle through: the cannon, then weapons with ammo.
  List<String> get available => [
        if (hasCannon) kCannon.id,
        for (final w in kWeapons)
          if (ammo(w.id) > 1e-6) w.id,
      ];

  bool get hasAny => available.isNotEmpty;

  /// Anything to fire right now (the FIRE button shows).
  bool get canFire => hasAny;

  /// A crate's contents; selects that weapon (it's what the pilot just
  /// picked up).
  void addFound(String id, double units) {
    _found[id] = found(id) + units;
    selectedId = id;
  }

  /// Takes [units] of the selected special weapon, found ammo first. False
  /// (nothing taken) when there isn't enough left — except a continuous
  /// weapon, which takes whatever remains.
  bool spend(String id, double units) {
    final w = weaponById(id);
    if (w == null || w.kind == WeaponKind.cannon) return false;
    final have = ammo(id);
    if (have <= 1e-6) return false;
    if (!w.continuous && have + 1e-6 < units) return false;
    var need = math.min(units, have);
    final f = found(id);
    final fromFound = math.min(f, need);
    if (fromFound > 0) {
      _found[id] = f - fromFound;
      need -= fromFound;
    }
    if (need > 1e-9) {
      _carried[id] = carried(id) - need;
      _unsaved[id] = (_unsaved[id] ?? 0) + need;
      _usedCarried = true;
    }
    if (ammo(id) <= 1e-6) _selectNextAfter(id);
    return true;
  }

  /// Picks [id] if it's on board (the HUD's ammo rail, number keys).
  bool select(String id) {
    if (!available.contains(id)) return false;
    selectedId = id;
    return true;
  }

  /// The next unit of [id] would come from the player's own stock and cost
  /// the run its third star (it hasn't yet).
  bool costsStar(String id) =>
      !_usedCarried && found(id) <= 1e-6 && carried(id) > 1e-6;

  /// Next weapon in [available] (wraps). Returns the new selection.
  String? cycle() {
    final list = available;
    if (list.isEmpty) return selectedId = null;
    final i = selectedId == null ? -1 : list.indexOf(selectedId!);
    return selectedId = list[(i + 1) % list.length];
  }

  void _selectNextAfter(String emptied) {
    final list = available;
    if (list.isEmpty) {
      selectedId = null;
    } else if (!list.contains(selectedId)) {
      selectedId = list.first;
    }
  }
}
