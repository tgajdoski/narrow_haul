import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/loadout.dart';
import 'package:narrow_haul/ui/armory.dart';
import 'package:narrow_haul/ui/space_ui.dart';
import 'package:narrow_haul/ui/store_feedback.dart';

const _garageAccent = SpaceColors.coral;

/// 'cosmetics' overlay — the Garage: liveries, tow gear, plumes and the
/// Armory, behind a segmented cockpit tab bar.
class GarageOverlay extends StatefulWidget {
  const GarageOverlay({super.key, required this.game});

  final NarrowHaulGame game;

  @override
  State<GarageOverlay> createState() => _GarageOverlayState();
}

class _GarageOverlayState extends State<GarageOverlay> {
  /// The weapons tab (not a cosmetics category).
  static const _armory = 'armory';
  String _selectedCategory = CosmeticsService.catShip;

  static const _tabs = [
    (CosmeticsService.catShip, 'Liveries', Icons.rocket_rounded),
    (CosmeticsService.catRope, 'Tow gear', Icons.link_rounded),
    (CosmeticsService.catPlume, 'Plumes', Icons.local_fire_department_outlined),
    (_armory, 'Armory', Icons.gps_fixed_rounded),
  ];

  Future<void> _onItemTap(
    CosmeticItem item,
    bool unlocked,
    bool equipped,
  ) async {
    if (equipped) return;
    if (unlocked) {
      await CosmeticsService.equip(item);
      if (mounted) setState(() {});
    } else if (item.supporterOnly) {
      final bought = await buyWithFeedback(context, ProductIds.supporterPack);
      if (bought) {
        await CosmeticsService.equip(item);
        if (mounted) setState(() {});
      }
    } else {
      final success = await CosmeticsService.unlock(item);
      if (success) {
        await CosmeticsService.equip(item);
        if (mounted) setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ProgressService.instance.getCosmeticCurrency();
    final items = CosmeticsService.all
        .where((e) => e.category == _selectedCategory)
        .toList();

    return SpaceScreen(
      title: 'Garage',
      accent: _garageAccent,
      onBack: () => widget.game.closeScreen('cosmetics'),
      trailing: [
        HoloChip(
          leading: const Text('💰', style: TextStyle(fontSize: 12)),
          label: '$currency',
          color: SpaceColors.green,
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                for (final (id, label, icon) in _tabs) ...[
                  Expanded(
                    child: _SegmentTab(
                      label: label,
                      icon: icon,
                      selected: _selectedCategory == id,
                      onTap: () => setState(() => _selectedCategory = id),
                    ),
                  ),
                  if (id != _armory) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Expanded(
            child: _selectedCategory == _armory
                ? ArmoryList(onCoinsChanged: () => setState(() {}))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final unlocked = CosmeticsService.isUnlocked(item);
                      final equipped =
                          CosmeticsService.getSavedEquippedId(item.category) ==
                          item.id;
                      final trying =
                          CosmeticsService.trialOverride[item.category] ==
                          item.id;
                      final rankLocked = CosmeticsService.isRankLocked(item);
                      final affordable = item.cost <= currency;
                      // Coin items can be test-flown for one level via an ad.
                      final canTry =
                          !unlocked &&
                          !trying &&
                          !item.supporterOnly &&
                          !rankLocked;
                      return CosmeticTile(
                        item: item,
                        unlocked: unlocked,
                        equipped: equipped,
                        trying: trying,
                        locked:
                            !unlocked &&
                            !item.supporterOnly &&
                            (rankLocked || !affordable),
                        tryButton: canTry
                            ? _TryButton(
                                onReward: () => setState(
                                  () => CosmeticsService.startTrial(item),
                                ),
                              )
                            : null,
                        onTap: () => _onItemTap(item, unlocked, equipped),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _garageAccent : Colors.white54;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (selected) return;
        AudioService.playUi(UiSound.select);
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 34,
        decoration: ShapeDecoration(
          color: selected
              ? _garageAccent.withValues(alpha: 0.2)
              : const Color(0x880B1626),
          shape: ChamferBorder(cut: 9),
          shadows: selected
              ? [
                  BoxShadow(
                    color: _garageAccent.withValues(alpha: 0.35),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        foregroundDecoration: ShapeDecoration(
          shape: _OutlinedChamfer(
            color: selected ? _garageAccent : Colors.white12,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Text(label.toUpperCase(), style: hudLabel(11.5, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlinedChamfer extends ChamferBorder {
  const _OutlinedChamfer({required this.color}) : super(cut: 9);
  final Color color;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawPath(
      chamferPath(rect.deflate(0.6), cut),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }
}

/// Garage "Try" chip: a rewarded ad lends the item for the next level.
class _TryButton extends StatelessWidget {
  const _TryButton({required this.onReward});
  final VoidCallback onReward;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MonetizationService.instance.rewardedReady,
      builder: (context, ready, _) => !ready
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(right: 10),
              child: HoloButton(
                label: 'Try',
                icon: Icons.ondemand_video_rounded,
                accent: SpaceColors.gold,
                height: 32,
                fontSize: 11,
                expand: false,
                onPressed: () => MonetizationService.instance.showRewarded(
                  AdPlacement.cosmeticTrial,
                  onReward: onReward,
                ),
              ),
            ),
    );
  }
}

/// One Garage item. [locked] items (rank or coins short) buzz on tap.
class CosmeticTile extends StatelessWidget {
  const CosmeticTile({
    super.key,
    required this.item,
    required this.unlocked,
    required this.equipped,
    required this.onTap,
    this.trying = false,
    this.locked = false,
    this.tryButton,
  });
  final CosmeticItem item;
  final bool unlocked;
  final bool equipped;
  final VoidCallback onTap;
  final bool locked;

  /// On loan for the next level (rewarded trial).
  final bool trying;
  final Widget? tryButton;

  @override
  Widget build(BuildContext context) {
    final Widget status;
    if (trying) {
      status = Text(
        'ON TRIAL · NEXT LEVEL',
        style: hudLabel(10.5, color: SpaceColors.gold),
      );
    } else if (equipped) {
      status = HoloChip(
        icon: Icons.check_rounded,
        label: 'EQUIPPED',
        color: _garageAccent,
        highlight: true,
      );
    } else if (unlocked) {
      status = Text('EQUIP', style: hudLabel(11, color: Colors.white54));
    } else if (item.supporterOnly) {
      status = const Text(
        '💎 Supporter Pack',
        style: TextStyle(
          color: Color(0xFF33D6C9),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
    } else if (CosmeticsService.isRankLocked(item)) {
      status = Text(
        '🔒 ${item.requiredRank.title}',
        style: const TextStyle(
          color: SpaceColors.gold,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
    } else {
      status = HoloChip(
        leading: const Text('💰', style: TextStyle(fontSize: 12)),
        label: '${item.cost}',
        color: locked ? Colors.white38 : SpaceColors.green,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _ItemTap(
        locked: locked,
        onTap: onTap,
        child: HoloPanel(
          accent: equipped ? _garageAccent : const Color(0xFF3A5068),
          glow: equipped ? 0.6 : 0,
          brackets: equipped,
          cut: 12,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Text(item.icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        color: unlocked ? Colors.white : Colors.white60,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (item.category == CosmeticsService.catRope)
                      RopeStatsView(rope: ropeById(item.id)),
                  ],
                ),
              ),
              ?tryButton,
              status,
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap handling for Garage tiles: select sound, or a buzz + shake when the
/// item can't be bought yet.
class _ItemTap extends StatefulWidget {
  const _ItemTap({
    required this.locked,
    required this.onTap,
    required this.child,
  });
  final bool locked;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_ItemTap> createState() => _ItemTapState();
}

class _ItemTapState extends State<_ItemTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (widget.locked) {
          AudioService.playUi(UiSound.denied);
          _shake.forward(from: 0);
          return;
        }
        AudioService.playUi(UiSound.select);
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final t = _shake.value;
          final dx = _shake.isAnimating
              ? math.sin(t * math.pi * 6) * 6 * (1 - t)
              : 0.0;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: widget.child,
      ),
    );
  }
}

/// Tow gear stats on a Garage tile: the trade-off line and four bars.
class RopeStatsView extends StatelessWidget {
  const RopeStatsView({super.key, required this.rope});
  final RopeSpec rope;

  @override
  Widget build(BuildContext context) {
    final st = RopeStats.of(rope);
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
              _StatBar(label: 'REACH', value: st.reach),
              _StatBar(label: 'GIVE', value: st.give),
              _StatBar(label: 'STEADY', value: st.steadiness),
              _StatBar(label: 'FUEL', value: st.economy),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBar extends StatelessWidget {
  const _StatBar({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
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
      ],
    );
  }
}
