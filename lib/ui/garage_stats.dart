
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/ship/loadout.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// Tow gear stats on a Garage tile: the trade-off line and four bars.
class RopeStatsView extends StatelessWidget {
  const RopeStatsView({super.key, required this.rope, this.compareTo});
  final RopeSpec rope;

  /// The line flown now: each bar shows ▲/▼ against it.
  final RopeSpec? compareTo;

  @override
  Widget build(BuildContext context) {
    final st = RopeStats.of(rope);
    final cmp = compareTo == null || compareTo!.id == rope.id
        ? null
        : RopeStats.of(compareTo!);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rope.blurb,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              StatBar(label: 'REACH', value: st.reach, was: cmp?.reach),
              // Give is a trait, not a strength: shown without a verdict.
              StatBar(label: 'GIVE', value: st.give, was: cmp?.give, neutral: true),
              StatBar(label: 'STEADY', value: st.steadiness, was: cmp?.steadiness),
              StatBar(label: 'FUEL', value: st.economy, was: cmp?.economy),
            ],
          ),
        ],
      ),
    );
  }
}

/// Handling kit stats on a Garage tile: the trade-off line and three bars.
class KitStatsView extends StatelessWidget {
  const KitStatsView({super.key, required this.kit, this.compareTo});
  final KitSpec kit;

  /// The kit fitted now: each bar shows ▲/▼ against it.
  final KitSpec? compareTo;

  @override
  Widget build(BuildContext context) {
    final st = KitStats.of(kit);
    final cmp = compareTo == null || compareTo!.id == kit.id
        ? null
        : KitStats.of(compareTo!);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kit.blurb,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              StatBar(label: 'TURN', value: st.turn, was: cmp?.turn),
              StatBar(label: 'STEADY', value: st.steady, was: cmp?.steady),
              StatBar(label: 'FUEL', value: st.economy, was: cmp?.economy),
            ],
          ),
        ],
      ),
    );
  }
}

/// One Garage stat: label, segmented bar, ▲/▼ against the fitted item.
class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.label,
    required this.value,
    this.was,
    this.neutral = false,
  });
  final String label;
  final double value;

  /// The same stat on the equipped item (null: no comparison).
  final double? was;

  /// More isn't better or worse (rope give): arrow without a colour verdict.
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          // One line always ("STEADY" wrapped at large text sizes).
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 56,
          child: HoloGauge(
            value: value,
            color: const Color(0xFF7DD3C0),
            height: 5,
            segments: 8,
          ),
        ),
        SizedBox(width: 14, child: _delta()),
      ],
    );
  }

  Widget? _delta() {
    final w = was;
    if (w == null) return null;
    final d = value - w;
    if (d.abs() < 0.03) return null;
    final up = d > 0;
    final color = neutral
        ? Colors.white54
        : (up ? const Color(0xFF7DD3C0) : SpaceColors.coral);
    return Text(
      up ? '▲' : '▼',
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 9),
    );
  }
}
