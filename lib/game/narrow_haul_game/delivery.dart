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
      _closeUp.pushIn(reducedMotion ? 1.2 : NarrowHaulGame._closeUpDelivery, NarrowHaulGame._winDelay);
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

    final progress = ProgressService.instance;
    final xpBefore = progress.getXp();
    final prevStars =
        isChallengeMode ? stars : progress.getStarsById(currentLevelDef.saveId);
    final worldsBefore = {
      for (final w in LevelRegistry.worlds)
        if (LevelRegistry.isWorldUnlocked(w)) w.id,
    };
    Analytics.levelEnd(
      levelId: currentLevelDef.saveId,
      stars: stars,
      prevStars: prevStars,
      attempt: _attempt,
      seconds: elapsed,
      fuelLeft: lastLevelFuelFraction,
      guided: guidedThisRun,
      continued: continuedThisRun,
      carriedAmmo: carriedWeaponUsedThisRun,
      mode: _analyticsMode,
      ship: ship?.spec.id ?? '',
      noseDownWarnings: _noseDown.warnings,
      steer: FlightTuning.tilt ? 'tilt' : FlightTuning.steer.name,
    );
    if (_noseDown.warnings == 0) {
      final clean = ProgressService.instance.noseDownCleanFlights;
      if (clean < kNoseDownCleanFlights) {
        unawaited(ProgressService.instance.setNoseDownCleanFlights(clean + 1));
      }
    }
    final saveId = currentLevelDef.saveId;
    if (prevStars == 0 && saveId.startsWith('rating_')) {
      Analytics.shipUnlock(saveId.substring('rating_'.length), 'rating');
    }
    _attemptLevel = null; // the next flight here is a fresh attempt series
    final currencyMul = CareerService.currencyMultiplier;
    int currency = 0;
    final XpBreakdown runXp;

    unawaited(progress.incrementStat(ProgressService.statDeliveries));
    unawaited(MonetizationService.instance.recordLevelClear());
    _lastWinDailyFirst = false;
    _currencyDoubled = false;
    final (levelWorld, _) = LevelRegistry.worldOf(levelIndex);
    final worldIndex = LevelRegistry.worlds.indexOf(levelWorld);
    int earnedStars = 0;
    bool personalBest = false;

    if (isChallengeMode) {
      final firstToday = !progress.isDailyChallengeComplete();
      _lastWinDailyFirst = firstToday;
      int streak = progress.getDailyStreak();
      if (firstToday) {
        currency += (50 * currencyMul).round(); // Daily reward
        streak = await progress.advanceDailyStreak();
      }
      unawaited(progress.markDailyChallengeComplete());
      unawaited(progress.saveDailyBestTime(elapsed));
      runXp = computeRunXp(
        challenge: true,
        firstClear: false,
        newStars: 0,
        tier: 1,
        cleanFlight: !_currentLevelRetried,
        personalBest: false,
        dailyFirstToday: firstToday,
        dailyStreak: streak,
        replayXpUsedToday: progress.getReplayXpToday(),
      );
      if (!firstToday) unawaited(progress.addReplayXpToday(runXp.total));
    } else {
      final def = currentLevelDef;
      final world = levelWorld;
      final prevStars = progress.getStarsById(def.saveId);
      final prevBest = progress.getBestTimeById(def.saveId);

      // Newly earned stars pay out cosmetic currency, scaled by world + rank.
      final newStars = stars - prevStars;
      earnedStars = math.max(0, newStars);
      personalBest = prevBest != null && elapsed < prevBest;
      if (newStars > 0) {
        currency += (newStars * world.rewardPerStar * currencyMul).round();
      }

      unawaited(progress.saveStarsById(def.saveId, stars));
      unawaited(progress.saveBestTimeById(def.saveId, elapsed));

      // No-retry streak
      if (!_currentLevelRetried) {
        final streak = progress.getNoRetryStreak() + 1;
        unawaited(progress.setNoRetryStreak(streak));
      }

      runXp = computeRunXp(
        challenge: false,
        firstClear: prevStars == 0,
        newStars: earnedStars,
        tier: worldTier(worldIndex),
        cleanFlight: !_currentLevelRetried,
        personalBest: personalBest,
        replayXpUsedToday: progress.getReplayXpToday(),
      );
      if (prevStars > 0 && newStars <= 0) {
        unawaited(progress.addReplayXpToday(runXp.total));
      }
    }

    final (
      contractLines,
      allContractsDone,
    ) = await ContractsService.recordDelivery(
      DeliveryEvent(
        worldIndex: worldIndex,
        challenge: isChallengeMode,
        clean: !_currentLevelRetried,
        fuelFraction: fuelLeft / _shipMaxFuel,
        seconds: elapsed,
        newStars: earnedStars,
        personalBest: personalBest,
        turretsDestroyed: _turretsDestroyed,
        salvageOpened: _salvageOpenedThisRun,
        cursed: _cursesThisRun.isNotEmpty,
      ),
    );

    // Reactor escape (Thrust's big finish): bonus the first time per level.
    final combatLines = <XpLine>[];
    if (reactorEscape) {
      unawaited(progress.incrementStat(ProgressService.statReactorEscapes));
      if (await progress.markOnce('reactor_${currentLevelDef.saveId}')) {
        combatLines.add(const XpLine('Reactor escape', kReactorEscapeXp));
        currency += (kReactorEscapeCurrency * currencyMul).round();
      }
    }

    // Mystery salvage: flying a curse home pays a little grit bonus.
    if (_cursesThisRun.isNotEmpty) {
      final curse = _cursesThisRun.last;
      combatLines.add(XpLine('Grit: ${_titleCase(curse.name)}', kSalvageGritXp));
      currency += (kSalvageGritCoins * currencyMul).round();
      unawaited(progress.incrementStat(ProgressService.statSalvageGrit));
    }
    if (_luckyCoins > 0) currency += (_luckyCoins * currencyMul).round();

    final unlocked = [
      ..._inFlightAchievements,
      ...await _checkAchievements(
        stars,
        elapsed,
        fuelLeft,
        allContractsDone: allContractsDone,
        reactorEscape: reactorEscape,
      ),
    ];
    _inFlightAchievements.clear();
    var xp = XpBreakdown([
      ...runXp.lines,
      ...combatLines,
      ...contractLines,
      for (final a in unlocked) XpLine('Achievement: ${a.title}', 100),
    ]);

    // Rank achievements depend on the XP just earned (and pay XP themselves).
    final rankUnlocks = await _checkRankAchievements(
      rankFor(xpBefore + xp.total),
    );
    if (rankUnlocks.isNotEmpty) {
      unlocked.addAll(rankUnlocks);
      xp = XpBreakdown([
        ...xp.lines,
        for (final a in rankUnlocks) XpLine('Achievement: ${a.title}', 100),
      ]);
    }
    final xpAfter = xpBefore + xp.total;
    await progress.setXp(xpAfter);

    // Each rank crossed pays its one-off bonus.
    for (
      int i = rankFor(xpBefore).index + 1;
      i <= rankFor(xpAfter).index;
      i++
    ) {
      currency += rankUpBonus(kRanks[i]);
    }
    final coinsBefore = progress.getCosmeticCurrency();
    if (currency > 0) unawaited(progress.addCosmeticCurrency(currency));

    if (currency > 0) Analytics.earnCoins(currency, 'delivery');
    final rankAfter = rankFor(xpAfter);
    if (rankAfter.index > rankFor(xpBefore).index) {
      Analytics.rankUp(rankAfter.index, rankAfter.title);
    }
    for (final a in unlocked) {
      Analytics.achievement(a.id);
    }
    if (currentLevelDef == LevelRegistry.trainingFinale && prevStars == 0) {
      Analytics.tutorialComplete();
    }
    for (final w in LevelRegistry.worlds) {
      if (!worldsBefore.contains(w.id) && LevelRegistry.isWorldUnlocked(w)) {
        Analytics.worldUnlocked(w.id);
      }
    }
    _syncAnalyticsUser();

    lastRunReward = RunReward(
      xp: xp,
      xpBefore: xpBefore,
      xpAfter: xpAfter,
      currency: currency,
      newAchievements: unlocked,
      coinsBefore: coinsBefore,
    );

    AudioService.playLand();
    if (stars >= 2) AudioService.playStar();
    MusicService.play(MusicService.resultsTrack, MusicService.resultsVolume);

    _resetInputState();
    // update() raises the dialog once the celebration has played.
    _winReady = true;
  }

  /// Player-level dimensions for every report (set at launch and after
  /// each delivery).
  void _syncAnalyticsUser() {
    final p = ProgressService.instance;
    Analytics.setUserProperty('pilot_rank', '${rankFor(p.getXp()).index}');
    Analytics.setUserProperty('total_stars', '${LevelRegistry.totalStars()}');
    Analytics.setUserProperty('payer', p.hasPurchased ? '1' : '0');
  }

  int _calculateStars(double fuelRemaining, double timeSeconds) {
    // A continued (rewarded ad) or guided run can never buy a perfect rating.
    final flown = ship?.spec;
    final fuelLeft = fuelRemaining / _shipMaxFuel;
    return currentLevelDef.stars.rate(
      // Another ship than the level's own: fuel scaled by range (fleet.dart).
      flown == null || isChallengeMode
          ? fuelLeft
          : normalisedFuelLeft(fuelLeft, flown, LevelRegistry.shipFor(levelIndex)),
      timeSeconds,
      capped: continuedThisRun ||
          guidedThisRun ||
          carriedWeaponUsedThisRun ||
          checkpointUsedThisRun,
    );
  }

  /// Runs the post-win achievement checks; returns the newly unlocked ones.
  Future<List<AchievementMeta>> _checkAchievements(
    int stars,
    double timeSeconds,
    double fuelRemaining, {
    required bool allContractsDone,
    bool reactorEscape = false,
  }) async {
    final progress = ProgressService.instance;
    final candidates = <String>[AchievementIds.firstHaul];

    if (reactorEscape) candidates.add(AchievementIds.meltdownEscape);
    final s = ship;
    if (s != null && s.spec.armed && s.shotsFired == 0 && currentLevel?.hasCombat == true) {
      candidates.add(AchievementIds.holdFire);
    }

    if (fuelRemaining >= 0.85 * _shipMaxFuel) candidates.add(AchievementIds.fuelMiser);
    if (timeSeconds < 30) candidates.add(AchievementIds.speedHauler);

    final streak = progress.getNoRetryStreak();
    if (!_currentLevelRetried && streak >= 5) {
      candidates.add(AchievementIds.noScratch);
    }

    int completed = 0;
    bool allPerfect = true;
    for (final def in LevelRegistry.career) {
      final s = progress.getStarsById(def.saveId);
      if (s > 0) completed++;
      if (s < 3) allPerfect = false;
    }
    if (completed >= 10) candidates.add(AchievementIds.level10);
    if (completed >= LevelRegistry.careerLevels) {
      candidates.add(AchievementIds.level20);
    }

    if (isChallengeMode) candidates.add(AchievementIds.dailyPilot);
    if (isChallengeMode && activeChallengeConfig?.shipId != null) {
      candidates.add(AchievementIds.testPilot);
    }

    // Flight-condition achievements.
    final fields = currentLevel?.fields ?? const <FieldSpec>[];
    if (stars >= 3 && fields.any((f) => f is WindZoneSpec)) {
      candidates.add(AchievementIds.stormRider);
    }
    if (stars >= 3 && fields.any((f) => f is GravityWellSpec)) {
      candidates.add(AchievementIds.orbitalMechanic);
    }
    if (_levelGravityG >= 1.5) candidates.add(AchievementIds.heavyLifter);
    if (stars >= 3 && !isChallengeMode && !flyingParShip) {
      candidates.add(AchievementIds.offType);
    }
    if (kShips.keys.every(LevelRegistry.hasTypeRating)) {
      candidates.add(AchievementIds.fleetQualified);
    }

    if (allPerfect) candidates.add(AchievementIds.perfectPilot);

    if (allContractsDone) candidates.add(AchievementIds.fullManifest);
    // Mystery salvage: delivered mid-curse.
    if (salvage.effect == SalvageEffect.swarmSting && (ship?.sizeMul ?? 1) > 1.05) {
      candidates.add(AchievementIds.beeLieveIt);
    }
    if (salvage.effect == SalvageEffect.sporeTrip) candidates.add(AchievementIds.badTrip);
    if (progress.getDailyStreak() >= 7) {
      candidates.add(AchievementIds.weekOnDuty);
    }
    if (progress.getStat(ProgressService.statDeliveries) >= 100) {
      candidates.add(AchievementIds.centuryHauler);
    }

    final unlocked = <AchievementMeta>[];
    for (final id in candidates) {
      if (await AchievementService.unlock(id)) {
        unlocked.add(AchievementService.all.firstWhere((a) => a.id == id));
      }
    }
    return unlocked;
  }

  Future<List<AchievementMeta>> _checkRankAchievements(PilotRank rank) async {
    final unlocked = <AchievementMeta>[];
    for (final (id, minRank) in [
      (AchievementIds.rankCommercial, 2),
      (AchievementIds.rankCaptain, 6),
      (AchievementIds.rankChief, 9),
    ]) {
      if (rank.index >= minRank && await AchievementService.unlock(id)) {
        unlocked.add(AchievementService.byId(id));
      }
    }
    return unlocked;
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

String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');
