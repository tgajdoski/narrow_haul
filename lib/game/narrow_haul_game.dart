import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/text.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/components/cargo_attachment.dart';
import 'package:narrow_haul/game/components/cargo_body.dart';
import 'package:narrow_haul/game/components/dual_landing_zone.dart';
import 'package:narrow_haul/game/components/hud_touch_controls.dart';
import 'package:narrow_haul/game/components/ship_body.dart';
import 'package:narrow_haul/game/components/wall_box.dart';
import 'package:narrow_haul/game/components/world_dromes.dart';
import 'package:narrow_haul/game/level/level_data.dart';
import 'package:narrow_haul/game/level/tiled_level_loader.dart';
import 'package:narrow_haul/game/physics_constants.dart';

enum RunState { menu, playing, gameOver, won }

class NarrowHaulGame extends Forge2DGame {
  static const double _baseZoom = 28;

  NarrowHaulGame()
    : super(
        gravity: narrowHaulGravity(),
        zoom: _baseZoom,
      );

  static const levelPaths = [
    'assets/tiles/level_01.tmx',
    'assets/tiles/level_02.tmx',
    'assets/tiles/level_03.tmx',
  ];

  RunState runState = RunState.menu;
  int levelIndex = 0;

  ShipBody? ship;
  CargoBody? cargo;
  CargoAttachment? cargoAttachment;

  double rotateAxis = 0;
  bool thrustHeld = false;

  final List<Component> _levelEntities = [];

  TextComponent? _hudText;
  HudTouchControls? _hudControls;
  Vector2? _currentWorldSize;

  int _towRotateStallFrames = 0;
  int _towThrustStallFrames = 0;
  double _prevLinSpeed = 0;

  @override
  Color backgroundColor() => const Color(0xFF050816);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.zoom = _baseZoom;

    _hudText = TextComponent(
      text: '',
      position: Vector2(12, 10),
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    camera.viewport.add(_hudText!);

    _hudControls = HudTouchControls(
      onRotateAxis: (v) => rotateAxis = v,
      onThrust: (v) => thrustHeld = v,
    );
    _hudControls!.size = camera.viewport.size;
    camera.viewport.add(_hudControls!);

    overlays.add('menu');
    pauseEngine();
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

  Future<void> beginPlay() async {
    overlays.remove('menu');
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    await loadCurrentLevel();
  }

  Future<void> loadCurrentLevel() async {
    _clearLevel();
    final path = levelPaths[levelIndex];
    final data = await loadLevelFromTmx(path, levelIndex: levelIndex);
    await _spawnLevel(data);
  }

  Future<void> _spawnLevel(LevelData data) async {
    final backdrop = RectangleComponent(
      size: data.worldSize,
      paint: Paint()..color = const Color(0xFF0B132B),
      priority: -2000,
    )..position = Vector2.zero();
    world.add(backdrop);
    _levelEntities.add(backdrop);

    for (final w in data.walls) {
      final box = WallBox(
        wallCenter: w.center,
        halfWidth: w.halfWidth,
        halfHeight: w.halfHeight,
      );
      await world.add(box);
      _levelEntities.add(box);
    }

    final helipad = HelipadVisual(
      center: data.shipSpawn,
      sizeMeters: Vector2(3.4, 2.4),
    );
    await world.add(helipad);
    _levelEntities.add(helipad);

    final landingStrip = LandingStripVisual(
      center: data.goalCenter,
      sizeMeters: Vector2(
        data.goalHalfWidth * 2,
        data.goalHalfHeight * 2,
      ),
    );
    await world.add(landingStrip);
    _levelEntities.add(landingStrip);

    late final CargoAttachment cargoLink;
    final shipBody = ShipBody(
      initialPosition: Vector2.copy(data.shipSpawn),
      onWallHit: _onShipHitWall,
      onHookTouchesCargo: () => cargoLink.onHookCargoTouch(),
    );
    final cargoBody = CargoBody(
      initialPosition: Vector2.copy(data.cargoSpawn),
    );
    cargoLink = CargoAttachment(
      ship: shipBody,
      cargo: cargoBody,
      ropeMaxLengthMeters: data.ropeMaxLength,
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

    final landing = DualLandingZone(
      padCenter: data.goalCenter,
      halfWidth: data.goalHalfWidth,
      halfHeight: data.goalHalfHeight,
      onBothLanded: _onGoalReached,
    );
    await world.add(landing);
    _levelEntities.add(landing);

    _currentWorldSize = data.worldSize;
    _applyContainedCamera(data.worldSize);
    _applyCameraBounds(data.worldSize);
    camera.stop();
    _snapCameraToShip();
  }

  void _applyContainedCamera(Vector2 worldSize) {
    final viewportSize = camera.viewport.size;
    if (viewportSize.x <= 0 || viewportSize.y <= 0) {
      return;
    }
    // Keep normal gameplay zoom, only zoom in when required to avoid world bleed.
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
    camera.viewfinder.position = _clampedCameraTarget(s.body.position, worldSize);
  }

  Vector2 _clampedCameraTarget(Vector2 desired, Vector2 worldSize) {
    final viewportSize = camera.viewport.size;
    final zoom = camera.viewfinder.zoom;
    if (viewportSize.x <= 0 || viewportSize.y <= 0 || zoom <= 0) {
      return desired;
    }

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

  void _clearLevel() {
    camera.stop();
    for (final c in _levelEntities.reversed) {
      c.removeFromParent();
    }
    _levelEntities.clear();
    ship = null;
    cargo = null;
    cargoAttachment = null;
    _currentWorldSize = null;
    _resetInputState();
  }

  void _resetInputState() {
    rotateAxis = 0;
    thrustHeld = false;
  }

  void _onShipHitWall() {
    if (runState != RunState.playing) return;
    _resetInputState();
    runState = RunState.gameOver;
    pauseEngine();
    overlays.add('gameOver');
  }

  void _onGoalReached() {
    if (runState != RunState.playing) return;
    _resetInputState();
    runState = RunState.won;
    pauseEngine();
    overlays.add('levelComplete');
  }

  void restartLevel() {
    overlays.remove('gameOver');
    _resetInputState();
    runState = RunState.playing;
    resumeEngine();
    loadCurrentLevel();
  }

  Future<void> nextLevel() async {
    overlays.remove('levelComplete');
    _resetInputState();
    if (levelIndex < levelPaths.length - 1) {
      levelIndex++;
    } else {
      levelIndex = 0;
    }
    runState = RunState.playing;
    resumeEngine();
    await loadCurrentLevel();
  }

  void backToMenu() {
    overlays.remove('gameOver');
    overlays.remove('levelComplete');
    _resetInputState();
    _clearLevel();
    runState = RunState.menu;
    pauseEngine();
    overlays.add('menu');
  }

  @override
  void update(double dt) {
    super.update(dt);
    final s = ship;
    if (s != null && runState == RunState.playing) {
      final worldSize = _currentWorldSize;
      if (worldSize != null) {
        final target = _clampedCameraTarget(s.body.position, worldSize);
        final current = camera.viewfinder.position;
        camera.viewfinder.position = current + (target - current) * 0.18;
      }

      final rot = rotateAxis;
      s.setInput(rotate: rot, thrust: thrustHeld);
      final tow = cargoAttachment?.attached == true;

      if (kDebugMode && tow) {
        final wTarget = rot.abs() * ShipBody.rotationSpeedRadPerSec;
        if (rot.abs() > 0.01 && s.body.angularVelocity.abs() < wTarget * 0.2) {
          _towRotateStallFrames++;
        } else {
          _towRotateStallFrames = 0;
        }
        final lin = s.body.linearVelocity.length;
        if (thrustHeld && s.fuel > 0) {
          if ((lin - _prevLinSpeed).abs() < 0.004 && lin < 0.35) {
            _towThrustStallFrames++;
          } else {
            _towThrustStallFrames = 0;
          }
        } else {
          _towThrustStallFrames = 0;
        }
        _prevLinSpeed = lin;
      } else {
        _towRotateStallFrames = 0;
        _towThrustStallFrames = 0;
        _prevLinSpeed = s.body.linearVelocity.length;
      }

      final dbg = kDebugMode && tow
          ? '${_towRotateStallFrames > 22 ? ' rot?' : ''}'
                '${_towThrustStallFrames > 40 ? ' thrust?' : ''}'
          : '';

      _hudText?.text = tow
          ? 'Level ${levelIndex + 1}/${levelPaths.length}  '
                'Fuel ${s.fuel.toStringAsFixed(0)}  '
                'TOWING — RopeJoint — land ship + cargo on green$dbg'
          : 'Level ${levelIndex + 1}/${levelPaths.length}  '
                'Fuel ${s.fuel.toStringAsFixed(0)}  '
                'Approach: faded line = range hint only — get close to engage tow';
    }
  }
}
