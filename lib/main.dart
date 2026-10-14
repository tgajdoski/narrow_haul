import 'dart:async';

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/perf/perf_monitor.dart';
import 'package:narrow_haul/game/services/error_reporter.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/reminder_service.dart';
import 'package:narrow_haul/game/services/system_ui.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/ship/flight_tuning.dart';
import 'package:narrow_haul/game/services/motion_input.dart';
import 'package:narrow_haul/app/narrow_haul_app.dart';
import 'package:narrow_haul/app/bootstrap.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PerfMonitor.mark('main');
  PerfMonitor.install();
  ErrorReporter.install();
  // Firebase and the save load don't depend on each other: start both.
  final firebase = initFirebase();
  registerLicenses();
  // Point the global Flame image cache at assets/ (not the default assets/images/).
  Flame.images.prefix = 'assets/';
  await ProgressService.init();
  await firebase;
  PerfMonitor.mark('firebase + save');
  FlightTuning.load(
    steerName: ProgressService.instance.steerMode,
    cameraName: ProgressService.instance.cameraMode,
    tiltOn: ProgressService.instance.tiltSteer ?? false,
    tiltSensitivityName: ProgressService.instance.tiltSensitivity,
    tiltModeName: ProgressService.instance.tiltMode,
  );
  // The joystick steers by default; tilt is opt-in in Settings, and only
  // offered where the phone has an accelerometer.
  unawaited(MotionInput.probe().then((ok) {
    if (!ok) FlightTuning.tilt = false;
  }));
  try {
    await CareerService.migrateIfNeeded();
  } catch (e, st) {
    // A failed XP backfill must not keep the game from starting.
    ErrorReporter.report(e, st, context: 'save_v3 migration');
  }
  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]));
  unawaited(applyImmersiveMode());
  final game = NarrowHaulGame();
  PerfMonitor.mark('runApp');
  runApp(NarrowHaulApp(game: game));
  // After runApp: the UMP consent form needs a live UI. Never blocks play.
  // On the first launch it waits for the credits, so the consent form and
  // the iOS tracking prompt don't pop up over the kids' photos.
  startServicesAfterCredits(game);
  // Opt-in return reminders: reschedules from today's state.
  unawaited(ReminderService.init());
}
