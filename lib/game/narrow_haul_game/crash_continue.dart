part of '../narrow_haul_game.dart';

/// Crashes, rewarded / free continues and the rewind snapshots.
extension GameCrashContinue on NarrowHaulGame {
  void _onShipHitWall({String cause = 'wall'}) {
    if (runState != RunState.playing || demoMode) return;
    if (cause != 'meltdown' && _salvageAbsorbs()) return;
    _luckyCoins = 0; // Lucky Salvage pays only on delivery
    final wreck = ship?.body.position;
    final tilt = ship?.tiltFromUpDeg ?? 0;
    final kind = classifyCrash(
      cause: cause,
      rock: ship?.lastHitRock ?? true,
      tiltDeg: tilt,
      groundCos: ship?.lastHitGroundCos ?? 0,
    );
    lastCrashKind = kind;
    Analytics.levelFail(
      levelId: currentLevelDef.saveId,
      cause: cause,
      attempt: _attempt,
      seconds: elapsedSeconds,
      fuelLeft: (ship?.fuel ?? 0) / _shipMaxFuel,
      towing: cargoAttachment?.attached ?? false,
      x: wreck?.x.floor() ?? 0,
      y: wreck?.y.floor() ?? 0,
      mode: _analyticsMode,
      crashKind: kind.name,
      tilt: tilt.round(),
    );
    crashStreak.onCrash(currentLevelDef.saveId);
    _currentLevelRetried = true;
    _recordSpentFuel();
    _recordPlaytime();
    _payInFlightAchievementXp();
    final progress = ProgressService.instance;
    progress.incrementStat(ProgressService.statCrashes);
    // Reset no-retry streak
    progress.setNoRetryStreak(0);
    AudioService.playCrash();
    Haptics.heavy();
    _resetInputState();
    runState = RunState.gameOver;
    PerfMonitor.flightEnded('crashed');
    _pauseButton?.visible = false;
    _clearGuidance();
    _meltdownAtCrash = _meltdownLeft;
    _crashElapsed = elapsedSeconds;
    _meltdownLeft = null;
    _turretsOfflineLeft = 0;
    _syncCombatHud();

    // Let the wreck play out (explosion + shake) before the dialog; the
    // overlay is raised from update() when [_crashTimer] runs out.
    final s = ship;
    if (s != null) {
      s.wreck();
      final p = s.body.position;
      final burst = ExplosionBurst(
        center: Offset(p.x, p.y),
        accent: currentLevel?.theme.uiAccent ?? HudColors.warn,
        seed: levelIndex,
      );
      world.add(burst);
      _levelEntities.add(burst);
    }
    _cam.shake.add(1);
    _crashTimer = NarrowHaulGame._crashDelay;
  }

  bool get canContinue =>
      runState == RunState.gameOver &&
      !_trainingRetryFree &&
      !_continueUsed &&
      !_crashedByMeltdown &&
      (ship?.launched ?? false) &&
      _pickSnapshot() != null;

  /// Rewinds to the last safe point before the crash: same ship, same world
  /// (destroyed turrets, collected fuel cells and a running meltdown stay as
  /// they were), ship at rest with a fuel top-up and turrets briefly quiet.
  /// The clock keeps running and the run is capped at 2★.
  void continueAfterCrash() => _resumeAfterCrash(free: false);

  bool get _trainingRetryFree =>
      !isChallengeMode &&
      !demoMode &&
      currentLevelDef is TmxLevelDef &&
      levelIndex < NarrowHaulGame._freeRetryLevels;

  bool get canFreeContinue =>
      runState == RunState.gameOver &&
      _trainingRetryFree &&
      !_crashedByMeltdown &&
      (ship?.launched ?? false) &&
      _pickSnapshot() != null;

  /// "Try again from here" (Training): the continue rewind, free and
  /// upright.
  void freeContinue() => _resumeAfterCrash(free: true);

  /// The crash screen's one line of advice.
  String? get crashAdvice {
    final k = lastCrashKind;
    return k == null ? null : crashTip(k);
  }

  void _resumeAfterCrash({required bool free}) {
    final snap = _pickSnapshot();
    final s = ship;
    final c = cargo;
    if (!(free ? canFreeContinue : canContinue) ||
        snap == null ||
        s == null ||
        c == null) {
      return;
    }
    if (!free) {
      _continueUsed = true;
      continuedThisRun = true;
    }
    // A crash is never flawless, even when a free rewind keeps 3★ open.
    wallScrapesThisRun++;
    _rewoundThisRun = true;
    overlays.remove(OverlayIds.gameOver);

    // Shells in flight would make the respawn a trap.
    for (final shell in world.children.whereType<Shell>().toList()) {
      shell.removeFromParent();
    }
    s.revive(
      position: snap.shipPos,
      // A free (Training) retry starts upright: the pilot may have rolled
      // over just before the crash.
      angle: free ? math.atan2(-s.localAccel.x, s.localAccel.y) : snap.shipAngle,
      fuel: math.min(s.maxFuel, snap.fuel + NarrowHaulGame._continueFuelBonus * s.maxFuel),
    );
    c.body
      ..setTransform(snap.cargoPos, snap.cargoAngle)
      ..linearVelocity.setZero()
      ..angularVelocity = 0;
    _fuelBaseline = s.fuel;
    elapsedSeconds = _crashElapsed;
    _timing = true;
    _meltdownLeft = _meltdownAtCrash;
    // The quiet spell starts at GO, not when the countdown does.
    _turretsOfflineLeft = math.max(
      _turretsOfflineLeft,
      NarrowHaulGame._resumeCountdownSeconds + NarrowHaulGame._continueTurretGrace,
    );
    _syncCombatHud();
    _snapshots.reset();
    // A free retry can rewind to the same spot again straight away.
    if (free) _snapshots.add(snap);
    _cam.shake.clear();
    _crashTimer = 0;
    _resetSalvage();
    _resetInputState();
    runState = RunState.playing;
    _pauseButton?.visible = true;
    // A wreck that slid onto the pad was refused; re-arm the pad, and land
    // straight away if the rewind put ship and pod on it.
    _landingZone
      ?..reset()
      ..recheck();
    // Don't surprise the pilot: hover (pod held too) on 3 · 2 · 1 · GO;
    // any input flies on at once.
    s.hold();
    if ((cargoAttachment?.attached ?? false) &&
        c.body.bodyType == BodyType.dynamic) {
      c.lock();
      _podHeldForResume = c;
    }
    _countdown = NarrowHaulGame._resumeCountdownSeconds;
    _countdownDone = false;
    resumeEngine();
  }

  /// Frees the pod parked for a continue's countdown.
  void _endResumeHold() {
    _podHeldForResume?.release();
    _podHeldForResume = null;
  }

  /// Newest snapshot well before the crash with the same tow state (so the
  /// rope never has to snap to a different length); else the newest one.
  FlightSnapshot? _pickSnapshot() => _snapshots.pick(
    attached: cargoAttachment?.attached ?? false,
    crashTime: _crashElapsed,
    rewind: NarrowHaulGame._continueRewind,
  );

  void _sampleSnapshot(double dt, ShipBody s) {
    if (!s.launched || isPaused) return;
    if (!_snapshots.due(dt)) return;
    final c = cargo;
    if (c == null || !_isSafeSpot(s, c)) return;
    _snapshots.add(
      FlightSnapshot(
        time: elapsedSeconds,
        shipPos: s.body.position.clone(),
        shipAngle: s.body.angle,
        fuel: s.fuel,
        cargoPos: c.body.position.clone(),
        cargoAngle: c.body.angle,
        attached: cargoAttachment?.attached ?? false,
      ),
    );
  }

  /// Clear of terrain/obstacles all round and not in a strong pull (well
  /// cores, heavy zones) — the ship respawns at rest, so it must be able to
  /// fly away from here.
  bool _isSafeSpot(ShipBody s, CargoBody c) {
    final base = world.gravity.length;
    if (s.localAccel.length > math.max(1.6 * base, 0.6)) return false;
    final p = s.body.position;
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final to = p + Vector2(math.cos(a), math.sin(a)) * NarrowHaulGame._safeClearance;
      if (!hasLineOfSight(world, p, to, ignore: c.body)) return false;
    }
    return true;
  }
}
