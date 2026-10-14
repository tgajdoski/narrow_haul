part of '../narrow_haul_game.dart';

/// Mystery salvage: caches, effects, curses and their HUD.
extension GameSalvage on NarrowHaulGame {
  bool get _chaosDay => isChallengeMode && (activeChallengeConfig?.chaos ?? false);

  /// Maybe drops "?" caches: any cave level and ship (three on a chaos day),
  /// never in demos or bot flights. Spots are clear of the anchors and of
  /// every turret's view.
  Future<void> _maybeSpawnSalvage(ShipSpec shipSpec) async {
    final def = currentLevelDef;
    if (def is! CaveLevelDef ||
        demoMode ||
        debugSkipHazards ||
        debugNoSalvage ||
        NarrowHaulGame._salvageDefine == 'never') {
      return;
    }
    final now = DateTime.now();
    final rng = _salvageRoll = isChallengeMode
        ? math.Random(now.year * 10000 + now.month * 100 + now.day)
        : salvageRng;
    final forced = NarrowHaulGame._salvageDefine.isNotEmpty || _chaosDay;
    if (!forced && rng.nextDouble() >= NarrowHaulGame.kSalvageChance) return;
    final crate = _crate?.pos;
    final spots = [
      for (final p in salvageSpots(def.spec, ship: shipSpec))
        if (crate == null || (Offset(p.x, p.y) - crate).distance > 3) Offset(p.x, p.y),
    ];
    final count = _chaosDay ? NarrowHaulGame._chaosCaches : 1;
    final placed = <Offset>[];
    for (var tries = 0; placed.length < count && spots.isNotEmpty && tries < 40; tries++) {
      final spot = spots.removeAt(rng.nextInt(spots.length));
      if (placed.any((p) => (p - spot).distance < 4)) continue;
      placed.add(spot);
    }
    for (final spot in placed) {
      final cache = SalvageCache(pos: spot, host: this, onCollected: _onSalvageCollected);
      _salvageCaches.add(cache);
      _levelEntities.add(cache);
      await world.add(cache);
    }
  }

  void _onSalvageCollected(SalvageCache cache) {
    final s = ship;
    final goal = currentLevel?.goalCenter;
    final nearPad = goal != null &&
        (Vector2(cache.pos.dx, cache.pos.dy) - goal).length < kSalvageNoCurseNearPad;
    final liveTurrets = world.children.whereType<Turret>().any((t) => !t.destroyed);
    final spec = salvageById(NarrowHaulGame._salvageDefine) ??
        pickSalvage(
          _salvageRoll,
          SalvageContext(
            liveTurrets: liveTurrets,
            nearPad: nearPad,
            lastWasCurse: !isChallengeMode && _lastSalvageCurse,
            towing: cargoAttachment?.attached ?? false,
            unarmed: !(s?.spec.armed ?? false),
            lowFuel: s != null && s.fuel < 0.3 * s.maxFuel,
            themeId: currentLevel?.theme.id,
            chaos: _chaosDay,
          ),
        );
    _lastSalvageCurse = !spec.good;
    _salvageOpenedThisRun++;
    // A cache opened mid-roulette replaces the one still spinning.
    _salvagePending = spec;
    _salvageRevealLeft = SalvageHud.rouletteSeconds;
    _salvageHud?.spin(spec);
    _salvageAura?.pop(cache.pos, Colors.white);
    _bookSalvageFind(spec);
    Analytics.salvageOpened(spec.id, good: spec.good);
    AudioService.playPickup();
    Haptics.light();
  }

  /// Stats, the Salvage Log and the salvage achievements for one find.
  void _bookSalvageFind(SalvageSpec spec) {
    final progress = ProgressService.instance;
    unawaited(progress.incrementStat(ProgressService.statSalvageOpened));
    if (!spec.good) unawaited(progress.incrementStat(ProgressService.statSalvageCurses));
    final firstOfKind = progress.salvageFound(spec.id) == 0;
    unawaited(progress.recordSalvageFound(spec.id));
    final streak = spec.good ? progress.getStat(ProgressService.statSalvageBoonStreak) + 1 : 0;
    unawaited(progress.setStat(ProgressService.statSalvageBoonStreak, streak));

    AchievementService.unlock(AchievementIds.openedTheBox, announce: true);
    if (progress.getStat(ProgressService.statSalvageOpened) + 1 >= 50) {
      AchievementService.unlock(AchievementIds.gambler, announce: true);
    }
    if (streak >= 3) AchievementService.unlock(AchievementIds.clover, announce: true);
    final all = kSalvage.every((s) => s.id == spec.id || progress.salvageFound(s.id) > 0);
    if (firstOfKind && all) {
      unawaited(() async {
        if (await AchievementService.unlock(AchievementIds.salvageCollector, announce: true)) {
          await progress.addCosmeticCurrency(kSalvageCollectorCoins);
          Analytics.earnCoins(kSalvageCollectorCoins, 'salvage_collector');
        }
      }());
    }
  }

  /// The roulette stopped: [spec] takes effect.
  void _applySalvage(SalvageSpec spec) {
    final s = ship;
    if (s == null || runState != RunState.playing) return;
    salvage.start(spec);
    switch (spec.effect) {
      case SalvageEffect.topOff:
        s.fuel = math.min(s.maxFuel, s.fuel + kTopOffFraction * s.maxFuel);
      case SalvageEffect.lucky:
        _luckyCoins += kLuckyCoins;
      case SalvageEffect.ammoCache:
        _giveSalvageAmmo(s);
      case SalvageEffect.hiccups:
        _hiccupIn = 0.5;
      default:
        break;
    }
    if (!spec.good) _cursesThisRun.add(spec);
    final p = s.body.position;
    _salvageAura?.pop(Offset(p.x, p.y), salvageColor(spec));
    if (spec.good) {
      AudioService.playSalvageBoon();
      Haptics.medium();
    } else {
      AudioService.playCurse();
      Haptics.heavy();
    }
    if (spec.effect == SalvageEffect.swarmSting) AudioService.playSizeUp();
    if (spec.effect == SalvageEffect.compactor) AudioService.playSizeDown();
    _comms?.say(
      CommsLine(id: 'salvage_${spec.id}_$_salvageOpenedThisRun', callsign: spec.callsign, text: spec.quip),
      urgent: true,
    );
  }

  /// Ammo Cache: a random weapon's ammo, as if a supply crate was flown
  /// through (the icon flies into the FIRE pad).
  void _giveSalvageAmmo(ShipBody s) {
    final r = _rack;
    final def = currentLevelDef;
    if (r == null) return;
    final hasTargets = def is CaveLevelDef && def.spec.obstacles.isNotEmpty;
    final pool = [
      for (final w in kWeapons)
        if (hasTargets || w.carvesRock) w,
    ];
    final w = pool[_salvageRoll.nextInt(pool.length)];
    final units = w.crateMin + _salvageRoll.nextInt(w.crateMax - w.crateMin + 1);
    _giveFoundAmmo(w, units.toDouble(), Offset(s.body.position.x, s.body.position.y));
  }

  /// Ticks the running effect and feeds it to the ship: engine, drain and
  /// steering, the cloak, extra forces, the screen effects and the hull
  /// size, which grows only into free space (a curse never wedges the ship
  /// into rock). [realDt] is wall time: Chrono slows the cave, not itself.
  void _updateSalvage(double realDt, ShipBody s) {
    final dt = realDt;
    if (_hitImmunity > 0) _hitImmunity -= dt;
    if (_salvageRevealLeft > 0) {
      _salvageRevealLeft -= dt;
      final spec = _salvagePending;
      if (_salvageRevealLeft <= 0 && spec != null) {
        _salvagePending = null;
        _applySalvage(spec);
      }
    }
    final angle = s.body.angle;
    final last = _salvageLastAngle;
    _salvageLastAngle = angle;
    var spin = 0.0;
    if (last != null) {
      spin = (angle - last) % (2 * math.pi);
      if (spin > math.pi) spin -= 2 * math.pi;
    }
    final before = salvage.effect;
    salvage.tick(dt, spinRadians: spin);
    if (before != null && salvage.effect == null) _onSalvageEnded(before);

    s
      ..salvageThrustMul = salvage.thrustMul
      ..salvageDrainMul = salvage.drainMul;
    final cloakTo = salvage.cloaked ? 1.0 : 0.0;
    s.cloak += (cloakTo - s.cloak).clamp(-dt * 4, dt * 4);
    if (salvage.cloaked) _checkGhostProtocol(s, dt);

    _updateSalvageForces(s);
    if (salvage.hiccups && s.launched) {
      _hiccupIn -= dt;
      if (_hiccupIn <= 0) {
        _hiccupIn = 0.7 + _salvageRoll.nextDouble() * 0.7;
        final kick = (_salvageRoll.nextBool() ? 1 : -1) * (0.18 + 0.12 * _salvageRoll.nextDouble());
        s.body
          ..setTransform(s.body.position, s.body.angle + kick)
          ..setAwake(true);
        _cam.shake.add(0.18);
        Haptics.light();
      }
    }

    // The size eases smoothly; the hull is rebuilt in 0.02 steps.
    final target = salvage.hullTarget;
    var k = _hullK;
    const growSpan = kSwellScale - 1;
    if (k < target) {
      final next = math.min(target, k + dt * growSpan / 1.5);
      final step = next >= s.sizeMul + 0.02 || next == target;
      k = step ? _swellStep(s, next) : next;
    } else if (k > target) {
      k = math.max(target, k - dt * growSpan / 0.6);
    }
    _hullK = k;
    if ((k - s.sizeMul).abs() >= 0.02 || (k == target && k != s.sizeMul)) {
      s.setSizeMul(k);
    }
    s.swell = ((s.sizeMul - 1) / growSpan).clamp(0.0, 1.0);
    s.sputtering = salvage.sputterCut;
    _salvageAura?.gravity.setFrom(s.localAccel);

    final fx = _salvageFx;
    if (fx != null) {
      final screen = camera.localToGlobal(s.body.position);
      fx
        ..shipScreen = Offset(screen.x, screen.y)
        ..pxPerMeter = camera.viewfinder.zoom
        ..noseAngle = s.body.angle
        ..darkness = salvage.darkness
        ..hallucination = salvage.hallucination
        ..chrono = salvage.effect == SalvageEffect.chrono ? salvage.ramp : 0;
    }
    _syncSporeShader();
    AudioService.setBuzz(salvage.effect == SalvageEffect.swarmSting);
    AudioService.setSpores(salvage.effect == SalvageEffect.sporeTrip);
  }

  /// Anti-grav lifts half the pull off ship and pod; Heavy Heart adds weight
  /// to the towed pod. Forces apply on the next physics step.
  void _updateSalvageForces(ShipBody s) {
    final lift = 1 - salvage.gravityMul;
    if (lift > 0 && s.launched) {
      s.body.applyForce(s.localAccel * (-lift * s.body.mass));
    }
    final c = cargo;
    if (c == null || !c.isMounted || c.body.bodyType != BodyType.dynamic) return;
    final extra = -lift + (cargoAttachment?.attached ?? false ? salvage.podWeightAdd : 0);
    if (extra == 0) return;
    final p = c.body.position;
    final g = _forces == null ? world.gravity : _accelAt(p);
    c.body.applyForce(g * (extra * c.body.mass));
  }

  void _onSalvageEnded(SalvageEffect e) {
    switch (e) {
      case SalvageEffect.swarmSting when salvage.takeShakenOff():
        _comms?.say(
          const CommsLine(id: 'salvage_shaken', callsign: 'TOWER', text: 'Bee\'s gone. Good shake.'),
          urgent: true,
        );
        AchievementService.unlock(AchievementIds.shakeItOff, announce: true);
      case SalvageEffect.compactor:
        _comms?.say(
          const CommsLine(id: 'salvage_regrow', callsign: 'OPS', text: 'Compactor\'s wearing off. You\'ll grow back when there\'s room.'),
          urgent: true,
        );
        AudioService.playSizeUp();
      default:
        break;
    }
  }

  /// Ghost Protocol: a turret's sights crossed while cloaked.
  void _checkGhostProtocol(ShipBody s, double dt) {
    _ghostCheckIn -= dt;
    if (_ghostCheckIn > 0) return;
    _ghostCheckIn = 0.25;
    final p = s.body.position;
    if (world.children.whereType<Turret>().any((t) => t.covers(p))) {
      AchievementService.unlock(AchievementIds.ghostProtocol, announce: true);
    }
  }

  /// Spore Trip warps the world through a fragment shader while it runs
  /// (the canvas overlay alone where shaders aren't available).
  void _syncSporeShader() {
    final program = NarrowHaulGame._sporeProgram;
    final want = program != null && salvage.hallucination > 0;
    if (want == (_sporePost != null)) return;
    if (want) {
      _sporePost = SporePostProcess(program, () => salvage.hallucination);
      camera.postProcess = _sporePost;
    } else {
      _sporePost = null;
      camera.postProcess = null;
    }
  }

  /// How far the hull may grow toward [want] this frame. Growing adds up to
  /// `Δk × circumradius` of reach on every side: with rock closer than that
  /// on one side (resting on a floor, hugging a wall), the ship eases away
  /// from it if there's room opposite; wedged in, it waits.
  double _swellStep(ShipBody s, double want) {
    const margin = 0.06;
    final k = s.sizeMul;
    final need = (want - k) * s.spec.circumradius;
    final near = probeRockNearby(world, s, range: need + 0.6);
    if (near == null || near.gap >= need + margin) return want;
    final push = need + margin - math.max(0.0, near.gap);
    final away = probeAhead(world, s, near.normal, range: push + need + 0.6);
    if (away != null && away < push + need + margin) return k;
    s.body
      ..setTransform(s.body.position + near.normal * push, s.body.angle)
      ..setAwake(true);
    return want;
  }

  /// A crash the salvage takes instead: the Overshield pops, or a curse
  /// that just started is forgiven. A bounce straight after doesn't count.
  bool _salvageAbsorbs() {
    if (_hitImmunity > 0) return true;
    if (!salvage.canAbsorb) return false;
    final shield = salvage.effect == SalvageEffect.overshield;
    salvage.absorb();
    _hitImmunity = 0.6;
    final s = ship;
    if (s != null) {
      final v = s.body.linearVelocity;
      final normal = v.length2 > 1e-4 ? -(v.normalized()) : Vector2(0, -1);
      world.add(ShieldFlash(ship: s, rockNormal: normal, strength: 1));
      final p = s.body.position;
      _salvageAura?.pop(Offset(p.x, p.y), shield ? kSalvageGood : Colors.white);
    }
    AudioService.playScrape();
    Haptics.medium();
    if (shield) {
      _comms?.say(
        const CommsLine(id: 'salvage_absorbed', callsign: 'OPS', text: 'Overshield took that one. It\'s gone now.'),
        urgent: true,
      );
    }
    return true;
  }

  /// Crossed Wires rests near the pad (never sabotage a landing).
  bool get _wiresCrossed {
    if (!salvage.crossed) return false;
    final s = ship, goal = currentLevel?.goalCenter;
    return s == null || goal == null || (s.body.position - goal).length >= kSalvageNoCurseNearPad;
  }

  void _resetSalvage() {
    salvage.reset();
    _salvagePending = null;
    _salvageRevealLeft = 0;
    _hitImmunity = 0;
    _salvageLastAngle = null;
    _hullK = 1;
    _hiccupIn = 0;
    final s = ship;
    if (s != null) {
      s
        ..salvageThrustMul = 1
        ..salvageDrainMul = 1
        ..cloak = 0
        ..swell = 0
        ..sputtering = false
        ..setSizeMul(1);
    }
    _salvageFx
      ?..darkness = 0
      ..hallucination = 0
      ..chrono = 0;
    if (_sporePost != null) {
      _sporePost = null;
      camera.postProcess = null;
    }
    AudioService.setBuzz(false);
    AudioService.setSpores(false);
  }
}
