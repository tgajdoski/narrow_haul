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

  // ── Player zoom (pinch, mouse wheel, + / −) ──────────────────────────────

  /// Zooming works while flying (and in a demo), never on menus or pause.
  bool get _canZoom => runState == RunState.playing && !isPaused;

  /// Raw pointers from the app (a `Listener` over the game, so it never
  /// takes a touch away from the controls).
  void zoomPointerDown(int id, Offset at) {
    if (!_canZoom) return;
    final pads = _hudControls?.padsZone;
    final blocked = pads != null &&
        at.dx >= pads.l &&
        at.dx <= pads.r &&
        at.dy >= pads.t &&
        at.dy <= pads.b;
    _pinch.down(id, at, zoom: FlightTuning.cameraZoom, blocked: blocked);
  }

  void zoomPointerMove(int id, Offset at) {
    final z = _pinch.move(id, at);
    if (z == null || !_canZoom) return;
    FlightTuning.cameraZoom = z;
  }

  void zoomPointerUp(int id) {
    if (_pinch.up(id)) _saveZoom();
  }

  /// Mouse wheel / keys: [notches] > 0 zooms in.
  void zoomBy(int notches) {
    if (!_canZoom || notches == 0) return;
    FlightTuning.cameraZoom = PinchZoom.step(FlightTuning.cameraZoom, notches);
    _saveZoom();
  }

  /// Back to the camera mode's own distance.
  void resetZoom() {
    FlightTuning.cameraZoom = 1;
    _saveZoom();
  }

  void _saveZoom() =>
      unawaited(ProgressService.instance.setCameraZoom(FlightTuning.cameraZoom));
}
