part of '../narrow_haul_game.dart';

/// Level entry points, load / spawn, teardown and the start countdown.
extension GameLevelLifecycle on NarrowHaulGame {
  /// Menu LAUNCH: flies the career's next mission, after its briefing when
  /// it's a first attempt ([needsBriefing]).
  Future<void> beginPlay() async {
    final next = LevelRegistry.nextLevelIndex();
    if (needsBriefing(next)) {
      openBriefing(next);
      return;
    }
    overlays.remove(OverlayIds.menu);
    overlays.remove(OverlayIds.levelSelect);
    _resetChallenge();
    levelIndex = next;
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    await loadCurrentLevel();
  }

  Future<void> beginChallenge() async {
    overlays.removeAll([OverlayIds.menu, OverlayIds.briefing]);
    isChallengeMode = true;
    final levels = NarrowHaulGame.unlockedLevelIndices();
    // Test Flight ship options run the full validator per ship (up to a few
    // hundred ms on a phone): do it on a background isolate, and only then.
    final (dailyLevel, testFlight) = DailyChallengeConfig.peekToday(levels);
    var shipIds = const <String>[];
    if (testFlight) {
      try {
        shipIds = await _testFlightShipIds(dailyLevel);
      } catch (e, st) {
        // No ship options means a standard daily run, never a blank screen.
        ErrorReporter.report(e, st, context: 'test flight options');
      }
    }
    activeChallengeConfig = DailyChallengeConfig.forToday(
      levels,
      shipOptions: (_) => shipIds,
      chaosOk: (i) => LevelRegistry.defAt(i) is CaveLevelDef,
    );
    levelIndex = activeChallengeConfig!.levelIndex;
    _gravityMultiplier = activeChallengeConfig!.gravityMultiplier;
    _fuelDrainMultiplier = activeChallengeConfig!.fuelDrainMultiplier;
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    await loadCurrentLevel();
  }

  /// [withRoute] (from the briefing) switches the route guide on or off for
  /// this level; null keeps it as it was (on across retries).
  void startLevel(int index, {bool? withRoute}) {
    overlays.removeAll([
      OverlayIds.menu,
      OverlayIds.levelSelect,
      OverlayIds.briefing,
      OverlayIds.gameOver,
      OverlayIds.levelComplete,
      OverlayIds.rankUp,
      OverlayIds.story,
      OverlayIds.pause,
      OverlayIds.settings,
    ]);
    _leaveDemo();
    _resetChallenge();
    levelIndex = index;
    if (withRoute != null) {
      _routeGuideLevel = withRoute
          ? LevelRegistry.defAt(index).saveId
          : null;
    }
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    loadCurrentLevel();
  }

  /// [retry] marks a reload of the same level after a crash or restart, so
  /// clean-flight bonuses and the no-retry streak don't apply. A level that
  /// fails to load is reported and drops back to the menu instead of leaving
  /// an empty, unplayable screen.
  Future<void> loadCurrentLevel({bool retry = false}) async {
    try {
      await _loadCurrentLevel(retry: retry);
    } on _LoadSuperseded {
      // The player moved on mid-load; whoever superseded it owns the screen.
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'loading ${currentLevelDef.saveId}');
      backToMenu();
    }
  }

  Future<void> _loadCurrentLevel({required bool retry}) async {
    final loadClock = kPerfProbe ? (Stopwatch()..start()) : null;
    _clearLevel();
    if (_ammoOfferedLevel != currentLevelDef.saveId) _ammoOffered = false;
    _currentLevelRetried = retry;
    lastCrashKind = null;
    _hookLogged = false;
    _snapshots.reset();
    _continueUsed = false;
    _podHeldForResume = null;
    continuedThisRun = false;
    _weaponsLogged.clear();
    guidedThisRun = false;
    // A resume flies on from the last staging pad; anything else starts the
    // Expedition over.
    legIndex = _resumeLeg;
    _resumeLeg = 0;
    _legLanded = false;
    checkpointUsedThisRun = legIndex > 0;
    if (legIndex == 0) {
      _checkpointLeg = 0;
      _checkpointElapsed = 0;
      _checkpointFuel = const [];
    }
    _legFuelLeft
      ..clear()
      ..addAll(_checkpointFuel.take(legIndex));
    _crashedByMeltdown = false;
    _meltdownAtCrash = null;
    _playtimeBooked = 0;
    _demoT = 0;
    _demoShot = 0;
    demoShellHits = 0;
    _demoTowing = false;
    if (!demoMode) {
      unawaited(ProgressService.instance.incrementStat(ProgressService.statFlights));
    }
    final gen = _levelGen;
    final route = await _routeForCurrentLevel();
    _checkLoad(gen);
    currentRoute = route;
    final def = currentLevelDef;
    // In debug, rebuild the cave on every load so hot-reloaded spec edits
    // show up (tests keep the cache: the spec can't change under them).
    if (kDebugMode && !debugKeepCaveCache && def is CaveLevelDef) {
      forgetCave(def.spec.id);
    }
    if (def is CaveLevelDef) await prebuildCave(def.spec);
    _checkLoad(gen);
    final data = switch (currentLevelDef) {
      TmxLevelDef def => await loadLevelFromTmx(
        def.assetPath,
        levelIndex: levelIndex,
      ),
      CaveLevelDef def => buildCaveLevelData(def),
    };
    _checkLoad(gen);
    await _spawnLevel(data, gen);
    MusicService.play(
      MusicService.flightTrackFor(currentLevelDef.themeId, keepCurrent: retry),
      MusicService.flightVolume,
    );
    if (!retry && !demoMode) AudioService.playStartLevel();
    if (!demoMode) _logLevelStart();
    _countdown = (demoMode || _tutorialHints) ? null : NarrowHaulGame._countdownSeconds;
    _countdownDone = false;
    _startCloseUp(retry: retry);
    _countdownHud
      ?..text = null
      ..accent = data.theme.uiAccent;
    if (loadClock != null) {
      PerfMonitor.levelLoaded(currentLevelDef.saveId, loadClock.elapsedMicroseconds / 1000);
    }
  }

  void _logLevelStart() {
    final id = currentLevelDef.saveId;
    if (_attemptLevel != id) {
      _attemptLevel = id;
      _attempt = 0;
    }
    _attempt++;
    final (world, _) = LevelRegistry.worldOf(levelIndex);
    if (!isChallengeMode && !world.expedition) ReminderService.noteMissionStarted(id);
    Analytics.levelStart(
      levelId: id,
      world: world.id,
      ship: ship?.spec.id ?? '',
      par: LevelRegistry.shipFor(levelIndex).id,
      rope: cargoAttachment?.rope.id ?? '',
      mode: _analyticsMode,
      attempt: _attempt,
      guided: routeGuideOn,
    );
  }

  /// Adds a level entity, tracked before the add so a teardown mid-load
  /// removes it too; then stops the load if it was superseded.
  Future<void> _addToLevel(Component c, int gen) async {
    _levelEntities.add(c);
    await world.add(c);
    _checkLoad(gen);
  }

  /// Throws [_LoadSuperseded] once a newer load or a teardown
  /// ([_clearLevel] bumps [_levelGen]) has replaced the load [gen].
  void _checkLoad(int gen) {
    if (gen != _levelGen) throw const _LoadSuperseded();
  }

  Future<void> _spawnLevel(LevelData data, int gen) async {
    final theme = data.theme;
    final mods = data.modifiers;

    // Gravity: base (debug-reduced) × daily challenge × level modifier.
    // Same total as combinedGravityMul (level × daily, clamped); split so
    // the field sampler gets the daily-scaled base and the level's part.
    final g0 = baseGravityY() * _gravityMultiplier;
    final gravityMul = mods.gravityMul.clamp(0.0, kMaxGravityMul / _gravityMultiplier);
    world.gravity = Vector2(0, g0 * gravityMul);

    // Optional per-world art (assets/themes/<id>/); missing files fall back
    // to the flat palette look.
    final art = await ThemeAssets.load(images, theme);
    _checkLoad(gen);

    // Theme the parallax sky: dedicated layers if present, else tinted shared.
    _parallax?.applyTheme(
      tint: theme.parallaxTint,
      alphas: theme.parallaxAlphas,
      far: art.far,
      mid: art.mid,
      near: art.near,
    );

    // With dedicated parallax art the backdrop becomes a haze so the world's
    // background shows through the cave; otherwise it stays solid.
    final backdrop = RectangleComponent(
      size: data.worldSize,
      paint: Paint()
        ..color = theme.backdropColor.withValues(
          alpha: art.hasParallax ? 0.35 : 1,
        ),
      priority: -2000,
    )..position = Vector2.zero();
    world.add(backdrop);
    _levelEntities.add(backdrop);

    for (final w in data.walls) {
      final box = WallBox(
        wallCenter: w.center,
        halfWidth: w.halfWidth,
        halfHeight: w.halfHeight,
        theme: theme,
        assets: art,
      );
      await _addToLevel(box, gen);
    }

    if (data.caveLoops.isEmpty) {
      await _addToLevel(
        WorldFrame(worldSize: data.worldSize, theme: theme, assets: art),
        gen,
      );
    }

    if (data.caveLoops.isNotEmpty) {
      final terrain = CaveTerrain(
        loops: data.caveLoops,
        worldSize: data.worldSize,
        theme: theme,
        assets: art,
        friction: mods.wallFriction ?? 0.35,
      );
      await _addToLevel(terrain, gen);
      _terrain = terrain;
      final def = currentLevelDef;
      if (def is CaveLevelDef) {
        _carver = TerrainCarver(
          buildCave(def.spec),
          guards: [
            for (final leg in data.legs)
              ...padGuards(
                shipSpawn: Pt(data.shipSpawn.x, data.shipSpawn.y),
                goalCenter: Pt(leg.goalCenter.x, leg.goalCenter.y),
                goalHalfW: leg.goalHalfWidth,
                goalHalfH: leg.goalHalfHeight,
              ),
          ],
        );
      }

      final decor = CaveDecor(
        loops: data.caveLoops,
        rockPath: terrain.rockPath,
        theme: theme,
        assets: art,
        anchors: [
          for (final v in [
            data.shipSpawn,
            for (final leg in data.legs) ...[leg.cargoSpawn, leg.goalCenter],
          ])
            Offset(v.x, v.y),
        ],
      );
      await _addToLevel(decor, gen);
      _decor = decor;
    }

    if (theme.ambient != AmbientKind.none) {
      final ambient = AmbientParticles(
        kind: theme.ambient,
        worldSize: data.worldSize,
        seed: levelIndex,
      );
      await _addToLevel(ambient, gen);
    }

    for (final field in data.fields) {
      if (field is! GravityWellSpec) continue;
      final core = WellCore(spec: field, theme: theme);
      await _addToLevel(core, gen);
    }

    for (final spec in debugSkipHazards ? const <ObstacleSpec>[] : data.obstacles) {
      final obstacle = obstacleFromSpec(spec, theme, this);
      await _addToLevel(obstacle, gen);
      if (obstacle is Turret) _turrets.add(obstacle);
    }

    for (final spec in data.pickups) {
      final pickup = switch (spec) {
        FuelCellSpec s => FuelCell(spec: s, host: this, accent: theme.uiAccent),
      };
      await _addToLevel(pickup, gen);
      _fuelCells.add(pickup);
    }

    final helipad = HelipadVisual(
      center: data.shipSpawn,
      sizeMeters: Vector2(3.4, 2.4),
      base: theme.padBase,
      accent: theme.padAccent,
    );
    await _addToLevel(helipad, gen);

    for (final leg in data.legs) {
      final landingStrip = LandingStripVisual(
        center: leg.goalCenter,
        sizeMeters: Vector2(leg.goalHalfWidth * 2, leg.goalHalfHeight * 2),
        // Cave pads land on the shelf the builder lays below the box.
        floorDrop: data.caveLoops.isNotEmpty ? kPadFloorDrop : null,
      );
      await _addToLevel(landingStrip, gen);
    }

    final startLeg = data.legs[legIndex];
    final challengeShip = isChallengeMode ? activeChallengeConfig?.shipId : null;
    // Dailies fly their own ship (par, or the Test Flight's). The route
    // guide and demos replay the par ship's recording, so they fly it too;
    // otherwise the pilot's pick (FleetService) when it fits.
    final shipSpec = challengeShip != null
        ? shipById(challengeShip)
        : isChallengeMode || demoMode || routeGuideOn
            ? LevelRegistry.shipFor(levelIndex)
            : FleetService.flownShipFor(levelIndex);
    _levelGravityG = g0 * gravityMul / baseGravityY();
    // Carried ammo stays home in a daily (a skill run) and in demos.
    final carryAmmo = !isChallengeMode && !demoMode;
    _ammoPeak.clear();
    final rack = _rack = WeaponRack(
      hasCannon: shipSpec.armed,
      carried: {
        if (carryAmmo)
          for (final w in kWeapons) w.id: ProgressService.instance.getAmmo(w.id),
      },
    );
    await _maybeSpawnCrate(shipSpec, theme);
    _checkLoad(gen);
    await _maybeSpawnSalvage(shipSpec);
    _checkLoad(gen);
    final shipBody = ShipBody(
      initialPosition: Vector2.copy(startLeg.startSpawn),
      onWallHit: () => _onShipHitWall(),
      onRockTouch: _onRockTouch,
      onHookTouchesCargo: () => cargoAttachment?.onHookCargoTouch(),
      onFire: _onShipFired,
      onWeapon: _onWeaponFired,
      rack: rack,
      fuelDrainMultiplier: _fuelDrainMultiplier * mods.fuelDrainMul,
      spec: shipSpec,
      kit: kitById(CosmeticsService.getEquippedId(CosmeticsService.catKit)),
      // The hull's rim light picks up the cave's glow (neutral without one).
      rimColor: theme.edgeGlow?.withValues(alpha: 1) ?? HullLighting.defaultRim,
    );
    // Every leg's pod: delivered ones parked on their pads, the rest
    // waiting (locked until hooked).
    _pods
      ..clear()
      ..addAll([
        for (final (k, leg) in data.legs.indexed)
          CargoBody(
            initialPosition: Vector2.copy(k < legIndex ? leg.parkedPod : leg.cargoSpawn),
            densityMul: mods.cargoDensityMul,
            clamped: k != legIndex || leg.cargoClamped,
            image: art.cargoFor(mods.cargoDensityMul),
            strapped: mods.cargoDensityMul > 1.0 && art.cargoHeavy == null,
          ),
      ]);
    final cargoBody = _pods[legIndex];
    final cargoLink = _towFor(shipBody, cargoBody, data);

    _levelEntities.addAll([shipBody, ..._pods, cargoLink]);
    await world.addAll([shipBody, ..._pods, cargoLink]);
    _checkLoad(gen);
    final glow = _shieldGlow = ShieldGlow(ship: shipBody);
    await _addToLevel(glow, gen);
    final aura = _salvageAura = SalvageAura(
      ship: shipBody,
      state: salvage,
      pod: () {
        final pod = cargo;
        return pod != null && pod.isMounted ? pod.body.position : null;
      },
    );
    await _addToLevel(aura, gen);

    ship = shipBody;
    cargo = cargoBody;
    cargoAttachment = cargoLink;
    final beam = _laserBeam = MiningLaserBeam(color: theme.uiAccent);
    await _addToLevel(beam, gen);
    _syncWeaponHud();
    _recorder = FlightRecorder(saveId: currentLevelDef.saveId, shipId: shipSpec.id);
    if (demoMode) cargoLink.scriptedTow = () => _demoTowing;

    _forces = null;
    if (data.fields.isNotEmpty) {
      final forces = _forces = ForceFieldSystem(
        sampler: FieldSampler(fields: data.fields, g0: g0, gravityMul: gravityMul),
        ship: shipBody,
        cargo: cargoBody,
        accent: theme.uiAccent,
        seed: levelIndex,
      );
      await _addToLevel(forces, gen);
    }
    _gravityHud
      ?..show = data.fields.isNotEmpty || (g0 * gravityMul - baseGravityY()).abs() > 1e-6
      ..accent = theme.uiAccent;

    final landing = _padFor(startLeg);
    await _addToLevel(landing, gen);
    _landingZone = landing;

    _currentWorldSize = data.worldSize;
    _cam.fitWorld(data.worldSize);
    camera.stop();
    _snapCameraToShip();

    currentLevel = data;
    _minimap?.setLevel(data);

    elapsedSeconds = legIndex > 0 ? _checkpointElapsed : 0;
    _timing = true;
    _fuelBaseline = shipBody.maxFuel;
    _thrustUsed = 0;
    _rotateUsed = 0;
    _fireCoachLeft = !demoMode &&
            shipBody.spec.armed &&
            data.hasCombat &&
            !ProgressService.instance.fireHintSeen
        ? NarrowHaulGame._fireCoachSeconds
        : 0;
    _canisterHintThisFlight = false;
    _tutorialHints =
        !isChallengeMode &&
        !demoMode &&
        levelIndex < 3 &&
        currentLevelDef is TmxLevelDef &&
        ProgressService.instance.getStarsById(currentLevelDef.saveId) == 0;
    _pauseButton?.visible = !demoMode;
    _syncRouteGuide();
    _clearGuidance();
    _setUpDrills(data);
    _noseDown.reset();
    _noseDownLesson = !demoMode &&
        ProgressService.instance.noseDownCleanFlights < kNoseDownCleanFlights;
    _scheduleComms(retry: _currentLevelRetried);
    _fuelGauge?.starMarks = [
      currentLevelDef.stars.star3Fuel,
      currentLevelDef.stars.star2Fuel,
    ];
    _updateLevelInfoHud();

    final (levelWorld, indexInWorld) = LevelRegistry.worldOf(levelIndex);
    _levelIntro?.show(
      title: currentLevelDef.name,
      subtitle: isChallengeMode
          ? 'Daily dispatch · ${activeChallengeConfig?.modifierName ?? ''}'
          : '${levelWorld.name} · ${indexInWorld + 1}/${levelWorld.levels.length}',
      accent: theme.uiAccent,
      note: [
        if (!isChallengeMode) ?storyFor(currentLevelDef.saveId)?.cargo,
        _flightNote(shipSpec, g0 * gravityMul / baseGravityY()),
      ].join(' · '),
    );
  }

  void _updateLevelInfoHud() {
    final info = _levelInfoHud;
    if (info == null) return;
    final challengeTag = isChallengeMode
        ? ' [${activeChallengeConfig?.modifierName ?? ''}]'
        : '';
    final (world, indexInWorld) = LevelRegistry.worldOf(levelIndex);
    final leg = isExpeditionRun ? ' · Leg ${legIndex + 1}/$legCount' : '';
    info.levelLabel =
        '${world.name} ${indexInWorld + 1}/${world.levels.length}$leg$challengeTag';
    info.stars = ProgressService.instance.getStarsById(currentLevelDef.saveId);
    info.starSpec = currentLevelDef.stars;
  }

  void _clearLevel() {
    PerfMonitor.flightEnded('left');
    _flushAmmo();
    _levelGen++;
    _turrets.clear();
    _fuelCells.clear();
    _shells.clear();
    _rack = null;
    _carver = null;
    _terrain = null;
    _decor = null;
    _carveBusy = false;
    _laserBeam = null;
    _crate = null;
    _crateNotice = null;
    _crateNoticeLeft = 0;
    _resetSalvage();
    _salvageCaches.clear();
    _salvageAura = null;
    _salvageHud?.clear();
    _cursesThisRun.clear();
    _salvageOpenedThisRun = 0;
    _luckyCoins = 0;
    scrapesThisRun = 0;
    _scrapeFxCooldown = 0;
    _scrapeSoundCooldown = 0;
    _shieldGlow = null;
    _proximityBuzzCooldown = 0;
    _hudControls?.weapon = null;
    camera.stop();
    for (final c in _levelEntities.reversed) {
      c.removeFromParent();
    }
    _levelEntities.clear();
    _guideComponents.clear();
    _recorder = null;
    ship = null;
    cargo = null;
    cargoAttachment = null;
    currentLevel = null;
    _minimap?.setLevel(null);
    _currentWorldSize = null;
    _timing = false;
    isPaused = false;
    _landingZone = null;
    _clearGuidance();
    _winTimer = 0;
    _winReady = false;
    _crashTimer = 0;
    _cam.shake.clear();
    _pauseButton?.visible = false;
    _hudControls?.showFire = false;
    _meltdownLeft = null;
    _turretsOfflineLeft = 0;
    _turretsDestroyed = 0;
    _reactorDestroyed = false;
    _syncCombatHud();
    _resetInputState();
  }

  void _resetChallenge() {
    isChallengeMode = false;
    activeChallengeConfig = null;
    _gravityMultiplier = 1.0;
    _fuelDrainMultiplier = 1.0;
    world.gravity = narrowHaulGravity();
  }

  /// 3 · 2 · 1 · GO, then the clock runs while the ship hovers on until the
  /// first input. Input during the countdown launches it at once and clears
  /// the numbers.
  void _updateCountdown(double dt, ShipBody s) {
    final left = _countdown;
    if (left == null) {
      // After GO: the first input releases a pod held for a resume.
      if (s.launched) _endResumeHold();
      return;
    }
    if (s.launched) {
      _countdown = null;
      _countdownHud?.text = null;
      _endResumeHold();
      return;
    }
    final now = left - dt;
    _countdown = now;
    if (now <= 0) {
      _countdown = null;
      _countdownDone = true;
      // GO starts the flight: gravity on, the pod free. Until the first
      // input the ship only sinks gently (ShipBody.goSinkSpeed), so a pilot
      // still reading settles on the rock instead of crashing.
      s.launch(gentle: true);
      _endResumeHold();
      _countdownHud?.go();
      AudioService.playCountdown(go: true);
      return;
    }
    if (now <= 3) {
      final n = now.ceil();
      if (n != left.ceil() || left > 3) AudioService.playCountdown(go: false);
      _countdownHud?.text = const ['0', '1', '2', '3'][n];
    }
  }
}

/// Intro-card line naming the ship and any non-standard gravity, so a
/// changed ship or pull is never a surprise.
String _flightNote(ShipSpec ship, double gravityG) {
  final g = (gravityG - 1).abs() > 0.01 ? ' · ${gravityG.toStringAsFixed(2)}g' : '';
  return '${ship.name}$g';
}
