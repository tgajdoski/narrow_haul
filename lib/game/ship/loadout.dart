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
    this.hookReach = 0.35,
    this.approachDistance = 2.5,
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

  /// Extra grab radius (m) around the nose hook. Also widens the
  /// centre-to-centre fallback by the same amount.
  final double hookReach;

  /// Ship–pod distance (m) at which the line starts to show.
  final double approachDistance;

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
  double get attachCenterDistance => 1.2 + (hookReach - 0.35);
}

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
    hookReach: 0.5,
    stiffnessHz: 4.5,
    dampingRatio: 0.35,
    maxStretch: 0.25,
  ),
  'rope_energy': RopeSpec(
    id: 'rope_energy',
    name: 'Magnetic Grapple',
    blurb: 'Grabs the pod from a hover. Springy: it bounces on stops.',
    hookReach: 0.9,
    approachDistance: 3.0,
    stiffnessHz: 2.5,
    dampingRatio: 0.25,
    maxStretch: 0.45,
  ),
  'rope_neon': RopeSpec(
    id: 'rope_neon',
    name: 'Shock Cord',
    blurb: 'Very elastic: soaks up bumps, slingshots the pod. Imprecise.',
    hookReach: 0.4,
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
    hookReach: 0.35,
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
    final reach = r.isBeam ? r.beamRange - 1.2 : r.hookReach;
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
