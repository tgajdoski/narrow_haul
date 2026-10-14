import 'dart:async';

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/garage_notices.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/ui/career_widgets.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// 'rankUp' overlay, pushed over the results when a run crossed a rank.
class RankUpOverlay extends StatefulWidget {
  const RankUpOverlay({super.key, required this.game});
  final NarrowHaulGame game;

  @override
  State<RankUpOverlay> createState() => _RankUpOverlayState();
}

class _RankUpOverlayState extends State<RankUpOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _close() => widget.game.closeRankUp();

  /// Garage items handed out by every rank this run crossed.
  late final List<CosmeticItem> _unlocks = () {
    final reward = widget.game.lastRunReward;
    if (reward == null) return <CosmeticItem>[];
    return [
      for (var i = reward.rankBefore.index + 1; i <= reward.rankAfter.index; i++)
        ...unlocksAtRank(CosmeticsService.all, i),
    ];
  }();

  @override
  void initState() {
    super.initState();
    // Shown here, so the Garage doesn't flag them NEW again (unfitted gear
    // still says FIT).
    unawaited(GarageNotices.markSeen(_unlocks));
  }

  Future<void> _fit(CosmeticItem item) async {
    await CosmeticsService.equip(item);
    if (mounted) setState(() {});
  }

  Widget _unlockRow(CosmeticItem item) {
    final fitted = CosmeticsService.getSavedEquippedId(item.category) == item.id;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text(item.icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  isGear(item)
                      ? 'Free · new tow gear in your Garage'
                      : 'Free · in your Garage',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          if (fitted)
            HoloChip(
              icon: Icons.check_rounded,
              label: isGear(item) ? 'FITTED' : 'EQUIPPED',
              color: SpaceColors.gold,
            )
          else
            HoloButton(
              label: isGear(item) ? 'Fit now' : 'Use now',
              accent: SpaceColors.gold,
              height: 32,
              fontSize: 11,
              expand: false,
              onPressed: () => _fit(item),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reward = widget.game.lastRunReward;
    if (reward == null) return const SizedBox.shrink();
    final rank = reward.rankAfter;
    final scale = CurvedAnimation(parent: _anim, curve: Curves.elasticOut);
    final next = nextRank(rank);
    final nextItems =
        next == null ? const <CosmeticItem>[] : unlocksAtRank(CosmeticsService.all, next.index);

    return GestureDetector(
      onTap: () {
        AudioService.playUi(UiSound.select);
        _close();
      },
      child: HoloDialog(
        accent: SpaceColors.gold,
        maxWidth: 560,
        scrim: const Color(0xE6050816),
        child: Row(
          children: [
            ScaleTransition(
              scale: scale,
              child: RankBadge(kind: rank.insignia, size: 110),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PROMOTED',
                    style: hudLabel(13, color: SpaceColors.cyan, spacing: 6),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    rank.title.toUpperCase(),
                    style: hudLabel(24, color: SpaceColors.gold, spacing: 3)
                        .copyWith(
                          shadows: const [
                            Shadow(color: Color(0x88FFD166), blurRadius: 16),
                          ],
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    rank.perk,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  if (rankUpBonus(rank) > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Promotion bonus +${rankUpBonus(rank)} 💰',
                      style: const TextStyle(
                        color: SpaceColors.green,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  for (final item in _unlocks) _unlockRow(item),
                  if (next != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Next: ${next.title} at ${next.minXp} XP'
                      '${nextItems.isEmpty ? '' : ' · ${nextItems.map((i) => i.name).join(', ')}'}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                    ),
                  ],
                  const SizedBox(height: 14),
                  HoloButton.primary(
                    label: 'Continue',
                    accent: SpaceColors.gold,
                    height: 44,
                    fontSize: 14,
                    expand: false,
                    onPressed: _close,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
