part of '../narrow_haul_game.dart';

/// Expedition legs: per-leg tow and pad, advancing, pad checkpoints.
extension GameExpeditionLegs on NarrowHaulGame {
  /// Pad callback: accepts the delivery only mid-flight, so a wreck sliding
  /// onto the pad (or a demo) leaves the zone armed for a later landing.
  bool _onBothLanded() {
    if (runState != RunState.playing || demoMode) return false;
    if (legIndex < legCount - 1) {
      // Contacts fire inside the physics step, where bodies can't change
      // type: the next frame moves on.
      _legLanded = true;
      return true;
    }
    unawaited(_onGoalReached());
    return true;
  }

  /// The tow line of [pod] (one per leg).
  CargoAttachment _towFor(ShipBody s, CargoBody pod, LevelData data) => CargoAttachment(
        ship: s,
        cargo: pod,
        ropeMaxLengthMeters: data.ropeMaxLength * s.spec.ropeLengthMul,
        rope: ropeById(CosmeticsService.getEquippedId(CosmeticsService.catRope)),
        onAttached: () {
          AudioService.playAttach();
          Haptics.light();
          _hookPulse(s, pod);
          _towTipOnce();
          _sayStory(BeatCue.hooked);
          if (_tutorialHints && !_hookLogged) {
            _hookLogged = true;
            Analytics.tutorialStep('hooked', levelId: currentLevelDef.saveId);
          }
        },
      )
        ..onBeamLost = Haptics.medium
        ..onReleased = () {
          Haptics.light();
          AudioService.playUi(UiSound.back);
        };

  /// The first hook-up past the Training Grounds: TOWER names the TOW pad
  /// once ever (`once_tow_tip`, cloud-synced).
  void _towTipOnce() {
    if (demoMode || isChallengeMode || !LevelRegistry.trainingComplete) return;
    final desktop = _desktop;
    unawaited(ProgressService.instance.markOnce('tow_tip').then((first) {
      if (!first) return;
      _comms?.say(CommsLine(
        id: 'tow_tip',
        callsign: 'TOWER',
        text: desktop
            ? 'Line control is yours: E drops the pod, Z and X reel it in and out.'
            : 'Line control is yours: tap TOW to drop the pod, drag it to reel the line.',
      ));
    }));
  }

  /// The hook-up "clamp": a ring at the winch, then one round the pod.
  void _hookPulse(ShipBody s, CargoBody pod) {
    final color = currentLevel?.theme.uiAccent ?? HudColors.cyan;
    Offset winch() {
      final p = s.body.worldPoint(Vector2(0, s.rearLocalY));
      return Offset(p.x, p.y);
    }

    Offset podAt() {
      final p = pod.body.worldCenter;
      return Offset(p.x, p.y);
    }

    for (final ring in [
      PulseRing(at: winch, color: color, endRadius: 0.55, life: 0.35),
      PulseRing(at: podAt, color: color, delay: 0.1, startRadius: 0.3, endRadius: 0.95),
    ]) {
      world.add(ring);
      _levelEntities.add(ring);
    }
  }

  /// The win sensors of [leg]'s pad.
  DualLandingZone _padFor(LegData leg) => DualLandingZone(
        padCenter: leg.goalCenter,
        halfWidth: leg.goalHalfWidth,
        halfHeight: leg.goalHalfHeight,
        onBothLanded: _onBothLanded,
      );

  /// An Expedition leg landed on its staging pad: the pod is parked, the
  /// crew refuels the ship, the pad becomes the checkpoint, and the next
  /// leg's pod and pad go live.
  void _advanceLeg() {
    final data = currentLevel, s = ship, delivered = cargo;
    if (data == null || s == null || delivered == null) return;
    final landed = data.legs[legIndex];
    _legFuelLeft.add(s.fuel / _shipMaxFuel);

    cargoAttachment?.removeFromParent();
    // A pad counts on touch, so the pod may still be swinging over its edge:
    // the crew sets it down on the deck (where a resume parks it too).
    delivered.lock(at: landed.parkedPod);
    _landingZone?.removeFromParent();

    _recorder?.leg();
    legIndex++;
    _checkpointLeg = legIndex;
    _checkpointElapsed = elapsedSeconds;
    _checkpointFuel = List.of(_legFuelLeft);
    s.fuel = s.maxFuel;
    // A continue never rewinds across a pad.
    _snapshots.clear();

    final next = data.legs[legIndex];
    final pod = _pods[legIndex];
    final link = _towFor(s, pod, data);
    final zone = _padFor(next);
    for (final c in [link, zone]) {
      _levelEntities.add(c);
      world.add(c);
    }
    cargo = pod;
    cargoAttachment = link;
    _landingZone = zone;
    _forces?.cargo = pod;

    final burst = CelebrationBurst(
      center: Offset(landed.goalCenter.x, landed.goalCenter.y),
      accent: data.theme.uiAccent,
      seed: levelIndex + legIndex,
    );
    world.add(burst);
    _levelEntities.add(burst);
    AudioService.playStar();
    Haptics.medium();
    _comms?.say(
      CommsLine(
        id: 'leg_$legIndex',
        callsign: 'OPS',
        text: 'Pod $legIndex delivered. Tanks full, this pad saves your place. '
            'Leg ${legIndex + 1} of $legCount: pod marked.',
      ),
      urgent: true,
    );
    _sayStory(BeatCue.landed, leg: legIndex - 1);
    _updateLevelInfoHud();
  }

  /// Demo: the recorded flight landed a leg; park its pod, tow the next.
  void _demoNextLeg() {
    final data = currentLevel, s = ship;
    if (data == null || s == null) return;
    cargoAttachment?.removeFromParent();
    cargo?.lock(at: data.legs[legIndex].parkedPod);
    legIndex++;
    final pod = _pods[legIndex];
    final link = _towFor(s, pod, data)..scriptedTow = () => _demoTowing;
    _levelEntities.add(link);
    world.add(link);
    cargo = pod;
    cargoAttachment = link;
    _forces?.cargo = pod;
    _updateLevelInfoHud();
  }

  /// Game over on an Expedition after a staging pad: fly on from there.
  bool get canResumeFromPad =>
      !demoMode && !isChallengeMode && isExpeditionRun && _checkpointLeg > 0;

  /// The staging pad [resumeFromPad] starts from (1 = the first pad).
  int get checkpointPad => _checkpointLeg;

  /// Reloads the Expedition at its last staging pad: earlier pods parked,
  /// the clock and their fuel record kept, the run capped at 2★.
  Future<void> resumeFromPad() {
    _resumeLeg = _checkpointLeg;
    return restartLevel();
  }
}
