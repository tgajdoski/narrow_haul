import 'dart:isolate';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/input.dart' show KeyboardEvents;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:narrow_haul/game/keyboard_input.dart';
import 'package:narrow_haul/game/level/cave/cave_builder.dart';
import 'package:narrow_haul/game/level/cave/crate_spots.dart';
import 'package:narrow_haul/game/level/cave/geom.dart';
import 'package:narrow_haul/game/level/cave/terrain_carver.dart';
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
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/error_reporter.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/music_service.dart';
import 'package:narrow_haul/game/services/contracts_service.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/haptics.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/loadout.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/game/ship/weapons.dart';
import 'package:narrow_haul/game/tags.dart';

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

class NarrowHaulGame extends Forge2DGame
    with KeyboardEvents
    implements CombatHost {
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

  // Touch HUD and keyboard each keep their own state; the flight inputs
  // above are both combined (either one can steer, thrust or fire).
  double _touchAxis = 0;
  bool _touchThrust = false;
  bool _touchFire = false;
  final KeyboardFlightInput _keys = KeyboardFlightInput();

  void _combineInputs() {
    rotateAxis = (_touchAxis + _keys.rotateAxis).clamp(-1.0, 1.0);
    thrustHeld = _touchThrust || _keys.thrust;
    fireHeld = _touchFire || _keys.fire;
  }

  /// Desktop keyboard: flight keys (see [KeyboardFlightInput]), Esc steps
  /// back like Android back, P toggles pause.
  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        handleBack();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyP && runState == RunState.playing) {
        isPaused ? resumeGame() : pauseGame();
        return KeyEventResult.handled;
      }
    }
    final flying = runState == RunState.playing && !isPaused && !demoMode;
    if (flying &&
        event is KeyDownEvent &&
        KeyboardFlightInput.cycleKeys.contains(event.logicalKey)) {
      cycleWeapon();
      return KeyEventResult.handled;
    }
    if (!flying) {
      _keys.reset();
      return KeyEventResult.ignored;
    }
    _keys.update(keysPressed);
    _combineInputs();
    return KeyboardFlightInput.isFlightKey(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

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

  // ── Weapons, blasts & supply crates ──────────────────────────────────────
  /// This flight's weapons (the Talon's cannon + special ammo).
  WeaponRack? get weaponRack => _rack;
  WeaponRack? _rack;

  /// Carried (bought / coin / ad) ammo was used: the run is capped at 2★.
  bool get carriedWeaponUsedThisRun => _rack?.usedCarried ?? false;

  /// Runtime rock removal (cave levels only).
  TerrainCarver? _carver;
  CaveTerrain? _terrain;
  CaveDecor? _decor;
  bool _carveBusy = false;

  /// Bumped on every level teardown, so a late off-thread carve result for
  /// the previous level is dropped.
  int _levelGen = 0;
  MiningLaserBeam? _laserBeam;
  double _laserTick = 0;
  double _rumble = 0;

  /// Chance per attempt of a supply crate on a level flown by an unarmed
  /// ship. `--dart-define=CRATES=always` (or `never`) overrides it.
  static const double kCrateChance = 0.35;
  static const String _cratesDefine = String.fromEnvironment('CRATES');

  /// Test-only: no supply crates (the autopilot flies a fixed level).
  @visibleForTesting
  bool debugNoCrates = false;

  /// Test-only: carve on the calling thread instead of a background isolate.
  @visibleForTesting
  bool debugSyncCarve = false;

  /// Source of crate odds/contents/spots (seedable in tests).
  @visibleForTesting
  math.Random crateRng = math.Random();

  /// The crate on the current level, if any (tests, hints).
  SupplyCrate? get supplyCrate => _crate;
  SupplyCrate? _crate;

  /// A short line shown in the hint slot after picking up a crate.
  String? _weaponHint;
  double _weaponHintLeft = 0;

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

  /// Analytics: loads of [_attemptLevel] since the player last switched
  /// levels or delivered it (a continue isn't a new attempt).
  String? _attemptLevel;
  int _attempt = 0;
  final Set<String> _weaponsLogged = {};

  String get _analyticsMode => !isChallengeMode
      ? 'normal'
      : activeChallengeConfig?.shipId != null
          ? 'test_flight'
          : 'daily';

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
  CountdownHud? _countdownHud;

  /// Seconds until the ship launches by itself (null: waits for input, as on
  /// the onboarding levels and in demos). Any input launches it sooner.
  double? _countdown;
  static const double _countdownSeconds = 4.0;
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

  /// The "Delivered by" credits, drawn by the app above the game (so they
  /// also cover loading). On by default until seen once; Settings replays them.
  final creditsVisible = ValueNotifier<bool>(
    !ProgressService.instance.creditsSeen,
  );

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

  /// Mission shown by the 'briefing' popup (a flat level index), and whether
  /// it is today's daily challenge rather than a mission from the map.
  int briefingLevel = 0;
  bool briefingDaily = false;

  /// Missions briefed this app session (see [needsBriefing]).
  final Set<String> _briefed = {};
  final List<Component> _guideComponents = [];

  /// Kinematic replay of [currentRoute]: no input, no crash, no rewards.
  bool demoMode = false;

  /// Enemy shells that reached the demo ship (a faithful replay has none).
  @visibleForTesting
  int demoShellHits = 0;
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
      onRotateAxis: (v) {
        _touchAxis = FlightTuning.shapeAxis(v);
        _combineInputs();
      },
      onFire: (v) {
        _touchFire = v;
        _combineInputs();
      },
      onThrust: (v) {
        _touchThrust = v;
        _combineInputs();
      },
      onCycleWeapon: cycleWeapon,
    );
    _hudControls!.size = camera.viewport.size;
    camera.viewport.add(_hudControls!);

    _pauseButton = PauseButtonHud(onPressed: pauseGame);
    camera.viewport.add(_pauseButton!);
    _levelIntro = LevelIntroHud();
    camera.viewport.add(_levelIntro!);
    _countdownHud = CountdownHud();
    camera.viewport.add(_countdownHud!);
    _hint = HintHud();
    camera.viewport.add(_hint!);
    _combatHud = CombatStatusHud();
    camera.viewport.add(_combatHud!);
    _applySafeInsets();

    applySettings();

    AchievementService.announced.addListener(_onAchievementAnnounced);
    _syncAnalyticsUser();

    overlays.add('menu');
    MusicService.play(MusicService.menuTrack, MusicService.menuVolume);
    pauseEngine();
  }

  @override
  void onRemove() {
    AchievementService.announced.removeListener(_onAchievementAnnounced);
    super.onRemove();
  }

  /// Screen insets (notch / Dynamic Island / home indicator) the HUD keeps
  /// clear of; the world itself still draws edge to edge. Set by the host
  /// widget from `MediaQuery.viewPaddingOf`.
  EdgeInsets get safeInsets => _safeInsets;
  EdgeInsets _safeInsets = EdgeInsets.zero;
  void setSafeInsets(EdgeInsets insets) {
    if (insets == _safeInsets) return;
    _safeInsets = insets;
    _applySafeInsets();
  }

  void _applySafeInsets() {
    final topLeft = Vector2(_safeInsets.left, _safeInsets.top);
    _fuelGauge?.position = topLeft;
    _gravityHud?.position = topLeft.clone();
    _levelInfoHud?.position = topLeft.clone();
    _hudControls?.insets = _safeInsets;
    _minimap?.refreshLayout();
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

  /// Menu LAUNCH: flies the career's next mission, after its briefing when
  /// it's a first attempt ([needsBriefing]).
  Future<void> beginPlay() async {
    final next = LevelRegistry.nextLevelIndex();
    if (needsBriefing(next)) {
      openBriefing(next);
      return;
    }
    overlays.remove('menu');
    overlays.remove('levelSelect');
    _resetChallenge();
    levelIndex = next;
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    await loadCurrentLevel();
  }

  Future<void> beginChallenge() async {
    overlays.removeAll(['menu', 'briefing']);
    isChallengeMode = true;
    final levels = unlockedLevelIndices();
    // Test Flight ship options run the full validator per ship (up to a few
    // hundred ms on a phone): do it on a background isolate, and only then.
    final (dailyLevel, testFlight) = DailyChallengeConfig.peekToday(levels);
    final shipIds = testFlight
        ? await Isolate.run(
            () => [
              for (final s in LevelRegistry.testFlightOptions(dailyLevel)) s.id,
            ],
          )
        : const <String>[];
    activeChallengeConfig = DailyChallengeConfig.forToday(
      levels,
      shipOptions: (_) => shipIds,
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
      'menu',
      'levelSelect',
      'briefing',
      'gameOver',
      'levelComplete',
      'rankUp',
      'pause',
      'settings',
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
    } catch (e, st) {
      ErrorReporter.report(e, st, context: 'loading ${currentLevelDef.saveId}');
      backToMenu();
    }
  }

  Future<void> _loadCurrentLevel({required bool retry}) async {
    _clearLevel();
    if (_ammoOfferedLevel != currentLevelDef.saveId) _ammoOffered = false;
    _currentLevelRetried = retry;
    _snapshots.clear();
    _snapshotTimer = 0;
    _continueUsed = false;
    continuedThisRun = false;
    _weaponsLogged.clear();
    guidedThisRun = false;
    _crashedByMeltdown = false;
    _meltdownAtCrash = null;
    _playtimeBooked = 0;
    _demoT = 0;
    _demoShot = 0;
    demoShellHits = 0;
    _demoTowing = false;
    if (!demoMode) {
      ProgressService.instance.incrementStat(ProgressService.statFlights);
    }
    currentRoute = await _routeForCurrentLevel();
    // In debug, rebuild caves every load so hot-reloaded spec edits show up.
    if (kDebugMode) clearCaveCache();
    final def = currentLevelDef;
    if (def is CaveLevelDef) await prebuildCave(def.spec);
    final data = switch (currentLevelDef) {
      TmxLevelDef def => await loadLevelFromTmx(
        def.assetPath,
        levelIndex: levelIndex,
      ),
      CaveLevelDef def => buildCaveLevelData(def),
    };
    await _spawnLevel(data);
    MusicService.play(
      MusicService.flightTrackFor(currentLevelDef.themeId, keepCurrent: retry),
      MusicService.flightVolume,
    );
    if (!retry && !demoMode) AudioService.playStartLevel();
    if (!demoMode) _logLevelStart();
    _countdown = (demoMode || _tutorialHints) ? null : _countdownSeconds;
    _countdownHud
      ?..text = null
      ..accent = data.theme.uiAccent;
  }

  void _logLevelStart() {
    final id = currentLevelDef.saveId;
    if (_attemptLevel != id) {
      _attemptLevel = id;
      _attempt = 0;
    }
    _attempt++;
    final (world, _) = LevelRegistry.worldOf(levelIndex);
    Analytics.levelStart(
      levelId: id,
      world: world.id,
      ship: ship?.spec.id ?? '',
      rope: cargoAttachment?.rope.id ?? '',
      mode: _analyticsMode,
      attempt: _attempt,
      guided: routeGuideOn,
    );
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
      _terrain = terrain;
      final def = currentLevelDef;
      if (def is CaveLevelDef) {
        _carver = TerrainCarver(
          buildCave(def.spec),
          guards: padGuards(
            shipSpawn: Pt(data.shipSpawn.x, data.shipSpawn.y),
            goalCenter: Pt(data.goalCenter.x, data.goalCenter.y),
            goalHalfW: data.goalHalfWidth,
            goalHalfH: data.goalHalfHeight,
          ),
        );
      }

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
      _decor = decor;
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
    // Carried ammo stays home in a daily (a skill run) and in demos.
    final carryAmmo = !isChallengeMode && !demoMode;
    final rack = _rack = WeaponRack(
      hasCannon: shipSpec.armed,
      carried: {
        if (carryAmmo)
          for (final w in kWeapons) w.id: ProgressService.instance.getAmmo(w.id),
      },
    );
    await _maybeSpawnCrate(shipSpec, theme);
    final shipBody = ShipBody(
      initialPosition: Vector2.copy(data.shipSpawn),
      onWallHit: () => _onShipHitWall(),
      onHookTouchesCargo: () => cargoLink.onHookCargoTouch(),
      onFire: _onShipFired,
      onWeapon: _onWeaponFired,
      rack: rack,
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
      rope: ropeById(CosmeticsService.getEquippedId(CosmeticsService.catRope)),
      onAttached: () {
        AudioService.playAttach();
        Haptics.light();
      },
    )..onBeamLost = Haptics.medium;

    await world.add(shipBody);
    await world.add(cargoBody);
    await world.add(cargoLink);
    _levelEntities.add(shipBody);
    _levelEntities.add(cargoBody);
    _levelEntities.add(cargoLink);

    ship = shipBody;
    cargo = cargoBody;
    cargoAttachment = cargoLink;
    final beam = _laserBeam = MiningLaserBeam(color: theme.uiAccent);
    await world.add(beam);
    _levelEntities.add(beam);
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

  /// Smallest zoom that still keeps the view inside the world.
  double _minContainZoom = 0;

  /// Smoothed camera lead ahead of the ship (m).
  final Vector2 _cameraLead = Vector2.zero();

  /// Camera follow per 1/60 s frame; [_followCamera] keeps it frame-rate
  /// independent, so 120 Hz phones track exactly like 60 Hz ones.
  static const double _cameraFollow = 0.18;

  void _applyContainedCamera(Vector2 worldSize) {
    final viewportSize = camera.viewport.size;
    if (viewportSize.x <= 0 || viewportSize.y <= 0) return;
    final minZoomX = viewportSize.x / worldSize.x;
    final minZoomY = viewportSize.y / worldSize.y;
    _minContainZoom = math.max(minZoomX, minZoomY) * 1.01;
    camera.viewfinder.zoom = math.max(_baseZoom, _minContainZoom);
  }

  void _followCamera(ShipBody s, Vector2 worldSize, double dt) {
    final frames = dt * 60;
    double ease(double perFrame) =>
        1 - math.pow(1 - perFrame, frames).toDouble();

    // Dev tuning: look ahead along the velocity and zoom out a little while
    // towing. Both are 0 by default, which is exactly the stock camera.
    final leadSeconds = FlightTuning.cameraLead;
    final desiredLead = Vector2.zero();
    if (leadSeconds > 0 && s.launched) {
      desiredLead.setFrom(s.body.linearVelocity * leadSeconds);
      if (desiredLead.length > FlightTuning.cameraLeadMaxMeters) {
        desiredLead.scaleTo(FlightTuning.cameraLeadMaxMeters);
      }
    }
    _cameraLead.add((desiredLead - _cameraLead) * ease(0.04));

    final towing = cargoAttachment?.attached ?? false;
    final restZoom = math.max(_baseZoom, _minContainZoom);
    final zoomTarget = math.max(
      _minContainZoom,
      towing ? restZoom * (1 - FlightTuning.towZoomOut) : restZoom,
    );
    final zoom = camera.viewfinder.zoom;
    if ((zoomTarget - zoom).abs() > 1e-3) {
      camera.viewfinder.zoom = zoom + (zoomTarget - zoom) * ease(0.03);
    }

    final target = _clampedCameraTarget(
      s.body.position + _cameraLead,
      worldSize,
    );
    final current = camera.viewfinder.position;
    camera.viewfinder.position =
        current + (target - current) * ease(_cameraFollow);
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
    _cameraLead.setZero();
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
    _flushAmmo();
    _levelGen++;
    _rack = null;
    _carver = null;
    _terrain = null;
    _decor = null;
    _carveBusy = false;
    _laserBeam = null;
    _crate = null;
    _rumble = 0;
    _weaponHint = null;
    _weaponHintLeft = 0;
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
    _touchAxis = 0;
    _touchThrust = false;
    _touchFire = false;
    _keys.reset();
    AudioService.stopEngine();
    AudioService.setAlarm(false);
  }

  void _resetChallenge() {
    isChallengeMode = false;
    activeChallengeConfig = null;
    _gravityMultiplier = 1.0;
    _fuelDrainMultiplier = 1.0;
    world.gravity = narrowHaulGravity();
  }

  // ── Game events ───────────────────────────────────────────────────────────

  void _onShipHitWall({String cause = 'wall'}) {
    if (runState != RunState.playing || demoMode) return;
    final wreck = ship?.body.position;
    Analytics.levelFail(
      levelId: currentLevelDef.saveId,
      cause: cause,
      attempt: _attempt,
      seconds: elapsedSeconds,
      fuelLeft: (ship?.fuel ?? 0) / _shipMaxFuel,
      towing: cargoAttachment?.attached ?? false,
      x: wreck?.x.floor() ?? 0,
      y: wreck?.y.floor() ?? 0,
      mode: _analyticsMode,
    );
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
    );
    _attemptLevel = null; // the next flight here is a fresh attempt series
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

    if (currency > 0) Analytics.earnCoins(currency, 'delivery');
    final rankAfter = rankFor(xpAfter);
    if (rankAfter.index > rankFor(xpBefore).index) {
      Analytics.rankUp(rankAfter.index, rankAfter.title);
    }
    for (final a in unlocked) {
      Analytics.achievement(a.id);
    }
    if (currentLevelDef.saveId == 'tut_10' && prevStars == 0) {
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

  /// Tests: lands the run as if ship and pod had touched down.
  @visibleForTesting
  Future<void> debugDeliver() => _onGoalReached();

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
        !guidedThisRun &&
        !carriedWeaponUsedThisRun) {
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

    if (fuelRemaining >= 0.85 * _shipMaxFuel) candidates.add(AchievementIds.fuelMiser);
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
      turrets: () => [for (final c in world.children) if (c is Turret) c],
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
    // The real velocity, so turrets lead their shots like they did live.
    final next = route.poseAt(_demoT + dt);
    s.drivePose(Vector2(pose.x, pose.y), pose.angle,
        thrust: pose.thrust,
        velocity: dt > 0 ? Vector2((next.x - pose.x) / dt, (next.y - pose.y) / dt) : null);
    cargo?.drivePosition(Vector2(pose.cx, pose.cy));
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

  // ── Monetization hooks ────────────────────────────────────────────────────

  /// Leaves the result screen via [then] (next mission / menu), showing an
  /// interstitial first only when pacing allows. Never on the daily's first
  /// clear or a rank-up, which are moments to celebrate, not interrupt.
  Future<void> leaveResults(Future<void> Function() then) async {
    if (_leavingResults) return; // a button tap and the back key can race
    _leavingResults = true;
    try {
      final rankedUp = lastRunReward?.rankedUp ?? false;
      if (!_lastWinDailyFirst && !rankedUp) {
        await MonetizationService.instance.maybeShowInterstitial();
      }
      await then();
    } finally {
      _leavingResults = false;
    }
  }

  bool _leavingResults = false;

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
  /// After two crashes in a row on a cave level, the game-over screen offers
  /// a Demolition Charge for a rewarded ad (once per level visit).
  bool get canOfferAmmo =>
      runState == RunState.gameOver &&
      !isChallengeMode &&
      !demoMode &&
      !_ammoOffered &&
      currentLevelDef is CaveLevelDef &&
      crashStreak.levelId == currentLevelDef.saveId &&
      crashStreak.count >= 2;
  bool _ammoOffered = false;
  String? _ammoOfferedLevel;

  /// Rewarded: one Demolition Charge into the carried stock (it's on the
  /// rack from the next attempt).
  Future<void> grantRewardedCharge() async {
    _ammoOffered = true;
    _ammoOfferedLevel = currentLevelDef.saveId;
    await ProgressService.instance.addAmmo(kDemoCharge.id, 1);
  }

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
    _logQuit('restart');
    _leaveDemo();
    overlays.removeAll(['gameOver', 'pause', 'settings']);
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    return loadCurrentLevel(retry: true);
  }

  Future<void> nextLevel() async {
    if (!isChallengeMode) {
      final next = levelIndex < LevelRegistry.totalLevels - 1
          ? levelIndex + 1
          : 0;
      // A mission never flown: brief it over the hangar (Back stays there).
      if (needsBriefing(next)) {
        backToMenu();
        openBriefing(next);
        return;
      }
    }
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
    _logQuit('menu');
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
    _countdown = null;
    _countdownHud?.text = null;
    runState = RunState.menu;
    pauseEngine();
    overlays.add('menu');
    MusicService.play(MusicService.menuTrack, MusicService.menuVolume);
  }

  /// A flight abandoned mid-air (restart or menu from the pause screen).
  void _logQuit(String reason) {
    if (runState != RunState.playing || demoMode || currentLevel == null) {
      return;
    }
    Analytics.levelQuit(
      levelId: currentLevelDef.saveId,
      reason: reason,
      seconds: elapsedSeconds,
      launched: ship?.launched ?? false,
    );
  }

  /// Landing status beats tutorial steps: it explains the both-on-pad rule
  /// at exactly the moment a player is confused by it.
  String? _currentHint() {
    if (_weaponHintLeft > 0 && _weaponHint != null) return _weaponHint;
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
      return _desktop
          ? 'Press F or Enter to fire at turrets — each shot costs fuel'
          : 'Tap FIRE to knock out turrets — each shot costs fuel';
    }
    if (routeGuideOn &&
        s != null &&
        s.spec.armed &&
        elapsedSeconds < 8 &&
        (currentRoute?.shots.isNotEmpty ?? false)) {
      return 'Route guide: stop at each red ⊕ and fire along its dashes. Red dots = under fire';
    }
    final pickupHint = _pickupHint();
    if (!_tutorialHints) {
      // First seconds of a flight: what the unfamiliar ship does, then the
      // canisters (until the pilot has collected one, ever).
      final shipHint = _shipHint();
      final t = elapsedSeconds;
      if (shipHint != null && t < 7) return shipHint;
      if (pickupHint != null && t < (shipHint != null ? 14 : 7)) return pickupHint;
      return null;
    }
    final attached = cargoAttachment?.attached == true;
    // Second mission, waiting on the pad: how stars are earned, before the
    // first flight that's scored on them. The live target sits under the
    // fuel bar during flight.
    if (levelIndex == 1 && ship?.launched == false) {
      return 'Stars: ★ deliver · ★★ save fuel · ★★★ save more fuel and beat '
          'the clock. Targets show under the fuel bar';
    }
    final steerSide = _hudControls?.leftHanded == true ? 'right' : 'left';
    final thrustSide = _hudControls?.leftHanded == true ? 'left' : 'right';
    if (_thrustUsed < 0.6) {
      return _desktop
          ? 'Hold ↑, W or Space (or the THRUST button) to fire the engine'
          : 'Hold the THRUST button ($thrustSide) to fire the engine';
    }
    if (_rotateUsed < 0.5) {
      return _desktop
          ? 'Press ← → or A D to rotate the ship'
          : 'Drag on the $steerSide side to rotate the ship';
    }
    if (!attached) {
      return pickupHint != null
          ? 'Fly close to the cargo to hook it — fuel canisters top up your tank'
          : 'Fly close to the cargo — the rope hooks on by itself';
    }
    return 'Bring ship and cargo down onto the green pad';
  }

  static bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Flying a ship before its type rating is earned (its rating level, or a
  /// Test Flight daily): one line on how it handles.
  String? _shipHint() {
    final spec = ship?.spec;
    if (spec == null || demoMode || spec.id == kKestrel.id) return null;
    if (LevelRegistry.hasTypeRating(spec.id)) return null;
    return '${spec.name}: ${spec.blurb}';
  }

  /// Until the first canister ever is collected, on levels that have one.
  String? _pickupHint() {
    if (demoMode || (currentLevel?.pickups.isEmpty ?? true)) return null;
    if (ProgressService.instance.getStat(ProgressService.statFuelCells) > 0) {
      return null;
    }
    return 'Fly through a fuel canister to top up your tank';
  }

  // ── Pause & settings ──────────────────────────────────────────────────────

  /// Hangar → a sub-screen ('levelSelect', 'cosmetics', 'settings'…).
  void openScreen(String key) {
    overlays.remove('menu');
    overlays.add(key);
  }

  /// A sub-screen → back to the hangar.
  void closeScreen(String key) {
    overlays.remove(key);
    overlays.add('menu');
  }

  /// LAUNCH and NEXT MISSION brief a mission first only when it's new: no
  /// stars yet and not briefed this session, so a crash → hangar → LAUNCH
  /// loop doesn't brief it every time. The star chart always briefs.
  bool needsBriefing(int index) {
    final id = LevelRegistry.defAt(index).saveId;
    return ProgressService.instance.getStarsById(id) == 0 &&
        !_briefed.contains(id);
  }

  /// Star chart / LAUNCH / NEXT MISSION → the mission briefing popup (over
  /// the map or the hangar).
  void openBriefing(int index) {
    briefingLevel = index;
    briefingDaily = false;
    _briefed.add(LevelRegistry.defAt(index).saveId);
    overlays.add('briefing');
  }

  /// Hangar Daily → today's challenge briefing (over the hangar).
  void openDailyBriefing() {
    briefingLevel = DailyChallengeConfig.peekToday(unlockedLevelIndices()).$1;
    briefingDaily = true;
    overlays.add('briefing');
  }

  void closeBriefing() => overlays.remove('briefing');

  /// Flat indices of every unlocked level (the daily's candidates).
  static List<int> unlockedLevelIndices() => [
    for (var i = 0; i < LevelRegistry.totalLevels; i++)
      if (LevelRegistry.isLevelUnlocked(i)) i,
  ];

  /// Android back / system back. Returns false only on the main menu, where
  /// the app may close; everywhere else it steps back one screen.
  bool handleBack() {
    final active = overlays.activeOverlays;
    // The briefing pops over the hangar too, so it goes before the
    // hangar's "let the app close" check.
    if (!creditsVisible.value && active.contains('briefing')) {
      AudioService.playUi(UiSound.back);
      closeBriefing();
      return true;
    }
    if (!creditsVisible.value && active.contains('menu')) return false;
    AudioService.playUi(UiSound.back);
    if (creditsVisible.value) {
      creditsVisible.value = false;
    } else if (active.contains('rankUp')) {
      overlays.remove('rankUp');
    } else if (active.contains('settings')) {
      overlays.remove('settings');
      overlays.add(isPaused ? 'pause' : 'menu');
    } else if (active.contains('pause')) {
      resumeGame();
    } else if (active.contains('levelComplete')) {
      leaveResults(() async => backToMenu());
    } else if (active.contains('gameOver') || active.contains('demo')) {
      backToMenu();
    } else if (const ['levelSelect', 'achievements', 'cosmetics', 'pilotProfile']
        .any(active.contains)) {
      overlays.removeAll(['levelSelect', 'achievements', 'cosmetics', 'pilotProfile']);
      overlays.add('menu');
    } else if (runState == RunState.playing) {
      pauseGame();
    }
    // Otherwise (crash explosion / delivery celebration): swallow it.
    return true;
  }

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
    MusicService.setEnabled(p.musicEnabled);
    _hudControls?.leftHanded = p.leftHanded;
    _minimap?.refreshLayout();
  }

  @override
  void lifecycleStateChange(AppLifecycleState state) {
    // Leaving the app mid-flight opens the pause menu, rather than letting
    // Flame silently auto-resume the flight on return.
    if (state != AppLifecycleState.resumed) {
      pauseGame();
      _flushAmmo();
    }
    if (state == AppLifecycleState.resumed) {
      MusicService.onForeground();
    } else {
      MusicService.onBackground();
    }
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
      (demoMode ? _demoLaunched : (ship?.launched ?? false));

  /// Demo flight past the recorded launch: turrets fight the replay exactly
  /// as they fought the recorded flight (their timing is seeded and runs on
  /// the same level-load clock).
  bool get _demoLaunched {
    final route = currentRoute;
    return route != null && _demoT >= route.launchT;
  }

  @override
  bool get turretsDisabled => _turretsOfflineLeft > 0 || _reactorDestroyed;

  @override
  void spawnShell(Shell shell) {
    world.add(shell);
    _levelEntities.add(shell);
    if (!shell.fromPlayer) AudioService.playEnemyShot();
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
  }

  @override
  void onShipShot() {
    // A replay can't dodge: a shell that drifts onto the demo ship just
    // vanishes (the shell expires on impact).
    if (demoMode) {
      demoShellHits++;
      return;
    }
    _onShipHitWall(cause: 'shot');
  }

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
    AudioService.playPickup();
    Haptics.light();
  }

  void _burstAt(Offset at, {double ringRadius = 2.7}) {
    final burst = ExplosionBurst(
      center: at,
      accent: currentLevel?.theme.uiAccent ?? const Color(0xFFFF6B35),
      seed: _combatRng.nextInt(1 << 20),
      ringRadius: ringRadius,
    );
    world.add(burst);
    _levelEntities.add(burst);
  }

  // ── Weapons (special ammo, blasts, rock carving, supply crates) ──────────

  /// Next weapon on the rack (HUD chip tap, Q / Tab).
  void cycleWeapon() {
    final r = _rack;
    if (r == null || r.available.length < 2) return;
    r.cycle();
    _syncWeaponHud();
    Haptics.light();
  }

  static String _weaponLabel(WeaponSpec w) => switch (w.kind) {
        WeaponKind.cannon => 'FIRE',
        WeaponKind.charge => 'CHARGE',
        WeaponKind.bomb => 'BOMB',
        WeaponKind.laser => 'LASER',
        WeaponKind.seeker => 'SEEKER',
        WeaponKind.flak => 'FLAK',
      };

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
    final String? count;
    if (w.kind == WeaponKind.cannon) {
      count = null;
    } else if (w.continuous) {
      count = '${r.ammo(w.id).ceil()}s';
    } else {
      count = '×${r.ammo(w.id).round()}';
    }
    hud.weapon = (_weaponLabel(w), count, r.available.length > 1);
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
        _cratesDefine == 'never') {
      return;
    }
    final always = _cratesDefine == 'always';
    if (!always && crateRng.nextDouble() >= kCrateChance) return;
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
    await world.add(crate);
    _levelEntities.add(crate);
  }

  void _onCrateCollected(SupplyCrate crate) {
    final r = _rack;
    if (r == null) return;
    r.addFound(crate.weapon.id, crate.units);
    Analytics.crateCollected(crate.weapon.id);
    _syncWeaponHud();
    final w = crate.weapon;
    final amount = w.continuous ? '${crate.units.round()} s' : '×${crate.units.round()}';
    final fire = _desktop ? 'press F' : 'tap ${_weaponLabel(w)}';
    _weaponHint = '${w.name} $amount — $fire';
    _weaponHintLeft = 3.5;
    AudioService.playPickup();
    Haptics.medium();
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
    if (_weaponHintLeft > 0) _weaponHintLeft -= dt;
    if (_rack != null && (s.laserFiring || _rack!.selected?.continuous == true)) {
      _syncWeaponHud();
    }
    if (_rumble > 0) {
      _rumble = math.max(0, _rumble - dt);
      final amp = 0.14 * (_rumble / 0.35);
      camera.viewfinder.position += Vector2(
            _combatRng.nextDouble() - 0.5,
            _combatRng.nextDouble() - 0.5,
          ) *
          (2 * amp);
    }
  }

  /// How far [p] is from the surface of a shootable body (m).
  static double _reachTo(BodyComponent c, Vector2 p) {
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

  static double _segmentDistance(Vector2 a, Vector2 b, Vector2 p) {
    final ab = b - a;
    final l2 = ab.length2;
    final t = l2 == 0 ? 0.0 : ((p - a).dot(ab) / l2).clamp(0.0, 1.0);
    return (a + ab * t - p).length;
  }

  @override
  void detonate(Vector2 at, WeaponSpec weapon) {
    final r = weapon.blastRadius;
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
    _rumble = 0.35;
  }

  @override
  void onObstacleDestroyed(Offset at) {
    _burstAt(at);
    AudioService.playBoom();
    Haptics.medium();
    ProgressService.instance.incrementStat(ProgressService.statObstaclesWrecked);
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
    Isolate.run(() => extractCaveLoops(field, nx, ny, cell)).then((loops) {
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

  /// 3 · 2 · 1 · GO, then the ship launches by itself. Input during the
  /// countdown launches it at once and clears the numbers.
  void _updateCountdown(double dt, ShipBody s) {
    final left = _countdown;
    if (left == null) return;
    if (s.launched) {
      _countdown = null;
      _countdownHud?.text = null;
      return;
    }
    final now = left - dt;
    _countdown = now;
    if (now <= 0) {
      _countdown = null;
      s.launch();
      _countdownHud?.go();
      AudioService.playCountdown(go: true);
      return;
    }
    if (now <= 3) {
      final n = now.ceil();
      if (n != left.ceil() || left > 3) AudioService.playCountdown(go: false);
      _countdownHud?.text = '$n';
    }
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
      _hint?.belowBanner = _combatHud?.showing ?? false;
      final worldSize = _currentWorldSize;
      if (worldSize != null) _followCamera(s, worldSize, dt);

      if (demoMode) {
        _updateDemo(dt, s);
      } else {
        s.setInput(rotate: rotateAxis, thrust: thrustHeld, fire: fireHeld);
        _updateCountdown(dt, s);
        if (routeGuideOn && s.launched) guidedThisRun = true;
      }
      AudioService.updateEngine(thrusting: s.isThrusting, dt: dt);
      AudioService.setAlarm(_meltdownLeft != null);
      _updateCombat(dt);
      _updateWeapons(dt, s);
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

/// Laser path: the first solid thing along the beam. The ship, the pod and
/// sensors don't stop it (a beam that cut the pod loose would be a trap).
class _LaserRay extends RayCastCallback {
  _LaserRay({this.cargo});
  final Body? cargo;
  Fixture? fixture;
  Vector2? point;

  @override
  double reportFixture(Fixture f, Vector2 p, Vector2 normal, double fraction) {
    if (f.isSensor || f.body == cargo) return -1;
    if (f.userData is ShipTag || f.body.userData is ShipBody) return -1;
    fixture = f;
    point = p.clone();
    return fraction;
  }
}
