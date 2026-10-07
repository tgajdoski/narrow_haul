// Headless driver for the real NarrowHaulGame: loads a level, steps the game
// at a fixed dt and feeds inputs exactly like the touch HUD does.
// ignore_for_file: invalid_use_of_internal_member
import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/route/flight_route.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const double kStepDt = 1 / 60;

/// Inputs for one frame (same seam as `HudTouchControls`).
class BotInput {
  const BotInput({this.rotate = 0, this.thrust = false, this.fire = false});
  final double rotate;
  final bool thrust;
  final bool fire;
  static const idle = BotInput();
}

enum FlightOutcome { delivered, crashed, timedOut }

/// One sample of a flight: ship position, fuel units burned so far
/// (refills don't count) and whether the pod is in tow.
typedef TrackPoint = ({double x, double y, double burned, bool towing});

class FlightResult {
  FlightResult({
    required this.outcome,
    required this.fuelLeft,
    required this.seconds,
    required this.stars,
    this.note = '',
    this.track = const [],
    this.heldSeconds = 0,
    this.exposedSeconds = 0,
    this.kills = 0,
    this.route,
  });

  /// Seconds the ship spent in a live turret's view (after launch).
  final double exposedSeconds;

  /// Turrets (and the reactor) the bot destroyed.
  final int kills;

  /// Trajectory samples (every 0.1 s) for canister placement.
  final List<TrackPoint> track;

  /// Seconds spent holding short of moving obstacles.
  final double heldSeconds;

  /// The game's own recording of a delivered flight (route export).
  final FlightRoute? route;
  final FlightOutcome outcome;

  /// Fraction of the tank left at delivery (stars use this).
  final double fuelLeft;
  final double seconds;
  final int stars;
  final String note;

  double get fuelUsed => 1 - fuelLeft;

  FlightResult copyWith(
          {String? note, List<TrackPoint>? track, double? heldSeconds, double? exposedSeconds, int? kills}) =>
      FlightResult(
        outcome: outcome,
        fuelLeft: fuelLeft,
        seconds: seconds,
        stars: stars,
        note: note ?? this.note,
        track: track ?? this.track,
        heldSeconds: heldSeconds ?? this.heldSeconds,
        exposedSeconds: exposedSeconds ?? this.exposedSeconds,
        kills: kills ?? this.kills,
        route: route,
      );

  @override
  String toString() => '${outcome.name} fuelLeft=${(fuelLeft * 100).toStringAsFixed(1)}% '
      't=${seconds.toStringAsFixed(1)}s ★$stars '
      '${exposedSeconds > 0 ? 'exposed=${exposedSeconds.toStringAsFixed(1)}s ' : ''}'
      '${kills > 0 ? 'kills=$kills ' : ''}$note';
}

Future<void> _yield() => Future<void>.delayed(Duration.zero);

class GameHarness {
  late final NarrowHaulGame game;

  Future<void> boot() async {
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'save_v2': true,
      'save_v3': true,
      'sound_enabled': false,
      'haptics_enabled': false,
    });
    await ProgressService.init();
    game = NarrowHaulGame();
    for (final name in const [
      'menu',
      'levelSelect',
      'achievements',
      'cosmetics',
      'gameOver',
      'levelComplete',
      'rankUp',
      'pilotProfile',
      'pause',
      'settings',
      'demo',
    ]) {
      game.overlays.addEntry(name, (_, _) => const SizedBox());
    }
    game.onGameResize(Vector2(960, 540));
    await game.load();
    game.mount();
    await game.ready();
  }

  /// Loads [index] fresh; obstacles start moving from this moment.
  Future<void> loadLevel(int index, {bool skipHazards = false}) async {
    game.debugSkipHazards = skipHazards;
    game.overlays.removeAll(game.overlays.activeOverlays.toList());
    game.levelIndex = index;
    game.runState = RunState.playing;
    game.thrustHeld = false;
    game.rotateAxis = 0;
    game.fireHeld = false;
    await game.loadCurrentLevel();
    await game.ready();
    for (var i = 0; i < 3; i++) {
      await _yield();
    }
  }

  /// Steps until delivery, crash or [maxSeconds] of game time. [pilot] is
  /// called before every frame with the frame index.
  Future<FlightResult> fly(
    BotInput Function(int frame) pilot, {
    double maxSeconds = 240,
    String Function()? describe,
    bool Function()? abort,
  }) async {
    final maxFrames = (maxSeconds / kStepDt).round();
    for (var frame = 0; frame < maxFrames; frame++) {
      final input = pilot(frame);
      if (abort?.call() ?? false) break;
      game.rotateAxis = input.rotate;
      game.thrustHeld = input.thrust;
      game.fireHeld = input.fire;
      game.update(kStepDt);
      // Rope attach and the win sequence complete in microtasks.
      await _yield();
      if (game.runState == RunState.won) {
        return FlightResult(
          outcome: FlightOutcome.delivered,
          fuelLeft: game.lastLevelFuelFraction,
          seconds: game.lastLevelTimeSeconds,
          stars: game.lastLevelStars,
          route: game.lastFlightRoute,
        );
      }
      if (game.runState == RunState.gameOver) {
        return FlightResult(
          outcome: FlightOutcome.crashed,
          fuelLeft: 0,
          seconds: game.elapsedSeconds,
          stars: 0,
          note: describe?.call() ?? '',
        );
      }
    }
    return FlightResult(
      outcome: FlightOutcome.timedOut,
      fuelLeft: 0,
      seconds: game.elapsedSeconds,
      stars: 0,
      note: describe?.call() ?? '',
    );
  }
}
