import 'dart:math' as math;

import 'package:narrow_haul/game/guidance/flight_drills.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

/// In-flight guidance, pure Dart. Every frame the game describes the flight
/// ([GuidanceInputs]) and [resolveGuidance] says what the HUD should point
/// at: a coach mark on a control (THRUST, the steering dial, FIRE), world
/// markers (turrets, the pod, the pad, a canister) and the star-target
/// frame. Spoken context (ship intro, star rules, route guide, scrapes) goes
/// through the comms line instead ([CommsQueue]).

/// The control a coach mark rings.
enum CoachTarget { thrust, dial, fire }

/// A callout on one control: what it does, its keys on desktop, and what it
/// costs.
class CoachMark {
  const CoachMark({
    required this.id,
    required this.target,
    required this.title,
    required this.detail,
    this.keys = const [],
    this.cost,
    this.glyph,
    this.confirmOnExit = true,
    this.subtle = false,
  });

  /// Stable id: the HUD restarts its animation only when this changes.
  final String id;
  final CoachTarget target;

  /// Caps label ('FIRE') and one short line ('Tap to knock out turrets').
  final String title;
  final String detail;

  /// Desktop keycaps ('F'); empty on touch.
  final List<String> keys;

  /// Fuel cost chip ('0.5% fuel / shot'); null = free.
  final String? cost;

  /// Weapon icon on the plate (a crate's weapon).
  final WeaponKind? glyph;

  /// A notice, not a lesson: the plate is lighter and see-through, so it
  /// never hides the flight.
  final bool subtle;

  /// The mark goes away because the pilot did the thing: ring collapses
  /// into the control with a tick. False for marks that just time out.
  final bool confirmOnExit;
}

/// What the pod's marker asks for.
enum PodTag { hook, lower }

/// The pad beacon: which of ship and pod are down.
class PadTag {
  const PadTag({required this.shipIn, required this.podIn});
  final bool shipIn;
  final bool podIn;

  @override
  bool operator ==(Object other) =>
      other is PadTag && other.shipIn == shipIn && other.podIn == podIn;

  @override
  int get hashCode => Object.hash(shipIn, podIn);
}

/// A crate just collected: its weapon, for a few seconds.
class CrateNotice {
  const CrateNotice({
    required this.kind,
    required this.name,
    required this.label,
    required this.amount,
  });
  final WeaponKind kind;

  /// 'Seeker Missile', the FIRE pad's 'SEEKER', and '×3' / '8 s'.
  final String name;
  final String label;
  final String amount;
}

/// The flight as guidance sees it.
class GuidanceInputs {
  const GuidanceInputs({
    this.demo = false,
    this.desktop = false,
    this.pointSteer = false,
    this.tiltSteer = false,
    this.tutorial = false,
    this.starRulesStep = false,
    this.thrustUsed = 0,
    this.rotateUsed = 0,
    this.attached = false,
    this.shipOnPad = false,
    this.podOnPad = false,
    this.armed = false,
    this.combatLevel = false,
    this.shotsFired = 0,
    this.levelStarred = false,
    this.fuelPerShotFrac = 0,
    this.crate,
    this.canisterUnseen = false,
    this.drill,
    this.noseDown = false,
  });

  final bool demo;
  final bool desktop;

  /// Point steering: the dial is dragged toward the nose's heading.
  final bool pointSteer;

  /// Steering by tilting the phone (Settings → Tilt steering).
  final bool tiltSteer;

  /// tut_01–03 before their first clear: the controls are taught.
  final bool tutorial;

  /// tut_02 waiting on the pad: the star rules (comms + target frame).
  final bool starRulesStep;

  /// Seconds the pilot has held thrust / turned so far this flight.
  final double thrustUsed;
  final double rotateUsed;

  final bool attached;
  final bool shipOnPad;
  final bool podOnPad;

  /// An armed ship on a level with turrets, before its first star.
  final bool armed;
  final bool combatLevel;
  final int shotsFired;
  final bool levelStarred;

  /// One cannon round as a share of the tank.
  final double fuelPerShotFrac;

  final CrateNotice? crate;

  /// The level has canisters and the pilot has never collected one.
  final bool canisterUnseen;

  /// The flight drill ring in progress (tut_01, before the first tow).
  final DrillView? drill;

  /// [NoseDownWatch] is warning: the nose points down and thrust or gravity
  /// is taking the ship toward the rock.
  final bool noseDown;
}

/// What the HUD shows this frame.
class Guidance {
  const Guidance({
    this.coach,
    this.markTurrets = false,
    this.pod,
    this.pad,
    this.markCanister = false,
    this.frameStarTarget = false,
    this.drill,
    this.noseUp = false,
  });

  final CoachMark? coach;
  final bool markTurrets;
  final PodTag? pod;
  final PadTag? pad;
  final bool markCanister;
  final bool frameStarTarget;

  /// The drill ring to fly to.
  final DrillView? drill;

  /// Show which way is up and the short turn back to it, on the ship.
  final bool noseUp;

  static const none = Guidance();
}

/// Seconds of thrust / turning after which the tutorial step counts as
/// learned.
const double kThrustLearned = 0.6;
const double kRotateLearned = 0.5;

Guidance resolveGuidance(GuidanceInputs i) {
  if (i.demo) return Guidance.none;

  final controlsTaught = !i.tutorial ||
      i.starRulesStep ||
      (i.thrustUsed >= kThrustLearned && i.rotateUsed >= kRotateLearned);

  CoachMark? coach;
  final crate = i.crate;
  if (crate != null) {
    coach = CoachMark(
      id: 'crate_${crate.kind.name}',
      target: CoachTarget.fire,
      title: '${crate.name.toUpperCase()} ${crate.amount}',
      detail: i.desktop ? 'Loaded. Fire with' : 'Loaded. Tap ${crate.label} to fire',
      keys: i.desktop ? const ['F'] : const [],
      glyph: crate.kind,
      confirmOnExit: false,
      subtle: true,
    );
  } else if (i.armed && i.combatLevel && i.shotsFired == 0 && !i.levelStarred) {
    coach = CoachMark(
      id: 'fire_turrets',
      target: CoachTarget.fire,
      title: 'FIRE',
      detail: i.desktop ? 'Knock out turrets' : 'Tap to knock out turrets',
      keys: i.desktop ? const ['F', 'ENTER'] : const [],
      cost: '${formatFuelPercent(i.fuelPerShotFrac)} fuel / shot',
      glyph: WeaponKind.cannon,
    );
  } else if (i.tutorial && !i.starRulesStep) {
    if (i.thrustUsed < kThrustLearned) {
      coach = CoachMark(
        id: 'thrust',
        target: CoachTarget.thrust,
        title: 'THRUST',
        detail: 'Hold to fire the engine',
        keys: i.desktop ? const ['↑', 'W', 'SPACE'] : const [],
      );
    } else if (i.rotateUsed < kRotateLearned) {
      coach = CoachMark(
        id: 'steer',
        target: CoachTarget.dial,
        title: 'STEER',
        detail: i.desktop
            ? 'Rotate the ship'
            : i.tiltSteer
                ? 'Tilt the phone like a wheel to rotate'
                : i.pointSteer
                ? 'Drag toward where the nose should point'
                : 'Drag left or right to rotate',
        keys: i.desktop ? const ['←', '→', 'A', 'D'] : const [],
      );
    }
  }

  // The both-on-pad rule, shown on the pad itself.
  PadTag? pad;
  PodTag? pod;
  if (i.shipOnPad != i.podOnPad) {
    pad = PadTag(shipIn: i.shipOnPad, podIn: i.podOnPad);
    if (i.shipOnPad) pod = PodTag.lower;
  } else if (i.tutorial && controlsTaught && i.drill == null) {
    if (!i.attached) {
      pod = PodTag.hook;
    } else if (!i.shipOnPad) {
      pad = const PadTag(shipIn: false, podIn: false);
    }
  }

  return Guidance(
    coach: coach,
    markTurrets: coach?.id == 'fire_turrets',
    pod: pod,
    pad: pad,
    markCanister: i.canisterUnseen && i.drill == null,
    frameStarTarget: i.starRulesStep,
    drill: i.attached ? null : i.drill,
    noseUp: i.noseDown,
  );
}

// ── Nose-down watch ──────────────────────────────────────────────────────────

/// Spots the classic beginner crash: the ship rolled past sideways, so the
/// engine (or gravity) drives it into the rock. Warns after the nose has
/// been more than [warnTilt] from local up for [warnAfter] seconds while
/// thrusting or falling, and stops once it's back within [clearTilt].
class NoseDownWatch {
  static const double warnTilt = 100;
  static const double clearTilt = 75;
  static const double warnAfter = 0.4;

  /// Falling faster than this (m/s along local down) counts as heading in.
  static const double fallSpeed = 0.5;

  double _over = 0;
  bool _warning = false;
  int _warnings = 0;

  bool get warning => _warning;

  /// Warnings this flight.
  int get warnings => _warnings;

  void reset() {
    _over = 0;
    _warning = false;
    _warnings = 0;
  }

  /// [tiltDeg]: nose to local up, 0–180. [downSpeed]: velocity along local
  /// down. Returns true when a new warning starts.
  bool update(
    double dt, {
    required double tiltDeg,
    required bool thrusting,
    required double downSpeed,
  }) {
    if (_warning) {
      if (tiltDeg <= clearTilt) {
        _warning = false;
        _over = 0;
      }
      return false;
    }
    final heading = thrusting || downSpeed > fallSpeed;
    _over = tiltDeg > warnTilt && heading ? _over + dt : 0;
    if (_over < warnAfter) return false;
    _warning = true;
    _warnings++;
    return true;
  }
}

/// Flights in a row without a nose-down warning before the lesson stops.
const int kNoseDownCleanFlights = 3;

/// '0.5%' under one percent, else whole percent.
String formatFuelPercent(double frac) {
  final pct = frac * 100;
  if (pct <= 0) return '0%';
  return pct < 1 ? '${pct.toStringAsFixed(1)}%' : '${pct.round()}%';
}

// ── Comms line ───────────────────────────────────────────────────────────────

/// One radio line: a callsign (TOWER for launch, landing and flying; OPS,
/// the company's dispatch, for the mission, the ship and the route) and a
/// sentence.
class CommsLine {
  const CommsLine({required this.id, required this.callsign, required this.text});
  final String id;
  final String callsign;
  final String text;
}

/// The comms queue: one line on air at a time, each id once per flight. It
/// types on, holds for its reading time, clears, and the radio stays quiet
/// for [gap] before the next line.
class CommsQueue {
  /// Typing speed (characters per second).
  static const double charsPerSecond = 60;

  /// Slide in / out.
  static const double fadeIn = 0.2;
  static const double fadeOut = 0.3;

  /// Quiet between two lines, so back-to-back lines read as separate calls.
  static const double gap = 0.6;

  /// (line, due time, drop time).
  final _pending = <(CommsLine, double, double)>[];
  final _said = <String>{};
  double _clock = 0;

  CommsLine? _current;
  double _onAir = 0;
  double _quiet = 0;

  /// The line on air (also while it slides out).
  CommsLine? get current => _current;

  /// Seconds the current line has been on air.
  double get onAir => _onAir;

  /// Ids said (or queued) this flight.
  bool hasSaid(String id) => _said.contains(id);

  /// Queue [line] unless its id was said this flight. [delay] counts from
  /// now; [urgent] jumps the queue (it still waits for the line on air).
  /// A line still waiting [expiresIn] seconds after it was due is dropped
  /// (situational help that would come too late).
  bool say(
    CommsLine line, {
    double delay = 0,
    bool urgent = false,
    double? expiresIn,
  }) {
    if (!_said.add(line.id)) return false;
    final due = _clock + delay;
    final entry = (line, due, expiresIn == null ? double.infinity : due + expiresIn);
    urgent ? _pending.insert(0, entry) : _pending.add(entry);
    return true;
  }

  /// A new flight: nothing on air, every line can be said again.
  void clear() {
    _pending.clear();
    _said.clear();
    _current = null;
    _onAir = 0;
    _quiet = 0;
    _clock = 0;
  }

  /// Seconds [line] stays up: typing, then about three words a second to
  /// read it plus a beat.
  static double holdSeconds(CommsLine line) {
    final words = line.text.split(RegExp(r'\s+')).length;
    return line.text.length / charsPerSecond + words / 3 + 1.5;
  }

  /// Returns true when a new line went on air this step.
  bool update(double dt) {
    _clock += dt;
    final cur = _current;
    if (cur != null) {
      _onAir += dt;
      if (_onAir >= holdSeconds(cur) + fadeOut) {
        _current = null;
        _onAir = 0;
        _quiet = gap;
      } else {
        return false;
      }
    }
    _pending.removeWhere((e) => e.$3 < _clock);
    if (_quiet > 0) {
      _quiet -= dt;
      return false;
    }
    final i = _pending.indexWhere((e) => e.$2 <= _clock);
    if (i < 0) return false;
    _current = _pending.removeAt(i).$1;
    _onAir = 0;
    return true;
  }

  /// Characters typed so far.
  int get visibleChars {
    final cur = _current;
    if (cur == null) return 0;
    return math.min(cur.text.length, (_onAir * charsPerSecond).floor());
  }

  /// 0–1: slides in, holds, slides out.
  double get alpha {
    final cur = _current;
    if (cur == null) return 0;
    final hold = holdSeconds(cur);
    if (_onAir < fadeIn) return _onAir / fadeIn;
    if (_onAir > hold) return (1 - (_onAir - hold) / fadeOut).clamp(0.0, 1.0);
    return 1;
  }
}
