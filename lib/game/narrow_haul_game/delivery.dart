part of '../narrow_haul_game.dart';

/// Delivery: booking the run (stars, XP, coins, stats, achievements).
extension GameDelivery on NarrowHaulGame {
  /// Books a delivery. A failure while saving (prefs, contracts,
  /// achievements) is reported and still raises the result screen, without
  /// the XP panel, so the flight never freezes on the pad.
  Future<void> _onGoalReached() async {
    if (runState != RunState.playing || demoMode) return;
    // Claim the win before any await so a second contact can't re-enter.
    runState = RunState.won;
    PerfMonitor.flightEnded('delivered');
    lastRunReward = null;
    try {
      await _bookDelivery();
      GamesService.progressChanged();
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'delivery ${currentLevelDef.saveId}');
      lastRunReward = null;
      _resetInputState();
      if (runState == RunState.won) _winReady = true;
    }
  }

  Future<void> _bookDelivery() async {
    debugBeforeBooking?.call();

    final elapsed = elapsedSeconds;
    final reactorEscape = _reactorDestroyed && _meltdownLeft != null;
    _meltdownLeft = null;
    _turretsOfflineLeft = 0;
    _syncCombatHud();
    _pauseButton?.visible = false;
    _clearGuidance();
    Haptics.medium();
    ship?.setInput(rotate: 0, thrust: false);
    _resetInputState();
    final goal = currentLeg?.goalCenter;
    if (goal != null) {
      final burst = CelebrationBurst(
        center: Offset(goal.x, goal.y),
        accent: currentLevel!.theme.uiAccent,
        seed: levelIndex,
      );
      world.add(burst);
      _levelEntities.add(burst);
    }
    _winTimer = NarrowHaulGame._winDelay;
    _winReady = false;
    // A slow push-in on ship and pod sitting on the pad.
    if (!FlightTuning.camera.profile.isStatic && !kStoreCapture) {
      _cam.pushInForDelivery(NarrowHaulGame._winDelay);
    }
    // An Expedition rates the fuel left on every pad, not just the last.
    final fuelLeft = _legFuelLeft.isEmpty
        ? ship?.fuel ?? 0.0
        : ([..._legFuelLeft, (ship?.fuel ?? 0) / _shipMaxFuel].reduce((a, b) => a + b) /
                (_legFuelLeft.length + 1)) *
            _shipMaxFuel;
    lastLevelFuelFraction = fuelLeft / _shipMaxFuel;

    _recordSpentFuel();
    _recordPlaytime();

    final stars = _calculateStars(fuelLeft, elapsed);
    lastLevelStars = stars;
    lastLevelTimeSeconds = elapsed;
    crashStreak.onDelivered();
    final s = ship;
    final c = cargo;
    if (s != null && c != null) {
      lastFlightRoute = _recorder?.finish(
        x: s.body.position.x,
        y: s.body.position.y,
        angle: s.body.angle,
        cx: c.body.position.x,
        cy: c.body.position.y,
        seconds: elapsed,
        stars: stars,
        fuelLeft: lastLevelFuelFraction,
      );
    }
    // Calibration line for the autopilot report (test/autopilot): a real
    // pilot's fuel/time next to the bot's.
    if (kDebugMode) {
      debugPrint('RUN ${currentLevelDef.saveId} ship=${ship?.spec.id} '
          'fuelLeft=${(lastLevelFuelFraction * 100).toStringAsFixed(1)}% '
          'time=${elapsed.toStringAsFixed(1)}s stars=$stars'
          '${continuedThisRun ? ' (continued)' : ''}');
    }

    _attemptLevel = null; // the next flight here is a fresh attempt series
    _lastWinDailyFirst = false;
    _currencyDoubled = false;
    final s2 = ship;
    final booking = await DeliveryBooker.book(
      DeliveryFacts(
        level: currentLevelDef,
        levelIndex: levelIndex,
        challenge: isChallengeMode,
        challengeShipId: activeChallengeConfig?.shipId,
        stars: stars,
        seconds: elapsed,
        fuelLeft: fuelLeft,
        maxFuel: _shipMaxFuel,
        attempt: _attempt,
        guided: guidedThisRun,
        continued: continuedThisRun,
        carriedAmmo: carriedWeaponUsedThisRun,
        mode: _analyticsMode,
        shipId: s2?.spec.id ?? '',
        noseDownWarnings: _noseDown.warnings,
        steer: FlightTuning.tilt ? 'tilt' : FlightTuning.steer.name,
        retried: _currentLevelRetried,
        turretsDestroyed: _turretsDestroyed,
        salvageOpened: _salvageOpenedThisRun,
        curses: List.of(_cursesThisRun),
        luckyCoins: _luckyCoins,
        reactorEscape: reactorEscape,
        inFlightAchievements: List.of(_inFlightAchievements),
        heldFire: s2 != null &&
            s2.spec.armed &&
            s2.shotsFired == 0 &&
            currentLevel?.hasCombat == true,
        fields: currentLevel?.fields ?? const <FieldSpec>[],
        gravityG: _levelGravityG,
        flyingParShip: flyingParShip,
        salvageEffect: salvage.effect,
        shipSizeMul: s2?.sizeMul ?? 1,
        scrapes: wallScrapesThisRun,
        ratedFuel: _ratedFuelFraction(fuelLeft),
      ),
    );
    _inFlightAchievements.clear();
    _keepPersonalBestRoute();
    _lastWinDailyFirst = booking.dailyFirst;
    _syncAnalyticsUser();
    lastRunReward = booking.reward;

    // The star sounds play on the result screen, one per star.
    AudioService.playLand();
    MusicService.play(MusicService.resultsTrack, MusicService.resultsVolume);

    _resetInputState();
    // update() raises the dialog once the celebration has played.
    _winReady = true;
  }

  /// A faster own flight becomes this level's ghost: career runs in the
  /// par ship only, flown straight through (no continue, rewind, guide or
  /// checkpoint), so the ghost is always a real, clean line to chase.
  void _keepPersonalBestRoute() {
    final route = lastFlightRoute;
    if (route == null ||
        isChallengeMode ||
        demoMode ||
        !flyingParShip ||
        guidedThisRun ||
        continuedThisRun ||
        checkpointUsedThisRun ||
        _rewoundThisRun) {
      return;
    }
    unawaited(PersonalBestRoutes.saveIfBest(route));
  }

  /// Player-level dimensions for every report (set at launch and after
  /// each delivery).
  void _syncAnalyticsUser() {
    final p = ProgressService.instance;
    Analytics.setUserProperty('pilot_rank', '${rankFor(p.getXp()).index}');
    Analytics.setUserProperty('total_stars', '${LevelRegistry.totalStars()}');
    Analytics.setUserProperty('payer', p.hasPurchased ? '1' : '0');
  }

  /// The fuel fraction the stars rate: another ship than the level's own
  /// has its fuel scaled by range (fleet.dart).
  double _ratedFuelFraction(double fuelRemaining) {
    final flown = ship?.spec;
    final fuelLeft = fuelRemaining / _shipMaxFuel;
    return flown == null || isChallengeMode
        ? fuelLeft
        : normalisedFuelLeft(fuelLeft, flown, LevelRegistry.shipFor(levelIndex));
  }

  int _calculateStars(double fuelRemaining, double timeSeconds) {
    // A continued (rewarded ad) or guided run can never buy a perfect rating.
    return currentLevelDef.stars.rate(
      _ratedFuelFraction(fuelRemaining),
      timeSeconds,
      capped: continuedThisRun ||
          guidedThisRun ||
          carriedWeaponUsedThisRun ||
          checkpointUsedThisRun,
    );
  }

  void _onAchievementAnnounced() {
    final a = AchievementService.announced.value;
    if (a != null && runState == RunState.playing) _inFlightAchievements.add(a);
  }

  void _payInFlightAchievementXp() {
    if (_inFlightAchievements.isEmpty) return;
    ProgressService.instance.addXp(100 * _inFlightAchievements.length);
    for (final a in _inFlightAchievements) {
      Analytics.achievement(a.id);
    }
    _inFlightAchievements.clear();
  }

  void _recordPlaytime() {
    if (!_timing) return;
    _timing = false; // stop the clock; also prevents double counting
    // After a continue, only the seconds not yet booked at the crash count.
    final seconds = elapsedSeconds.floor() - _playtimeBooked;
    _playtimeBooked = elapsedSeconds.floor();
    if (seconds > 0) {
      ProgressService.instance.incrementStat(
        ProgressService.statPlaytimeSeconds,
        seconds,
      );
    }
  }

  void _recordSpentFuel() {
    if (ship != null) {
      final spent = _fuelBaseline - ship!.fuel;
      if (spent > 0) {
        ProgressService.instance.addFuelSpent(spent);
        ship!.fuel = ship!.maxFuel; // prevent double counting
        _fuelBaseline = ship!.maxFuel;
      }
    }
  }
}
