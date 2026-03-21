import 'package:forge2d/forge2d.dart';

/// One Forge2D world unit = 1 meter; Tiled maps use [pixelsPerMeter] px = 1 m.
const double pixelsPerMeter = 32;

const int categoryWall = 0x0001;
const int categoryShip = 0x0002;
const int categoryCargo = 0x0004;
const int categoryGoalCargo = 0x0008;
const int categoryGoalShip = 0x0010;
const int categoryHook = 0x0020;
const int categoryRope = 0x0040;

Filter filterWall() => Filter()
  ..categoryBits = categoryWall
  ..maskBits = categoryShip | categoryCargo | categoryRope;

Filter filterShip() => Filter()
  ..categoryBits = categoryShip
  ..maskBits = categoryWall | categoryCargo | categoryGoalShip;

Filter filterCargo() => Filter()
  ..categoryBits = categoryCargo
  ..maskBits = categoryWall | categoryShip | categoryGoalCargo | categoryHook;

Filter filterHook() => Filter()
  ..categoryBits = categoryHook
  ..maskBits = categoryCargo;

/// Rope segment: collides with terrain only (joints link ship & cargo).
Filter filterRope() => Filter()
  ..categoryBits = categoryRope
  ..maskBits = categoryWall;

Filter filterGoalCargo() => Filter()
  ..categoryBits = categoryGoalCargo
  ..maskBits = categoryCargo;

Filter filterGoalShip() => Filter()
  ..categoryBits = categoryGoalShip
  ..maskBits = categoryShip;
