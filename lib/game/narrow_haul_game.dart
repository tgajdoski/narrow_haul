import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/cargo_attachment.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/dual_landing_zone.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/components/parallax_background.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/components/wall_box.dart';
import 'package:narrow_haul/game/components/world_dromes.dart';
import 'package:narrow_haul/game/level/level_data.dart';
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

  static const levelPaths = [
    'assets/tiles/level_01.tmx',
    'assets/tiles/level_02.tmx',
    'assets/tiles/level_03.tmx',
    'assets/tiles/level_04.tmx',
    'assets/tiles/level_05.tmx',
    'assets/tiles/level_06.tmx',
    'assets/tiles/level_07.tmx',
    'assets/tiles/level_08.tmx',
    'assets/tiles/level_09.tmx',
    'assets/tiles/level_10.tmx',
    'assets/tiles/level_11.tmx',
    'assets/tiles/level_12.tmx',
    'assets/tiles/level_13.tmx',
    'assets/tiles/level_14.tmx',
    'assets/tiles/level_15.tmx',
    'assets/tiles/level_16.tmx',
    'assets/tiles/level_17.tmx',
    'assets/tiles/level_18.tmx',
    'assets/tiles/level_19.tmx',
    'assets/tiles/level_20.tmx',
  ];

  /// Fuel remaining thresholds for 3-star rating (by level index).
  static const List<double> _star3FuelThreshold = [
    70, 70, 70,             // tutorial 1-3
    65, 65, 65, 65,         // beginner 4-7
    55, 55, 55, 55, 55,     // intermediate 8-12
    45, 45, 45, 45,         // advanced 13-16
    38, 38, 38, 38,         // expert 17-20
  ];

  RunState runState = RunState.menu;
  int levelIndex = 0;

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
    add(ParallaxBackground());

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
    activeChallengeConfig = DailyChallengeConfig.forToday(levelPaths.length);
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
    final path = levelPaths[levelIndex];
    final data = await loadLevelFromTmx(path, levelIndex: levelIndex);
    await _spawnLevel(data);
  }

  Future<void> _spawnLevel(LevelData data) async {
    // Apply daily challenge gravity override
    if (_gravityMultiplier != 1.0) {
      final baseY = kDebugMode && kDebugReduceGravity
          ? kGravityY * kDebugGravityScale
          : kGravityY;
      world.gravity = Vector2(0, baseY * _gravityMultiplier);
    } else {
      world.gravity = narrowHaulGravity();
    }

    final backdrop = RectangleComponent(
      size: data.worldSize,
      paint: Paint()..color = const Color(0xFF0B132B),
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

    final helipad = HelipadVisual(
      center: data.shipSpawn,
      sizeMeters: Vector2(3.4, 2.4),
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
      fuelDrainMultiplier: _fuelDrainMultiplier,
    );
    final cargoBody = CargoBody(
      initialPosition: Vector2.copy(data.cargoSpawn),
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
    info.levelLabel = 'Mission ${levelIndex + 1}/${levelPaths.length}$challengeTag';
    info.stars = ProgressService.instance.getStars(levelIndex);
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

    final stars = _calculateStars(fuelLeft);
    lastLevelStars = stars;
    lastLevelTimeSeconds = elapsed;

    final progress = ProgressService.instance;
    progress.saveStars(levelIndex, stars);
    progress.saveBestTime(levelIndex, elapsed);

    // Unlock next level
    if (levelIndex + 1 < levelPaths.length) {
      progress.unlockLevel(levelIndex + 1);
    }

    // No-retry streak
    if (!_currentLevelRetried) {
      final streak = progress.getNoRetryStreak() + 1;
      progress.setNoRetryStreak(streak);
    }

    // Daily challenge completion
    if (isChallengeMode) {
      progress.markDailyChallengeComplete();
    }

    _checkAchievements(stars, elapsed, fuelLeft);

    AudioService.playLand();
    if (stars >= 2) AudioService.playStar();

    _resetInputState();
    runState = RunState.won;
    pauseEngine();
    overlays.add('levelComplete');
  }

  int _calculateStars(double fuelRemaining) {
    final threshold3 = levelIndex < _star3FuelThreshold.length
        ? _star3FuelThreshold[levelIndex]
        : 38.0;
    if (fuelRemaining >= threshold3) return 3;
    if (fuelRemaining >= 40) return 2;
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

    if (levelIndex >= 9) AchievementService.unlock(AchievementIds.level10);
    if (levelIndex >= 19) AchievementService.unlock(AchievementIds.level20);

    if (isChallengeMode) AchievementService.unlock(AchievementIds.dailyPilot);

    // Perfect pilot: check all levels have 3 stars
    bool allPerfect = true;
    for (int i = 0; i < levelPaths.length; i++) {
      if (progress.getStars(i) < 3) {
        allPerfect = false;
        break;
      }
    }
    if (allPerfect) AchievementService.unlock(AchievementIds.perfectPilot);
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
      if (levelIndex < levelPaths.length - 1) {
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
