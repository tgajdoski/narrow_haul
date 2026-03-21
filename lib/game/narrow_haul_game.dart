import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;
import 'package:flame/text.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
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

enum RunState { menu, playing, gameOver, won }

class NarrowHaulGame extends Forge2DGame {
  NarrowHaulGame()
    : super(
        gravity: Vector2(0, 1.375),
        zoom: 28,
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

  bool rotateLeftHeld = false;
  bool rotateRightHeld = false;
  bool thrustHeld = false;

  final List<Component> _levelEntities = [];

  TextComponent? _hudText;
  HudTouchControls? _hudControls;

  @override
  Color backgroundColor() => const Color(0xFF050816);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewfinder.anchor = Anchor.center;
    camera.viewfinder.zoom = 28;

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
      onRotateLeft: (v) => rotateLeftHeld = v,
      onRotateRight: (v) => rotateRightHeld = v,
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
  }

  Future<void> beginPlay() async {
    overlays.remove('menu');
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
    );

    await world.add(shipBody);
    await world.add(cargoBody);
    await world.add(cargoLink);
    _levelEntities.add(shipBody);
    _levelEntities.add(cargoBody);
    _levelEntities.add(cargoLink);

    ship = shipBody;
    cargo = cargoBody;

    final landing = DualLandingZone(
      padCenter: data.goalCenter,
      halfWidth: data.goalHalfWidth,
      halfHeight: data.goalHalfHeight,
      onBothLanded: _onGoalReached,
    );
    await world.add(landing);
    _levelEntities.add(landing);

    camera.follow(shipBody, maxSpeed: 85, snap: true);
    camera.setBounds(
      Rectangle.fromLTWH(
        0,
        0,
        data.worldSize.x,
        data.worldSize.y,
      ),
      considerViewport: true,
    );
  }

  void _clearLevel() {
    camera.stop();
    for (final c in _levelEntities.reversed) {
      c.removeFromParent();
    }
    _levelEntities.clear();
    ship = null;
    cargo = null;
  }

  void _onShipHitWall() {
    if (runState != RunState.playing) return;
    runState = RunState.gameOver;
    pauseEngine();
    overlays.add('gameOver');
  }

  void _onGoalReached() {
    if (runState != RunState.playing) return;
    runState = RunState.won;
    pauseEngine();
    overlays.add('levelComplete');
  }

  void restartLevel() {
    overlays.remove('gameOver');
    runState = RunState.playing;
    resumeEngine();
    loadCurrentLevel();
  }

  Future<void> nextLevel() async {
    overlays.remove('levelComplete');
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
      var rot = 0.0;
      if (rotateLeftHeld) rot -= 1;
      if (rotateRightHeld) rot += 1;
      s.setInput(rotate: rot, thrust: thrustHeld);
      _hudText?.text =
          'Level ${levelIndex + 1}/${levelPaths.length}  '
          'Fuel ${s.fuel.toStringAsFixed(0)}  '
          'Nose hook touches cargo to tow — land both on green';
    }
  }
}
