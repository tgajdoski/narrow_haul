import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/ambient_particles.dart';
import 'package:narrow_haul/game/components/cargo_attachment.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/cave_decor.dart';
import 'package:narrow_haul/game/components/cave_terrain.dart';
import 'package:narrow_haul/game/components/dual_landing_zone.dart';
import 'package:narrow_haul/game/components/force_field_system.dart';
import 'package:narrow_haul/game/components/flight_hud.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/components/minimap_hud.dart';
import 'package:narrow_haul/game/components/obstacles.dart';
import 'package:narrow_haul/game/components/parallax_background.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/components/wall_box.dart';
import 'package:narrow_haul/game/components/world_dromes.dart';
import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/field_sampler.dart';
import 'package:narrow_haul/game/level/level_data.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/level/theme_assets.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/level/tiled_level_loader.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/contracts_service.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/haptics.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

enum RunState { menu, playing, gameOver, won }

/// Everything a successful delivery paid out, for the level-complete screen.
class RunReward {
  const RunReward({
    required this.xp,
    required this.xpBefore,
    required this.xpAfter,
    required this.currency,
    required this.newAchievements,
  });

  final XpBreakdown xp;
  final int xpBefore;
  final int xpAfter;
  final int currency;
  final List<AchievementMeta> newAchievements;

  PilotRank get rankBefore => rankFor(xpBefore);
  PilotRank get rankAfter => rankFor(xpAfter);
  bool get rankedUp => rankAfter.index > rankBefore.index;
}

class NarrowHaulGame extends Forge2DGame {
  static const double _baseZoom = 28;

  NarrowHaulGame() : super(gravity: narrowHaulGravity(), zoom: _baseZoom);

  RunState runState = RunState.menu;

  /// Flat index into [LevelRegistry.flat].
  int levelIndex = 0;

  LevelDef get currentLevelDef => LevelRegistry.defAt(levelIndex);

  ShipBody? ship;

  /// Intro-card line naming the ship and any non-standard gravity, so a
  /// changed ship or pull is never a surprise.
  static String _flightNote(ShipSpec ship, double gravityG) {
    final g = (gravityG - 1).abs() > 0.01 ? ' · ${gravityG.toStringAsFixed(2)}g' : '';
    return '${ship.name}$g';
  }

  /// Tank size of the active ship (fuel fractions for stars/HUD).
  double get _shipMaxFuel => ship?.maxFuel ?? kKestrel.maxFuel;
  CargoBody? cargo;
  CargoAttachment? cargoAttachment;

  /// Data of the level currently in play; null outside a level.
  LevelData? currentLevel;

  double rotateAxis = 0;
  bool thrustHeld = false;

  // ── Star / time tracking ─────────────────────────────────────────────────
  int lastLevelStars = 0;
  double lastLevelTimeSeconds = 0.0;
  RunReward? lastRunReward;

  /// In-flight seconds this attempt. Accumulated from game time, so pauses
  /// and backgrounding never count against the star time limit.
  double elapsedSeconds = 0;
  bool _timing = false;

  /// Fuel fraction left at the last delivery (for the "missed star" hint).
  double lastLevelFuelFraction = 1;
  bool _currentLevelRetried = false;

  // ── Challenge mode ───────────────────────────────────────────────────────
  bool isChallengeMode = false;
  DailyChallengeConfig? activeChallengeConfig;
  double _gravityMultiplier = 1.0;
  double _fuelDrainMultiplier = 1.0;

  // ── HUD refs ─────────────────────────────────────────────────────────────
  HudTouchControls? _hudControls;
  FuelGaugeHud? _fuelGauge;
  GravityIndicatorHud? _gravityHud;
  ForceFieldSystem? _forces;
  LevelInfoHud? _levelInfoHud;
  MinimapHud? _minimap;
  PauseButtonHud? _pauseButton;
  LevelIntroHud? _levelIntro;
  HintHud? _hint;
  DualLandingZone? _landingZone;

  // Onboarding: step hints on the first tutorial levels until first clear.
  bool _tutorialHints = false;
  double _thrustUsed = 0;
  double _rotateUsed = 0;

  // Win sequence: confetti plays while rewards are computed, then the dialog.
  static const double _winDelay = 1.1;
  double _winTimer = 0;
  bool _winReady = false;

  /// True while the pause overlay is up (runState stays [RunState.playing]).
  bool isPaused = false;

  // Crash sequence: explosion + shake play out before the gameOver overlay.
  static const double _crashDelay = 0.9;
  static const double _shakeDuration = 0.45;
  double _crashTimer = 0;
  double _shakeTimer = 0;
  Vector2? _shakeBase;
  final math.Random _shakeRng = math.Random();
  ParallaxBackground? _parallax;
  Vector2? _currentWorldSize;

  final List<Component> _levelEntities = [];

  @override
  Color backgroundColor() => const Color(0xFF050816);

  @override
  Future<void> onLoad() async {
    // Resolve game assets from assets/ root (not the default assets/images/).
    images.prefix = 'assets/';
    await super.onLoad();
    await AudioService.init();

    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.zoom = _baseZoom;

    // Parallax background — added to the game (not the viewport) at priority
    // −9999 so it renders before the CameraComponent and therefore behind
    // the world, tile layers, and all HUD elements.
    _parallax = ParallaxBackground();
    add(_parallax!);

    _fuelGauge = FuelGaugeHud();
    camera.viewport.add(_fuelGauge!);

    _gravityHud = GravityIndicatorHud();
    camera.viewport.add(_gravityHud!);

    _levelInfoHud = LevelInfoHud();
    camera.viewport.add(_levelInfoHud!);

    _minimap = MinimapHud();
    camera.viewport.add(_minimap!);

    _hudControls = HudTouchControls(
      onRotateAxis: (v) => rotateAxis = v,
      onThrust: (v) {
        thrustHeld = v;
        if (v) {
          AudioService.startThrust();
        } else {
          AudioService.stopThrust();
        }
      },
    );
    _hudControls!.size = camera.viewport.size;
    camera.viewport.add(_hudControls!);

    _pauseButton = PauseButtonHud(onPressed: pauseGame);
    camera.viewport.add(_pauseButton!);
    _levelIntro = LevelIntroHud();
    camera.viewport.add(_levelIntro!);
    _hint = HintHud();
    camera.viewport.add(_hint!);

    applySettings();

    AchievementService.announced.addListener(_onAchievementAnnounced);

    overlays.add('menu');
    pauseEngine();
  }

  @override
  void onRemove() {
    AchievementService.announced.removeListener(_onAchievementAnnounced);
    super.onRemove();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _hudControls?.size = camera.viewport.size;
    final worldSize = _currentWorldSize;
    if (worldSize != null) {
      _applyContainedCamera(worldSize);
      _applyCameraBounds(worldSize);
    }
  }

  // ── Level lifecycle ───────────────────────────────────────────────────────

  Future<void> beginPlay() async {
    overlays.remove('menu');
    overlays.remove('levelSelect');
    _resetChallenge();
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    await loadCurrentLevel();
  }

  Future<void> beginChallenge() async {
    overlays.remove('menu');
    isChallengeMode = true;
    activeChallengeConfig = DailyChallengeConfig.forToday(
      LevelRegistry.totalLevels,
    );
    levelIndex = activeChallengeConfig!.levelIndex;
    _gravityMultiplier = activeChallengeConfig!.gravityMultiplier;
    _fuelDrainMultiplier = activeChallengeConfig!.fuelDrainMultiplier;
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    await loadCurrentLevel();
  }

  void startLevel(int index) {
    overlays.removeAll([
      'menu',
      'levelSelect',
      'gameOver',
      'levelComplete',
      'rankUp',
      'pause',
      'settings',
    ]);
    _resetChallenge();
    levelIndex = index;
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    loadCurrentLevel();
  }

  /// [retry] marks a reload of the same level after a crash or restart, so
  /// clean-flight bonuses and the no-retry streak don't apply.
  Future<void> loadCurrentLevel({bool retry = false}) async {
    _clearLevel();
    _currentLevelRetried = retry;
    ProgressService.instance.incrementStat(ProgressService.statFlights);
    // In debug, rebuild caves every load so hot-reloaded spec edits show up.
    if (kDebugMode) clearCaveCache();
    final data = switch (currentLevelDef) {
      TmxLevelDef def => await loadLevelFromTmx(
        def.assetPath,
        levelIndex: levelIndex,
      ),
      CaveLevelDef def => buildCaveLevelData(def),
    };
    await _spawnLevel(data);
  }

  Future<void> _spawnLevel(LevelData data) async {
    final theme = data.theme;
    final mods = data.modifiers;

    // Gravity: base (debug-reduced) × daily challenge × level modifier.
    final g0 = baseGravityY() * _gravityMultiplier;
    final gravityMul = mods.gravityMul.clamp(0.0, kMaxGravityMul / _gravityMultiplier);
    world.gravity = Vector2(0, g0 * gravityMul);

    // Optional per-world art (assets/themes/<id>/); missing files fall back
    // to the flat palette look.
    final art = await ThemeAssets.load(images, theme);

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
      await world.add(box);
      _levelEntities.add(box);
    }

    if (data.caveLoops.isNotEmpty) {
      final terrain = CaveTerrain(
        loops: data.caveLoops,
        worldSize: data.worldSize,
        theme: theme,
        assets: art,
        friction: mods.wallFriction ?? 0.35,
      );
      await world.add(terrain);
      _levelEntities.add(terrain);

      final decor = CaveDecor(
        loops: data.caveLoops,
        rockPath: terrain.rockPath,
        theme: theme,
        assets: art,
        anchors: [
          for (final v in [data.shipSpawn, data.cargoSpawn, data.goalCenter])
            Offset(v.x, v.y),
        ],
      );
      await world.add(decor);
      _levelEntities.add(decor);
    }

    if (theme.ambient != AmbientKind.none) {
      final ambient = AmbientParticles(
        kind: theme.ambient,
        worldSize: data.worldSize,
        seed: levelIndex,
      );
      await world.add(ambient);
      _levelEntities.add(ambient);
    }

    for (final spec in data.obstacles) {
      final obstacle = obstacleFromSpec(spec, theme);
      await world.add(obstacle);
      _levelEntities.add(obstacle);
    }

    final helipad = HelipadVisual(
      center: data.shipSpawn,
      sizeMeters: Vector2(3.4, 2.4),
      base: theme.padBase,
      accent: theme.padAccent,
    );
    await world.add(helipad);
    _levelEntities.add(helipad);

    final landingStrip = LandingStripVisual(
      center: data.goalCenter,
      sizeMeters: Vector2(data.goalHalfWidth * 2, data.goalHalfHeight * 2),
    );
    await world.add(landingStrip);
    _levelEntities.add(landingStrip);

    late final CargoAttachment cargoLink;
    final shipSpec = LevelRegistry.shipFor(levelIndex);
    final shipBody = ShipBody(
      initialPosition: Vector2.copy(data.shipSpawn),
      onWallHit: _onShipHitWall,
      onHookTouchesCargo: () => cargoLink.onHookCargoTouch(),
      fuelDrainMultiplier: _fuelDrainMultiplier * mods.fuelDrainMul,
      spec: shipSpec,
    );
    final cargoBody = CargoBody(
      initialPosition: Vector2.copy(data.cargoSpawn),
      densityMul: mods.cargoDensityMul,
    );
    cargoLink = CargoAttachment(
      ship: shipBody,
      cargo: cargoBody,
      ropeMaxLengthMeters: data.ropeMaxLength * shipSpec.ropeLengthMul,
      onAttached: () {
        AudioService.playAttach();
        Haptics.light();
      },
    );

    await world.add(shipBody);
    await world.add(cargoBody);
    await world.add(cargoLink);
    _levelEntities.add(shipBody);
    _levelEntities.add(cargoBody);
    _levelEntities.add(cargoLink);

    ship = shipBody;
    cargo = cargoBody;
    cargoAttachment = cargoLink;

    _forces = null;
    if (data.fields.isNotEmpty) {
      final forces = _forces = ForceFieldSystem(
        sampler: FieldSampler(fields: data.fields, g0: g0, gravityMul: gravityMul),
        ship: shipBody,
        cargo: cargoBody,
      );
      await world.add(forces);
      _levelEntities.add(forces);
    }
    _gravityHud
      ?..show = data.fields.isNotEmpty || (g0 * gravityMul - baseGravityY()).abs() > 1e-6
      ..accent = theme.uiAccent;

    final landing = DualLandingZone(
      padCenter: data.goalCenter,
      halfWidth: data.goalHalfWidth,
      halfHeight: data.goalHalfHeight,
      onBothLanded: _onGoalReached,
    );
    await world.add(landing);
    _levelEntities.add(landing);
    _landingZone = landing;

    _currentWorldSize = data.worldSize;
    _applyContainedCamera(data.worldSize);
    _applyCameraBounds(data.worldSize);
    camera.stop();
    _snapCameraToShip();

    currentLevel = data;
    _minimap?.setLevel(data);

    elapsedSeconds = 0;
    _timing = true;
    _thrustUsed = 0;
    _rotateUsed = 0;
    _tutorialHints =
        !isChallengeMode &&
        levelIndex < 3 &&
        currentLevelDef is TmxLevelDef &&
        ProgressService.instance.getStarsById(currentLevelDef.saveId) == 0;
    _pauseButton?.visible = true;
    _fuelGauge?.starMarks = [
      currentLevelDef.stars.star3Fuel,
      currentLevelDef.stars.star2Fuel,
    ];
    _updateLevelInfoHud();

    final (levelWorld, indexInWorld) = LevelRegistry.worldOf(levelIndex);
    _levelIntro?.show(
      title: currentLevelDef.name,
      subtitle: isChallengeMode
          ? 'Daily Challenge · ${activeChallengeConfig?.modifierName ?? ''}'
          : '${levelWorld.name} · ${indexInWorld + 1}/${levelWorld.levels.length}',
      accent: theme.uiAccent,
      note: _flightNote(shipSpec, g0 * gravityMul / baseGravityY()),
    );
  }

  void _updateLevelInfoHud() {
    final info = _levelInfoHud;
    if (info == null) return;
    final challengeTag = isChallengeMode
        ? ' [${activeChallengeConfig?.modifierName ?? ''}]'
        : '';
    final (world, indexInWorld) = LevelRegistry.worldOf(levelIndex);
    info.levelLabel =
        '${world.name} ${indexInWorld + 1}/${world.levels.length}$challengeTag';
    info.stars = ProgressService.instance.getStarsById(currentLevelDef.saveId);
    final spec = currentLevelDef.stars;
    info
      ..star3Fuel = spec.star3Fuel
      ..star2Fuel = spec.star2Fuel
      ..star3Time = spec.star3Time;
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  void _applyContainedCamera(Vector2 worldSize) {
    final viewportSize = camera.viewport.size;
    if (viewportSize.x <= 0 || viewportSize.y <= 0) return;
    final minZoomX = viewportSize.x / worldSize.x;
    final minZoomY = viewportSize.y / worldSize.y;
    final minContainZoom = math.max(minZoomX, minZoomY) * 1.01;
    camera.viewfinder.zoom = math.max(_baseZoom, minContainZoom);
  }

  void _applyCameraBounds(Vector2 worldSize) {
    camera.setBounds(
      Rectangle.fromLTWH(0, 0, worldSize.x, worldSize.y),
      considerViewport: true,
    );
  }

  void _snapCameraToShip() {
    final s = ship;
    final worldSize = _currentWorldSize;
    if (s == null || worldSize == null) return;
    camera.viewfinder.position = _clampedCameraTarget(
      s.body.position,
      worldSize,
    );
  }

  Vector2 _clampedCameraTarget(Vector2 desired, Vector2 worldSize) {
    final viewportSize = camera.viewport.size;
    final zoom = camera.viewfinder.zoom;
    if (viewportSize.x <= 0 || viewportSize.y <= 0 || zoom <= 0) return desired;

    final halfViewW = (viewportSize.x / zoom) / 2;
    final halfViewH = (viewportSize.y / zoom) / 2;

    final minX = halfViewW;
    final maxX = worldSize.x - halfViewW;
    final minY = halfViewH;
    final maxY = worldSize.y - halfViewH;

    final x = minX > maxX ? worldSize.x / 2 : desired.x.clamp(minX, maxX);
    final y = minY > maxY ? worldSize.y / 2 : desired.y.clamp(minY, maxY);
    return Vector2(x.toDouble(), y.toDouble());
  }

  // ── Level cleanup ─────────────────────────────────────────────────────────

  void _clearLevel() {
    camera.stop();
    for (final c in _levelEntities.reversed) {
      c.removeFromParent();
    }
    _levelEntities.clear();
    ship = null;
    cargo = null;
    cargoAttachment = null;
    currentLevel = null;
    _minimap?.setLevel(null);
    _currentWorldSize = null;
    _timing = false;
    isPaused = false;
    _landingZone = null;
    _hint?.message = null;
    _winTimer = 0;
    _winReady = false;
    _crashTimer = 0;
    _shakeTimer = 0;
    _pauseButton?.visible = false;
    _resetInputState();
  }

  void _resetInputState() {
    rotateAxis = 0;
    thrustHeld = false;
    AudioService.stopThrust();
  }

  void _resetChallenge() {
    isChallengeMode = false;
    activeChallengeConfig = null;
    _gravityMultiplier = 1.0;
    _fuelDrainMultiplier = 1.0;
    world.gravity = narrowHaulGravity();
  }

  // ── Game events ───────────────────────────────────────────────────────────

  void _onShipHitWall() {
    if (runState != RunState.playing) return;
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
    _pauseButton?.visible = false;
    _hint?.message = null;

    // Let the wreck play out (explosion + shake) before the dialog; the
    // overlay is raised from update() when [_crashTimer] runs out.
    final s = ship;
    if (s != null) {
      s.wreck();
      final p = s.body.position;
      final burst = ExplosionBurst(
        center: Offset(p.x, p.y),
        accent: currentLevel?.theme.uiAccent ?? const Color(0xFFFF6B35),
        seed: levelIndex,
      );
      world.add(burst);
      _levelEntities.add(burst);
    }
    _shakeBase = camera.viewfinder.position.clone();
    _shakeTimer = _shakeDuration;
    _crashTimer = _crashDelay;
  }

  Future<void> _onGoalReached() async {
    if (runState != RunState.playing) return;
    // Claim the win before any await so a second contact can't re-enter.
    runState = RunState.won;

    final elapsed = elapsedSeconds;
    _pauseButton?.visible = false;
    _hint?.message = null;
    Haptics.medium();
    ship?.setInput(rotate: 0, thrust: false);
    _resetInputState();
    final goal = currentLevel?.goalCenter;
    if (goal != null) {
      final burst = CelebrationBurst(
        center: Offset(goal.x, goal.y),
        accent: currentLevel!.theme.uiAccent,
        seed: levelIndex,
      );
      world.add(burst);
      _levelEntities.add(burst);
    }
    _winTimer = _winDelay;
    _winReady = false;
    final fuelLeft = ship?.fuel ?? 0.0;
    lastLevelFuelFraction = fuelLeft / _shipMaxFuel;

    _recordSpentFuel();
    _recordPlaytime();

    final stars = _calculateStars(fuelLeft, elapsed);
    lastLevelStars = stars;
    lastLevelTimeSeconds = elapsed;

    final progress = ProgressService.instance;
    final xpBefore = progress.getXp();
    final currencyMul = CareerService.currencyMultiplier;
    int currency = 0;
    final XpBreakdown runXp;

    progress.incrementStat(ProgressService.statDeliveries);
    final (levelWorld, _) = LevelRegistry.worldOf(levelIndex);
    final worldIndex = LevelRegistry.worlds.indexOf(levelWorld);
    int earnedStars = 0;
    bool personalBest = false;

    if (isChallengeMode) {
      final firstToday = !progress.isDailyChallengeComplete();
      int streak = progress.getDailyStreak();
      if (firstToday) {
        currency += (50 * currencyMul).round(); // Daily reward
        streak = await progress.advanceDailyStreak();
      }
      progress.markDailyChallengeComplete();
      progress.saveDailyBestTime(elapsed);
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
      if (!firstToday) progress.addReplayXpToday(runXp.total);
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

      progress.saveStarsById(def.saveId, stars);
      progress.saveBestTimeById(def.saveId, elapsed);

      // No-retry streak
      if (!_currentLevelRetried) {
        final streak = progress.getNoRetryStreak() + 1;
        progress.setNoRetryStreak(streak);
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
        progress.addReplayXpToday(runXp.total);
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
      ),
    );

    final unlocked = [
      ..._inFlightAchievements,
      ...await _checkAchievements(
        stars,
        elapsed,
        fuelLeft,
        allContractsDone: allContractsDone,
      ),
    ];
    _inFlightAchievements.clear();
    var xp = XpBreakdown([
      ...runXp.lines,
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
    if (currency > 0) progress.addCosmeticCurrency(currency);

    lastRunReward = RunReward(
      xp: xp,
      xpBefore: xpBefore,
      xpAfter: xpAfter,
      currency: currency,
      newAchievements: unlocked,
    );

    AudioService.playLand();
    if (stars >= 2) AudioService.playStar();

    _resetInputState();
    // update() raises the dialog once the celebration has played.
    _winReady = true;
  }

  int _calculateStars(double fuelRemaining, double timeSeconds) {
    final pct = fuelRemaining / _shipMaxFuel;
    final spec = currentLevelDef.stars;
    if (pct >= spec.star3Fuel && timeSeconds <= spec.star3Time) return 3;
    if (pct >= spec.star2Fuel) return 2;
    return 1;
  }

  /// Runs the post-win achievement checks; returns the newly unlocked ones.
  Future<List<AchievementMeta>> _checkAchievements(
    int stars,
    double timeSeconds,
    double fuelRemaining, {
    required bool allContractsDone,
  }) async {
    final progress = ProgressService.instance;
    final candidates = <String>[AchievementIds.firstHaul];

    if (fuelRemaining >= 0.9 * _shipMaxFuel) candidates.add(AchievementIds.fuelMiser);
    if (timeSeconds < 30) candidates.add(AchievementIds.speedHauler);

    final streak = progress.getNoRetryStreak();
    if (!_currentLevelRetried && streak >= 5) {
      candidates.add(AchievementIds.noScratch);
    }

    int completed = 0;
    bool allPerfect = true;
    for (final def in LevelRegistry.flat) {
      final s = progress.getStarsById(def.saveId);
      if (s > 0) completed++;
      if (s < 3) allPerfect = false;
    }
    if (completed >= 10) candidates.add(AchievementIds.level10);
    if (completed >= LevelRegistry.totalLevels) {
      candidates.add(AchievementIds.level20);
    }

    if (isChallengeMode) candidates.add(AchievementIds.dailyPilot);

    if (allPerfect) candidates.add(AchievementIds.perfectPilot);

    if (allContractsDone) candidates.add(AchievementIds.fullManifest);
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

  /// Achievements unlocked mid-flight (e.g. Cargo Swinger). Their XP is paid
  /// with the delivery, or straight away if the flight ends in a crash.
  final List<AchievementMeta> _inFlightAchievements = [];

  void _onAchievementAnnounced() {
    final a = AchievementService.announced.value;
    if (a != null && runState == RunState.playing) _inFlightAchievements.add(a);
  }

  void _payInFlightAchievementXp() {
    if (_inFlightAchievements.isEmpty) return;
    ProgressService.instance.addXp(100 * _inFlightAchievements.length);
    _inFlightAchievements.clear();
  }

  void _recordPlaytime() {
    if (!_timing) return;
    _timing = false; // stop the clock; also prevents double counting
    final seconds = elapsedSeconds.floor();
    if (seconds > 0) {
      ProgressService.instance.incrementStat(
        ProgressService.statPlaytimeSeconds,
        seconds,
      );
    }
  }

  void _recordSpentFuel() {
    if (ship != null) {
      final spent = ship!.maxFuel - ship!.fuel;
      if (spent > 0) {
        ProgressService.instance.addFuelSpent(spent);
        ship!.fuel = ship!.maxFuel; // prevent double counting
      }
    }
  }

  // ── Public navigation ─────────────────────────────────────────────────────

  void restartLevel() {
    overlays.removeAll(['gameOver', 'pause', 'settings']);
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    loadCurrentLevel(retry: true);
  }

  Future<void> nextLevel() async {
    overlays.removeAll(['levelComplete', 'rankUp']);
    _resetInputState();
    if (!isChallengeMode) {
      if (levelIndex < LevelRegistry.totalLevels - 1) {
        levelIndex++;
      } else {
        levelIndex = 0;
      }
    }
    runState = RunState.playing;
    resumeEngine();
    await loadCurrentLevel();
  }

  void backToMenu() {
    overlays.removeAll(['gameOver', 'pause', 'settings']);
    // Quitting mid-flight still counts the time flown.
    _recordPlaytime();
    overlays.removeAll(['levelComplete', 'rankUp']);
    _recordSpentFuel();
    _resetInputState();
    _clearLevel();
    _resetChallenge();
    runState = RunState.menu;
    pauseEngine();
    overlays.add('menu');
  }

  /// Landing status beats tutorial steps: it explains the both-on-pad rule
  /// at exactly the moment a player is confused by it.
  String? _currentHint() {
    final zone = _landingZone;
    if (zone != null && zone.shipInside != zone.cargoInside) {
      return zone.shipInside
          ? 'Lower the cargo onto the pad too'
          : 'Cargo is on the pad — now land the ship';
    }
    if (!_tutorialHints) return null;
    final attached = cargoAttachment?.attached == true;
    final steerSide = _hudControls?.leftHanded == true ? 'right' : 'left';
    final thrustSide = _hudControls?.leftHanded == true ? 'left' : 'right';
    if (_thrustUsed < 0.6) {
      return 'Hold the THRUST button ($thrustSide) to fire the engine';
    }
    if (_rotateUsed < 0.5) {
      return 'Drag on the $steerSide side to rotate the ship';
    }
    if (!attached) {
      return 'Fly close to the cargo — the rope hooks on by itself';
    }
    return 'Bring ship and cargo down onto the green pad';
  }

  // ── Pause & settings ──────────────────────────────────────────────────────

  void pauseGame() {
    if (runState != RunState.playing || isPaused || ship == null) return;
    isPaused = true;
    _resetInputState();
    ship?.setInput(rotate: 0, thrust: false);
    pauseEngine();
    overlays.add('pause');
  }

  void resumeGame() {
    if (!isPaused) return;
    isPaused = false;
    overlays.removeAll(['pause', 'settings']);
    resumeEngine();
  }

  /// Pushes persisted settings into the running systems.
  void applySettings() {
    final p = ProgressService.instance;
    AudioService.setEnabled(p.soundEnabled);
    _hudControls?.leftHanded = p.leftHanded;
    _minimap?.refreshLayout();
  }

  @override
  void lifecycleStateChange(AppLifecycleState state) {
    // Leaving the app mid-flight opens the pause menu, rather than letting
    // Flame silently auto-resume the flight on return.
    if (state != AppLifecycleState.resumed) pauseGame();
    super.lifecycleStateChange(state);
  }

  // ── Update loop ───────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    super.update(dt);

    if (_crashTimer > 0) {
      _crashTimer -= dt;
      if (_crashTimer <= 0 && runState == RunState.gameOver) {
        pauseEngine();
        overlays.add('gameOver');
      }
    }
    final shakeBase = _shakeBase;
    if (_shakeTimer > 0 && shakeBase != null) {
      _shakeTimer = math.max(0, _shakeTimer - dt);
      final amp = 0.35 * (_shakeTimer / _shakeDuration);
      camera.viewfinder.position =
          shakeBase +
          Vector2(_shakeRng.nextDouble() - 0.5, _shakeRng.nextDouble() - 0.5) *
              (2 * amp);
    }

    if (_winTimer > 0) _winTimer -= dt;
    if (_winReady && _winTimer <= 0 && runState == RunState.won) {
      _winReady = false;
      pauseEngine();
      overlays.add('levelComplete');
    }

    final s = ship;
    if (s != null && runState == RunState.playing) {
      // The clock starts with the first input (the ship waits on its pad).
      if (_timing && s.launched) elapsedSeconds += dt;
      if (thrustHeld) _thrustUsed += dt;
      if (rotateAxis.abs() > 0.3) _rotateUsed += dt;
      _hint?.message = _currentHint();
      final worldSize = _currentWorldSize;
      if (worldSize != null) {
        final target = _clampedCameraTarget(s.body.position, worldSize);
        final current = camera.viewfinder.position;
        camera.viewfinder.position = current + (target - current) * 0.18;
      }

      s.setInput(rotate: rotateAxis, thrust: thrustHeld);

      final tow = cargoAttachment?.attached == true;

      // Update fuel gauge
      _fuelGauge?.fuelFraction = s.fuel / s.maxFuel;
      _fuelGauge?.towing = tow;
      _gravityHud?.accelG
        ?..setFrom(_forces?.shipAccel ?? world.gravity)
        ..scale(1 / baseGravityY());
      _levelInfoHud
        ?..elapsed = elapsedSeconds
        ..fuelFraction = s.fuel / s.maxFuel;
    }
  }
}
