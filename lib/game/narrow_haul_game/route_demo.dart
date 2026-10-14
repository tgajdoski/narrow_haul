part of '../narrow_haul_game.dart';

/// Route guide, demo flight replay and the flight recorder.
extension GameRouteDemo on NarrowHaulGame {
  /// The bundled route, when it was recorded with this level's ship (a
  /// daily's modifiers or Test Flight ship would make it wrong).
  Future<FlightRoute?> _routeForCurrentLevel() async {
    if (isChallengeMode) return null;
    final route = await RouteRepository.load(currentLevelDef.saveId);
    if (route == null || route.shipId != LevelRegistry.shipFor(levelIndex).id) return null;
    return route;
  }

  bool get routeGuideOn =>
      !isChallengeMode && _routeGuideLevel == currentLevelDef.saveId;

  /// The pause toggle: this level's route was unlocked before.
  bool get routeGuideAvailable =>
      currentRoute != null &&
      flyingParShip &&
      !isChallengeMode &&
      ProgressService.instance.isRouteUnlocked(currentLevelDef.saveId);

  /// The level's own ship is flying (routes were recorded with it).
  bool get flyingParShip =>
      ship == null || ship!.spec.id == LevelRegistry.shipFor(levelIndex).id;

  /// Game-over help: after [CrashStreak.offerAfter] crashes in a row, or
  /// whenever this level's route was unlocked before.
  bool get canShowRoute =>
      currentRoute != null &&
      !isChallengeMode &&
      (crashStreak.shouldOfferFor(
            currentLevelDef.saveId,
            training: currentLevelDef is TmxLevelDef,
          ) ||
          ProgressService.instance.isRouteUnlocked(currentLevelDef.saveId));

  /// "Show route": unlock it for this level and retry with the guide on.
  Future<void> showRoute() async {
    if (!canShowRoute) return;
    await ProgressService.instance.setRouteUnlocked(currentLevelDef.saveId);
    Analytics.routeShown(currentLevelDef.saveId);
    _routeGuideLevel = currentLevelDef.saveId;
    await restartLevel();
  }

  /// Pause-menu toggle. Switching it on mid-flight caps the run at 2★.
  void setRouteGuide(bool on) {
    _routeGuideLevel = on ? currentLevelDef.saveId : null;
    _syncRouteGuide();
  }

  /// Adds/removes the dotted route (and the ghost ship outside demos).
  void _syncRouteGuide() {
    for (final c in _guideComponents) {
      c.removeFromParent();
      _levelEntities.remove(c);
    }
    _guideComponents.clear();
    final route = currentRoute;
    final level = currentLevel;
    final s = ship;
    if (route == null || level == null || s == null) return;
    if (!routeGuideOn && !demoMode) return;
    _guideComponents.add(RouteGuideLine(
      route: route,
      accent: level.theme.uiAccent,
      turrets: () => _turrets,
      turretsOffline: () => turretsDisabled,
    ));
    if (!demoMode) {
      _guideComponents.add(RouteGhost(
        route: route,
        ship: s.spec,
        flightTime: () => (ship?.launched ?? false) ? elapsedSeconds : null,
      ));
    }
    for (final c in _guideComponents) {
      world.add(c);
      _levelEntities.add(c);
    }
  }

  /// "Watch a demo flight": reloads the level with the engine stopped (so
  /// obstacles start in step with the recording), then replays it.
  Future<void> startDemoFlight() async {
    if (!canShowRoute) return;
    await ProgressService.instance.setRouteUnlocked(currentLevelDef.saveId);
    Analytics.demoWatched(currentLevelDef.saveId);
    overlays.removeAll([OverlayIds.gameOver, OverlayIds.pause, OverlayIds.settings]);
    _resetInputState();
    demoMode = true;
    demoFinished.value = false;
    runState = RunState.playing;
    pauseEngine();
    await loadCurrentLevel(retry: true);
    _hudControls?.removeFromParent();
    overlays.add(OverlayIds.demo);
    resumeEngine();
  }

  /// Ends a demo (back to normal flight state; the caller loads what's next).
  void _leaveDemo() {
    if (!demoMode) return;
    demoMode = false;
    demoFinished.value = false;
    overlays.remove(OverlayIds.demo);
    final hud = _hudControls;
    if (hud != null && hud.parent == null) camera.viewport.add(hud);
  }

  /// "Take the controls": fly the level yourself (the guide stays as it was).
  Future<void> takeControlsFromDemo() => restartLevel();

  void _updateDemo(double dt, ShipBody s) {
    final route = currentRoute;
    if (route == null) return;
    _demoT += dt;
    // An Expedition's demo moves on to the next pod when the recording did.
    while (legIndex < route.legT.length &&
        legIndex < legCount - 1 &&
        route.legT[legIndex] <= _demoT) {
      _demoNextLeg();
    }
    final pose = route.poseAt(_demoT);
    // The real velocity, so turrets lead their shots like they did live.
    final next = route.poseAt(_demoT + dt);
    s.drivePose(Vector2(pose.x, pose.y), pose.angle,
        thrust: pose.thrust,
        velocity: dt > 0 ? Vector2((next.x - pose.x) / dt, (next.y - pose.y) / dt) : null);
    // The sample after a pad handover already holds the next pod, so stop
    // the delivered pod one sample short: it stays on its pad.
    final handover = legIndex < route.legT.length ? route.legT[legIndex] - FlightRecorder.sampleEvery : null;
    final podPose = handover != null && _demoT > handover ? route.poseAt(handover) : pose;
    cargo?.drivePosition(Vector2(podPose.cx, podPose.cy));
    _demoTowing = pose.towing;
    while (_demoShot < route.shots.length && route.shots[_demoShot] <= _demoT) {
      final k = _demoShot++;
      if (k < route.shotRays.length) {
        // The very shell the recorded flight fired.
        final r = route.shotRays[k];
        _onShipFired(Vector2(r[0], r[1]), Vector2(r[2], r[3]));
        continue;
      }
      final a = route.poseAt(_demoT - 0.05);
      final b = route.poseAt(_demoT + 0.05);
      s.fireScripted(Vector2((b.x - a.x) / 0.1, (b.y - a.y) / 0.1));
    }
    if (_demoT >= route.endT && !demoFinished.value) demoFinished.value = true;
  }

  void _recordFrame(double dt, ShipBody s) {
    final rec = _recorder;
    final c = cargo;
    if (rec == null || c == null || demoMode) return;
    rec.tick(
      dt,
      x: s.body.position.x,
      y: s.body.position.y,
      angle: s.body.angle,
      cx: c.body.position.x,
      cy: c.body.position.y,
      launched: s.launched,
      towing: cargoAttachment?.attached ?? false,
      thrust: s.isThrusting,
    );
  }
}
