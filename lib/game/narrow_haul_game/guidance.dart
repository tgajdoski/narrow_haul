part of '../narrow_haul_game.dart';

/// In-flight guidance: coach marks, world markers, comms, drills, story.
extension GameGuidance on NarrowHaulGame {
  /// Coach marks and world markers for this frame ([resolveGuidance]); the
  /// route-guide comms once the guide is on.
  void _updateGuidance(ShipBody s) {
    final zone = _landingZone;
    final crate = _crateNotice;
    final g = resolveGuidance(GuidanceInputs(
      demo: demoMode,
      desktop: _desktop,
      pointSteer: FlightTuning.steer.isPointer,
      tiltSteer: FlightTuning.tilt,
      tutorial: _tutorialHints,
      starRulesStep: _starRulesStep && !s.launched,
      thrustUsed: _thrustUsed,
      rotateUsed: _rotateUsed,
      attached: cargoAttachment?.attached == true,
      shipOnPad: zone?.shipInside ?? false,
      podOnPad: zone?.cargoInside ?? false,
      armed: s.spec.armed,
      combatLevel: currentLevel?.hasCombat == true,
      shotsFired: s.shotsFired,
      levelStarred:
          ProgressService.instance.getStarsById(currentLevelDef.saveId) > 0,
      fuelPerShotFrac: s.spec.fuelPerShot * s.fuelDrainMultiplier / s.maxFuel,
      crate: crate,
      canisterUnseen: _pickupHint() != null,
      drill: _drills?.view,
      noseDown: _noseDownLesson && _noseDown.warning,
    ));
    _coach?.mark = g.coach;
    _levelInfoHud?.frameTarget = g.frameStarTarget;

    final m = _markers;
    if (m != null) {
      m
        ..zoom = camera.viewfinder.zoom
        ..turrets = g.markTurrets
            ? [
                for (final c in _turrets)
                  if (!c.destroyed) Offset(c.spec.base.x, c.spec.base.y),
              ]
            : const []
        ..turretRadius = Turret.domeRadius
        ..podTag = g.pod
        ..pod = _cargoPos()
        ..padCenter = zone == null ? null : Offset(zone.padCenter.x, zone.padCenter.y)
        ..pad = g.pad
        ..canister = g.markCanister ? _nearestCanister(s) : null
        ..podRadius = CargoBody.radius
        ..drill = g.drill
        ..shipAt = Offset(s.body.position.x, s.body.position.y)
        ..noseUp = g.noseUp && s.localAccel.length2 > 1e-4
            ? NoseUpCue(
                nose: Offset(s.noseDir.x, s.noseDir.y),
                up: Offset(-s.localAccel.x, -s.localAccel.y) /
                    s.localAccel.length,
              )
            : null;
    }

    if (routeGuideOn &&
        s.spec.armed &&
        !demoMode &&
        (currentRoute?.shots.isNotEmpty ?? false)) {
      _comms?.say(
        const CommsLine(
          id: 'route',
          callsign: 'OPS',
          text: 'Route is on your screen. Hold at each red ⊕ and fire along its '
              'dashes. Red dots are under fire.',
        ),
        delay: NarrowHaulGame._commsAfterIntro,
        expiresIn: NarrowHaulGame._commsHelpExpiry,
      );
    }
  }

  Offset? _cargoPos() {
    final c = cargo;
    if (c == null) return null;
    final p = c.body.position;
    return Offset(p.x, p.y);
  }

  Offset? _nearestCanister(ShipBody s) {
    final p = s.body.position;
    Offset? best;
    var bestD = double.infinity;
    for (final c in _fuelCells) {
      if (c.collected) continue;
      final d = (c.spec.pos.x - p.x) * (c.spec.pos.x - p.x) +
          (c.spec.pos.y - p.y) * (c.spec.pos.y - p.y);
      if (d < bestD) {
        bestD = d;
        best = Offset(c.spec.pos.x, c.spec.pos.y);
      }
    }
    return best;
  }

  /// tut_02 before its first clear: the star rules are explained on the pad.
  bool get _starRulesStep => _tutorialHints && levelIndex == 1;

  /// The comms lines a flight opens with, after the intro card.
  void _scheduleComms({required bool retry}) {
    _storyThisFlight = false;
    final comms = _comms;
    if (comms == null || demoMode) return;
    const afterIntro = NarrowHaulGame._commsAfterIntro;
    final saveId = currentLevelDef.saveId;
    _storyThisFlight = !isChallengeMode &&
        !retry &&
        ProgressService.instance.getStarsById(saveId) == 0 &&
        _storyToldThisSession.add(saveId);
    final drill = _drills?.current;
    if (drill != null) {
      comms.say(
        CommsLine(id: 'drill_${_drills!.index}', callsign: 'TOWER', text: drill.tower),
        delay: afterIntro,
      );
    }
    if (_starRulesStep) {
      comms.say(
        const CommsLine(
          id: 'stars',
          callsign: 'TOWER',
          text: 'Stars: ★ deliver, ★★ save fuel, ★★★ save more and beat the '
              'clock. Your target is under the fuel bar.',
        ),
        delay: afterIntro,
      );
    }
    final shipHint = _shipHint();
    if (shipHint != null && !retry) {
      comms.say(CommsLine(id: 'ship', callsign: 'OPS', text: shipHint), delay: afterIntro);
    }
    _sayStory(BeatCue.start, after: afterIntro);
    if (_pickupHint() != null && !retry) {
      comms.say(
        const CommsLine(
          id: 'canister',
          callsign: 'OPS',
          text: 'Fuel canister marked. Fly through it to top up the tank.',
        ),
        delay: afterIntro,
        expiresIn: NarrowHaulGame._commsHelpExpiry,
      );
    }
    // The first flight of an app session names the camera, so players learn
    // there are others. Last in the queue: it drops if it would air late.
    if (!retry && !isChallengeMode && !_tutorialHints && !_cameraTipToldThisSession) {
      _cameraTipToldThisSession = true;
      comms.say(
        CommsLine(
          id: 'camera',
          callsign: 'TOWER',
          text: 'Camera: ${FlightTuning.camera.label}. '
              'Change it any time in Pause → Settings → Camera.',
        ),
        delay: afterIntro,
        expiresIn: NarrowHaulGame._commsHelpExpiry,
      );
    }
  }

  /// The mission's story beats for [cue] (docs/STORY.md): until the
  /// mission's first clear, once per app session, and not on a retry, a
  /// demo or a daily.
  void _sayStory(BeatCue cue, {double after = 0, int? leg}) {
    final comms = _comms;
    if (comms == null || !_storyThisFlight) return;
    final story = storyFor(currentLevelDef.saveId);
    if (story == null) return;
    final atLeg = leg ?? legIndex;
    for (final (i, b) in story.beats.indexed) {
      if (b.cue != cue || (b.leg != null && b.leg != atLeg)) continue;
      comms.say(
        CommsLine(id: 'story_$i', callsign: b.callsign, text: b.text),
        delay: after + b.delay,
      );
    }
  }

  void _setUpDrills(LevelData data) {
    final id = currentLevelDef.saveId;
    if (_drillLevel != id) {
      _drillLevel = id;
      _drillStart = 0;
      _drillsOver = false;
    }
    _drills = _tutorialHints && !_drillsOver && data.drills.isNotEmpty
        ? DrillCourse(data.drills, start: _drillStart)
        : null;
  }

  /// Advances the drill rings; hooking the pod ends them.
  void _updateDrills(double dt, ShipBody s) {
    final d = _drills;
    if (d == null || d.done) return;
    final id = currentLevelDef.saveId;
    if (cargoAttachment?.attached ?? false) {
      d.skip();
      _drillsOver = true;
      Analytics.tutorialStep('drills_skipped', levelId: id);
      return;
    }
    final p = s.body.position;
    final event = d.update(
      dt,
      DrillShip(
        pos: Pt(p.x, p.y),
        speed: s.body.linearVelocity.length,
        tiltDeg: s.tiltFromUpDeg,
        launched: s.launched,
      ),
    );
    if (event == null) return;
    if (event != DrillEvent.skipped) {
      _drillStart = d.index;
      Analytics.tutorialStep('drill_${d.index}', levelId: id);
      AudioService.playPickup();
      Haptics.light();
    }
    final next = d.current;
    if (next != null) {
      _comms?.say(
        CommsLine(id: 'drill_${d.index}', callsign: 'TOWER', text: next.tower),
        urgent: true,
      );
      return;
    }
    _drillsOver = true;
    final skipped = event == DrillEvent.skipped;
    Analytics.tutorialStep(skipped ? 'drills_skipped' : 'drills_done', levelId: id);
    _comms?.say(
      CommsLine(
        id: 'drills_end',
        callsign: 'TOWER',
        text: skipped
            ? 'Good enough for now. Go and hook the pod: hover low over it.'
            : 'Nicely flown. Now the pod: hover low over it and the hook '
                'catches it.',
      ),
      urgent: true,
    );
  }

  /// Nose pointing down while thrusting or falling: TOWER calls it once a
  /// flight while the lesson runs; any warning restarts the lesson.
  void _updateNoseDown(double dt, ShipBody s) {
    if (!s.launched) return;
    final started = _noseDown.update(
      dt,
      tiltDeg: s.tiltFromUpDeg,
      thrusting: thrustHeld,
      downSpeed: s.downSpeed,
    );
    if (!started) return;
    unawaited(ProgressService.instance.setNoseDownCleanFlights(0));
    if (!_noseDownLesson) return;
    Haptics.light();
    _comms?.say(
      const CommsLine(
        id: 'nose_down',
        callsign: 'TOWER',
        text: 'Nose down! The engine pushes where the nose points. '
            'Turn back toward up before you burn.',
      ),
      urgent: true,
      expiresIn: 2,
    );
  }

  void _clearGuidance() {
    _coach?.clear();
    _markers?.clear();
    _comms?.clear();
    _levelInfoHud?.frameTarget = false;
  }

  /// A ship's first flight (`LevelRegistry.isShipNew`: its rating level, a
  /// bought ship, a Test Flight daily): one line on how it handles. It counts
  /// as heard once it airs (`CommsHud.onLine`).
  String? _shipHint() {
    final spec = ship?.spec;
    if (spec == null || demoMode || !LevelRegistry.isShipNew(spec.id)) return null;
    return "You're flying the ${spec.name}. ${spec.blurb}";
  }

  /// Until the first canister ever is collected, on levels that have one.
  String? _pickupHint() {
    if (demoMode || (currentLevel?.pickups.isEmpty ?? true)) return null;
    if (ProgressService.instance.getStat(ProgressService.statFuelCells) > 0) {
      return null;
    }
    return 'Fly through a fuel canister to top up your tank';
  }
}

bool get _desktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);
