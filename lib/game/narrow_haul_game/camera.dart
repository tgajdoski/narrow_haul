part of '../narrow_haul_game.dart';

/// Camera follow, safe frame, close-ups, shake and bounds.
extension GameCamera on NarrowHaulGame {
  /// Opens a level on the ship: it holds through the level card, then
  /// eases out over 3 · 2 · 1 to the flight view at GO. Without a countdown
  /// (onboarding) it holds until the first input. Any input releases it.
  void _startCloseUp({required bool retry}) {
    _closeUp.reset();
    if (demoMode || kStoreCapture || FlightTuning.camera.profile.isStatic) return;
    final s = ship;
    if (s == null) return;
    // As in the briefing: a ship's first flight.
    final newShip = !retry && LevelRegistry.isShipNew(s.spec.id);
    var peak = retry ? NarrowHaulGame._closeUpRetry : (newShip ? NarrowHaulGame._closeUpNewShip : NarrowHaulGame._closeUpFirst);
    if (reducedMotion) peak = 1 + (peak - 1) * 0.4;
    final countdown = _countdown;
    _closeUp.intro(
      peak: peak,
      hold: countdown == null ? double.infinity : countdown - 3,
      out: 3,
    );
  }

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
        NarrowHaulGame._baseZoom * _screenScale * FlightTuning.camera.profile.zoomMul,
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
          : s.body.position - Vector2(0, (NarrowHaulGame._closeUpShipY - 0.5) * view.y / zoom);
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
}
