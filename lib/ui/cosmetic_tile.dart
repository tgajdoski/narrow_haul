part of 'garage_overlay.dart';

/// Garage "Try" chip: a rewarded ad lends the item for the next level.
class _TryButton extends StatelessWidget {
  const _TryButton({required this.onReward});
  final VoidCallback onReward;

  @override
  Widget build(BuildContext context) {
    return WhenRewardedReady(
      child: Padding(
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

/// One Garage item. [locked] items (rank or coins short) buzz on tap and
/// say why ([onLocked]).
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
    this.mark = GarageMark.none,
    this.coins = 0,
    this.compareTo,
    this.onLocked,
  });
  final CosmeticItem item;
  final bool unlocked;
  final bool equipped;
  final VoidCallback onTap;
  final bool locked;

  /// On loan for the next level (rewarded trial).
  final bool trying;
  final Widget? tryButton;

  /// NEW / AFFORDABLE / NOT FITTED ribbon.
  final GarageMark mark;
  final int coins;

  /// Id of the equipped item in this category, for ▲▼ stat deltas.
  final String? compareTo;
  final VoidCallback? onLocked;

  Widget _small(String text, Color color) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final gear = isGear(item);
    final Widget status;
    if (trying) {
      status = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ON TRIAL · NEXT LEVEL', style: hudLabel(10.5, color: SpaceColors.gold)),
          if (item.cost > 0) _small('own it for ${item.cost} 💰', Colors.white54),
        ],
      );
    } else if (equipped) {
      status = HoloChip(
        icon: Icons.check_rounded,
        label: gear ? 'FITTED' : 'EQUIPPED',
        color: _garageAccent,
        highlight: true,
      );
    } else if (unlocked) {
      status = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          HoloChip(
            icon: Icons.add_rounded,
            label: gear ? 'FIT' : 'USE',
            color: SpaceColors.cyan,
          ),
          _small('owned', Colors.white54),
        ],
      );
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
      final xpToGo = (item.requiredRank.minXp - CareerService.xp).clamp(0, 1 << 30);
      status = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '🔒 ${item.requiredRank.title}',
            style: const TextStyle(
              color: SpaceColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          _small('free · $xpToGo XP to go', Colors.white54),
        ],
      );
    } else {
      status = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          HoloChip(
            leading: const Text('💰', style: TextStyle(fontSize: 12)),
            label: '${item.cost}',
            color: locked ? Colors.white38 : SpaceColors.green,
          ),
          if (locked) _small('need ${item.cost - coins} more', Colors.white38),
        ],
      );
    }

    final compare = compareTo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _ItemTap(
        locked: locked,
        onTap: onTap,
        onLocked: onLocked,
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
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item.name,
                          style: TextStyle(
                            color: unlocked ? Colors.white : Colors.white60,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        ?_ribbon(mark),
                      ],
                    ),
                    if (item.category == CosmeticsService.catRope)
                      RopeStatsView(
                        rope: ropeById(item.id),
                        compareTo: compare == null ? null : ropeById(compare),
                      ),
                    if (item.category == CosmeticsService.catKit)
                      KitStatsView(
                        kit: kitById(item.id),
                        compareTo: compare == null ? null : kitById(compare),
                      ),
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

  static Widget? _ribbon(GarageMark mark) {
    final (text, color) = switch (mark) {
      GarageMark.none => (null, Colors.transparent),
      GarageMark.newUnlock => ('NEW', SpaceColors.gold),
      GarageMark.affordable => ('AFFORDABLE', SpaceColors.green),
      GarageMark.notFitted => ('NOT FITTED', SpaceColors.cyan),
    };
    if (text == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: ShapeDecoration(
        color: color,
        shape: ChamferBorder(cut: 4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: SpaceColors.bg,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
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
    this.onLocked,
  });
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback? onLocked;
  final Widget child;

  @override
  State<_ItemTap> createState() => _ItemTapState();
}

class _ItemTapState extends State<_ItemTap>
    with SingleTickerProviderStateMixin, DeniedShake {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (widget.locked) {
          deny();
          widget.onLocked?.call();
          return;
        }
        AudioService.playUi(UiSound.select);
        widget.onTap();
      },
      child: shaking(widget.child),
    );
  }
}
