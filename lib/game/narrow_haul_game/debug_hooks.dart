part of '../narrow_haul_game.dart';

/// Test hooks (`@visibleForTesting`).
extension GameDebugHooks on NarrowHaulGame {
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
  double get debugCloseUp => _cam.closeUp.factor;

  /// Tests: the coach mark on a control this frame.
  @visibleForTesting
  CoachMark? get debugCoachMark => _coach?.mark;

  /// Tests: the crate notice currently on air.
  @visibleForTesting
  CrateNotice? get debugCrateNotice => _crateNotice;

  /// Tests: as if [crate] had just been flown through.
  @visibleForTesting
  void debugCollectCrate(SupplyCrate crate) => _onCrateCollected(crate);

  /// Tests: lands the run as if ship and pod had touched down.
  @visibleForTesting
  Future<void> debugDeliver() => _onGoalReached();

  @visibleForTesting
  int debugStars(double fuelFraction, double timeSeconds) =>
      _calculateStars(fuelFraction * _shipMaxFuel, timeSeconds);

  /// Tests: as if [cache] had just been flown through.
  @visibleForTesting
  void debugCollectSalvage(SalvageCache cache) => _onSalvageCollected(cache);

  /// Tests: applies [spec] at once (no roulette).
  @visibleForTesting
  void debugApplySalvage(SalvageSpec spec) => _applySalvage(spec);

  /// Tests: coins Lucky Salvage will pay on delivery.
  @visibleForTesting
  int get debugLuckyCoins => _luckyCoins;
}
