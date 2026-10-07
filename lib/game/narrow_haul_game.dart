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
import 'package:narrow_haul/game/components/combat.dart';
import 'package:narrow_haul/game/components/defences.dart';
import 'package:narrow_haul/game/components/dual_landing_zone.dart';
import 'package:narrow_haul/game/components/force_field_system.dart';
import 'package:narrow_haul/game/components/well_core.dart';
import 'package:narrow_haul/game/components/flight_hud.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/components/minimap_hud.dart';
import 'package:narrow_haul/game/components/obstacles.dart';
import 'package:narrow_haul/game/components/parallax_background.dart';
import 'package:narrow_haul/game/components/route_guide.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/components/wall_box.dart';
import 'package:narrow_haul/game/components/world_dromes.dart';
import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/field_sampler.dart';
import 'package:narrow_haul/game/level/cave/level_spec.dart';
import 'package:narrow_haul/game/level/level_data.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/level/theme_assets.dart';
import 'package:narrow_haul/game/level/theme_spec.dart';
import 'package:narrow_haul/game/level/tiled_level_loader.dart';
import 'package:narrow_haul/game/physics_constants.dart';
import 'package:narrow_haul/game/route/crash_streak.dart';
import 'package:narrow_haul/game/route/flight_route.dart';
import 'package:narrow_haul/game/route/route_repository.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/contracts_service.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/haptics.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

enum RunState { menu, playing, gameOver, won }

/// First reactor escape on a level pays this XP and currency (once).
const int kReactorEscapeXp = 150;
const int kReactorEscapeCurrency = 40;

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

  RunReward withCurrency(int value) => RunReward(
    xp: xp,
    xpBefore: xpBefore,
    xpAfter: xpAfter,
    currency: value,
    newAchievements: newAchievements,
  );

  PilotRank get rankBefore => rankFor(xpBefore);
  PilotRank get rankAfter => rankFor(xpAfter);
  bool get rankedUp => rankAfter.index > rankBefore.index;
}

class NarrowHaulGame extends Forge2DGame implements CombatHost {
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

  /// Effective base gravity of the running level, in g (for achievements).
  double _levelGravityG = 1;

  /// Tank size of the active ship (fuel fractions for stars/HUD).
  double get _shipMaxFuel => ship?.maxFuel ?? kKestrel.maxFuel;
  CargoBody? cargo;
  CargoAttachment? cargoAttachment;

  /// Data of the level currently in play; null outside a level.
  LevelData? currentLevel;

  double rotateAxis = 0;
  bool thrustHeld = false;
  bool fireHeld = false;

  /// Test-only: load levels without obstacles and defences, to measure the
  /// pure flight cost of a route (autopilot "clean run").
  @visibleForTesting
  bool debugSkipHazards = false;

  // ── Combat (turrets, reactor, fuel cells) ────────────────────────────────
  CombatStatusHud? _combatHud;

  /// Seconds left to deliver after the reactor was destroyed; null = calm.
  double? _meltdownLeft;
  double _turretsOfflineLeft = 0;
  int _turretsDestroyed = 0;
  bool _reactorDestroyed = false;
  final math.Random _combatRng = math.Random();

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

  // ── Continue after crash (rewarded ad) ───────────────────────────────────
  /// Safe points sampled while flying; the newest few seconds only.
  final List<_FlightSnapshot> _snapshots = [];
  double _snapshotTimer = 0;
  static const double _snapshotEvery = 0.5;
  static const int _snapshotKeep = 10;

  /// Restore at least this long before the crash (not the doomed approach).
  static const double _continueRewind = 1.5;
  static const double _continueFuelBonus = 0.25;
  static const double _continueTurretGrace = 3;
  static const double _safeClearance = 0.9;
  bool _continueUsed = false;

  /// This attempt was continued: capped at 2★, never a clean flight.
  bool continuedThisRun = false;
  bool _crashedByMeltdown = false;
  double? _meltdownAtCrash;
  double _crashElapsed = 0;
  int _playtimeBooked = 0;
  double _fuelBaseline = 0;

  // ── Route guide & demo flight ────────────────────────────────────────────
  /// Crashes in a row on one level (3 → the game-over screen offers help).
  final CrashStreak crashStreak = CrashStreak();

  /// Recorded flight bundled for this level (null: none, or a daily run).
  FlightRoute? currentRoute;

  /// This attempt's own flight, finished on delivery (autopilot export).
  FlightRoute? lastFlightRoute;
  FlightRecorder? _recorder;

  /// Level the route guide is switched on for (stays on across retries).
  String? _routeGuideLevel;

  /// The guide was showing during this flight: capped at 2★.
  bool guidedThisRun = false;
  final List<Component> _guideComponents = [];

  /// Kinematic replay of [currentRoute]: no input, no crash, no rewards.
  bool demoMode = false;
  double _demoT = 0;
  int _demoShot = 0;
  bool _demoTowing = false;

  /// The demo reached the end of its recording (the overlay offers to fly).
  final ValueNotifier<bool> demoFinished = ValueNotifier(false);

  /// The last win paid the daily's first-clear reward (no interstitial then).
  bool _lastWinDailyFirst = false;
  bool _currencyDoubled = false;

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
      onFire: (v) => fireHeld = v,
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
    _combatHud = CombatStatusHud();
    camera.viewport.add(_combatHud!);

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
      shipOptions: (i) => [
        for (final s in LevelRegistry.testFlightOptions(i)) s.id,
      ],
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
    _leaveDemo();
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
    _snapshots.clear();
    _snapshotTimer = 0;
    _continueUsed = false;
    continuedThisRun = false;
    guidedThisRun = false;
    _crashedByMeltdown = false;
    _meltdownAtCrash = null;
    _playtimeBooked = 0;
    _demoT = 0;
    _demoShot = 0;
    _demoTowing = false;
    if (!demoMode) {
      ProgressService.instance.incrementStat(ProgressService.statFlights);
    }
    currentRoute = await _routeForCurrentLevel();
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

    for (final field in data.fields) {
      if (field is! GravityWellSpec) continue;
      final core = WellCore(spec: field, theme: theme);
      await world.add(core);
      _levelEntities.add(core);
    }

    for (final spec in debugSkipHazards ? const <ObstacleSpec>[] : data.obstacles) {
      final obstacle = obstacleFromSpec(spec, theme, this);
      await world.add(obstacle);
      _levelEntities.add(obstacle);
    }

    for (final spec in data.pickups) {
      final pickup = switch (spec) {
        FuelCellSpec s => FuelCell(spec: s, host: this, accent: theme.uiAccent),
      };
      await world.add(pickup);
      _levelEntities.add(pickup);
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
    final challengeShip = isChallengeMode ? activeChallengeConfig?.shipId : null;
    final shipSpec = challengeShip != null
        ? shipById(challengeShip)
        : LevelRegistry.shipFor(levelIndex);
    _levelGravityG = g0 * gravityMul / baseGravityY();
    final shipBody = ShipBody(
      initialPosition: Vector2.copy(data.shipSpawn),
      onWallHit: _onShipHitWall,
      onHookTouchesCargo: () => cargoLink.onHookCargoTouch(),
      onFire: _onShipFired,
      fuelDrainMultiplier: _fuelDrainMultiplier * mods.fuelDrainMul,
      spec: shipSpec,
    );
    final cargoBody = CargoBody(
      initialPosition: Vector2.copy(data.cargoSpawn),
      densityMul: mods.cargoDensityMul,
      clamped: data.cargoClamped,
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
    _hudControls?.showFire = shipSpec.armed;
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
    _fuelBaseline = shipBody.maxFuel;
    _thrustUsed = 0;
    _rotateUsed = 0;
    _tutorialHints =
        !isChallengeMode &&
        !demoMode &&
        levelIndex < 3 &&
        currentLevelDef is TmxLevelDef &&
        ProgressService.instance.getStarsById(currentLevelDef.saveId) == 0;
    _pauseButton?.visible = !demoMode;
    _syncRouteGuide();
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
    _hint?.message = null;
    _winTimer = 0;
    _winReady = false;
    _crashTimer = 0;
    _shakeTimer = 0;
    _pauseButton?.visible = false;
    _hudControls?.showFire = false;
    _meltdownLeft = null;
    _turretsOfflineLeft = 0;
    _turretsDestroyed = 0;
    _reactorDestroyed = false;
    _syncCombatHud();
    _resetInputState();
  }

  void _resetInputState() {
    rotateAxis = 0;
    thrustHeld = false;
    fireHeld = false;
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
    if (runState != RunState.playing || demoMode) return;
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
    _pauseButton?.visible = false;
    _hint?.message = null;
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
    if (runState != RunState.playing || demoMode) return;
    // Claim the win before any await so a second contact can't re-enter.
    runState = RunState.won;

    final elapsed = elapsedSeconds;
    final reactorEscape = _reactorDestroyed && _meltdownLeft != null;
    _meltdownLeft = null;
    _turretsOfflineLeft = 0;
    _syncCombatHud();
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
    final currencyMul = CareerService.currencyMultiplier;
    int currency = 0;
    final XpBreakdown runXp;

    progress.incrementStat(ProgressService.statDeliveries);
    MonetizationService.instance.recordLevelClear();
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
        turretsDestroyed: _turretsDestroyed,
      ),
    );

    // Reactor escape (Thrust's big finish): bonus the first time per level.
    final combatLines = <XpLine>[];
    if (reactorEscape) {
      progress.incrementStat(ProgressService.statReactorEscapes);
      if (await progress.markOnce('reactor_${currentLevelDef.saveId}')) {
        combatLines.add(const XpLine('Reactor escape', kReactorEscapeXp));
        currency += (kReactorEscapeCurrency * currencyMul).round();
      }
    }

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

  @visibleForTesting
  int debugStars(double fuelFraction, double timeSeconds) =>
      _calculateStars(fuelFraction * _shipMaxFuel, timeSeconds);

  int _calculateStars(double fuelRemaining, double timeSeconds) {
    final pct = fuelRemaining / _shipMaxFuel;
    final spec = currentLevelDef.stars;
    // A continued (rewarded ad) or guided run can never buy a perfect rating.
    if (pct >= spec.star3Fuel &&
        timeSeconds <= spec.star3Time &&
        !continuedThisRun &&
        !guidedThisRun) {
      return 3;
    }
    if (pct >= spec.star2Fuel) return 2;
    return 1;
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
    if (kShips.keys.every(LevelRegistry.hasTypeRating)) {
      candidates.add(AchievementIds.fleetQualified);
    }

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

  // ── Route guide & demo flight ─────────────────────────────────────────────

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
      !isChallengeMode &&
      ProgressService.instance.isRouteUnlocked(currentLevelDef.saveId);

  /// Game-over help: after [CrashStreak.offerAfter] crashes in a row, or
  /// whenever this level's route was unlocked before.
  bool get canShowRoute =>
      currentRoute != null &&
      !isChallengeMode &&
      (crashStreak.shouldOfferFor(currentLevelDef.saveId) ||
          ProgressService.instance.isRouteUnlocked(currentLevelDef.saveId));

  /// "Show route": unlock it for this level and retry with the guide on.
  Future<void> showRoute() async {
    if (!canShowRoute) return;
    await ProgressService.instance.setRouteUnlocked(currentLevelDef.saveId);
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
    _guideComponents.add(RouteGuideLine(route: route, accent: level.theme.uiAccent));
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
    overlays.removeAll(['gameOver', 'pause', 'settings']);
    _resetInputState();
    demoMode = true;
    demoFinished.value = false;
    runState = RunState.playing;
    pauseEngine();
    await loadCurrentLevel(retry: true);
    _hudControls?.removeFromParent();
    overlays.add('demo');
    resumeEngine();
  }

  /// Ends a demo (back to normal flight state; the caller loads what's next).
  void _leaveDemo() {
    if (!demoMode) return;
    demoMode = false;
    demoFinished.value = false;
    overlays.remove('demo');
    final hud = _hudControls;
    if (hud != null && hud.parent == null) camera.viewport.add(hud);
  }

  /// "Take the controls": fly the level yourself (the guide stays as it was).
  Future<void> takeControlsFromDemo() => restartLevel();

  void _updateDemo(double dt, ShipBody s) {
    final route = currentRoute;
    if (route == null) return;
    _demoT += dt;
    final pose = route.poseAt(_demoT);
    s.drivePose(Vector2(pose.x, pose.y), pose.angle, thrust: pose.thrust);
    cargo?.drivePosition(Vector2(pose.cx, pose.cy));
    _demoTowing = pose.towing;
    while (_demoShot < route.shots.length && route.shots[_demoShot] <= _demoT) {
      _demoShot++;
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

  // ── Monetization hooks ────────────────────────────────────────────────────

  /// Leaves the result screen via [then] (next mission / menu), showing an
  /// interstitial first only when pacing allows. Never on the daily's first
  /// clear or a rank-up, which are moments to celebrate, not interrupt.
  Future<void> leaveResults(Future<void> Function() then) async {
    final rankedUp = lastRunReward?.rankedUp ?? false;
    if (!_lastWinDailyFirst && !rankedUp) {
      await MonetizationService.instance.maybeShowInterstitial();
    }
    await then();
  }

  /// 2× coins on the result screen is offered once, when the run paid any.
  bool get canDoubleCurrency =>
      runState == RunState.won &&
      !_currencyDoubled &&
      (lastRunReward?.currency ?? 0) > 0;

  /// Rewarded "2× coins": pays the run's currency a second time.
  Future<void> doubleRunCurrency() async {
    final reward = lastRunReward;
    if (!canDoubleCurrency || reward == null) return;
    _currencyDoubled = true;
    await ProgressService.instance.addCosmeticCurrency(reward.currency);
    lastRunReward = reward.withCurrency(reward.currency * 2);
  }

  /// Rewarded "continue": offered once per attempt after a mistake (not a
  /// meltdown running out), when a safe point from before the crash exists.
  bool get canContinue =>
      runState == RunState.gameOver &&
      !_continueUsed &&
      !_crashedByMeltdown &&
      (ship?.launched ?? false) &&
      _pickSnapshot() != null;

  /// Rewinds to the last safe point before the crash: same ship, same world
  /// (destroyed turrets, collected fuel cells and a running meltdown stay as
  /// they were), ship at rest with a fuel top-up and turrets briefly quiet.
  /// The clock keeps running and the run is capped at 2★.
  void continueAfterCrash() {
    final snap = _pickSnapshot();
    final s = ship;
    final c = cargo;
    if (!canContinue || snap == null || s == null || c == null) return;
    _continueUsed = true;
    continuedThisRun = true;
    overlays.remove('gameOver');

    // Shells in flight would make the respawn a trap.
    for (final shell in world.children.whereType<Shell>().toList()) {
      shell.removeFromParent();
    }
    s.revive(
      position: snap.shipPos,
      angle: snap.shipAngle,
      fuel: math.min(s.maxFuel, snap.fuel + _continueFuelBonus * s.maxFuel),
    );
    c.body
      ..setTransform(snap.cargoPos, snap.cargoAngle)
      ..linearVelocity.setZero()
      ..angularVelocity = 0;
    _fuelBaseline = s.fuel;
    elapsedSeconds = _crashElapsed;
    _timing = true;
    _meltdownLeft = _meltdownAtCrash;
    _turretsOfflineLeft = math.max(_turretsOfflineLeft, _continueTurretGrace);
    _syncCombatHud();
    _snapshots.clear();
    _snapshotTimer = 0;
    _shakeTimer = 0;
    _crashTimer = 0;
    _resetInputState();
    runState = RunState.playing;
    _pauseButton?.visible = true;
    resumeEngine();
  }

  /// Newest snapshot well before the crash with the same tow state (so the
  /// rope never has to snap to a different length); else the newest one.
  _FlightSnapshot? _pickSnapshot() {
    final tow = cargoAttachment?.attached ?? false;
    _FlightSnapshot? fallback;
    for (final snap in _snapshots.reversed) {
      if (snap.attached != tow) continue;
      if (_crashElapsed - snap.time >= _continueRewind) return snap;
      fallback ??= snap;
    }
    return fallback;
  }

  void _sampleSnapshot(double dt, ShipBody s) {
    if (!s.launched || isPaused) return;
    _snapshotTimer += dt;
    if (_snapshotTimer < _snapshotEvery) return;
    _snapshotTimer = 0;
    final c = cargo;
    if (c == null || !_isSafeSpot(s, c)) return;
    _snapshots.add(
      _FlightSnapshot(
        time: elapsedSeconds,
        shipPos: s.body.position.clone(),
        shipAngle: s.body.angle,
        fuel: s.fuel,
        cargoPos: c.body.position.clone(),
        cargoAngle: c.body.angle,
        attached: cargoAttachment?.attached ?? false,
      ),
    );
    if (_snapshots.length > _snapshotKeep) _snapshots.removeAt(0);
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
      final to = p + Vector2(math.cos(a), math.sin(a)) * _safeClearance;
      if (!hasLineOfSight(world, p, to, ignore: c.body)) return false;
    }
    return true;
  }

  // ── Public navigation ─────────────────────────────────────────────────────

  Future<void> restartLevel() {
    _leaveDemo();
    overlays.removeAll(['gameOver', 'pause', 'settings']);
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    return loadCurrentLevel(retry: true);
  }

  Future<void> nextLevel() async {
    overlays.removeAll(['levelComplete', 'rankUp']);
    _resetInputState();
    CosmeticsService.clearTrials(); // a trial lasts until its level is won
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
    _leaveDemo();
    overlays.removeAll(['gameOver', 'pause', 'settings']);
    CosmeticsService.clearTrials();
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
    if (_meltdownLeft != null) return 'Reactor critical — deliver the pod before it blows!';
    final s = ship;
    if (s != null &&
        s.spec.armed &&
        s.shotsFired == 0 &&
        currentLevel?.hasCombat == true &&
        ProgressService.instance.getStarsById(currentLevelDef.saveId) == 0) {
      return 'Tap FIRE to knock out turrets — each shot costs fuel';
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

  // ── Combat (CombatHost) ──────────────────────────────────────────────────

  @override
  ShipBody? get combatShip => ship;

  @override
  Body? get combatCargo {
    final c = cargo;
    return c != null && c.isMounted ? c.body : null;
  }

  @override
  bool get combatLive =>
      runState == RunState.playing &&
      !isPaused &&
      !demoMode &&
      (ship?.launched ?? false);

  @override
  bool get turretsDisabled => _turretsOfflineLeft > 0 || _reactorDestroyed;

  @override
  void spawnShell(Shell shell) {
    world.add(shell);
    _levelEntities.add(shell);
  }

  void _onShipFired(Vector2 muzzle, Vector2 velocity) {
    _recorder?.shot();
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
  }

  @override
  void onShipShot() => _onShipHitWall();

  @override
  void onTurretDestroyed(Offset at) {
    if (demoMode) {
      _burstAt(at);
      AudioService.playBoom();
      return;
    }
    _turretsDestroyed++;
    ProgressService.instance.incrementStat(ProgressService.statTurretsDestroyed);
    _burstAt(at);
    AudioService.playBoom();
    Haptics.medium();
    AchievementService.unlock(AchievementIds.weaponsHot, announce: true);
  }

  @override
  void onReactorDisabledTurrets(double seconds) {
    _turretsOfflineLeft = seconds;
    Haptics.medium();
    _syncCombatHud();
  }

  @override
  void onReactorDestroyed(Offset at, double escapeSeconds) {
    if (runState != RunState.playing) return;
    if (demoMode) {
      // No meltdown in a demo: the replay can't run from it.
      _reactorDestroyed = true;
      _burstAt(at);
      AudioService.playBoom();
      return;
    }
    _reactorDestroyed = true;
    _meltdownLeft = escapeSeconds;
    _turretsOfflineLeft = 0;
    _burstAt(at);
    AudioService.playBoom();
    Haptics.heavy();
    _syncCombatHud();
  }

  @override
  void onFuelCollected(double amount, Offset at) {
    final s = ship;
    if (s == null) return;
    s.fuel = math.min(s.maxFuel, s.fuel + amount);
    final progress = ProgressService.instance;
    progress.incrementStat(ProgressService.statFuelCells);
    if (progress.getStat(ProgressService.statFuelCells) >= 10) {
      AchievementService.unlock(AchievementIds.hotRefuel, announce: true);
    }
    AudioService.playAttach();
    Haptics.light();
  }

  void _burstAt(Offset at) {
    final burst = ExplosionBurst(
      center: at,
      accent: currentLevel?.theme.uiAccent ?? const Color(0xFFFF6B35),
      seed: _combatRng.nextInt(1 << 20),
    );
    world.add(burst);
    _levelEntities.add(burst);
  }

  /// Turret-offline timer and the meltdown countdown; a meltdown that runs
  /// out takes the ship with it.
  void _updateCombat(double dt) {
    if (_turretsOfflineLeft > 0) {
      _turretsOfflineLeft = math.max(0, _turretsOfflineLeft - dt);
    }
    final melt = _meltdownLeft;
    if (melt != null) {
      final left = melt - dt;
      _meltdownLeft = left;
      // The cave rumbles harder as the clock runs down.
      final amp = 0.03 + 0.07 * (1 - (left / 30).clamp(0.0, 1.0));
      camera.viewfinder.position += Vector2(
            _combatRng.nextDouble() - 0.5,
            _combatRng.nextDouble() - 0.5,
          ) *
          (2 * amp);
      if (left <= 0) {
        _meltdownLeft = null;
        _crashedByMeltdown = true;
        _onShipHitWall();
      }
    }
    _syncCombatHud();
  }

  void _syncCombatHud() {
    _combatHud
      ?..meltdownLeft = _meltdownLeft
      ..turretsOfflineLeft = _turretsOfflineLeft;
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

      if (demoMode) {
        _updateDemo(dt, s);
      } else {
        s.setInput(rotate: rotateAxis, thrust: thrustHeld, fire: fireHeld);
        if (routeGuideOn && s.launched) guidedThisRun = true;
      }
      _updateCombat(dt);
      _sampleSnapshot(dt, s);
      _recordFrame(dt, s);

      final tow = cargoAttachment?.attached == true;

      // Update fuel gauge
      _fuelGauge?.fuelFraction = s.fuel / s.maxFuel;
      _fuelGauge?.towing = tow;
      s.localAccel.setFrom(_forces?.shipAccel ?? world.gravity);
      _gravityHud?.accelG
        ?..setFrom(s.localAccel)
        ..scale(1 / baseGravityY());
      _levelInfoHud
        ?..elapsed = elapsedSeconds
        ..fuelFraction = s.fuel / s.maxFuel;
    }
  }
}

/// One safe point of a flight, for "continue after crash".
class _FlightSnapshot {
  _FlightSnapshot({
    required this.time,
    required this.shipPos,
    required this.shipAngle,
    required this.fuel,
    required this.cargoPos,
    required this.cargoAngle,
    required this.attached,
  });

  final double time;
  final Vector2 shipPos;
  final double shipAngle;
  final double fuel;
  final Vector2 cargoPos;
  final double cargoAngle;
  final bool attached;
}
