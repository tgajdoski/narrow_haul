part of '../narrow_haul_game.dart';

/// Combat host helpers, weapons and ammo, crates, blasts, shell interception, rock carving and combat timers.
extension GameCombat on NarrowHaulGame {
  /// Demo flight past the recorded launch: turrets fight the replay exactly
  /// as they fought the recorded flight (their timing is seeded and runs on
  /// the same level-load clock).
  bool get _demoLaunched {
    final route = currentRoute;
    return route != null && _demoT >= route.launchT;
  }

  void _onShipFired(Vector2 muzzle, Vector2 velocity) {
    _recorder?.shot([muzzle.x, muzzle.y, velocity.x, velocity.y]);
    spawnShell(Shell(
      position: muzzle,
      velocity: velocity,
      fromPlayer: true,
      host: this,
      world: world,
      color: currentLevel?.theme.uiAccent ?? const Color(0xFFFFD166),
    ));
    AudioService.playShot();
    Haptics.light();
    final s = ship;
    if (s != null && !demoMode) {
      _fuelGauge?.flashCost(s.spec.fuelPerShot * s.fuelDrainMultiplier / s.maxFuel);
    }
  }

  void _burstAt(Offset at, {double ringRadius = 2.7}) {
    final burst = ExplosionBurst(
      center: at,
      accent: currentLevel?.theme.uiAccent ?? HudColors.warn,
      seed: _combatRng.nextInt(1 << 20),
      ringRadius: ringRadius,
    );
    world.add(burst);
    _levelEntities.add(burst);
  }

  /// Next weapon on the rack (HUD chip tap, Q / Tab).
  void cycleWeapon() {
    final r = _rack;
    if (r == null || r.available.length < 2) return;
    r.cycle();
    _syncWeaponHud();
    Haptics.light();
  }

  /// Loads weapon [id] (HUD ammo rail tap).
  void selectWeapon(String id) {
    final r = _rack;
    if (r == null || r.selectedId == id || !r.select(id)) return;
    _syncWeaponHud();
    Haptics.light();
  }

  /// Loads the rail's [slot]th weapon (number keys 1–6).
  void selectWeaponSlot(int slot) {
    final list = _rack?.available ?? const <String>[];
    if (slot < list.length) selectWeapon(list[slot]);
  }

  void _syncWeaponHud() {
    final hud = _hudControls;
    final r = _rack;
    if (hud == null) return;
    hud.showFire = r?.canFire ?? false;
    final w = r?.selected;
    if (r == null || w == null) {
      hud.weapon = null;
      return;
    }
    final ids = r.available;
    final slots = [
      for (final id in ids)
        if (weaponById(id) case final spec?) _weaponSlot(r, spec),
    ];
    hud.weapon = WeaponHud(slots: slots, selectedIndex: math.max(0, ids.indexOf(w.id)));
  }

  WeaponSlot _weaponSlot(WeaponRack r, WeaponSpec w) {
    final ammo = r.ammo(w.id);
    final peak = _ammoPeak[w.id] = math.max(_ammoPeak[w.id] ?? 0, ammo);
    return WeaponSlot(
      id: w.id,
      kind: w.kind,
      label: _weaponLabel(w),
      name: w.name,
      count: switch (w.kind) {
        WeaponKind.cannon => null,
        WeaponKind.laser => '${ammo.ceil()}s',
        _ => '×${ammo.round()}',
      },
      ammo: ammo,
      peak: peak,
      costsStar: r.costsStar(w.id),
    );
  }

  /// Writes carried ammo spent this flight back to the save.
  void _flushAmmo() {
    final r = _rack;
    if (r == null) return;
    r.takeCarriedSpent().forEach((id, units) {
      ProgressService.instance.addAmmo(id, -units);
    });
  }

  /// Maybe drops a supply crate: only cave levels flown by an unarmed ship
  /// (the Talon has its gun), never in demos or test flights of the bot.
  Future<void> _maybeSpawnCrate(ShipSpec shipSpec, ThemeSpec theme) async {
    final def = currentLevelDef;
    if (def is! CaveLevelDef ||
        shipSpec.armed ||
        demoMode ||
        debugSkipHazards ||
        debugNoCrates ||
        NarrowHaulGame._cratesDefine == 'never') {
      return;
    }
    final always = NarrowHaulGame._cratesDefine == 'always';
    if (!always && crateRng.nextDouble() >= NarrowHaulGame.kCrateChance) return;
    final spots = crateSpots(def.spec, ship: shipSpec);
    if (spots.isEmpty) return;
    final spot = spots[crateRng.nextInt(spots.length)];
    // Seekers and flak need machinery to aim at.
    final hasTargets = def.spec.obstacles.isNotEmpty;
    final pool = [
      for (final w in kWeapons)
        if (hasTargets || w.carvesRock) w,
    ];
    final w = pool[crateRng.nextInt(pool.length)];
    final units = w.crateMin + crateRng.nextInt(w.crateMax - w.crateMin + 1);
    final crate = _crate = SupplyCrate(
      pos: Offset(spot.x, spot.y),
      weapon: w,
      units: units.toDouble(),
      host: this,
      accent: theme.uiAccent,
      onCollected: _onCrateCollected,
    );
    _levelEntities.add(crate);
    await world.add(crate);
  }

  void _onCrateCollected(SupplyCrate crate) {
    if (_rack == null) return;
    Analytics.crateCollected(crate.weapon.id);
    _giveFoundAmmo(crate.weapon, crate.units, crate.pos);
    AudioService.playPickup();
    Haptics.medium();
  }

  /// Found ammo (a supply crate, a salvage Ammo Cache) for this flight: the
  /// weapon's icon flies from [at] (world) into the FIRE pad.
  void _giveFoundAmmo(WeaponSpec w, double units, Offset at) {
    final r = _rack;
    if (r == null) return;
    r.addFound(w.id, units);
    _syncWeaponHud();
    // The plate teaches a weapon once; later pickups just fly the icon in.
    final progress = ProgressService.instance;
    if (!progress.crateHintSeen(w.id)) {
      unawaited(progress.markCrateHintSeen(w.id));
      _crateNotice = CrateNotice(
        kind: w.kind,
        name: w.name,
        label: _weaponLabel(w),
        amount: w.continuous ? '${units.round()} s' : '×${units.round()}',
      );
      _crateNoticeLeft = 2.5;
    }
    final from = camera.localToGlobal(Vector2(at.dx, at.dy));
    _coach?.flyIn(Offset(from.x, from.y), w.kind);
  }

  /// Local acceleration at [p] (bombs fall along it): fields included.
  Vector2 _accelAt(Vector2 p) {
    final forces = _forces;
    if (forces == null) return world.gravity.clone();
    final a = forces.sampler.accelAt(p.x, p.y, t: forces.time);
    return Vector2(a.x, a.y);
  }

  /// Seeker target: the nearest live shootable in sight, within 14 m.
  Vector2? _seekTarget(Vector2 from) {
    Vector2? best;
    var bestD = 14.0 * 14.0;
    for (final c in world.children) {
      if (c is! BodyComponent || c is! Shootable || !c.isMounted) continue;
      if ((c as Shootable).destroyed) continue;
      final p = c.body.position;
      final d = (p - from).length2;
      if (d >= bestD) continue;
      if (!hasLineOfSight(world, from, p, ignore: c.body)) continue;
      bestD = d;
      best = p.clone();
    }
    return best;
  }

  void _onWeaponFired(WeaponSpec w, double dt) {
    final s = ship;
    if (s == null) return;
    // Once per weapon per flight (the laser fires every frame it's held).
    if (_weaponsLogged.add(w.id)) {
      Analytics.weaponUsed(w.id, carried: carriedWeaponUsedThisRun);
    }
    final accent = currentLevel?.theme.uiAccent ?? const Color(0xFFFFD166);
    final v = s.body.linearVelocity;
    final nose = s.noseDir;
    switch (w.kind) {
      case WeaponKind.charge:
        detonate(s.body.position.clone(), w);
      case WeaponKind.bomb:
        spawnShell(Shell(
          position: s.bellyWorld,
          velocity: v - nose * w.speed,
          fromPlayer: true,
          host: this,
          world: world,
          color: accent,
          weapon: w,
          gravity: _accelAt,
          lifetime: 8,
        ));
        AudioService.playShot();
      case WeaponKind.seeker:
        spawnShell(Shell(
          position: s.muzzleWorld,
          velocity: v * 0.5 + nose * w.speed,
          fromPlayer: true,
          host: this,
          world: world,
          color: accent,
          weapon: w,
          homing: _seekTarget,
          lifetime: 5,
        ));
        AudioService.playShot();
      case WeaponKind.flak:
        final base = math.atan2(nose.y, nose.x);
        for (var k = 0; k < w.pellets; k++) {
          final a = base + w.spread * (k / (w.pellets - 1) - 0.5);
          spawnShell(Shell(
            position: s.muzzleWorld,
            velocity: v + Vector2(math.cos(a), math.sin(a)) * w.speed,
            fromPlayer: true,
            host: this,
            world: world,
            color: accent,
            weapon: w,
            lifetime: 0.9,
          ));
        }
        AudioService.playShot();
      case WeaponKind.laser:
        _fireLaser(w, dt, s);
      case WeaponKind.cannon:
        return;
    }
    if (!w.continuous) Haptics.light();
    _syncWeaponHud();
  }

  void _fireLaser(WeaponSpec w, double dt, ShipBody s) {
    final from = s.muzzleWorld;
    final dir = s.noseDir;
    final to = from + dir * w.range;
    final ray = _LaserRay(cargo: combatCargo);
    world.raycast(ray, from, to);
    final hit = ray.fixture;
    final end = ray.point ?? to;
    _laserBeam
      ?..from = Offset(from.x, from.y)
      ..to = Offset(end.x, end.y)
      ..hitting = hit != null;
    // The beam burns turret shells crossing it (every frame, not per tick).
    for (final shell in _liveShells(fromPlayer: false)) {
      if (sweptSegmentHit(shell.prevPos.x, shell.prevPos.y, shell.pos.x, shell.pos.y,
          from.x, from.y, end.x, end.y, kLaserInterceptRadius)) {
        _shootDown(shell);
      }
    }
    _laserTick += dt;
    if (hit == null || _laserTick < w.tick) return;
    _laserTick = 0;
    final owner = hit.body.userData;
    if (owner is Shootable) {
      owner.takeHit(damage: w.damage, heavy: true);
    } else if (hit.body == _terrain?.body) {
      // Just inside the face: each tick cuts ~0.45 m deeper (≈2 m/s).
      final c = end + dir * 0.1;
      if (_carver?.carve(c.x, c.y, w.carveRadius) ?? false) _scheduleCarve();
    }
  }

  void _updateWeapons(double dt, ShipBody s) {
    _laserBeam?.active = s.laserFiring;
    if (!s.laserFiring) _laserTick = 0;
    if (_crateNoticeLeft > 0) {
      _crateNoticeLeft -= dt;
      if (_crateNoticeLeft <= 0) _crateNotice = null;
    }
    if (_rack != null && (s.laserFiring || _rack!.selected?.continuous == true)) {
      _syncWeaponHud();
    }
  }

  Iterable<Shell> _liveShells({required bool fromPlayer}) => world.children
      .whereType<Shell>()
      .where((s) => s.fromPlayer == fromPlayer && !s.spent)
      .toList();

  /// Player rounds meet turret shells (`combat/intercept.dart`): equal
  /// strength trades both, a stronger round flies on.
  void _interceptShells() {
    final enemies = _liveShells(fromPlayer: false);
    if (enemies.isEmpty) return;
    for (final mine in _liveShells(fromPlayer: true)) {
      for (final shell in enemies) {
        if (shell.spent || mine.spent) continue;
        if (!sweptCircleHit(
          mine.prevPos.x, mine.prevPos.y, mine.pos.x, mine.pos.y,
          shell.prevPos.x, shell.prevPos.y, shell.pos.x, shell.pos.y,
          kInterceptRadius,
        )) {
          continue;
        }
        switch (resolveIntercept(interceptStrength(mine.weapon))) {
          case InterceptOutcome.trade:
            mine.kill();
            _shootDown(shell);
          case InterceptOutcome.pierce:
            _shootDown(shell);
          case InterceptOutcome.blocked:
            mine.kill();
        }
      }
    }
  }

  /// A turret shell shot down: a small burst and a pop ([quiet] when a
  /// blast already makes the noise).
  void _shootDown(Shell shell, {bool quiet = false}) {
    shell.kill();
    _burstAt(Offset(shell.pos.x, shell.pos.y), ringRadius: 0.5);
    ProgressService.instance.incrementStat(ProgressService.statShellsIntercepted);
    if (quiet) return;
    AudioService.playIntercept();
    Haptics.light();
  }

  /// Re-extracts the carved rock (off the UI thread unless [debugSyncCarve])
  /// and swaps it in. One job at a time; holes carved meanwhile are picked
  /// up by the next run.
  void _scheduleCarve() {
    final carver = _carver;
    if (carver == null || _carveBusy || !carver.dirty) return;
    final gen = _levelGen;
    final field = carver.snapshot();
    final (nx, ny, cell) = (carver.nx, carver.ny, carver.cell);
    if (debugSyncCarve) {
      _applyCarvedLoops(extractCaveLoops(field, nx, ny, cell));
      return;
    }
    _carveBusy = true;
    extractCaveLoopsInBackground(field, nx, ny, cell).then((loops) {
      if (gen != _levelGen) return;
      _carveBusy = false;
      _applyCarvedLoops(loops);
      _scheduleCarve();
    }, onError: (Object e, StackTrace st) {
      if (gen == _levelGen) _carveBusy = false;
      ErrorReporter.report(e, st, context: 'carving rock');
    });
  }

  void _applyCarvedLoops(List<List<Pt>> loops) {
    final terrain = _terrain;
    final carver = _carver;
    if (terrain == null || carver == null || !terrain.isMounted) return;
    terrain.applyLoops(loops);
    _decor?.removeFloating((p) => carver.fieldAt(p.dx, p.dy) < 0);
    _minimap?.updateCaveLoops(loops);
    // Whatever rested on the old rock must notice it's gone.
    ship?.body.setAwake(true);
    combatCargo?.setAwake(true);
  }

  /// Turret-offline timer and the meltdown countdown; a meltdown that runs
  /// out takes the ship with it.
  void _updateCombat(double dt) {
    if (_turretsOfflineLeft > 0) {
      _turretsOfflineLeft = math.max(0, _turretsOfflineLeft - dt);
    }
    final melt = _meltdownLeft;
    _shake.floor = 0;
    // A continue's countdown holds the meltdown clock too.
    if (melt != null && (ship?.launched ?? true)) {
      final left = melt - dt;
      _meltdownLeft = left;
      // The cave rumbles harder as the clock runs down.
      _shake.floor = 0.26 + 0.21 * (1 - (left / 30).clamp(0.0, 1.0));
      if (left <= 0) {
        _meltdownLeft = null;
        _crashedByMeltdown = true;
        _onShipHitWall(cause: 'meltdown');
      }
    }
    _syncCombatHud();
  }

  void _syncCombatHud() {
    _combatHud
      ?..meltdownLeft = _meltdownLeft
      ..turretsOfflineLeft = _turretsOfflineLeft;
  }

  void _detonate(Vector2 at, WeaponSpec weapon) {
    final r = weapon.blastRadius;
    // The blast also swats turret shells out of the air.
    for (final shell in _liveShells(fromPlayer: false)) {
      if (shell.pos.distanceTo(at) <= r + Shell.radius) _shootDown(shell, quiet: true);
    }
    for (final c in world.children.toList()) {
      if (c is! BodyComponent || c is! Shootable || !c.isMounted) continue;
      final target = c as Shootable;
      if (target.destroyed) continue;
      if (_reachTo(c, at) <= r) target.takeHit(damage: weapon.damage, heavy: true);
    }
    // Shove the pod (and the ship, unless the blast is its own charge).
    final shove = r * 1.6;
    void push(Body body, double strength) {
      final d = body.worldCenter - at;
      final dist = d.length;
      if (dist >= shove || dist < 1e-4) return;
      final dv = strength * (1 - dist / shove);
      body
        ..setAwake(true)
        ..applyLinearImpulse(d.normalized()..scale(dv * body.mass));
    }

    final pod = combatCargo;
    if (pod != null && pod.bodyType == BodyType.dynamic) push(pod, 2.4);
    final s = ship;
    if (s != null && s.isMounted && weapon.kind != WeaponKind.charge) {
      push(s.body, 1.6);
    }
    if (weapon.carvesRock && (_carver?.carve(at.x, at.y, weapon.carveRadius) ?? false)) {
      _scheduleCarve();
    }
    _burstAt(Offset(at.x, at.y), ringRadius: r);
    AudioService.playBoom();
    Haptics.medium();
    _shake.add(0.55);
  }
}

String _weaponLabel(WeaponSpec w) => switch (w.kind) {
      WeaponKind.cannon => 'FIRE',
      WeaponKind.charge => 'CHARGE',
      WeaponKind.bomb => 'BOMB',
      WeaponKind.laser => 'LASER',
      WeaponKind.seeker => 'SEEKER',
      WeaponKind.flak => 'FLAK',
    };

/// How far [p] is from the surface of a shootable body (m).
double _reachTo(BodyComponent c, Vector2 p) {
  final pos = c.body.position;
  return switch (c) {
    RotatingBar b => () {
        final half = Vector2(math.cos(b.body.angle), math.sin(b.body.angle))
          ..scale(b.spec.halfLength);
        return _segmentDistance(pos - half, pos + half, p) - b.spec.thickness;
      }(),
    Pendulum q => (pos - p).length - q.spec.bobRadius,
    SlidingBlock k => (pos - p).length - math.min(k.spec.halfW, k.spec.halfH),
    Turret() => (pos - p).length - Turret.domeRadius,
    Reactor r => (pos - p).length - r.spec.radius,
    _ => (pos - p).length,
  };
}

double _segmentDistance(Vector2 a, Vector2 b, Vector2 p) {
  final ab = b - a;
  final l2 = ab.length2;
  final t = l2 == 0 ? 0.0 : ((p - a).dot(ab) / l2).clamp(0.0, 1.0);
  return (a + ab * t - p).length;
}
