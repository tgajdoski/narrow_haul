import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show FragmentProgram;
import 'dart:math' as math;

import 'package:flame/components.dart';
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
import 'package:narrow_haul/game/camera/camera_rig.dart';
import 'package:narrow_haul/game/components/rock_proximity.dart';
import 'package:narrow_haul/game/components/salvage_fx.dart';
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
import 'package:narrow_haul/game/story/story.dart';
import 'package:narrow_haul/game/route/crash_streak.dart';
import 'package:narrow_haul/game/route/flight_route.dart';
import 'package:narrow_haul/game/route/route_repository.dart';
import 'package:narrow_haul/game/salvage/salvage.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/error_reporter.dart';
import 'package:narrow_haul/game/services/games_service.dart';
import 'package:narrow_haul/game/services/fleet_service.dart';
import 'package:narrow_haul/game/services/achievement_service.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/music_service.dart';
import 'package:narrow_haul/game/services/daily_challenge.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/haptics.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/motion_input.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/reminder_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/services/system_ui.dart';
import 'package:narrow_haul/game/ship/loadout.dart';
import 'package:narrow_haul/game/ship/fleet.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/ship/tilt_steer.dart';
import 'package:narrow_haul/game/guidance/crash_tip.dart';
import 'package:narrow_haul/game/guidance/flight_drills.dart';
import 'package:narrow_haul/game/guidance/flight_guidance.dart';
import 'package:narrow_haul/game/ship/hull_contact.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/game/ship/weapons.dart';
import 'package:narrow_haul/game/tags.dart';
import 'package:narrow_haul/game/overlay_ids.dart';
import 'package:narrow_haul/game/run/delivery_booker.dart';
import 'package:narrow_haul/game/run/snapshot_buffer.dart';

export 'package:narrow_haul/game/run/delivery_booker.dart' show RunReward, kReactorEscapeCurrency, kReactorEscapeXp;
import 'package:narrow_haul/game/env.dart';
import 'package:narrow_haul/game/components/flight_gauges_hud.dart';
import 'package:narrow_haul/game/components/hud_holo.dart';

part 'narrow_haul_game/input.dart';
part 'narrow_haul_game/level_lifecycle.dart';
part 'narrow_haul_game/camera.dart';
part 'narrow_haul_game/rock_contact.dart';
part 'narrow_haul_game/crash_continue.dart';
part 'narrow_haul_game/expedition_legs.dart';
part 'narrow_haul_game/delivery.dart';
part 'narrow_haul_game/debug_hooks.dart';
part 'narrow_haul_game/route_demo.dart';
part 'narrow_haul_game/navigation.dart';
part 'narrow_haul_game/guidance.dart';
part 'narrow_haul_game/combat.dart';
part 'narrow_haul_game/salvage.dart';

enum RunState { menu, playing, gameOver, won }

/// Test Flight ship options for [level], on a background isolate. Top-level
/// so the closure can't capture the game, which an isolate can't receive.
Future<List<String>> _testFlightShipIds(int level) => Isolate.run(
      () => [for (final s in LevelRegistry.testFlightOptions(level)) s.id],
    );

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

  /// Tilt steering (Settings → Tilt steering): the phone's lean, added to
  /// the stick and keys. Sensors run only while a tilt flight is live.
  final MotionInput _motion = MotionInput();

  /// Seconds the phone has been lying too flat to read a lean.
  double _tiltFlatFor = 0;

  /// How long the current turn key has been held (keyboard boost).
  double _keyHeld = 0;
  double _keyDir = 0;
  bool _wasBoosting = false;

  /// How far the stick's fast speed has built up (0…1, see
  /// [FlightTuning.boostBuildUp]).
  double _boostCharge = 0;

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
  /// This level's turrets and fuel canisters (kept when destroyed /
  /// collected; the flags say so), and the shells in flight: read every
  /// frame without scanning the world.
  final List<Turret> _turrets = [];
  final List<FuelCell> _fuelCells = [];
  final List<Shell> _shells = [];
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

  /// Test-only: the radio queue of the current flight.
  @visibleForTesting
  CommsQueue? get debugComms => _comms?.queue;

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

  // ── Mystery salvage (lib/game/salvage/) ─────────────────────────────────
  /// Chance per attempt of a "?" cache on a cave level.
  /// `--dart-define=SALVAGE=always|never|<effect>` overrides it (an effect
  /// name, e.g. `swarmSting`, also forces what's inside).
  static const double kSalvageChance = 0.4;
  static const String _salvageDefine = String.fromEnvironment('SALVAGE');

  /// Test-only: no salvage caches (the autopilot flies a fixed level). Off
  /// by default under `flutter test`, so a random cache never changes a
  /// test's flight; tests that want one switch it on.
  @visibleForTesting
  bool debugNoSalvage = kInFlutterTest;

  /// Source of salvage odds, spots and contents (seedable in tests).
  @visibleForTesting
  math.Random salvageRng = math.Random();

  /// The effect running this flight (one at a time).
  final ActiveSalvage salvage = ActiveSalvage();

  /// The caches on the current level (three on a chaos day; tests).
  List<SalvageCache> get salvageCaches => _salvageCaches;
  SalvageCache? get salvageCache => _salvageCaches.firstOrNull;
  final List<SalvageCache> _salvageCaches = [];
  SalvageHud? _salvageHud;
  SalvageAura? _salvageAura;
  SalvageScreenFx? _salvageFx;

  /// Spore Trip's warp shader (null where shaders aren't available) and
  /// the post process running it.
  static FragmentProgram? _sporeProgram;
  SporePostProcess? _sporePost;

  /// Caches opened this flight, Lucky Salvage coins riding on delivery, and
  /// the Hiccups / Ghost Protocol timers.
  int _salvageOpenedThisRun = 0;
  int _luckyCoins = 0;
  double _hiccupIn = 0;
  double _ghostCheckIn = 0;

  /// Rolled on pickup, applied when the roulette stops.
  SalvageSpec? _salvagePending;
  double _salvageRevealLeft = 0;

  /// Bad luck protection: the last cache (this session) was a curse.
  bool _lastSalvageCurse = false;

  /// Curses taken this flight (a delivery pays a grit bonus).
  final List<SalvageSpec> _cursesThisRun = [];

  /// After an absorbed hit, a bounce back into the rock doesn't count.
  double _hitImmunity = 0;
  double? _salvageLastAngle;

  /// Smoothed hull size (see [_updateSalvage]).
  double _hullK = 1;

  /// This frame's wall-clock step (Chrono scales the rest).
  double _realDt = 0;

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

  /// The countdown reached GO: the clock runs, but the ship keeps hovering
  /// until the first input (a player still reading never drops into rock).
  bool _countdownDone = false;
  static const double _countdownSeconds = 4.0;
  CoachMarkHud? _coach;
  WorldMarkerHud? _markers;
  CommsHud? _comms;
  DualLandingZone? _landingZone;

  // Onboarding: step hints on the first tutorial levels until first clear.
  bool _tutorialHints = false;
  double _thrustUsed = 0;
  double _rotateUsed = 0;

  /// tut_01's flight drills (hover, drift, set down) before the first tow.
  /// Progress survives retries within the app session.
  DrillCourse? _drills;
  String? _drillLevel;
  int _drillStart = 0;
  bool _drillsOver = false;
  bool _hookLogged = false;

  /// Nose pointing down while heading into the rock: the HUD shows the way
  /// back up and TOWER calls it, until a few clean deliveries in a row.
  final NoseDownWatch _noseDown = NoseDownWatch();
  bool _noseDownLesson = false;

  /// Why the last crash happened (the crash screen's advice).
  CrashKind? lastCrashKind;

  @visibleForTesting
  DrillView? get debugDrill => _drills?.view;
  @visibleForTesting
  bool get debugNoseDownWarning => _noseDown.warning;

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
  final SnapshotBuffer _snapshots = SnapshotBuffer();

  /// Restore at least this long before the crash (not the doomed approach).
  static const double _continueRewind = 1.5;
  static const double _continueFuelBonus = 0.25;
  static const double _continueTurretGrace = 3;
  /// A continue hovers on 3 · 2 · 1 · GO first (no intro card, so "3" shows
  /// and beeps on the first frame).
  static const double _resumeCountdownSeconds = 3.05;
  /// The towed pod parked (kinematic) while a continue counts down.
  CargoBody? _podHeldForResume;
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

  // ── Expedition legs (docs/STORY.md §3) ────────────────────────────────────

  /// The leg in flight (0-based; always 0 on a one-haul mission).
  int legIndex = 0;
  int get legCount => currentLevel?.legs.length ?? 1;
  bool get isExpeditionRun => legCount > 1;

  /// The haul in flight: its pod, its pad.
  LegData? get currentLeg {
    final legs = currentLevel?.legs;
    return legs == null || legIndex >= legs.length ? null : legs[legIndex];
  }

  /// Every leg's pod, in leg order (one on a mission).
  final List<CargoBody> _pods = [];

  /// The staging pad to fly on from after a crash: the number of legs
  /// landed this attempt, with the clock and the fuel they landed with.
  int _checkpointLeg = 0;
  double _checkpointElapsed = 0;
  List<double> _checkpointFuel = const [];

  /// Set by [resumeFromPad] for the next load.
  int _resumeLeg = 0;

  /// A staging pad took its leg this step ([_advanceLeg] runs next frame).
  bool _legLanded = false;

  /// Fuel left (tank fraction) at each staging pad this flight.
  final List<double> _legFuelLeft = [];

  /// Flown on from a staging pad after a crash: max 2★.
  bool checkpointUsedThisRun = false;

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
    GamesService.totalStars = LevelRegistry.totalStars;
    GamesService.onSaveMerged = _onCloudSaveMerged;

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
      onTiltTap: recentreTilt,
    );
    _hudControls!.size = camera.viewport.size;
    camera.viewport.add(_hudControls!);

    _pauseButton = PauseButtonHud(onPressed: pauseGame);
    camera.viewport.add(_pauseButton!);
    _levelIntro = LevelIntroHud();
    camera.viewport.add(_levelIntro!);
    _countdownHud = CountdownHud();
    camera.viewport.add(_countdownHud!);
    _markers = WorldMarkerHud()
      ..project = (p) {
        final v = camera.localToGlobal(Vector2(p.dx, p.dy));
        return Offset(v.x, v.y);
      };
    camera.viewport.add(_markers!);
    _coach = CoachMarkHud(controls: _hudControls!);
    camera.viewport.add(_coach!);
    _comms = CommsHud(
      controls: _hudControls!,
      avoid: () => _coach?.plateRect,
      onLine: (line) {
        AudioService.playUi(UiSound.open);
        // Heard once it's on air, so quitting during the level card keeps it.
        final s = ship;
        if (line.id == 'ship' && s != null) {
          unawaited(ProgressService.instance.markShipIntroSeen(s.spec.id));
        }
      },
    );
    camera.viewport.add(_comms!);
    _combatHud = CombatStatusHud();
    camera.viewport.add(_combatHud!);
    _salvageHud = SalvageHud(
      state: salvage,
      onTick: () => AudioService.playUi(UiSound.tap),
    );
    camera.viewport.add(_salvageHud!);
    _salvageFx = SalvageScreenFx();
    camera.viewport.add(_salvageFx!);
    unawaited(_loadSporeShader());
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

  /// Spore Trip's shader; without it the hallucination is the overlay only.
  static Future<void> _loadSporeShader() async {
    if (_sporeProgram != null) return;
    try {
      _sporeProgram = await FragmentProgram.fromAsset('shaders/spore.frag');
    } catch (e) {
      if (kDebugMode) debugPrint('Spore shader unavailable: $e');
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
    _salvageHud?.insets = _safeInsets;
    _markers?.insets = _safeInsets;
    _minimap?.refreshLayout();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _hudControls?.size = camera.viewport.size;
    final worldSize = _currentWorldSize;
    if (worldSize != null) {
      _cam.fitWorld(worldSize);
    }
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  /// Follow, safe frame, close-ups, shake and bounds (`camera/camera_rig.dart`).
  late final CameraRig _cam = CameraRig(camera, world: world)
    ..baseZoom = (() => _baseZoom * _screenScale)
    ..avoidZones = _cameraAvoidZones;

  /// The system asks for reduced motion (set by the app): softer zoom and shake.
  bool get reducedMotion => _cam.reducedMotion;
  set reducedMotion(bool v) => _cam.reducedMotion = v;

  // ── Delivery ─────────────────────────────────────────────────────────────

  /// Tests: runs first in the delivery booking (throw to simulate a failed
  /// save).
  @visibleForTesting
  void Function()? debugBeforeBooking;

  /// Achievements unlocked mid-flight (e.g. Cargo Swinger). Their XP is paid
  /// with the delivery, or straight away if the flight ends in a crash.
  final List<AchievementMeta> _inFlightAchievements = [];

  // ── Monetization hooks ────────────────────────────────────────────────────

  bool _leavingResults = false;

  bool _ammoOffered = false;
  String? _ammoOfferedLevel;

  /// The first Training Grounds missions: a crash rewinds for free, as often
  /// as needed, with no star cap, so learning to fly never costs a restart.
  static const int _freeRetryLevels = 5;

  // ── Comms & story ────────────────────────────────────────────────────────

  /// Opening comms wait for the level card to clear.
  static const double _commsAfterIntro = 2.6;

  /// Situational help that hasn't aired this long after it was due is no
  /// longer worth saying.
  static const double _commsHelpExpiry = 8;

  /// Missions whose story beats played this app session.
  final _storyToldThisSession = <String>{};

  /// The camera tip aired this app session (`_scheduleComms`).
  bool _cameraTipToldThisSession = false;

  /// Whether this flight tells the mission's story (set by `_scheduleComms`).
  bool _storyThisFlight = false;

  // ── Screens ──────────────────────────────────────────────────────────────

  /// The world whose story outro is showing (docs/STORY.md).
  WorldDef? storyOutroWorld;

  /// Where the Garage returns to when opened from a mission briefing.
  ({String under, int level})? _garageReturn;

  /// Tab the Garage opens on next (read once by the overlay; null: news).
  String? garageTab;

  /// Flat indices of every unlocked career level (the daily's candidates;
  /// an Expedition is too long for one).
  static List<int> unlockedLevelIndices() => [
    for (var i = 0; i < LevelRegistry.totalLevels; i++)
      if (!LevelRegistry.isExpedition(i) && LevelRegistry.isLevelUnlocked(i)) i,
  ];

  @override
  void lifecycleStateChange(AppLifecycleState state) {
    // Leaving the app mid-flight opens the pause menu, rather than letting
    // Flame silently auto-resume the flight on return.
    if (state != AppLifecycleState.resumed) {
      pauseGame();
      _flushAmmo();
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(applyImmersiveMode());
      MusicService.onForeground();
      MonetizationService.instance.refreshIfNeeded();
      unawaited(ReminderService.onForeground());
    } else {
      MusicService.onBackground();
      // Leaving: schedule from what was just played.
      if (state == AppLifecycleState.paused) {
        unawaited(ReminderService.reschedule());
        GamesService.appPaused();
      }
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

  @override
  bool get turretsDisabled => _turretsOfflineLeft > 0 || _reactorDestroyed;

  @override
  bool get shipCloaked => salvage.cloaked;

  @override
  bool get shipFlared => salvage.flared;

  @override
  void spawnShell(Shell shell) {
    world.add(shell);
    _levelEntities.add(shell);
    _shells.add(shell);
    if (!shell.fromPlayer) AudioService.playEnemyShot();
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

  // ── Weapons ──────────────────────────────────────────────────────────────

  /// Most of each weapon held this flight: the FIRE pad's ammo ring is
  /// drawn against it.
  final Map<String, double> _ammoPeak = {};

  /// The laser fired last frame (the HUD syncs once more when it stops).
  bool _laserWasFiring = false;

  // ── Mystery salvage ──────────────────────────────────────────────────────

  /// Odds and contents for this flight's caches. A daily is seeded from the
  /// date, so every pilot gets the same gamble.
  math.Random _salvageRoll = math.Random();

  /// Chaos daily: this many caches.
  static const int _chaosCaches = 3;

  @override
  void detonate(Vector2 at, WeaponSpec weapon) => _detonate(at, weapon);

  @override
  void onObstacleDestroyed(Offset at) {
    _burstAt(at);
    AudioService.playBoom();
    Haptics.medium();
    ProgressService.instance.incrementStat(ProgressService.statObstaclesWrecked);
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
    // Chrono (mystery salvage) slows the whole cave; its own clock and the
    // camera shake run in real time.
    _realDt = dt;
    final scaled = dt * salvage.timeScale;
    super.update(scaled);
    final logicStart = clock?.elapsedMicroseconds ?? 0;
    _cam.removeShake();
    if (_legLanded) {
      _legLanded = false;
      if (runState == RunState.playing) _advanceLeg();
    }
    _updateGame(scaled);
    _cam.applyShake(dt, meltdown: _meltdownLeft != null);
    if (clock != null) {
      final now = clock.elapsedMicroseconds;
      PerfMonitor.update.add(now / 1000);
      PerfMonitor.logic.add((now - logicStart) / 1000);
    }
  }

  void _updateGame(double dt) {
    _motion.setActive(
      FlightTuning.tilt && runState == RunState.playing && !isPaused && !demoMode && ship != null,
    );

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
      // The clock starts with the first input or at GO, whichever is first
      // (the ship waits on its pad either way).
      if (_timing && (s.launched || _countdownDone)) elapsedSeconds += dt;
      if (thrustHeld) _thrustUsed += dt;
      if (rotateAxis.abs() > 0.3) _rotateUsed += dt;
      if (!demoMode) {
        _updateDrills(dt, s);
        _updateNoseDown(dt, s);
      }
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
        _cam.idleFor = thrustHeld || fireHeld || rotateAxis != 0 ? 0 : _cam.idleFor + dt;
        _boostCharge = FlightTuning.nextBoostCharge(_boostCharge, _touchAxis, dt);
        // Re-shape held input every frame: the key boost ramps with time
        // and the boost shrinks once the pod is hooked.
        if (_motion.active) _updateTilt(s);
        if (_motion.active ||
            _touchAxis != 0 ||
            _stickX != 0 ||
            _stickY != 0 ||
            _keys.rotateAxis != 0) {
          _combineInputs();
        }
        s.setInput(
          rotate: _wiresCrossed ? -rotateAxis : rotateAxis,
          thrust: thrustHeld,
          fire: fireHeld,
        );
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
      _updateSalvage(_realDt, s);
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
      s.localGravity.setFrom(_forces?.shipGravity ?? world.gravity);
      _gravityHud?.accelG
        ?..setFrom(s.localAccel)
        ..scale(salvage.gravityMul / baseGravityY());
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
