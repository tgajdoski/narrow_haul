import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

// Ship look: world-fixed hull lighting, bank, RCS puffs, nav lights and
// engine heat. Visual only; nothing here touches the body or its fixtures.

// ─────────────────────────────────────────────────────────────────────────────
// Normal map
// ─────────────────────────────────────────────────────────────────────────────

/// Bakes a normal map from a ship sprite ([rgba] straight alpha, [w]×[h]).
///
/// The hull is a soft bevelled slab (height rises over [bevelPx] from the
/// silhouette) on a low dome (over [domePx]), so whole faces turn toward or
/// away from the light; the art's dark outline and panel lines are cut in as
/// grooves, and brighter paint is embossed a little. Returns premultiplied
/// RGBA (normal encoded as `n * 0.5 + 0.5`, alpha = the sprite's), ready for
/// [ui.decodeImageFromPixels].
Uint8List bakeHullNormals(
  Uint8List rgba,
  int w,
  int h, {
  double bevelPx = 12,
  double bevelHeight = 7,
  double domePx = 48,
  double domeHeight = 14,
  double grooveDepth = 1.6,
  double emboss = 0.8,
}) {
  final n = w * h;
  final inside = Uint8List(n);
  for (var i = 0; i < n; i++) {
    inside[i] = rgba[i * 4 + 3] >= 128 ? 1 : 0;
  }

  // Chamfer (3-4) distance to the nearest outside pixel, two passes.
  const big = 1 << 28;
  final d = Int32List(n);
  for (var i = 0; i < n; i++) {
    d[i] = inside[i] == 1 ? big : 0;
  }
  int at(int x, int y) =>
      (x < 0 || y < 0 || x >= w || y >= h) ? 0 : d[y * w + x];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (d[i] == 0) continue;
      var v = d[i];
      v = math.min(v, at(x - 1, y) + 3);
      v = math.min(v, at(x, y - 1) + 3);
      v = math.min(v, at(x - 1, y - 1) + 4);
      v = math.min(v, at(x + 1, y - 1) + 4);
      d[i] = v;
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      if (d[i] == 0) continue;
      var v = d[i];
      v = math.min(v, at(x + 1, y) + 3);
      v = math.min(v, at(x, y + 1) + 3);
      v = math.min(v, at(x + 1, y + 1) + 4);
      v = math.min(v, at(x - 1, y + 1) + 4);
      d[i] = v;
    }
  }

  // Height: a quarter-round bevel, minus grooves on dark lines, plus emboss.
  var hf = Float32List(n);
  for (var i = 0; i < n; i++) {
    if (inside[i] == 0) continue;
    final t = math.min(d[i] / 3.0 / bevelPx, 1.0);
    final s = 1 - t;
    final td = 1 - math.min(d[i] / 3.0 / domePx, 1.0);
    var v = bevelHeight * math.sqrt(1 - s * s) + domeHeight * math.sqrt(1 - td * td);
    final lum = (0.3 * rgba[i * 4] + 0.59 * rgba[i * 4 + 1] + 0.11 * rgba[i * 4 + 2]) / 255;
    final groove = ((0.32 - lum) / 0.17).clamp(0.0, 1.0);
    v += emboss * lum - grooveDepth * groove;
    hf[i] = v;
  }

  // Two 3×3 box blurs soften the steps.
  for (var pass = 0; pass < 2; pass++) {
    final out = Float32List(n);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = (y + dy).clamp(0, h - 1);
          for (var dx = -1; dx <= 1; dx++) {
            sum += hf[yy * w + (x + dx).clamp(0, w - 1)];
          }
        }
        out[y * w + x] = sum / 9;
      }
    }
    hf = out;
  }

  final px = Uint8List(n * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final a = rgba[i * 4 + 3];
      if (a == 0) continue;
      final gx = (hf[y * w + math.min(x + 1, w - 1)] - hf[y * w + math.max(x - 1, 0)]) * 0.5;
      final gy = (hf[math.min(y + 1, h - 1) * w + x] - hf[math.max(y - 1, 0) * w + x]) * 0.5;
      final len = math.sqrt(gx * gx + gy * gy + 1);
      final k = a / 255;
      px[i * 4] = ((-gx / len * 0.5 + 0.5) * 255 * k).round();
      px[i * 4 + 1] = ((-gy / len * 0.5 + 0.5) * 255 * k).round();
      px[i * 4 + 2] = ((1 / len * 0.5 + 0.5) * 255 * k).round();
      px[i * 4 + 3] = a;
    }
  }
  return px;
}

Uint8List _bakeEntry((Uint8List, int, int) a) => bakeHullNormals(a.$1, a.$2, a.$3);

final Map<String, Future<ui.Image?>> _normalCache = {};

/// The baked normal map for [sprite] (once per sprite, off the UI isolate).
/// Null if anything fails: the ship is then drawn flat, as before.
Future<ui.Image?> hullNormalMap(String key, ui.Image sprite) =>
    _normalCache[key] ??= _bake(sprite);

Future<ui.Image?> _bake(ui.Image sprite) async {
  try {
    final data = await sprite.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) return null;
    final w = sprite.width, h = sprite.height;
    final px = await compute(_bakeEntry, (data.buffer.asUint8List(), w, h));
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
    return await done.future;
  } catch (_) {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lighting
// ─────────────────────────────────────────────────────────────────────────────

/// A colour matrix that turns a normal map pixel into
/// `tint × clamp(k·(n·dir) + b)`, with `n = 2c − 1`. The light is linear in
/// the normal, so a plain [ColorFilter.matrix] lights the hull.
List<double> normalLightMatrix(
  double dx,
  double dy,
  double dz, {
  required double k,
  required double b,
  Color tint = Colors.white,
}) {
  final off = 255 * (b - k * (dx + dy + dz));
  List<double> row(double t) => [2 * k * dx * t, 2 * k * dy * t, 2 * k * dz * t, 0, off * t];
  return [
    ...row(tint.r),
    ...row(tint.g),
    ...row(tint.b),
    0, 0, 0, 1, 0,
  ];
}

/// World-fixed light rig, rotated into the ship's frame each frame.
class HullLighting {
  /// Key light: from above-left of the screen, toward the viewer.
  static final Vector3 key = Vector3(-0.5, -0.75, 0.45)..normalize();

  /// Glint: the key light at a grazing angle, so only bevels facing it shine.
  static final Vector3 glint = Vector3(-0.55, -0.8, 0.22)..normalize();

  /// Rim: cave glow from below-right, grazing.
  static final Vector3 rim = Vector3(0.45, 0.88, 0.06)..normalize();

  /// Roll for a full bank (rad).
  static const double maxRoll = 0.55;

  /// [world] in the ship's frame: undo the body [angle] (y down, so a
  /// positive angle turns clockwise), then roll by [bank] about the hull's
  /// long axis (a positive bank dips the right side away from the viewer).
  static Vector3 toLocal(Vector3 world, double angle, double bank) {
    final c = math.cos(angle), s = math.sin(angle);
    final lx = world.x * c + world.y * s;
    final ly = -world.x * s + world.y * c;
    final phi = bank * maxRoll;
    final cp = math.cos(phi), sp = math.sin(phi);
    return Vector3(lx * cp - world.z * sp, ly, lx * sp + world.z * cp);
  }

  final Paint shade = Paint()..blendMode = BlendMode.multiply;
  final Paint gloss = Paint()
    ..blendMode = BlendMode.plus
    ..color = const Color(0x8CFFFFFF);
  final Paint rimPaint = Paint()..blendMode = BlendMode.plus;

  Color rimColor = const Color(0xFFBFE6FF);

  /// Sets the three filters for the ship at [angle] with [bank].
  void aim(double angle, double bank, {double rimStrength = 0.55}) {
    final kl = toLocal(key, angle, bank);
    shade.colorFilter = ColorFilter.matrix(normalLightMatrix(kl.x, kl.y, kl.z, k: 0.5, b: 0.66));
    final gl = toLocal(glint, angle, bank);
    gloss.colorFilter = ColorFilter.matrix(normalLightMatrix(
      gl.x, gl.y, gl.z,
      k: 2.4, b: -1.25, tint: const Color(0xFFFFF4E0),
    ));
    final rl = toLocal(rim, angle, bank);
    rimPaint
      ..color = Color.fromRGBO(255, 255, 255, rimStrength)
      ..colorFilter = ColorFilter.matrix(normalLightMatrix(rl.x, rl.y, rl.z, k: 2.6, b: -0.95, tint: rimColor));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Motion state
// ─────────────────────────────────────────────────────────────────────────────

/// Pure per-frame look state: bank, engine envelope, RCS demand.
class ShipLook {
  /// −1…1, eased: positive while turning clockwise.
  double bank = 0;

  /// Eased engine output 0…1 (fast attack, soft release).
  double thrust = 0;

  /// Nozzle heat 0…1: builds over a burn, lingers after it.
  double heat = 0;

  /// 1 on the frame a burn starts, decays fast.
  double kick = 0;

  /// Smoothed angular acceleration (rad/s²); its sign picks the RCS side.
  double angAccel = 0;

  double _w = 0;
  bool _wasThrusting = false;
  double _puffBudget = 0;

  static double _ease(double from, double to, double dt, double tau) =>
      from + (to - from) * (1 - math.exp(-dt / tau));

  /// Advances by [dt]; [angularVelocity] in rad/s, [turnRate] at full stick.
  /// Returns how many RCS puff pairs to emit this frame.
  int update(double dt, {
    required double angularVelocity,
    required double turnRate,
    required bool thrusting,
  }) {
    if (dt <= 0) return 0;
    final target = turnRate > 0 ? (angularVelocity / (turnRate * 1.3)).clamp(-1.0, 1.0) : 0.0;
    bank = _ease(bank, target, dt, 0.15);

    final prevW = _w;
    _w = _ease(_w, angularVelocity, dt, 0.05);
    angAccel = _ease(angAccel, (_w - prevW) / dt, dt, 0.06);

    thrust = _ease(thrust, thrusting ? 1 : 0, dt, thrusting ? 0.04 : 0.12);
    heat = _ease(heat, thrusting ? 1 : 0, dt, thrusting ? 0.5 : 0.7);
    if (thrusting && !_wasThrusting) kick = 1;
    _wasThrusting = thrusting;
    kick = _ease(kick, 0, dt, 0.08);

    final intensity = turnRate > 0 ? (angAccel.abs() / (turnRate * 3)).clamp(0.0, 1.0) : 0.0;
    if (intensity < 0.08) {
      _puffBudget = 0;
      return 0;
    }
    _puffBudget += intensity * 28 * dt;
    final count = _puffBudget.floor();
    _puffBudget -= count;
    return count;
  }
}

/// Where the lights and thrusters sit on a hull (body space, m).
class HullPoints {
  HullPoints._(this.wingTip, this.noseSide, this.spine);

  /// Right wing tip (mirror for the left).
  final Offset wingTip;

  /// Widest point near the nose, right side (mirror for the left).
  final Offset noseSide;

  /// On the hull's centre line, mid-body: the beacon.
  final Offset spine;

  factory HullPoints.of(ShipSpec spec) {
    var tip = Offset.zero;
    var noseY = double.infinity;
    for (final poly in spec.hullPolygons) {
      for (final (x, y) in poly) {
        if (x.abs() > tip.dx) tip = Offset(x.abs(), y);
        noseY = math.min(noseY, y);
      }
    }
    final band = noseY + (spec.rearLocalY - noseY) * 0.3;
    var nw = 0.0;
    for (final poly in spec.hullPolygons) {
      for (final (x, y) in poly) {
        if (y <= band) nw = math.max(nw, x.abs());
      }
    }
    // A little inside the outline, so the lights sit on the hull.
    final inset = 0.05 * spec.hullScale;
    return HullPoints._(
      Offset(tip.dx - inset, tip.dy),
      Offset(math.max(nw - inset * 0.5, 0.02), band),
      Offset(0, noseY + (spec.rearLocalY - noseY) * 0.55),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RCS puffs
// ─────────────────────────────────────────────────────────────────────────────

/// Attitude-thruster puffs: short-lived, kept in world space (they don't
/// swing with the hull), drawn in the ship's frame.
class RcsPuffs {
  static const int _max = 16;
  static const double _life = 0.28;

  final Float64List _x = Float64List(_max);
  final Float64List _y = Float64List(_max);
  final Float64List _vx = Float64List(_max);
  final Float64List _vy = Float64List(_max);
  final Float64List _age = Float64List(_max)..fillRange(0, _max, _life);
  int _next = 0;
  final Paint _paint = Paint();

  void emit(Vector2 pos, Vector2 vel) {
    final i = _next;
    _next = (_next + 1) % _max;
    _x[i] = pos.x;
    _y[i] = pos.y;
    _vx[i] = vel.x;
    _vy[i] = vel.y;
    _age[i] = 0;
  }

  void update(double dt) {
    for (var i = 0; i < _max; i++) {
      if (_age[i] >= _life) continue;
      _age[i] += dt;
      _x[i] += _vx[i] * dt;
      _y[i] += _vy[i] * dt;
      final drag = 1 - 4 * dt;
      _vx[i] *= drag;
      _vy[i] *= drag;
    }
  }

  void render(Canvas canvas, Body body, double scale) {
    final p = Vector2.zero();
    for (var i = 0; i < _max; i++) {
      final age = _age[i];
      if (age >= _life) continue;
      final t = age / _life;
      p.setValues(_x[i], _y[i]);
      final l = body.localPoint(p);
      final fade = (1 - t) * (1 - t);
      _paint.color = Color.fromRGBO(225, 236, 245, 0.6 * fade);
      canvas.drawCircle(Offset(l.x, l.y), (0.03 + 0.12 * t) * scale, _paint);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav lights & engine heat
// ─────────────────────────────────────────────────────────────────────────────

/// Red/green wing-tip lights with a white double strobe, and a slow red
/// beacon on the spine.
class NavLights {
  final Paint _core = Paint();
  final Paint _halo = Paint()..blendMode = BlendMode.plus;

  static const _red = Color(0xFFFF3B3B);
  static const _green = Color(0xFF39FF7A);
  static const _white = Color(0xFFFFFFFF);

  /// The strobe's two flashes in each 1.4 s cycle (0 when dark).
  static double strobe(double time) {
    final t = time % 1.4;
    if (t < 0.05) return 1;
    if (t > 0.16 && t < 0.21) return 1;
    return 0;
  }

  void render(Canvas canvas, HullPoints pts, double time, double scale) {
    final tip = pts.wingTip;
    final flash = strobe(time);
    _light(canvas, Offset(-tip.dx, tip.dy), flash > 0 ? _white : _red, scale, flash > 0 ? 1.0 : 0.7);
    _light(canvas, tip, flash > 0 ? _white : _green, scale, flash > 0 ? 1.0 : 0.7);
    final beacon = 0.5 + 0.5 * math.sin(time * 4.2);
    if (beacon > 0.55) {
      _light(canvas, pts.spine, _red, scale * 0.8, (beacon - 0.55) / 0.45 * 0.8);
    }
  }

  void _light(Canvas canvas, Offset at, Color c, double scale, double strength) {
    _halo.color = c.withValues(alpha: 0.32 * strength);
    canvas.drawCircle(at, 0.11 * scale, _halo);
    _core.color = Color.lerp(c, _white, 0.55)!.withValues(alpha: math.min(1, 0.4 + strength));
    canvas.drawCircle(at, 0.026 * scale, _core);
  }
}

/// Warm additive glow round the nozzle while it's hot.
class EngineHeat {
  final Paint _paint = Paint()
    ..blendMode = BlendMode.plus
    ..shader = ui.Gradient.radial(
      Offset.zero,
      1,
      const [Color(0xFFFFC27A), Color(0x66FF6A1F), Color(0x00FF4A10)],
      const [0, 0.45, 1],
    );

  void render(Canvas canvas, double nozzleY, double heat, double scale) {
    if (heat < 0.02) return;
    _paint.color = Color.fromRGBO(255, 255, 255, (0.55 * heat).clamp(0.0, 1.0));
    canvas
      ..save()
      ..translate(0, nozzleY - 0.04 * scale)
      ..scale(0.42 * scale, 0.32 * scale)
      ..drawCircle(Offset.zero, 1, _paint)
      ..restore();
  }
}
