part of '../narrow_haul_game.dart';

/// Feeds the [CameraRig] from the flight.
extension GameCamera on NarrowHaulGame {
  /// Opens a level on the ship (see [CameraRig.startCloseUp]).
  void _startCloseUp({required bool retry}) {
    final s = ship;
    if (s == null) {
      _cam.closeUp.reset();
      return;
    }
    _cam.startCloseUp(
      retry: retry,
      // As in the briefing: a ship's first flight.
      newShip: !retry && LevelRegistry.isShipNew(s.spec.id),
      countdown: _countdown,
      enabled: !demoMode && !kStoreCapture,
    );
  }

  void _followCamera(ShipBody s, Vector2 worldSize, double dt) {
    final towing = demoMode ? _demoTowing : (cargoAttachment?.attached ?? false);
    final pod = cargo?.body.position;
    _cam.follow(
      CameraFrame(
        ship: s,
        worldSize: worldSize,
        towing: towing,
        pod: pod,
        delivered: runState == RunState.won,
        demo: demoMode,
      ),
      dt,
    );
    // Help text (coach plate, comms line) keeps off the ship and the pod.
    final rects = _cam.shipShield(s, towing ? pod : null);
    _coach?.shield = rects;
    _comms?.shield = rects;
  }

  void _snapCameraToShip() {
    final s = ship;
    final worldSize = _currentWorldSize;
    if (s == null || worldSize == null) return;
    _cam.snapTo(s, worldSize, demo: demoMode);
  }

  /// Screen rects the ship keeps out from under: the touch controls
  /// ([HudTouchControls.controlZones]) and the top-left gauges.
  List<({double l, double t, double r, double b})> _cameraAvoidZones() {
    final hud = _hudControls;
    if (hud == null) return const [];
    final insets = _safeInsets;
    return [
      ...hud.controlZones,
      // Fuel gauge and level info.
      (l: insets.left, t: insets.top, r: insets.left + 240.0, b: insets.top + 96.0),
    ];
  }
}
