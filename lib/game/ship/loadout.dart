/// Tow gear the player picks in the Garage. Pure data (no Flame), so tests
/// and tools can read it. Every item is a sidegrade: the stock cable is
/// exactly the original tow, the others trade one strength for a weakness.
library;

enum TowKind { rope, beam }

class RopeSpec {
  const RopeSpec({
    required this.id,
    required this.name,
    required this.blurb,
    this.kind = TowKind.rope,
    this.hookReach = kStockHookReach,
    this.approachDistance = 3.0,
    this.minTowLength = 1.0,
    this.stiffnessHz = 0,
    this.dampingRatio = 0.5,
    this.maxStretch = 0,
    this.swingDamping = 0,
    this.podMassAdd = 0,
    this.beamRange = 0,
    this.beamHoldLength = 0,
    this.beamMaxAccel = 0,
    this.beamFuelFracPerSec = 0,
  });

  final String id;
  final String name;

  /// One line for the Garage: what it's good at and what it costs.
  final String blurb;

  final TowKind kind;

  /// Extra grab radius (m) around the winch hook under the tail. Also
  /// widens the centre-to-centre fallback by the same amount.
  final double hookReach;

  /// Ship–pod distance (m) at which the line starts to show.
  final double approachDistance;

  /// Shortest tow (m, winch to pod centre). A catch closer than this pays
  /// the line out to it (the rope is slack until the ship climbs), so the
  /// pod always hangs clear of the hull.
  final double minTowLength;

  /// Spring rate of an elastic line (Hz, one-sided: only pulls when
  /// stretched). 0 = rigid, the original hard rope.
  final double stiffnessHz;
  final double dampingRatio;

  /// How far (fraction of length) an elastic line may stretch before it
  /// goes taut against the hard cap.
  final double maxStretch;

  /// Damps the pod's swing relative to the ship (1/s). Pulls on the ship
  /// too, so it never adds or removes energy from the pair as a whole.
  final double swingDamping;

  /// Weight the line itself adds to the towed pod (fraction of its mass).
  final double podMassAdd;

  // Tractor beam only.

  /// Lock-on and break range (m), ship winch to pod centre.
  final double beamRange;

  /// Where the beam holds the pod: this far below the winch (m).
  final double beamHoldLength;

  /// Strongest pull the beam can give the pod (m/s²). A heavy pod gets
  /// the same force, so it lags more on hard manoeuvres.
  final double beamMaxAccel;

  /// Extra fuel per second while the beam holds the pod, as a fraction of
  /// the tank (so it costs every ship the same share).
  final double beamFuelFracPerSec;

  bool get isBeam => kind == TowKind.beam;
  bool get isElastic => stiffnessHz > 0;

  /// Center-to-center attach fallback, widened with the hook reach.
  double get attachCenterDistance =>
      kAttachCenterBase + (hookReach - kStockHookReach);
}

/// Stock hook reach (m): with the hook radius and the pod's, a Kestrel
/// hovering over the pod catches it with ~0.8 m of air under the tail.
const double kStockHookReach = 0.6;

/// Stock centre-to-centre catch (m), for approaches from the side.
const double kAttachCenterBase = 1.7;

const kStockRope = RopeSpec(
  id: 'rope_cable',
  name: 'Steel Winch Cable',
  blurb: 'Rigid and predictable. The baseline.',
);

const kRopes = <String, RopeSpec>{
  'rope_cable': kStockRope,
  'rope_chain': RopeSpec(
    id: 'rope_chain',
    name: 'Tow Chain',
    blurb: 'Heavy links calm the swing, but add weight to the load.',
    swingDamping: 2.2,
    podMassAdd: 0.35,
  ),
  'rope_braided': RopeSpec(
    id: 'rope_braided',
    name: 'Long Line',
    blurb: 'Grabs a little further and gives on hard stops; swings wider.',
    hookReach: 0.75,
    stiffnessHz: 4.5,
    dampingRatio: 0.35,
    maxStretch: 0.25,
  ),
  'rope_energy': RopeSpec(
    id: 'rope_energy',
    name: 'Magnetic Grapple',
    blurb: 'Grabs the pod from a hover. Springy: it bounces on stops.',
    hookReach: 1.15,
    approachDistance: 3.4,
    stiffnessHz: 2.5,
    dampingRatio: 0.25,
    maxStretch: 0.45,
  ),
  'rope_neon': RopeSpec(
    id: 'rope_neon',
    name: 'Shock Cord',
    blurb: 'Very elastic: soaks up bumps, slingshots the pod. Imprecise.',
    hookReach: 0.65,
    stiffnessHz: 1.1,
    dampingRatio: 0.2,
    maxStretch: 0.8,
  ),
  'rope_tractor': RopeSpec(
    id: 'rope_tractor',
    name: 'Tractor Beam',
    blurb: 'Locks on from range, no line. Burns fuel; rock breaks the beam.',
    kind: TowKind.beam,
    approachDistance: 3.4,
    beamRange: 2.8,
    beamHoldLength: 1.0,
    beamMaxAccel: 22,
    beamFuelFracPerSec: 0.004,
    stiffnessHz: 1.6,
    dampingRatio: 0.9,
  ),
};

RopeSpec ropeById(String id) => kRopes[id] ?? kStockRope;

/// Garage stat bars, each 0..1 (stock cable sits mid-scale where it can).
class RopeStats {
  const RopeStats({
    required this.reach,
    required this.give,
    required this.steadiness,
    required this.economy,
  });
  final double reach;
  final double give;
  final double steadiness;
  final double economy;

  static RopeStats of(RopeSpec r) {
    double c(double v) => v.clamp(0.05, 1.0);
    final reach = r.isBeam ? r.beamRange - 1.2 : r.hookReach - 0.25;
    return RopeStats(
      reach: c(reach / 1.6),
      give: r.isBeam ? 0.6 : c(r.maxStretch / 0.8),
      steadiness: r.isBeam
          ? 0.75
          : c(0.5 + r.swingDamping * 0.22 - r.maxStretch * 0.45),
      economy: r.isBeam ? 0.25 : c(1.0 - r.podMassAdd * 1.4),
    );
  }
}

/// Handling kits the player fits in the Garage (Handling tab). Sidegrades
/// like the tow gear: each one makes flying easier in one way and costs
/// fuel or tank for it. The autopilot, validator and 3★ checks fly stock.
class KitSpec {
  const KitSpec({
    required this.id,
    required this.name,
    required this.blurb,
    this.turnMul = 1,
    this.levelAssist = false,
    this.dampingAdd = 0,
    this.fuelDrainMul = 1,
    this.tankMul = 1,
  });

  final String id;
  final String name;

  /// One line for the Garage: what it's good at and what it costs.
  final String blurb;

  /// Multiplies the ship's turn rate (both stick speeds).
  final double turnMul;

  /// Eases the nose upright against local gravity when both controls are
  /// released, at a gentler rate than the Skate's built-in stabiliser.
  final bool levelAssist;

  /// Added to the hull's linear damping: drift dies away sooner, which
  /// makes stopping and hovering easier but caps top speed.
  final double dampingAdd;

  /// Multiplies fuel burn (assists draw power).
  final double fuelDrainMul;

  /// Multiplies tank size.
  final double tankMul;
}

/// The stock fit: exactly the ship as specified.
const kStockKit = KitSpec(id: 'kit_none', name: 'Standard Fit', blurb: 'The ship as delivered.');

const Map<String, KitSpec> kKits = {
  'kit_none': kStockKit,
  // Skate-style auto-level for any ship. Lets a beginner let go and recover;
  // the gyros cost 6% more fuel.
  'kit_gyro': KitSpec(
    id: 'kit_gyro',
    name: 'Gyro Stabiliser',
    blurb: 'Rights the ship when you let go. Burns 6% more fuel.',
    levelAssist: true,
    fuelDrainMul: 1.06,
  ),
  // +25% turn rate: a Kestrel flips in 0.8 s. The extra plumbing takes
  // 10% of the tank.
  'kit_verniers': KitSpec(
    id: 'kit_verniers',
    name: 'Vernier Thrusters',
    blurb: 'Turns 25% faster. Tank 10% smaller.',
    turnMul: 1.25,
    tankMul: 0.9,
  ),
  // +0.25 damping roughly doubles the Kestrel's (0.22): a 2.5 m/s drift
  // halves in ~1.5 s instead of ~3 s. Slower top speed, 8% more fuel.
  'kit_dampers': KitSpec(
    id: 'kit_dampers',
    name: 'Inertial Dampers',
    blurb: 'Drift dies away: easy stops and hovers. Slower, 8% more fuel.',
    dampingAdd: 0.25,
    fuelDrainMul: 1.08,
  ),
};

KitSpec kitById(String id) => kKits[id] ?? kStockKit;

/// Garage stat bars for a kit, each 0..1 (stock sits mid-scale).
class KitStats {
  const KitStats({
    required this.turn,
    required this.steady,
    required this.economy,
  });
  final double turn;
  final double steady;
  final double economy;

  static KitStats of(KitSpec k) {
    double c(double v) => v.clamp(0.05, 1.0);
    return KitStats(
      turn: c(0.5 * k.turnMul + (k.levelAssist ? 0.1 : 0)),
      steady: c(0.5 + k.dampingAdd * 1.4 + (k.levelAssist ? 0.25 : 0)),
      economy: c(0.6 - (k.fuelDrainMul - 1) * 4 - (1 - k.tankMul) * 3),
    );
  }
}
