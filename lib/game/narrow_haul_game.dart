import 'dart:async';
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
import 'package:narrow_haul/game/components/guidance_hud.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/components/minimap_hud.dart';
import 'package:narrow_haul/game/components/obstacles.dart';
import 'package:narrow_haul/game/components/parallax_background.dart';
import 'package:narrow_haul/game/components/route_guide.dart';
import 'package:narrow_haul/game/camera/camera_director.dart';
import 'package:narrow_haul/game/components/rock_proximity.dart';
import 'package:narrow_haul/game/components/world_frame.dart';
import 'package:narrow_haul/game/components/shield_flash.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/components/ship_fx.dart';
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
import 'package:narrow_haul/game/combat/intercept.dart';
import 'package:narrow_haul/game/perf/perf_monitor.dart';
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
import 'package:narrow_haul/game/guidance/flight_guidance.dart';
import 'package:narrow_haul/game/ship/hull_contact.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/game/ship/weapons.dart';
import 'package:narrow_haul/game/tags.dart';
import 'package:narrow_haul/game/overlay_ids.dart';

enum RunState { menu, playing, gameOver, won }

/// First reactor escape on a level pays this XP and currency (once).
/// Test Flight ship options for [level], on a background isolate. Top-level
/// so the closure can't capture the game, which an isolate can't receive.
Future<List<String>> _testFlightShipIds(int level) => Isolate.run(
      () => [for (final s in LevelRegistry.testFlightOptions(level)) s.id],
    );

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
    this.coinsBefore = 0,
  });

  final XpBreakdown xp;
  final int xpBefore;
  final int xpAfter;
  final int currency;
  final List<AchievementMeta> newAchievements;

  /// Coin balance before this payout (what it made affordable).
  final int coinsBefore;

  RunReward withCurrency(int value) => RunReward(
    xp: xp,
    xpBefore: xpBefore,
    xpAfter: xpAfter,
    currency: value,
    newAchievements: newAchievements,
    coinsBefore: coinsBefore,
  );

  PilotRank get rankBefore => rankFor(xpBefore);
  PilotRank get rankAfter => rankFor(xpAfter);
  bool get rankedUp => rankAfter.index > rankBefore.index;
}

class NarrowHaulGame extends Forge2DGame
    with KeyboardEvents
    implements CombatHost {
  /// Pixels per metre on a reference phone (landscape height
  /// [_referenceViewHeight] logical px). Larger screens zoom in by the same
  /// ratio, so every screen shows the same height of cave and the ship and
  /// pod take the same share of it (macOS window, iPad).
  static const double _baseZoom = 28;
  static const double _referenceViewHeight = 390;

  /// Screen height relative to the reference phone (0.8–3).
  double get _screenScale {
    final h = camera.viewport.size.y;
    if (h <= 0) return 1;
    return (h / _referenceViewHeight).clamp(0.8, 3.0);
  }

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
  double _touchAxis = 0; // raw stick deflection, shaped in [_combineInputs]
  double _stickX = 0, _stickY = 0; // the stick as a direction (point mode)
  bool _touchThrust = false;
  bool _touchFire = false;
  final KeyboardFlightInput _keys = KeyboardFlightInput();

  /// How long the current turn key has been held (keyboard boost).
  double _keyHeld = 0;
  double _keyDir = 0;
  bool _wasBoosting = false;

  /// How far the stick's fast speed has built up (0…1, see
  /// [FlightTuning.boostBuildUp]).
  double _boostCharge = 0;

  /// Two-speed steering (see [FlightTuning]): ±1 is the ship's precise turn
  /// rate, the stick's outer zone or a held key boosts past it.
  void _combineInputs() {
    final boost = ship?.maxRotateInput ?? 1.0;
    final s = ship;
    final touch = FlightTuning.steer.isPointer
        ? (s == null
              ? 0.0
              : FlightTuning.pointerAxis(
                  x: _stickX,
                  y: _stickY,
                  shipAngle: s.body.angle,
                  baseRate: s.turnRate,
                  boost: boost,
                ))
        : FlightTuning.applyBoostCharge(
            FlightTuning.shapeStick(_touchAxis, boost),
            _boostCharge,
          );
    final key = FlightTuning.keyAxis(_keys.rotateAxis, _keyHeld, boost);
    rotateAxis = (touch + key).clamp(-boost, boost);
    final boosting = rotateAxis.abs() > 1.001;
    if (boosting && !_wasBoosting && FlightTuning.steer.hasZones) {
      Haptics.light();
    }
    _wasBoosting = boosting;
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
    final slotKey = KeyboardFlightInput.slotKeys.indexOf(event.logicalKey);
    if (flying && event is KeyDownEvent && slotKey >= 0) {
      selectWeaponSlot(slotKey);
      return KeyEventResult.handled;
    }
    if (!flying) {
      _keys.reset();
      return KeyEventResult.ignored;
    }
    _keys.update(keysPressed);
    if (_keys.rotateAxis != _keyDir) {
      _keyDir = _keys.rotateAxis;
      _keyHeld = 0;
    }
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

  /// Test-only: keep built caves across level loads (debug builds otherwise
  /// rebuild the loaded level's cave for hot-reload authoring).
  @visibleForTesting
  bool debugKeepCaveCache = false;

  /// Source of crate odds/contents/spots (seedable in tests).
  @visibleForTesting
  math.Random crateRng = math.Random();

  /// The crate on the current level, if any (tests, hints).
  SupplyCrate? get supplyCrate => _crate;
  SupplyCrate? _crate;

  /// A short line shown in the hint slot after picking up a crate.
  // Timed hint: a picked-up weapon, or the first scrape ever.
  /// A crate just collected: its weapon is coached on FIRE for a moment.
  CrateNotice? _crateNotice;
  double _crateNoticeLeft = 0;

  /// Rock touches this flight that didn't crash, and the cooldown that keeps
  /// a slide along a wall from machine-gunning sound and haptics.
  int scrapesThisRun = 0;
  double _scrapeFxCooldown = 0;

  /// Shield glow facing nearby rock (see [_updateRockWarning]).
  ShieldGlow? _shieldGlow;
  double _proximityBuzzCooldown = 0;

  /// A bounce or a slide re-touches within a moment: one shield sound per
  /// [_scrapeSoundGap] seconds.
  double _scrapeSoundCooldown = 0;
  static const double _scrapeSoundGap = 0.4;

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
  CoachMarkHud? _coach;
  WorldMarkerHud? _markers;
  CommsHud? _comms;
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

  /// The launch intro (ship orbiting a planet while the game loads), drawn by
  /// the app above the game on every start that doesn't play the credits.
  final introVisible = ValueNotifier<bool>(
    ProgressService.instance.creditsSeen,
  );

  // Crash sequence: explosion + shake play out before the gameOver overlay.
  static const double _crashDelay = 0.9;
  double _crashTimer = 0;
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
    PerfMonitor.mark('audio');

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
        _touchAxis = v;
        _combineInputs();
      },
      onStick: (x, y) {
        _stickX = x;
        _stickY = y;
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
      onSelectWeapon: selectWeapon,
    );
    _hudControls!.size = camera.viewport.size;
    camera.viewport.add(_hudControls!);

    _pauseButton = PauseButtonHud(onPressed: pauseGame);
    camera.viewport.add(_pauseButton!);
    _levelIntro = LevelIntroHud();
    camera.viewport.add(_levelIntro!);
    _countdownHud = CountdownHud();
    camera.viewport.add(_countdownHud!);
    _markers = WorldMarkerHud();
    camera.viewport.add(_markers!);
    _coach = CoachMarkHud(controls: _hudControls!);
    camera.viewport.add(_coach!);
    _comms = CommsHud(
      controls: _hudControls!,
      avoid: () => _coach?.plateRect,
      onLine: (_) => AudioService.playUi(UiSound.open),
    );
    camera.viewport.add(_comms!);
    _combatHud = CombatStatusHud();
    camera.viewport.add(_combatHud!);
    _applySafeInsets();

    applySettings();

    AchievementService.announced.addListener(_onAchievementAnnounced);
    _syncAnalyticsUser();

    overlays.add(OverlayIds.menu);
    MusicService.play(MusicService.menuTrack, MusicService.menuVolume);
    pauseEngine();
    if (kPerfProbe) {
      camera.viewport.add(PerfHud());
      PerfMonitor.mark('game loaded');
    }
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
    _combatHud?.insets = _safeInsets;
    _markers?.insets = _safeInsets;
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
    final levels = unlockedLevelIndices();
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
    _countdown = (demoMode || _tutorialHints) ? null : _countdownSeconds;
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
    }

    for (final spec in data.pickups) {
      final pickup = switch (spec) {
        FuelCellSpec s => FuelCell(spec: s, host: this, accent: theme.uiAccent),
      };
      await _addToLevel(pickup, gen);
    }

    final helipad = HelipadVisual(
      center: data.shipSpawn,
      sizeMeters: Vector2(3.4, 2.4),
      base: theme.padBase,
      accent: theme.padAccent,
    );
    await _addToLevel(helipad, gen);

    final landingStrip = LandingStripVisual(
      center: data.goalCenter,
      sizeMeters: Vector2(data.goalHalfWidth * 2, data.goalHalfHeight * 2),
      // Cave pads land on the shelf the builder lays below the box.
      floorDrop: data.caveLoops.isNotEmpty ? kPadFloorDrop : null,
    );
    await _addToLevel(landingStrip, gen);

    late final CargoAttachment cargoLink;
    final challengeShip = isChallengeMode ? activeChallengeConfig?.shipId : null;
    final shipSpec = challengeShip != null
        ? shipById(challengeShip)
        : LevelRegistry.shipFor(levelIndex);
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
    final shipBody = ShipBody(
      initialPosition: Vector2.copy(data.shipSpawn),
      onWallHit: () => _onShipHitWall(),
      onRockTouch: _onRockTouch,
      onHookTouchesCargo: () => cargoLink.onHookCargoTouch(),
      onFire: _onShipFired,
      onWeapon: _onWeaponFired,
      rack: rack,
      fuelDrainMultiplier: _fuelDrainMultiplier * mods.fuelDrainMul,
      spec: shipSpec,
      kit: kitById(CosmeticsService.getEquippedId(CosmeticsService.catKit)),
      // The hull's rim light picks up the cave's glow (neutral without one).
      rimColor: theme.edgeGlow?.withValues(alpha: 1) ?? HullLighting.defaultRim,
    );
    final cargoBody = CargoBody(
      initialPosition: Vector2.copy(data.cargoSpawn),
      densityMul: mods.cargoDensityMul,
      clamped: data.cargoClamped,
      image: art.cargoFor(mods.cargoDensityMul),
      strapped: mods.cargoDensityMul > 1.0 && art.cargoHeavy == null,
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

    _levelEntities.addAll([shipBody, cargoBody, cargoLink]);
    await world.addAll([shipBody, cargoBody, cargoLink]);
    _checkLoad(gen);
    final glow = _shieldGlow = ShieldGlow(ship: shipBody);
    await _addToLevel(glow, gen);

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

    final landing = DualLandingZone(
      padCenter: data.goalCenter,
      halfWidth: data.goalHalfWidth,
      halfHeight: data.goalHalfHeight,
      onBothLanded: _onBothLanded,
    );
    await _addToLevel(landing, gen);
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
    _clearGuidance();
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
    info.starSpec = currentLevelDef.stars;
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  /// Smallest zoom that still keeps the view inside the world.
  double _minContainZoom = 0;

  /// Decides focus and zoom from the flight (pure, `camera/camera_director.dart`);
  /// this class only clamps it to the world and adds the shake.
  final CameraDirector _director = CameraDirector(FlightTuning.camera.profile);

  /// Crash, blasts and the meltdown rumble, added after the follow.
  final TraumaShake _shake = TraumaShake();
  Vector2 _shakeApplied = Vector2.zero();

  /// The system asks for reduced motion (set by the app): softer zoom and shake.
  bool reducedMotion = false;

  /// Rock along the velocity, refreshed every other frame.
  double? _aheadGap;
  bool _aheadTick = false;

  /// Seconds since the player last thrust, turned or fired (the camera
  /// zooms in once they let go).
  double _idleFor = 0;

  /// Level-start close-up of the ship and the delivery push-in.
  final CloseUp _closeUp = CloseUp();

  /// Close-up zooms (× the flight zoom): a first look at a new mission, a
  /// new ship's first flight (shown off longest), and a quick one on retry.
  static const double _closeUpFirst = 2.2;
  static const double _closeUpNewShip = 2.6;
  static const double _closeUpRetry = 1.5;
  static const double _closeUpDelivery = 1.5;

  /// Where the ship sits in a close-up (fraction of the screen height):
  /// below the level card (top third) and the 3 · 2 · 1 (centre).
  static const double _closeUpShipY = 0.72;

  /// Opens a level on the ship: it holds through the level card, then
  /// eases out over 3 · 2 · 1 to the flight view at GO. Without a countdown
  /// (onboarding) it holds until the first input. Any input releases it.
  void _startCloseUp({required bool retry}) {
    _closeUp.reset();
    if (demoMode || kStoreCapture || FlightTuning.camera.profile.isStatic) return;
    final s = ship;
    if (s == null) return;
    // Kestrel is the training ship, so it's never new (as in the briefing).
    final newShip =
        !retry && s.spec.id != kKestrel.id && !LevelRegistry.hasTypeRating(s.spec.id);
    var peak = retry ? _closeUpRetry : (newShip ? _closeUpNewShip : _closeUpFirst);
    if (reducedMotion) peak = 1 + (peak - 1) * 0.4;
    final countdown = _countdown;
    _closeUp.intro(
      peak: peak,
      hold: countdown == null ? double.infinity : countdown - 3,
      out: 3,
    );
  }

  /// Camera shift (m) that keeps the ship out from under the controls,
  /// eased in quickly and out slowly.
  final Spring _nudgeX = Spring();
  final Spring _nudgeY = Spring();

  void _applyContainedCamera(Vector2 worldSize) {
    final viewportSize = camera.viewport.size;
    if (viewportSize.x <= 0 || viewportSize.y <= 0) return;
    final minZoomX = viewportSize.x / worldSize.x;
    final minZoomY = viewportSize.y / worldSize.y;
    _minContainZoom = math.max(minZoomX, minZoomY) * 1.01;
    camera.viewfinder.zoom = math.max(_restZoom * _director.zoom, _minContainZoom);
  }

  /// Normal zoom for the camera mode, never showing outside the world.
  double get _restZoom => math.max(
        _baseZoom * _screenScale * FlightTuning.camera.profile.zoomMul,
        _minContainZoom,
      );

  void _followCamera(ShipBody s, Vector2 worldSize, double dt) {
    _director.profile = FlightTuning.camera.profile;
    final vel = s.body.linearVelocity;
    final speed = vel.length;
    if (_aheadTick = !_aheadTick) {
      _aheadGap = speed > 0.5 && _director.profile.impactZoomOut > 0
          ? probeAhead(world, s, vel / speed)
          : null;
    }
    final towing = demoMode ? _demoTowing : (cargoAttachment?.attached ?? false);
    final pod = towing ? cargo?.body.position : null;
    // Local gravity (fields included) sets "down"; none in zero-g.
    final g = s.localAccel;
    final gLen = g.length;
    final down = gLen > 0.2 * baseGravityY() ? g / gLen : Vector2.zero();
    final restZoom = _restZoom;
    final view = camera.viewport.size;
    final shot = _director.update(
      CameraInputs(
        shipX: s.body.position.x,
        shipY: s.body.position.y,
        velX: vel.x,
        velY: vel.y,
        launched: s.launched,
        towing: towing,
        podX: pod?.x,
        podY: pod?.y,
        aheadGap: _aheadGap,
        downX: down.x,
        downY: down.y,
        idleFor: demoMode ? 0 : _idleFor,
        viewHalfW: view.x / restZoom / 2,
        viewHalfH: view.y / restZoom / 2,
      ),
      dt,
    );
    // Reduced motion halves the zoom swings (in log space).
    final factor = reducedMotion ? math.sqrt(shot.zoom) : shot.zoom;
    if (s.launched) _closeUp.release();
    _closeUp.update(dt);
    final close = _closeUp.factor;
    final zoom = math.max(restZoom * factor * close, _minContainZoom);
    camera.viewfinder.zoom = zoom;
    var focus = Vector2(shot.x, shot.y);
    final w = _closeUp.weight;
    if (w > 0) {
      // Frame the subject: the ship a little low (level start), or ship
      // and pod together on the pad (delivery).
      final podNow = cargo?.body.position;
      final subject = runState == RunState.won && podNow != null
          ? (s.body.position + podNow) / 2
          : s.body.position - Vector2(0, (_closeUpShipY - 0.5) * view.y / zoom);
      focus += (subject - focus) * w;
    }
    final base = _clampedCameraTarget(focus, worldSize);
    final want = _safeFrameShift(s, base);
    double time(Spring n, double w) => w.abs() > n.x.abs() ? 0.3 : 0.8;
    _nudgeX.step(want.x, time(_nudgeX, want.x), dt);
    _nudgeY.step(want.y, time(_nudgeY, want.y), dt);
    camera.viewfinder.position = _clampedCameraTarget(
      base + Vector2(_nudgeX.x, _nudgeY.x),
      worldSize,
      overscroll: true,
    );
    _shieldShipFromText(s, pod);
  }

  /// Help text (coach plate, comms line) keeps off the ship and the pod.
  void _shieldShipFromText(ShipBody s, Vector2? pod) {
    final zoom = camera.viewfinder.zoom;
    Rect box(Vector2 p, double r) {
      final c = camera.localToGlobal(p);
      return Rect.fromCircle(center: Offset(c.x, c.y), radius: r * zoom + 10);
    }

    final rects = [
      box(s.body.position, s.spec.circumradius),
      if (pod != null) box(pod, kCargoRadius),
    ];
    _coach?.shield = rects;
    _comms?.shield = rects;
  }

  /// Camera shift (m) from [base] that keeps the ship clear of the touch
  /// controls ([HudTouchControls.controlZones]) and the top-left gauges.
  /// Near the world's floor or walls the clamp would leave the ship under
  /// THRUST or the dial; this lets the view look a little past the edge.
  Vector2 _safeFrameShift(ShipBody s, Vector2 base) {
    final hud = _hudControls;
    final view = camera.viewport.size;
    final zoom = camera.viewfinder.zoom;
    if (hud == null || demoMode || view.x <= 0 || zoom <= 0) return Vector2.zero();
    final insets = _safeInsets;
    final zones = [
      ...hud.controlZones,
      // Fuel gauge and level info.
      (l: insets.left, t: insets.top, r: insets.left + 240.0, b: insets.top + 96.0),
    ];
    final p = (s.body.position - base) * zoom + view / 2;
    final (dx, dy) = safeFrameNudge(
      p.x,
      p.y,
      s.spec.circumradius * 0.7 * zoom,
      zones,
      view.x,
      view.y,
    );
    // The ship moves by (dx, dy) px when the camera moves the other way.
    return Vector2(-dx, -dy) / zoom;
  }

  /// Takes last frame's shake out of the camera, so nothing reads or keeps it.
  void _removeShake() {
    if (_shakeApplied.x == 0 && _shakeApplied.y == 0) return;
    camera.viewfinder.position -= _shakeApplied;
    _shakeApplied = Vector2.zero();
  }

  /// Adds this frame's shake on top of the settled camera.
  void _applyShake(double dt) {
    if (_meltdownLeft == null) _shake.floor = 0;
    _shake
      ..scale = reducedMotion ? 0.3 : 1
      ..update(dt);
    final (x, y) = _shake.offset;
    if (x == 0 && y == 0) return;
    _shakeApplied = Vector2(x, y);
    camera.viewfinder.position += _shakeApplied;
  }

  /// Flame's own bounds allow the overscroll; [_clampedCameraTarget] keeps
  /// the view inside the world unless the controls need the room.
  void _applyCameraBounds(Vector2 worldSize) {
    camera.setBounds(
      Rectangle.fromLTRB(
        -kCameraOverscroll,
        -kCameraOverscrollTop,
        worldSize.x + kCameraOverscroll,
        worldSize.y + kCameraOverscroll,
      ),
      considerViewport: true,
    );
  }

  void _snapCameraToShip() {
    final s = ship;
    final worldSize = _currentWorldSize;
    if (s == null || worldSize == null) return;
    _director
      ..profile = FlightTuning.camera.profile
      ..reset(s.body.position.x, s.body.position.y);
    _shake.clear();
    _shakeApplied = Vector2.zero();
    _aheadGap = null;
    _idleFor = 0;
    camera.viewfinder.zoom = math.max(_restZoom, _minContainZoom);
    final base = _clampedCameraTarget(s.body.position, worldSize);
    // Start already clear of the controls (a pad on the world's floor).
    final shift = _safeFrameShift(s, base);
    _nudgeX.set(shift.x);
    _nudgeY.set(shift.y);
    camera.viewfinder.position =
        _clampedCameraTarget(base + shift, worldSize, overscroll: true);
  }

  /// Keeps the view inside the world, or with [overscroll] up to
  /// [kCameraOverscroll] past it (the rock is drawn that far out).
  Vector2 _clampedCameraTarget(
    Vector2 desired,
    Vector2 worldSize, {
    bool overscroll = false,
  }) {
    final viewportSize = camera.viewport.size;
    final zoom = camera.viewfinder.zoom;
    if (viewportSize.x <= 0 || viewportSize.y <= 0 || zoom <= 0) return desired;

    final halfViewW = (viewportSize.x / zoom) / 2;
    final halfViewH = (viewportSize.y / zoom) / 2;
    final side = overscroll ? kCameraOverscroll : 0.0;
    final top = overscroll ? kCameraOverscrollTop : 0.0;

    final minX = halfViewW - side;
    final maxX = worldSize.x - halfViewW + side;
    final minY = halfViewH - top;
    final maxY = worldSize.y - halfViewH + side;

    final x = minX > maxX ? worldSize.x / 2 : desired.x.clamp(minX, maxX);
    final y = minY > maxY ? worldSize.y / 2 : desired.y.clamp(minY, maxY);
    return Vector2(x.toDouble(), y.toDouble());
  }

  // ── Level cleanup ─────────────────────────────────────────────────────────

  void _clearLevel() {
    PerfMonitor.flightEnded('left');
    _flushAmmo();
    _levelGen++;
    _rack = null;
    _carver = null;
    _terrain = null;
    _decor = null;
    _carveBusy = false;
    _laserBeam = null;
    _crate = null;
    _crateNotice = null;
    _crateNoticeLeft = 0;
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
    _shake.clear();
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
    _stickX = 0;
    _stickY = 0;
    _touchThrust = false;
    _touchFire = false;
    _keys.reset();
    _keyHeld = 0;
    _keyDir = 0;
    _wasBoosting = false;
    _boostCharge = 0;
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

  /// A slow rock touch ([classifyHullContact]): the shield flares (plus a
  /// dust puff on a touchdown), a soft knock, and the first time ever, a
  /// hint that slow touches are safe.
  void _onRockTouch(Vector2 point, Vector2 normal, HullContact kind) {
    if (runState != RunState.playing || demoMode) return;
    scrapesThisRun++;
    if (_scrapeFxCooldown > 0) return;
    _scrapeFxCooldown = 0.2;
    final touchdown = kind == HullContact.touchdown;
    final s = ship;
    if (s != null) {
      world.add(
        ShieldFlash(ship: s, rockNormal: normal, strength: touchdown ? 0.55 : 1),
      );
    }
    if (touchdown) {
      world.add(
        DustPuff(
          center: Offset(point.x, point.y),
          normal: Offset(normal.x, normal.y),
          seed: scrapesThisRun,
        ),
      );
    }
    if (_scrapeSoundCooldown <= 0) {
      _scrapeSoundCooldown = _scrapeSoundGap;
      AudioService.playScrape(touchdown: touchdown);
    }
    touchdown ? Haptics.medium() : Haptics.light();
    final progress = ProgressService.instance;
    if (!progress.scrapeHintSeen) {
      progress.markScrapeHintSeen();
      _comms?.say(
        const CommsLine(
          id: 'scrape',
          callsign: 'TOWER',
          text: 'Shields take slow touches. Hit the rock fast and you crash.',
        ),
        urgent: true,
      );
    }
  }

  /// The shield glows toward rock within 1 m, cyan while the ship's speed
  /// into it would only scrape, amber→red when it would crash
  /// ([kScrapeMaxSpeed]); one light buzz when a crash-speed approach is
  /// about to land.
  void _updateRockWarning(ShipBody s, double dt) {
    final glow = _shieldGlow;
    if (glow == null) return;
    if (_proximityBuzzCooldown > 0) _proximityBuzzCooldown -= dt;
    final near = s.launched && !demoMode ? probeRockNearby(world, s) : null;
    if (near == null || near.gap > 1.0) {
      glow.hide();
      return;
    }
    final closeness = 1 - (near.gap / 1.0).clamp(0.0, 1.0);
    // Coming down upright onto flat ground is a touchdown, which is safe
    // at a higher speed than a scrape.
    final up = s.localAccel.length2 > 1e-4
        ? -(s.localAccel.normalized())
        : near.normal;
    final nose = s.body.worldVector(Vector2(0, -1));
    final landing =
        nose.dot(up) >= math.cos(kTouchdownMaxTilt) &&
        near.normal.dot(up) >= math.cos(kTouchdownMaxSlope);
    final limit = landing ? kTouchdownMaxSpeed : kScrapeMaxSpeed;
    // Machinery, turrets and well cores crash at any speed: always red.
    final danger = near.lethal
        ? 1.0
        : ((near.approach - 0.6 * limit) / (0.6 * limit)).clamp(0.0, 1.0);
    glow.show(-near.normal, closeness * closeness, danger);
    if (danger >= 1 &&
        near.approach > 0.05 &&
        near.gap < 0.5 &&
        _proximityBuzzCooldown <= 0) {
      _proximityBuzzCooldown = 1.0;
      Haptics.light();
    }
  }

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
    PerfMonitor.flightEnded('crashed');
    _pauseButton?.visible = false;
    _clearGuidance();
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
    _shake.add(1);
    _crashTimer = _crashDelay;
  }

  /// Pad callback: accepts the delivery only mid-flight, so a wreck sliding
  /// onto the pad (or a demo) leaves the zone armed for a later landing.
  bool _onBothLanded() {
    if (runState != RunState.playing || demoMode) return false;
    unawaited(_onGoalReached());
    return true;
  }

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
    // A slow push-in on ship and pod sitting on the pad.
    if (!FlightTuning.camera.profile.isStatic && !kStoreCapture) {
      _closeUp.pushIn(reducedMotion ? 1.2 : _closeUpDelivery, _winDelay);
    }
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

  /// Tests: the delivery pad's sensors.
  @visibleForTesting
  DualLandingZone? get debugLandingZone => _landingZone;

  /// Tests: the touch controls (layout, safe-frame zones, handedness).
  @visibleForTesting
  HudTouchControls? get debugHudControls => _hudControls;

  /// Tests: one camera step on its own (no physics).
  @visibleForTesting
  void debugCameraStep(double dt) {
    final s = ship, worldSize = _currentWorldSize;
    if (s != null && worldSize != null) _followCamera(s, worldSize, dt);
  }

  /// Tests: the close-up zoom (× the flight zoom) right now.
  @visibleForTesting
  double get debugCloseUp => _closeUp.factor;

  /// Tests: the crate notice currently on air.
  @visibleForTesting
  CrateNotice? get debugCrateNotice => _crateNotice;

  /// Tests: as if [crate] had just been flown through.
  @visibleForTesting
  void debugCollectCrate(SupplyCrate crate) => _onCrateCollected(crate);

  /// Tests: lands the run as if ship and pod had touched down.
  @visibleForTesting
  Future<void> debugDeliver() => _onGoalReached();

  /// Tests: runs first in the delivery booking (throw to simulate a failed
  /// save).
  @visibleForTesting
  void Function()? debugBeforeBooking;

  @visibleForTesting
  int debugStars(double fuelFraction, double timeSeconds) =>
      _calculateStars(fuelFraction * _shipMaxFuel, timeSeconds);

  int _calculateStars(double fuelRemaining, double timeSeconds) {
    // A continued (rewarded ad) or guided run can never buy a perfect rating.
    return currentLevelDef.stars.rate(
      fuelRemaining / _shipMaxFuel,
      timeSeconds,
      capped: continuedThisRun || guidedThisRun || carriedWeaponUsedThisRun,
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
    overlays.remove(OverlayIds.gameOver);

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
    _shake.clear();
    _crashTimer = 0;
    _resetInputState();
    runState = RunState.playing;
    _pauseButton?.visible = true;
    // A wreck that slid onto the pad was refused; re-arm the pad, and land
    // straight away if the rewind put ship and pod on it.
    _landingZone
      ?..reset()
      ..recheck();
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
    overlays.removeAll([OverlayIds.gameOver, OverlayIds.pause, OverlayIds.settings]);
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
    overlays.removeAll([OverlayIds.levelComplete, OverlayIds.rankUp]);
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
    PerfMonitor.flightEnded(demoMode ? 'demo' : 'quit');
    // Back online since launch? Ads and store products come back here.
    MonetizationService.instance.refreshIfNeeded();
    _logQuit('menu');
    _leaveDemo();
    overlays.removeAll([OverlayIds.gameOver, OverlayIds.pause, OverlayIds.settings]);
    CosmeticsService.clearTrials();
    // Quitting mid-flight still counts the time flown.
    _recordPlaytime();
    overlays.removeAll([OverlayIds.levelComplete, OverlayIds.rankUp]);
    _recordSpentFuel();
    _resetInputState();
    _clearLevel();
    _resetChallenge();
    _countdown = null;
    _countdownHud?.text = null;
    runState = RunState.menu;
    pauseEngine();
    overlays.add(OverlayIds.menu);
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

  /// Coach marks and world markers for this frame ([resolveGuidance]); the
  /// route-guide comms once the guide is on.
  void _updateGuidance(ShipBody s) {
    final zone = _landingZone;
    final crate = _crateNotice;
    final g = resolveGuidance(GuidanceInputs(
      demo: demoMode,
      desktop: _desktop,
      pointSteer: FlightTuning.steer.isPointer,
      tutorial: _tutorialHints,
      starRulesStep: _starRulesStep && !s.launched,
      thrustUsed: _thrustUsed,
      rotateUsed: _rotateUsed,
      attached: cargoAttachment?.attached == true,
      shipOnPad: zone?.shipInside ?? false,
      podOnPad: zone?.cargoInside ?? false,
      armed: s.spec.armed,
      combatLevel: currentLevel?.hasCombat == true,
      shotsFired: s.shotsFired,
      levelStarred:
          ProgressService.instance.getStarsById(currentLevelDef.saveId) > 0,
      fuelPerShotFrac: s.spec.fuelPerShot * s.fuelDrainMultiplier / s.maxFuel,
      crate: crate,
      canisterUnseen: _pickupHint() != null,
    ));
    _coach?.mark = g.coach;
    _levelInfoHud?.frameTarget = g.frameStarTarget;

    final m = _markers;
    if (m != null) {
      m
        ..project = (p) {
          final v = camera.localToGlobal(Vector2(p.dx, p.dy));
          return Offset(v.x, v.y);
        }
        ..zoom = camera.viewfinder.zoom
        ..turrets = g.markTurrets
            ? [
                for (final c in world.children)
                  if (c is Turret && !c.destroyed)
                    Offset(c.spec.base.x, c.spec.base.y),
              ]
            : const []
        ..turretRadius = Turret.domeRadius
        ..podTag = g.pod
        ..pod = _cargoPos()
        ..padCenter = zone == null ? null : Offset(zone.padCenter.x, zone.padCenter.y)
        ..pad = g.pad
        ..canister = g.markCanister ? _nearestCanister(s) : null
        ..podRadius = CargoBody.radius;
    }

    if (routeGuideOn &&
        s.spec.armed &&
        !demoMode &&
        (currentRoute?.shots.isNotEmpty ?? false)) {
      _comms?.say(const CommsLine(
        id: 'route',
        callsign: 'OPS',
        text: 'Route is on your screen. Hold at each red ⊕ and fire along its '
            'dashes. Red dots are under fire.',
      ));
    }
  }

  Offset? _cargoPos() {
    final c = cargo;
    if (c == null) return null;
    final p = c.body.position;
    return Offset(p.x, p.y);
  }

  Offset? _nearestCanister(ShipBody s) {
    final p = s.body.position;
    Offset? best;
    var bestD = double.infinity;
    for (final c in world.children) {
      if (c is! FuelCell || c.collected) continue;
      final d = (c.spec.pos.x - p.x) * (c.spec.pos.x - p.x) +
          (c.spec.pos.y - p.y) * (c.spec.pos.y - p.y);
      if (d < bestD) {
        bestD = d;
        best = Offset(c.spec.pos.x, c.spec.pos.y);
      }
    }
    return best;
  }

  /// tut_02 before its first clear: the star rules are explained on the pad.
  bool get _starRulesStep => _tutorialHints && levelIndex == 1;

  /// The comms lines a flight opens with, after the intro card.
  void _scheduleComms({required bool retry}) {
    final comms = _comms;
    if (comms == null || demoMode) return;
    const afterIntro = 2.6;
    if (_starRulesStep) {
      comms.say(
        const CommsLine(
          id: 'stars',
          callsign: 'TOWER',
          text: 'Stars: ★ deliver, ★★ save fuel, ★★★ save more and beat the '
              'clock. Your target is under the fuel bar.',
        ),
        delay: afterIntro,
      );
    }
    final shipHint = _shipHint();
    if (shipHint != null && !retry) {
      comms.say(CommsLine(id: 'ship', callsign: 'OPS', text: shipHint), delay: afterIntro);
    }
    if (_pickupHint() != null) {
      comms.say(
        const CommsLine(
          id: 'canister',
          callsign: 'OPS',
          text: 'Fuel canister marked. Fly through it to top up the tank.',
        ),
        delay: afterIntro,
      );
    }
  }

  void _clearGuidance() {
    _coach?.clear();
    _markers?.clear();
    _comms?.clear();
    _levelInfoHud?.frameTarget = false;
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
    return "You're flying the ${spec.name}. ${spec.blurb}";
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
    MonetizationService.instance.refreshIfNeeded();
    overlays.remove(OverlayIds.menu);
    overlays.add(key);
  }

  /// Pause menu → Settings.
  void openSettingsFromPause() {
    overlays.remove(OverlayIds.pause);
    overlays.add(OverlayIds.settings);
  }

  /// Settings → wherever it was opened from (pause menu or hangar).
  void closeSettings() {
    overlays.remove(OverlayIds.settings);
    overlays.add(isPaused ? OverlayIds.pause : OverlayIds.menu);
  }

  /// The rank-up card over the results screen.
  void showRankUp() => overlays.add(OverlayIds.rankUp);
  void closeRankUp() => overlays.remove(OverlayIds.rankUp);

  /// A sub-screen → back to the hangar (or to the briefing the Garage was
  /// opened from).
  void closeScreen(String key) {
    MonetizationService.instance.refreshIfNeeded();
    overlays.remove(key);
    final back = _garageReturn;
    _garageReturn = null;
    if (key == OverlayIds.cosmetics && back != null) {
      overlays.add(back.under);
      briefingLevel = back.level;
      briefingDaily = false;
      overlays.add(OverlayIds.briefing);
      return;
    }
    overlays.add(OverlayIds.menu);
  }

  /// Where the Garage returns to when opened from a mission briefing.
  ({String under, int level})? _garageReturn;

  /// Briefing → Garage (change tow gear or kit); closing it comes back to
  /// the same briefing.
  void openGarageFromBriefing() {
    final under = overlays.isActive(OverlayIds.levelSelect)
        ? OverlayIds.levelSelect
        : OverlayIds.menu;
    _garageReturn = (under: under, level: briefingLevel);
    MonetizationService.instance.refreshIfNeeded();
    overlays.removeAll([OverlayIds.briefing, under]);
    overlays.add(OverlayIds.cosmetics);
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
    overlays.add(OverlayIds.briefing);
  }

  /// Hangar Daily → today's challenge briefing (over the hangar).
  void openDailyBriefing() {
    briefingLevel = DailyChallengeConfig.peekToday(unlockedLevelIndices()).$1;
    briefingDaily = true;
    overlays.add(OverlayIds.briefing);
  }

  void closeBriefing() => overlays.remove(OverlayIds.briefing);

  /// Flat indices of every unlocked level (the daily's candidates).
  static List<int> unlockedLevelIndices() => [
    for (var i = 0; i < LevelRegistry.totalLevels; i++)
      if (LevelRegistry.isLevelUnlocked(i)) i,
  ];

  /// Android back / system back. Returns false only on the main menu, where
  /// the app may close; everywhere else it steps back one screen.
  bool handleBack() {
    final active = overlays.activeOverlays;
    final covered = creditsVisible.value || introVisible.value;
    // The briefing pops over the hangar too, so it goes before the
    // hangar's "let the app close" check.
    if (!covered && active.contains(OverlayIds.briefing)) {
      AudioService.playUi(UiSound.back);
      closeBriefing();
      return true;
    }
    if (!covered && active.contains(OverlayIds.menu)) return false;
    AudioService.playUi(UiSound.back);
    if (covered) {
      creditsVisible.value = false;
      introVisible.value = false;
    } else if (active.contains(OverlayIds.rankUp)) {
      closeRankUp();
    } else if (active.contains(OverlayIds.settings)) {
      closeSettings();
    } else if (active.contains(OverlayIds.pause)) {
      resumeGame();
    } else if (active.contains(OverlayIds.levelComplete)) {
      leaveResults(() async => backToMenu());
    } else if (active.contains(OverlayIds.gameOver) || active.contains(OverlayIds.demo)) {
      backToMenu();
    } else if (_garageReturn != null && active.contains(OverlayIds.cosmetics)) {
      closeScreen(OverlayIds.cosmetics);
    } else if (OverlayIds.subScreens
        .any(active.contains)) {
      overlays.removeAll(OverlayIds.subScreens);
      overlays.add(OverlayIds.menu);
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
    overlays.add(OverlayIds.pause);
  }

  void resumeGame() {
    if (!isPaused) return;
    isPaused = false;
    overlays.removeAll([OverlayIds.pause, OverlayIds.settings]);
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
      MonetizationService.instance.refreshIfNeeded();
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
    final s = ship;
    if (s != null && !demoMode) {
      _fuelGauge?.flashCost(s.spec.fuelPerShot * s.fuelDrainMultiplier / s.maxFuel);
    }
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

  /// Most of each weapon held this flight: the FIRE pad's ammo ring is
  /// drawn against it.
  final Map<String, double> _ammoPeak = {};

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
    _levelEntities.add(crate);
    await world.add(crate);
  }

  void _onCrateCollected(SupplyCrate crate) {
    final r = _rack;
    if (r == null) return;
    r.addFound(crate.weapon.id, crate.units);
    Analytics.crateCollected(crate.weapon.id);
    _syncWeaponHud();
    final w = crate.weapon;
    // The plate teaches a weapon once; later pickups just fly the icon in.
    final progress = ProgressService.instance;
    if (!progress.crateHintSeen(w.id)) {
      unawaited(progress.markCrateHintSeen(w.id));
      _crateNotice = CrateNotice(
        kind: w.kind,
        name: w.name,
        label: _weaponLabel(w),
        amount: w.continuous ? '${crate.units.round()} s' : '×${crate.units.round()}',
      );
      _crateNoticeLeft = 2.5;
    }
    final from = camera.localToGlobal(Vector2(crate.pos.dx, crate.pos.dy));
    _coach?.flyIn(Offset(from.x, from.y), w.kind);
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
    if (_scrapeFxCooldown > 0) _scrapeFxCooldown -= dt;
    if (_scrapeSoundCooldown > 0) _scrapeSoundCooldown -= dt;
    if (_rack != null && (s.laserFiring || _rack!.selected?.continuous == true)) {
      _syncWeaponHud();
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
    _shake.floor = 0;
    if (melt != null) {
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

  // ── Update loop ───────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    if (!PerfMonitor.sampling) return super.render(canvas);
    final clock = Stopwatch()..start();
    super.render(canvas);
    PerfMonitor.render.add(clock.elapsedMicroseconds / 1000);
  }

  @override
  void update(double dt) {
    final clock = PerfMonitor.sampling ? (Stopwatch()..start()) : null;
    super.update(dt);
    final logicStart = clock?.elapsedMicroseconds ?? 0;
    _removeShake();
    _updateGame(dt);
    _applyShake(dt);
    if (clock != null) {
      final now = clock.elapsedMicroseconds;
      PerfMonitor.update.add(now / 1000);
      PerfMonitor.logic.add((now - logicStart) / 1000);
    }
  }

  void _updateGame(double dt) {

    if (_crashTimer > 0) {
      _crashTimer -= dt;
      if (_crashTimer <= 0 && runState == RunState.gameOver) {
        pauseEngine();
        overlays.add(OverlayIds.gameOver);
      }
    }

    if (_winTimer > 0) _winTimer -= dt;
    if (_winReady && _winTimer <= 0 && runState == RunState.won) {
      _winReady = false;
      pauseEngine();
      overlays.add(OverlayIds.levelComplete);
    }

    final s = ship;
    // The camera keeps going on the pad, for the delivery push-in.
    final wonWorld = _currentWorldSize;
    if (s != null && runState == RunState.won && wonWorld != null) {
      _followCamera(s, wonWorld, dt);
    }
    if (s != null && runState == RunState.playing) {
      // The clock starts with the first input (the ship waits on its pad).
      if (_timing && s.launched) elapsedSeconds += dt;
      if (thrustHeld) _thrustUsed += dt;
      if (rotateAxis.abs() > 0.3) _rotateUsed += dt;
      if (kPerfProbe) PerfMonitor.lapStart();
      _updateGuidance(s);
      if (kPerfProbe) PerfMonitor.lap('guidance');
      final worldSize = _currentWorldSize;
      if (worldSize != null) _followCamera(s, worldSize, dt);
      if (kPerfProbe) PerfMonitor.lap('camera');

      if (demoMode) {
        _updateDemo(dt, s);
      } else {
        s.towing = cargoAttachment?.attached ?? false;
        if (_keys.rotateAxis != 0) _keyHeld += dt;
        _idleFor = thrustHeld || fireHeld || rotateAxis != 0 ? 0 : _idleFor + dt;
        _boostCharge = FlightTuning.nextBoostCharge(_boostCharge, _touchAxis, dt);
        // Re-shape held input every frame: the key boost ramps with time
        // and the boost shrinks once the pod is hooked.
        if (_touchAxis != 0 || _stickX != 0 || _stickY != 0 || _keys.rotateAxis != 0) {
          _combineInputs();
        }
        s.setInput(rotate: rotateAxis, thrust: thrustHeld, fire: fireHeld);
        _updateCountdown(dt, s);
        if (routeGuideOn && s.launched) guidedThisRun = true;
      }
      if (kPerfProbe) PerfMonitor.lap('input');
      _updateRockWarning(s, dt);
      if (kPerfProbe) PerfMonitor.lap('rock');
      AudioService.updateEngine(thrusting: s.isThrusting, dt: dt);
      AudioService.setAlarm(_meltdownLeft != null);
      if (kPerfProbe) PerfMonitor.lap('audio');
      _updateCombat(dt);
      _updateWeapons(dt, s);
      if (kPerfProbe) PerfMonitor.lap('weapons');
      _interceptShells();
      if (kPerfProbe) PerfMonitor.lap('intercept');
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

/// A level load overtaken by another load or a return to the menu; it
/// stops quietly (see [NarrowHaulGame._checkLoad]).
class _LoadSuperseded implements Exception {
  const _LoadSuperseded();
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
