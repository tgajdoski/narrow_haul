import 'dart:math' as math;

/// Mystery salvage: a "?" cache on cave levels. Flying through it rolls a
/// surprise: mostly a boon, sometimes a (silly, never lethal) curse.
/// Pure Dart: the picker and the timers are tested headless
/// (`test/salvage_test.dart`); the game reads the modifiers each frame.
enum SalvageEffect {
  // Boons.
  overshield,
  topOff,
  afterburner,
  fuelSaver,
  stealth,
  compactor,
  chrono,
  antiGrav,
  lucky,
  ammoCache,
  // Curses.
  swarmSting,
  fuelLeak,
  sporeTrip,
  crossedWires,
  sputter,
  blackout,
  hiccups,
  heavyHeart,
  flareBeacon,
}

class SalvageSpec {
  const SalvageSpec({
    required this.effect,
    required this.name,
    required this.good,
    required this.seconds,
    required this.weight,
    required this.callsign,
    required this.quip,
    required this.blurb,
    this.needsTurrets = false,
    this.needsTow = false,
    this.needsUnarmed = false,
    this.notOnLowFuel = false,
    this.worldWeights = const {},
  });

  final SalvageEffect effect;

  /// HUD badge name (upper case, short).
  final String name;

  /// A boon (gold) or a curse (purple).
  final bool good;

  /// How long it lasts; 0 = instant (Top-off, Lucky Salvage, Ammo Cache).
  final double seconds;

  /// Odds within its own pool (boons or curses).
  final double weight;

  /// The radio line when it's revealed.
  final String callsign;
  final String quip;

  /// What it does, for the Salvage Log.
  final String blurb;

  /// Only where a live turret can be fooled or alerted.
  final bool needsTurrets;

  /// Only while the pod is in tow (Heavy Heart).
  final bool needsTow;

  /// Only for a ship without a gun (Ammo Cache).
  final bool needsUnarmed;

  /// Never when the tank is low (Sputter would be cruel).
  final bool notOnLowFuel;

  /// Weight multipliers per world theme id (spores in the Alien caves…).
  final Map<String, double> worldWeights;

  String get id => effect.name;
  bool get timed => seconds > 0;

  double weightIn(String? themeId) => weight * (worldWeights[themeId] ?? 1);
}

/// Share of tank that Top-off adds.
const double kTopOffFraction = 0.3;

/// Afterburner thrust and the drain multipliers of Fuel Saver / Fuel Leak.
const double kAfterburnerThrustMul = 1.4;
const double kFuelLeakDrainMul = 2.0;

/// How big Swarm Sting swells the hull, and how small the Compactor makes
/// it (the hull only ever grows into free space).
const double kSwellScale = 1.25;
const double kCompactScale = 0.7;

/// Spinning shakes the bee off: each full turn takes this much off a sting.
const double kStingSecondsPerTurn = 2.0;

/// Chrono: the world runs at this speed (effect timers run in real time).
const double kChronoTimeScale = 0.6;

/// Anti-grav Bubble: share of the local pull that's left.
const double kAntiGravMul = 0.5;

/// Heavy Heart: extra pod weight (share of its own).
const double kHeavyHeartAdd = 0.4;

/// Flare Beacon: turrets reload this much faster.
const double kFlareTempo = 1.5;

/// Sputter: the engine cuts for [kSputterCut] s every [kSputterPeriod] s.
const double kSputterPeriod = 1.0;
const double kSputterCut = 0.2;

/// Lucky Salvage: coins paid on delivery (lost on a crash).
const int kLuckyCoins = 60;

/// No curse from a cache this close to the pad (m): the last stretch is
/// never sabotaged. Crossed Wires also rests this close to the pad.
const double kSalvageNoCurseNearPad = 4.0;

/// Delivering after a curse: a little XP and coins for the grit.
const int kSalvageGritXp = 25;
const int kSalvageGritCoins = 10;

/// Finding every effect once (the Salvage Log's Collector award).
const int kSalvageCollectorCoins = 300;

/// A crash this soon after a curse starts is forgiven (the curse never
/// kills by itself).
const double kCurseGraceSeconds = 1.5;

const List<SalvageSpec> kSalvage = [
  SalvageSpec(
    effect: SalvageEffect.overshield,
    name: 'OVERSHIELD',
    good: true,
    seconds: 10,
    weight: 1.2,
    callsign: 'OPS',
    quip: 'Overshield up. It takes one hit for you.',
    blurb: 'The next crash or shell within 10 s just bounces off.',
  ),
  SalvageSpec(
    effect: SalvageEffect.topOff,
    name: 'TOP-OFF',
    good: true,
    seconds: 0,
    weight: 1.0,
    callsign: 'OPS',
    quip: 'Spare fuel in that one. Tank topped off.',
    blurb: 'A third of a tank, on the spot.',
  ),
  SalvageSpec(
    effect: SalvageEffect.afterburner,
    name: 'AFTERBURNER',
    good: true,
    seconds: 8,
    weight: 1.0,
    callsign: 'OPS',
    quip: 'Afterburner kit. Extra push, same fuel.',
    blurb: '40% more thrust for 8 s, no extra fuel.',
  ),
  SalvageSpec(
    effect: SalvageEffect.fuelSaver,
    name: 'FUEL SAVER',
    good: true,
    seconds: 10,
    weight: 1.0,
    callsign: 'OPS',
    quip: 'Fuel saver online. Burn all you like.',
    blurb: 'The engine burns nothing for 10 s.',
  ),
  SalvageSpec(
    effect: SalvageEffect.stealth,
    name: 'STEALTH FIELD',
    good: true,
    seconds: 8,
    weight: 1.4,
    callsign: 'OPS',
    quip: 'Stealth field. The guns can\'t see you.',
    blurb: 'Turrets can\'t lock on for 8 s.',
    needsTurrets: true,
  ),
  SalvageSpec(
    effect: SalvageEffect.compactor,
    name: 'COMPACTOR',
    good: true,
    seconds: 15,
    weight: 1.0,
    callsign: 'OPS',
    quip: 'Compactor! You\'re pocket-sized. Squeeze through while it lasts.',
    blurb: 'The ship shrinks to 70% for 15 s. It grows back when there\'s room.',
  ),
  SalvageSpec(
    effect: SalvageEffect.chrono,
    name: 'CHRONO',
    good: true,
    seconds: 6,
    weight: 0.9,
    callsign: 'OPS',
    quip: 'Chrono field. Everything slows down. Take your time.',
    blurb: 'The cave runs at 60% speed for 6 s.',
  ),
  SalvageSpec(
    effect: SalvageEffect.antiGrav,
    name: 'ANTI-GRAV',
    good: true,
    seconds: 10,
    weight: 0.9,
    callsign: 'OPS',
    quip: 'Anti-grav bubble. Light as a feather.',
    blurb: 'Half the pull on ship and pod for 10 s.',
    worldWeights: {'orbit': 1.5, 'lava': 1.5},
  ),
  SalvageSpec(
    effect: SalvageEffect.lucky,
    name: 'LUCKY SALVAGE',
    good: true,
    seconds: 0,
    weight: 0.8,
    callsign: 'OPS',
    quip: 'Valuables! Bring them home: +$kLuckyCoins coins on delivery.',
    blurb: '+$kLuckyCoins coins, paid if you deliver.',
  ),
  SalvageSpec(
    effect: SalvageEffect.ammoCache,
    name: 'AMMO CACHE',
    good: true,
    seconds: 0,
    weight: 0.8,
    callsign: 'OPS',
    quip: 'Ordnance in there. Check your FIRE button.',
    blurb: 'A random weapon\'s ammo for this flight.',
    needsUnarmed: true,
  ),
  SalvageSpec(
    effect: SalvageEffect.swarmSting,
    name: 'SWARM STING',
    good: false,
    seconds: 10,
    weight: 1.0,
    callsign: 'TOWER',
    quip: 'That was a hive. You\'re swelling up. Spin to shake it off!',
    blurb: 'A bee stings the hull: it swells for 10 s. Spinning shakes it off.',
  ),
  SalvageSpec(
    effect: SalvageEffect.fuelLeak,
    name: 'FUEL LEAK',
    good: false,
    seconds: 8,
    weight: 1.0,
    callsign: 'TOWER',
    quip: 'Booby trap! You\'re leaking fuel. Set down to patch it.',
    blurb: 'Double fuel burn for 8 s. A touchdown patches it.',
    worldWeights: {'lava': 2},
  ),
  SalvageSpec(
    effect: SalvageEffect.sporeTrip,
    name: 'SPORE TRIP',
    good: false,
    seconds: 8,
    weight: 1.0,
    callsign: 'TOWER',
    quip: 'Those were spores. Things may look… wobbly. Trust your gauges.',
    blurb: 'Alien spores: the cave wobbles and shimmers for 8 s.',
    worldWeights: {'alien': 3},
  ),
  SalvageSpec(
    effect: SalvageEffect.crossedWires,
    name: 'CROSSED WIRES',
    good: false,
    seconds: 5,
    weight: 0.8,
    callsign: 'TOWER',
    quip: 'Short circuit! Left is right and right is left. Easy now.',
    blurb: 'Steering swaps sides for 5 s (never near the pad).',
  ),
  SalvageSpec(
    effect: SalvageEffect.sputter,
    name: 'SPUTTER',
    good: false,
    seconds: 6,
    weight: 0.9,
    callsign: 'TOWER',
    quip: 'Dirty fuel. The engine\'s coughing.',
    blurb: 'The engine cuts out for a blink every second, for 6 s.',
    notOnLowFuel: true,
    worldWeights: {'mine': 2},
  ),
  SalvageSpec(
    effect: SalvageEffect.blackout,
    name: 'BLACKOUT',
    good: false,
    seconds: 8,
    weight: 1.0,
    callsign: 'TOWER',
    quip: 'Lights out! Headlamp only. Use the minimap.',
    blurb: 'Only the headlamp lights the cave for 8 s.',
    worldWeights: {'ice': 2},
  ),
  SalvageSpec(
    effect: SalvageEffect.hiccups,
    name: 'HICCUPS',
    good: false,
    seconds: 6,
    weight: 1.0,
    callsign: 'TOWER',
    quip: 'Gyro hiccups. Hold on… hic!',
    blurb: 'The gyro kicks the nose about for 6 s.',
  ),
  SalvageSpec(
    effect: SalvageEffect.heavyHeart,
    name: 'HEAVY HEART',
    good: false,
    seconds: 10,
    weight: 0.8,
    callsign: 'TOWER',
    quip: 'Something crawled into the pod. It\'s heavier now.',
    blurb: 'The towed pod weighs 40% more for 10 s.',
    needsTow: true,
  ),
  SalvageSpec(
    effect: SalvageEffect.flareBeacon,
    name: 'FLARE BEACON',
    good: false,
    seconds: 6,
    weight: 1.0,
    callsign: 'TOWER',
    quip: 'A flare\'s stuck to your hull. Every gun knows where you are!',
    blurb: 'Turrets reload 50% faster for 6 s.',
    needsTurrets: true,
  ),
];

SalvageSpec salvageSpec(SalvageEffect e) => kSalvage[e.index];

SalvageSpec? salvageById(String id) {
  for (final s in kSalvage) {
    if (s.id == id) return s;
  }
  return null;
}

/// Odds of a boon, after a curse (bad luck protection), and on a chaos day.
const double kSalvageGoodChance = 0.7;
const double kSalvageGoodAfterCurse = 0.85;
const double kSalvageChaosGoodChance = 0.5;

/// What the cache can roll here.
class SalvageContext {
  const SalvageContext({
    this.liveTurrets = false,
    this.nearPad = false,
    this.lastWasCurse = false,
    this.towing = false,
    this.unarmed = true,
    this.lowFuel = false,
    this.themeId,
    this.chaos = false,
  });

  /// A turret is still shooting (Stealth Field / Flare Beacon matter).
  final bool liveTurrets;

  /// The cache is close to the pad: no curse on the last stretch.
  final bool nearPad;

  /// The previous cache was a curse: never two in a row.
  final bool lastWasCurse;

  /// The pod is in tow (Heavy Heart).
  final bool towing;

  /// The ship has no gun (Ammo Cache).
  final bool unarmed;

  /// Under 30% fuel (no Sputter).
  final bool lowFuel;

  /// World theme, for [SalvageSpec.worldWeights].
  final String? themeId;

  /// Chaos daily: 50/50 and no bad luck protection.
  final bool chaos;

  bool allows(SalvageSpec s) =>
      (!s.needsTurrets || liveTurrets) &&
      (!s.needsTow || towing) &&
      (!s.needsUnarmed || unarmed) &&
      (!s.notOnLowFuel || !lowFuel);
}

/// Rolls a cache: 70% boon (85% after a curse, 50% on a chaos day); never a
/// curse near the pad, nor twice in a row outside chaos; context-only
/// effects only where they make sense.
SalvageSpec pickSalvage(math.Random rng, SalvageContext ctx) {
  final goodChance = ctx.chaos
      ? kSalvageChaosGoodChance
      : ctx.lastWasCurse
          ? kSalvageGoodAfterCurse
          : kSalvageGoodChance;
  final curseOk = !ctx.nearPad && (ctx.chaos || !ctx.lastWasCurse);
  final good = !curseOk || rng.nextDouble() < goodChance;
  final pool = [
    for (final s in kSalvage)
      if (s.good == good && ctx.allows(s)) s,
  ];
  final total = pool.fold<double>(0, (a, s) => a + s.weightIn(ctx.themeId));
  var r = rng.nextDouble() * total;
  for (final s in pool) {
    r -= s.weightIn(ctx.themeId);
    if (r < 0) return s;
  }
  return pool.last;
}

/// The surprise running on this flight: one timed effect at a time (a new
/// cache replaces it), read by the game as multipliers and flags.
class ActiveSalvage {
  SalvageSpec? _spec;
  double _left = 0;
  double _since = 1e9;
  bool _shieldSpent = false;
  double _spin = 0;
  bool _shakenOff = false;

  SalvageSpec? get spec => _spec;
  SalvageEffect? get effect => _spec?.effect;

  /// Seconds left, and the share of the effect still to run (badge ring).
  double get left => _left;
  double get fraction {
    final s = _spec;
    return s == null || !s.timed ? 0 : (_left / s.seconds).clamp(0.0, 1.0);
  }

  /// Seconds since the last cache took effect.
  double get since => _since;

  bool get active => _spec != null;
  bool get cursed => _spec != null && !_spec!.good;
  bool _is(SalvageEffect e) => _spec?.effect == e;

  /// The last sting ended because the pilot spun the bee off (read once).
  bool takeShakenOff() {
    final v = _shakenOff;
    _shakenOff = false;
    return v;
  }

  /// Starts [spec] (replacing whatever ran). Instant effects aren't kept.
  void start(SalvageSpec spec) {
    _since = 0;
    _spin = 0;
    _shieldSpent = false;
    if (!spec.timed) {
      _spec = null;
      _left = 0;
      return;
    }
    _spec = spec;
    _left = spec.seconds;
  }

  /// [dt] is real time (Chrono slows the cave, not its own clock).
  /// [spinRadians]: how far the ship turned this frame (a sting is shaken
  /// off by spinning).
  void tick(double dt, {double spinRadians = 0}) {
    _since += dt;
    if (_spec == null) return;
    var drop = dt;
    if (_is(SalvageEffect.swarmSting)) {
      _spin += spinRadians.abs();
      if (_spin >= 2 * math.pi) {
        _spin -= 2 * math.pi;
        drop += kStingSecondsPerTurn;
      }
    }
    _left -= drop;
    if (_left <= 0) {
      // Ended by the spin, not by the clock.
      final spun = drop - dt;
      _shakenOff = spun > 0 && _left + spun > 0;
      end();
    }
  }

  void end() {
    _spec = null;
    _left = 0;
  }

  /// Clears everything (new flight, continue after a crash).
  void reset() {
    end();
    _since = 1e9;
    _spin = 0;
    _shieldSpent = false;
    _shakenOff = false;
  }

  /// 0 → 1 over the first 0.6 s, back to 0 over the last 0.8 s: screen
  /// effects ease in and out instead of snapping.
  double get ramp {
    if (_spec == null) return 0;
    return math.min(1.0, math.min(_since / 0.6, _left / 0.8)).clamp(0.0, 1.0);
  }

  double get thrustMul => _is(SalvageEffect.afterburner) ? kAfterburnerThrustMul : 1;

  double get drainMul => _is(SalvageEffect.fuelSaver)
      ? 0
      : _is(SalvageEffect.fuelLeak)
          ? kFuelLeakDrainMul
          : 1;

  bool get cloaked => _is(SalvageEffect.stealth);
  bool get flared => _is(SalvageEffect.flareBeacon);

  /// The hull size the effect wants (the game grows into free space only).
  double get hullTarget => _is(SalvageEffect.swarmSting)
      ? kSwellScale
      : _is(SalvageEffect.compactor)
          ? kCompactScale
          : 1;

  /// Speed of the cave (Chrono), eased in and out.
  double get timeScale =>
      _is(SalvageEffect.chrono) ? 1 - (1 - kChronoTimeScale) * ramp : 1;

  /// Share of the local pull on ship and pod (Anti-grav).
  double get gravityMul => _is(SalvageEffect.antiGrav) ? kAntiGravMul : 1;

  /// Extra pod weight (Heavy Heart).
  double get podWeightAdd => _is(SalvageEffect.heavyHeart) ? kHeavyHeartAdd : 0;

  /// −1 while Crossed Wires swaps the steering.
  bool get crossed => _is(SalvageEffect.crossedWires);

  /// The engine is cutting out this instant (Sputter).
  bool get sputterCut =>
      _is(SalvageEffect.sputter) && (_since % kSputterPeriod) > kSputterPeriod - kSputterCut;

  bool get hiccups => _is(SalvageEffect.hiccups);

  /// Screen effects (0…1, eased).
  double get hallucination => _is(SalvageEffect.sporeTrip) ? ramp : 0;
  double get darkness => _is(SalvageEffect.blackout) ? ramp : 0;

  /// A crash right now would be absorbed: by the Overshield (once), or the
  /// grace after a curse starts.
  bool get canAbsorb =>
      (_is(SalvageEffect.overshield) && !_shieldSpent) ||
      (cursed && _since < kCurseGraceSeconds);

  /// Takes the hit: the Overshield pops (and ends), a curse's grace stays.
  void absorb() {
    if (_is(SalvageEffect.overshield)) {
      _shieldSpent = true;
      end();
    }
  }

  /// Fuel Leak patched by setting down on rock.
  void patchLeak() {
    if (_is(SalvageEffect.fuelLeak)) end();
  }
}
