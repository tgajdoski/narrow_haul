import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/cargo_attachment.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/cave_terrain.dart';
import 'package:narrow_haul/game/components/dual_landing_zone.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/components/obstacles.dart';
import 'package:narrow_haul/game/components/parallax_background.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/components/wall_box.dart';
import 'package:narrow_haul/game/components/world_dromes.dart';
import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/level_data.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/level/tiled_level_loader.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

enum RunState { menu, playing, gameOver, won }

class NarrowHaulGame extends Forge2DGame {
  static const double _baseZoom = 28;

  NarrowHaulGame()
    : super(
        gravity: narrowHaulGravity(),
        zoom: _baseZoom,
      );

  RunState runState = RunState.menu;

  /// Flat index into [LevelRegistry.flat].
  int levelIndex = 0;

  LevelDef get currentLevelDef => LevelRegistry.defAt(levelIndex);

  ShipBody? ship;
  CargoBody? cargo;
  CargoAttachment? cargoAttachment;

  double rotateAxis = 0;
  bool thrustHeld = false;

  // ── Star / time tracking ─────────────────────────────────────────────────
  int lastLevelStars = 0;
  double lastLevelTimeSeconds = 0.0;
  DateTime? _levelStartTime;
  bool _currentLevelRetried = false;

  // ── Challenge mode ───────────────────────────────────────────────────────
  bool isChallengeMode = false;
  DailyChallengeConfig? activeChallengeConfig;
  double _gravityMultiplier = 1.0;
  double _fuelDrainMultiplier = 1.0;

  // ── HUD refs ─────────────────────────────────────────────────────────────
  HudTouchControls? _hudControls;
  FuelGaugeHud? _fuelGauge;
  LevelInfoHud? _levelInfoHud;
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

    _levelInfoHud = LevelInfoHud();
    camera.viewport.add(_levelInfoHud!);

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

    overlays.add('menu');
    pauseEngine();
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
    activeChallengeConfig = DailyChallengeConfig.forToday(LevelRegistry.totalLevels);
    levelIndex = activeChallengeConfig!.levelIndex;
    _gravityMultiplier = activeChallengeConfig!.gravityMultiplier;
    _fuelDrainMultiplier = activeChallengeConfig!.fuelDrainMultiplier;
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    await loadCurrentLevel();
  }

  void startLevel(int index) {
    overlays.remove('menu');
    overlays.remove('levelSelect');
    _resetChallenge();
    levelIndex = index;
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    loadCurrentLevel();
  }

  Future<void> loadCurrentLevel() async {
    _clearLevel();
    _currentLevelRetried = false;
    // In debug, rebuild caves every load so hot-reloaded spec edits show up.
    if (kDebugMode) clearCaveCache();
    final data = switch (currentLevelDef) {
      TmxLevelDef def => await loadLevelFromTmx(def.assetPath, levelIndex: levelIndex),
      CaveLevelDef def => buildCaveLevelData(def),
    };
    await _spawnLevel(data);
  }

  Future<void> _spawnLevel(LevelData data) async {
    final theme = data.theme;
    final mods = data.modifiers;

    // Gravity: base (debug-reduced) × daily challenge × level modifier.
    final baseY = kDebugMode && kDebugReduceGravity
        ? kGravityY * kDebugGravityScale
        : kGravityY;
    world.gravity = Vector2(0, baseY * _gravityMultiplier * mods.gravityMul);

    // Theme the shared parallax sky.
    _parallax?.tint = theme.parallaxTint;
    _parallax?.alphas = theme.parallaxAlphas;

    final backdrop = RectangleComponent(
      size: data.worldSize,
      paint: Paint()..color = theme.backdropColor,
      priority: -2000,
    )..position = Vector2.zero();
    world.add(backdrop);
    _levelEntities.add(backdrop);

    for (final w in data.walls) {
      final box = WallBox(
        wallCenter: w.center,
        halfWidth: w.halfWidth,
        halfHeight: w.halfHeight,
      );
      await world.add(box);
      _levelEntities.add(box);
    }

    if (data.caveLoops.isNotEmpty) {
      final terrain = CaveTerrain(
        loops: data.caveLoops,
        worldSize: data.worldSize,
        theme: theme,
        friction: mods.wallFriction ?? 0.35,
      );
      await world.add(terrain);
      _levelEntities.add(terrain);
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
      sizeMeters: Vector2(
        data.goalHalfWidth * 2,
        data.goalHalfHeight * 2,
      ),
    );
    await world.add(landingStrip);
    _levelEntities.add(landingStrip);

    late final CargoAttachment cargoLink;
    final shipBody = ShipBody(
      initialPosition: Vector2.copy(data.shipSpawn),
      onWallHit: _onShipHitWall,
      onHookTouchesCargo: () => cargoLink.onHookCargoTouch(),
      fuelDrainMultiplier: _fuelDrainMultiplier * mods.fuelDrainMul,
    );
    final cargoBody = CargoBody(
      initialPosition: Vector2.copy(data.cargoSpawn),
      densityMul: mods.cargoDensityMul,
    );
    cargoLink = CargoAttachment(
      ship: shipBody,
      cargo: cargoBody,
      ropeMaxLengthMeters: data.ropeMaxLength,
      onAttached: AudioService.playAttach,
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

    final landing = DualLandingZone(
      padCenter: data.goalCenter,
      halfWidth: data.goalHalfWidth,
      halfHeight: data.goalHalfHeight,
      onBothLanded: _onGoalReached,
    );
    await world.add(landing);
    _levelEntities.add(landing);

    _currentWorldSize = data.worldSize;
    _applyContainedCamera(data.worldSize);
    _applyCameraBounds(data.worldSize);
    camera.stop();
    _snapCameraToShip();

    _levelStartTime = DateTime.now();
    _updateLevelInfoHud();
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
    camera.viewfinder.position = _clampedCameraTarget(s.body.position, worldSize);
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
    _currentWorldSize = null;
    _levelStartTime = null;
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
    // Reset no-retry streak
    ProgressService.instance.setNoRetryStreak(0);
    AudioService.playCrash();
    _resetInputState();
    runState = RunState.gameOver;
    pauseEngine();
    overlays.add('gameOver');
  }

  void _onGoalReached() {
    if (runState != RunState.playing) return;

    final elapsed = _levelStartTime != null
        ? DateTime.now().difference(_levelStartTime!).inMilliseconds / 1000.0
        : double.infinity;
    final fuelLeft = ship?.fuel ?? 0.0;

    _recordSpentFuel();

    final stars = _calculateStars(fuelLeft, elapsed);
    lastLevelStars = stars;
    lastLevelTimeSeconds = elapsed;

    final progress = ProgressService.instance;

    if (isChallengeMode) {
      final wasAlreadyComplete = progress.isDailyChallengeComplete();
      if (!wasAlreadyComplete) {
        progress.addCosmeticCurrency(50); // Daily reward
      }
      progress.markDailyChallengeComplete();
      progress.saveDailyBestTime(elapsed);
    } else {
      final def = currentLevelDef;
      final (world, _) = LevelRegistry.worldOf(levelIndex);

      // Newly earned stars pay out cosmetic currency, scaled by world.
      final newStars = stars - progress.getStarsById(def.saveId);
      if (newStars > 0) {
        progress.addCosmeticCurrency(newStars * world.rewardPerStar);
      }

      progress.saveStarsById(def.saveId, stars);
      progress.saveBestTimeById(def.saveId, elapsed);

      // No-retry streak
      if (!_currentLevelRetried) {
        final streak = progress.getNoRetryStreak() + 1;
        progress.setNoRetryStreak(streak);
      }
    }

    _checkAchievements(stars, elapsed, fuelLeft);

    AudioService.playLand();
    if (stars >= 2) AudioService.playStar();

    _resetInputState();
    runState = RunState.won;
    pauseEngine();
    overlays.add('levelComplete');
  }

  int _calculateStars(double fuelRemaining, double timeSeconds) {
    final pct = fuelRemaining / ShipBody.maxFuel;
    final spec = currentLevelDef.stars;
    if (pct >= spec.star3Fuel && timeSeconds <= spec.star3Time) return 3;
    if (pct >= spec.star2Fuel) return 2;
    return 1;
  }

  void _checkAchievements(int stars, double timeSeconds, double fuelRemaining) {
    final progress = ProgressService.instance;

    AchievementService.unlock(AchievementIds.firstHaul);

    if (fuelRemaining >= 90) AchievementService.unlock(AchievementIds.fuelMiser);
    if (timeSeconds < 30) AchievementService.unlock(AchievementIds.speedHauler);

    final streak = progress.getNoRetryStreak();
    if (!_currentLevelRetried && streak >= 5) {
      AchievementService.unlock(AchievementIds.noScratch);
    }

    int completed = 0;
    bool allPerfect = true;
    for (final def in LevelRegistry.flat) {
      final s = progress.getStarsById(def.saveId);
      if (s > 0) completed++;
      if (s < 3) allPerfect = false;
    }
    if (completed >= 10) AchievementService.unlock(AchievementIds.level10);
    if (completed >= 20) AchievementService.unlock(AchievementIds.level20);

    if (isChallengeMode) AchievementService.unlock(AchievementIds.dailyPilot);

    if (allPerfect) AchievementService.unlock(AchievementIds.perfectPilot);
  }

  void _recordSpentFuel() {
    if (ship != null) {
      final spent = ShipBody.maxFuel - ship!.fuel;
      if (spent > 0) {
        ProgressService.instance.addFuelSpent(spent);
        ship!.fuel = ShipBody.maxFuel; // prevent double counting
      }
    }
  }

  // ── Public navigation ─────────────────────────────────────────────────────

  void restartLevel() {
    overlays.remove('gameOver');
    _currentLevelRetried = true;
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    loadCurrentLevel();
  }

  Future<void> nextLevel() async {
    overlays.remove('levelComplete');
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
    overlays.remove('gameOver');
    overlays.remove('levelComplete');
    _recordSpentFuel();
    _resetInputState();
    _clearLevel();
    _resetChallenge();
    runState = RunState.menu;
    pauseEngine();
    overlays.add('menu');
  }

  // ── Update loop ───────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    super.update(dt);
    final s = ship;
    if (s != null && runState == RunState.playing) {
      final worldSize = _currentWorldSize;
      if (worldSize != null) {
        final target = _clampedCameraTarget(s.body.position, worldSize);
        final current = camera.viewfinder.position;
        camera.viewfinder.position = current + (target - current) * 0.18;
      }

      s.setInput(rotate: rotateAxis, thrust: thrustHeld);

      final tow = cargoAttachment?.attached == true;

      // Update fuel gauge
      _fuelGauge?.fuelFraction = s.fuel / ShipBody.maxFuel;
      _fuelGauge?.towing = tow;

    }
  }
}
