part of '../level_select_overlay.dart';

/// One tab per world under the map: tap to fly the map to that world.
class _WorldTabs extends StatefulWidget {
  const _WorldTabs({
    required this.active,
    required this.totalStars,
    required this.onSelect,
  });

  final int active;
  final int totalStars;
  final ValueChanged<int> onSelect;

  @override
  State<_WorldTabs> createState() => _WorldTabsState();
}

class _WorldTabsState extends State<_WorldTabs> {
  final _keys = [for (final _ in LevelRegistry.worlds) GlobalKey()];

  @override
  void initState() {
    super.initState();
    _reveal(animate: false);
  }

  @override
  void didUpdateWidget(_WorldTabs old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _reveal(animate: true);
  }

  /// Keeps the lit tab on screen when the row is wider than the phone.
  void _reveal({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[widget.active].currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final worlds = LevelRegistry.worlds;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (int wi = 0; wi < worlds.length; wi++)
              Padding(
                key: _keys[wi],
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _tab(wi, worlds[wi]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tab(int wi, WorldDef world) {
    final unlocked = widget.totalStars >= world.starsRequired;
    final active = wi == widget.active;
    final accent = (gameThemes[world.themeId] ?? tutorialTheme).uiAccent;
    final color = !unlocked
        ? (active ? Colors.white70 : Colors.white38)
        : (active ? accent : accent.withValues(alpha: 0.6));
    return GestureDetector(
      key: ValueKey('worldTab_${world.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AudioService.playUi(UiSound.select);
        widget.onSelect(wi);
      },
      child: HoloChip(
        label: world.name.toUpperCase(),
        icon: unlocked ? null : Icons.lock_outline,
        color: color,
        highlight: active,
      ),
    );
  }
}

class _WorldHeader extends StatelessWidget {
  const _WorldHeader({
    required this.world,
    required this.unlocked,
    required this.totalStars,
  });

  final WorldDef world;
  final bool unlocked;
  final int totalStars;

  @override
  Widget build(BuildContext context) {
    final accent = (gameThemes[world.themeId] ?? tutorialTheme).uiAccent;
    final worldStars = LevelRegistry.starsIn(world.levels);
    return SizedBox(
      width: 126,
      child: Center(
        child: HoloPanel(
          accent: unlocked ? accent : Colors.white24,
          glow: unlocked ? 0.6 : 0,
          cut: 12,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                world.name.toUpperCase(),
                textAlign: TextAlign.center,
                style: hudLabel(
                  12,
                  color: unlocked ? accent : Colors.white30,
                  spacing: 1.4,
                ),
              ),
              const SizedBox(height: 5),
              if (unlocked) ...[
                HoloRing(
                  value: worldStars / (world.levels.length * 3),
                  color: accent,
                  child: Text(
                    '$worldStars/${world.levels.length * 3}',
                    style: hudLabel(9.5, color: accent, spacing: 0),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.rocket_rounded,
                      size: 11,
                      color: accent.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: MarqueeText(
                        shipById(world.defaultShipId).name,
                        style: TextStyle(
                          color: accent.withValues(alpha: 0.9),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                HoloRing(
                  value: totalStars / world.starsRequired,
                  color: Colors.white38,
                  child: const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: Colors.white30,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$totalStars / ${world.starsRequired} ★',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
