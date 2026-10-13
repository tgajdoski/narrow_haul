// Difficulty curve: `dart run tool/difficulty_curve.dart`
// Scores how hard each cave mission is to *finish* (course_metrics.dart),
// world by world in play order, and flags breaks in the sawtooth (spikes,
// hard openers, soft finales, worlds easier than the one before). Bot stats
// from build/autopilot_report.json are folded in when present. Writes
// build/difficulty_curve.md. The Training Grounds (TMX) aren't scored.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:narrow_haul/game/level/cave/course_metrics.dart';
import 'package:narrow_haul/game/level/level_def.dart';
import 'package:narrow_haul/game/level/specs/expeditions.dart';
import 'package:narrow_haul/game/level/specs/world_alien.dart';
import 'package:narrow_haul/game/level/specs/world_ice.dart';
import 'package:narrow_haul/game/level/specs/world_lava.dart';
import 'package:narrow_haul/game/level/specs/world_mine.dart';
import 'package:narrow_haul/game/level/specs/world_orbit.dart';
import 'package:narrow_haul/game/level/specs/world_redoubt.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';

void main() {
  final bots = <String, BotStats>{};
  final report = File('build/autopilot_report.json');
  if (report.existsSync()) {
    for (final l in jsonDecode(report.readAsStringSync()) as List) {
      final m = l as Map<String, dynamic>;
      final real = m['real'] as Map<String, dynamic>?;
      bots[m['id'] as String] = (
        profilesOk: m['profilesOk'] as int,
        profiles: (m['profiles'] as List).length,
        heldSeconds: (m['heldSeconds'] as num).toDouble(),
        exposedSeconds: (real?['exposedSeconds'] as num?)?.toDouble() ?? 0,
      );
    }
  } else {
    print('(no build/autopilot_report.json: scoring without bot stats)');
  }

  final worlds = [
    ('Alien', alienLevels, alienShipId),
    ('Mine', mineLevels, mineShipId),
    ('Ice', iceLevels, iceShipId),
    ('Lava', lavaLevels, lavaShipId),
    ('Orbit', orbitLevels, orbitShipId),
    ('Redoubt', redoubtLevels, redoubtShipId),
  ];

  final out = StringBuffer()
    ..writeln('# Difficulty curve')
    ..writeln()
    ..writeln('Completion difficulty 0–100 (how hard to *finish*, not to 3★): squeezes 25, '
        'timing & turrets 25, length & turns 20, physics 20, bot profiles that failed 10. '
        'Type ratings are listed but left out of the curve. '
        '${bots.isEmpty ? 'No bot stats.' : 'Bot stats from build/autopilot_report.json.'}')
    ..writeln();

  final curves = <WorldCurve>[];
  void table(String world, List<LevelDef> levels, String shipId, {bool curve = true}) {
    out
      ..writeln('## $world')
      ..writeln()
      ..writeln('| # | level | score | | squeeze m (tow) | min gap | gates | turrets | field m | length | turns | g | pod |')
      ..writeln('|---|---|---|---|---|---|---|---|---|---|---|---|---|');
    final scored = <(String, double)>[];
    for (final (k, def) in levels.whereType<CaveLevelDef>().indexed) {
      final spec = def.spec;
      final m = measureCourse(spec, ship: shipById(def.shipId ?? shipId));
      if (m == null) {
        out.writeln('| ${k + 1} | ${spec.id} | – | no route | | | | | | | | | |');
        continue;
      }
      final s = completionScore(m, bot: bots[spec.id]);
      final rating = spec.id.startsWith('rating_');
      if (!rating) scored.add((spec.id, s));
      final bar = '█' * (s / 5).round();
      out.writeln('| ${k + 1} | ${rating ? '_${spec.id}_' : spec.id} | ${s.toStringAsFixed(0)} | `$bar` | '
          '${m.squeezeMeters.toStringAsFixed(0)} (${m.towSqueezeMeters.toStringAsFixed(0)}) | '
          '${m.minMargin.toStringAsFixed(2)} | ${m.timingGates} | ${m.turretsOnRoute} | '
          '${m.fieldMeters.toStringAsFixed(0)} | ${m.length.toStringAsFixed(0)} | '
          '${m.turnQuarters.toStringAsFixed(0)} | ${m.gravityMul} | ${m.cargoMul} |');
      print('${spec.id.padRight(13)} ${s.toStringAsFixed(1).padLeft(5)} $bar');
    }
    if (scored.isNotEmpty) {
      final xs = [for (final (_, s) in scored) s];
      out
        ..writeln()
        ..writeln('median ${curveMedian(xs).toStringAsFixed(0)}, peak ${xs.reduce(math.max).toStringAsFixed(0)}. '
            'Sorted: ${([...scored]..sort((a, b) => a.$2.compareTo(b.$2))).map((e) => e.$1).join(' → ')}');
    }
    out.writeln();
    if (curve) curves.add((world: world, levels: scored));
  }

  for (final (name, levels, shipId) in worlds) {
    print('── $name');
    table(name, levels, shipId);
  }
  print('── Expeditions');
  table('Expeditions (post-career, not in the curve)', expeditionLevels, expeditionShipId,
      curve: false);

  final flags = curveFlags(curves);
  out
    ..writeln('## Curve flags')
    ..writeln();
  for (final f in flags) {
    out.writeln('- $f');
  }
  if (flags.isEmpty) out.writeln('None.');
  print('\n${flags.length} curve flag(s):');
  for (final f in flags) {
    print('  - $f');
  }

  Directory('build').createSync(recursive: true);
  File('build/difficulty_curve.md').writeAsStringSync(out.toString());
  print('\nwrote build/difficulty_curve.md');
}
