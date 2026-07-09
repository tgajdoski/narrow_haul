import 'dart:math' as math;

/// Const-constructible 2D point for level specs (Vector2 is not const).
class Pt {
  const Pt(this.x, this.y);
  final double x;
  final double y;
}

// ── Splines ────────────────────────────────────────────────────────────────

/// Tessellates a Catmull-Rom spline through [points] with ~[step] meter
/// spacing. Returns the sampled polyline including both endpoints, plus a
/// parallel list of interpolated per-point values from [values] (radii).
(List<Pt>, List<double>) tessellateCatmullRom(
  List<Pt> points,
  List<double> values, {
  double step = 0.25,
}) {
  assert(points.length == values.length);
  if (points.length < 2) return (List.of(points), List.of(values));

  final outPts = <Pt>[points.first];
  final outVals = <double>[values.first];

  for (int i = 0; i < points.length - 1; i++) {
    final p0 = points[math.max(i - 1, 0)];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[math.min(i + 2, points.length - 1)];

    final segLen = _dist(p1, p2);
    final n = math.max((segLen / step).ceil(), 1);
    for (int s = 1; s <= n; s++) {
      final t = s / n;
      outPts.add(_catmullRom(p0, p1, p2, p3, t));
      outVals.add(values[i] + (values[i + 1] - values[i]) * t);
    }
  }
  return (outPts, outVals);
}

Pt _catmullRom(Pt p0, Pt p1, Pt p2, Pt p3, double t) {
  final t2 = t * t;
  final t3 = t2 * t;
  double c(double a, double b, double cc, double d) =>
      0.5 *
      ((2 * b) +
          (-a + cc) * t +
          (2 * a - 5 * b + 4 * cc - d) * t2 +
          (-a + 3 * b - 3 * cc + d) * t3);
  return Pt(c(p0.x, p1.x, p2.x, p3.x), c(p0.y, p1.y, p2.y, p3.y));
}

double _dist(Pt a, Pt b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

// ── Signed distance primitives (negative = open cave, positive = rock) ─────

/// Distance from (px,py) to segment (ax,ay)-(bx,by) minus lerped radius.
double sdCapsule(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
  double ra,
  double rb,
) {
  final abx = bx - ax;
  final aby = by - ay;
  final apx = px - ax;
  final apy = py - ay;
  final abLen2 = abx * abx + aby * aby;
  final t = abLen2 == 0 ? 0.0 : ((apx * abx + apy * aby) / abLen2).clamp(0.0, 1.0);
  final dx = apx - abx * t;
  final dy = apy - aby * t;
  return math.sqrt(dx * dx + dy * dy) - (ra + (rb - ra) * t);
}

/// Approximate ellipse SDF via scaled-space distance (exact on circles).
double sdEllipseApprox(double px, double py, double cx, double cy, double rx, double ry) {
  final dx = (px - cx) / rx;
  final dy = (py - cy) / ry;
  final k = math.sqrt(dx * dx + dy * dy);
  // Gradient magnitude of the scaled field ≈ 1/min(rx,ry); rescale so the
  // result approximates meters.
  return (k - 1) * math.min(rx, ry);
}

/// Polynomial smooth minimum — organic fillets where cave volumes merge.
double smin(double a, double b, double k) {
  final h = (0.5 + 0.5 * (b - a) / k).clamp(0.0, 1.0);
  return b + (a - b) * h - k * h * (1 - h);
}

// ── Deterministic value noise (seeded — levels are FIXED, never random) ────

double _hash2(int x, int y, int seed) {
  int h = seed;
  h = (h ^ (x * 0x27d4eb2d)) & 0x7fffffff;
  h = (h ^ (y * 0x165667b1)) & 0x7fffffff;
  h = (h * 0x2545f491) & 0x7fffffff;
  h ^= h >> 13;
  h = (h * 0x5bd1e995) & 0x7fffffff;
  h ^= h >> 15;
  return (h & 0xffffff) / 0xffffff;
}

double _valueNoise(double x, double y, int seed) {
  final xi = x.floor();
  final yi = y.floor();
  final xf = x - xi;
  final yf = y - yi;
  final u = xf * xf * (3 - 2 * xf);
  final v = yf * yf * (3 - 2 * yf);
  final a = _hash2(xi, yi, seed);
  final b = _hash2(xi + 1, yi, seed);
  final c = _hash2(xi, yi + 1, seed);
  final d = _hash2(xi + 1, yi + 1, seed);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

/// Fractal value noise in [-1, 1], deterministic for a given [seed].
double fbm2(double x, double y, int seed, {int octaves = 3}) {
  double sum = 0;
  double amp = 1;
  double freq = 1;
  double norm = 0;
  for (int o = 0; o < octaves; o++) {
    sum += amp * (_valueNoise(x * freq, y * freq, seed + o * 101) * 2 - 1);
    norm += amp;
    amp *= 0.45;
    freq *= 2.2;
  }
  return sum / norm;
}

double smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

// ── Polyline post-processing ───────────────────────────────────────────────

/// One Chaikin corner-cutting pass on a closed loop.
List<Pt> chaikinClosed(List<Pt> loop) {
  if (loop.length < 3) return loop;
  final out = <Pt>[];
  for (int i = 0; i < loop.length; i++) {
    final a = loop[i];
    final b = loop[(i + 1) % loop.length];
    out.add(Pt(a.x * 0.75 + b.x * 0.25, a.y * 0.75 + b.y * 0.25));
    out.add(Pt(a.x * 0.25 + b.x * 0.75, a.y * 0.25 + b.y * 0.75));
  }
  return out;
}

/// Douglas-Peucker simplification of a closed loop with tolerance [epsilon].
List<Pt> simplifyClosed(List<Pt> loop, double epsilon) {
  if (loop.length < 4) return loop;
  // Treat as open polyline anchored at index 0 and the farthest point from it.
  int far = 1;
  double best = -1;
  for (int i = 1; i < loop.length; i++) {
    final d = _dist(loop[0], loop[i]);
    if (d > best) {
      best = d;
      far = i;
    }
  }
  final part1 = _dpSimplify([...loop.sublist(0, far + 1)], epsilon);
  final part2 = _dpSimplify([...loop.sublist(far), loop[0]], epsilon);
  return [...part1.sublist(0, part1.length - 1), ...part2.sublist(0, part2.length - 1)];
}

List<Pt> _dpSimplify(List<Pt> pts, double epsilon) {
  if (pts.length < 3) return pts;
  double maxD = 0;
  int index = 0;
  final a = pts.first;
  final b = pts.last;
  for (int i = 1; i < pts.length - 1; i++) {
    final d = _perpDist(pts[i], a, b);
    if (d > maxD) {
      maxD = d;
      index = i;
    }
  }
  if (maxD <= epsilon) return [a, b];
  final left = _dpSimplify(pts.sublist(0, index + 1), epsilon);
  final right = _dpSimplify(pts.sublist(index), epsilon);
  return [...left.sublist(0, left.length - 1), ...right];
}

double _perpDist(Pt p, Pt a, Pt b) {
  final abx = b.x - a.x;
  final aby = b.y - a.y;
  final len = math.sqrt(abx * abx + aby * aby);
  if (len == 0) return _dist(p, a);
  return ((p.x - a.x) * aby - (p.y - a.y) * abx).abs() / len;
}

double loopPerimeter(List<Pt> loop) {
  double sum = 0;
  for (int i = 0; i < loop.length; i++) {
    sum += _dist(loop[i], loop[(i + 1) % loop.length]);
  }
  return sum;
}
