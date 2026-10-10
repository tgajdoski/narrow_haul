import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/fleet_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/fleet.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/ui/garage_overlay.dart' show StatBar;
import 'package:narrow_haul/ui/ship_showcase.dart';
import 'package:narrow_haul/ui/space_ui.dart';
import 'package:narrow_haul/ui/store_feedback.dart';

/// Garage → Ships: the whole fleet, what each flies like, and how to get the
/// ones not in the hangar yet (type rating, coins or the store). Owned ships
/// can be set to fly by default wherever they fit.
class ShipHangar extends StatefulWidget {
  const ShipHangar({
    super.key,
    required this.accent,
    required this.onOffer,
    required this.onChanged,
    this.news = const {},
  });

  final Color accent;

  /// Ship ids to flag NEW / AFFORDABLE (news when the tab opened).
  final Set<String> news;

  /// A locked ship was tapped: the Garage shows [ShipOfferDialog].
  final void Function(ShipSpec ship) onOffer;

  /// Coins or the default ship changed (the Garage header refreshes).
  final VoidCallback onChanged;

  @override
  State<ShipHangar> createState() => _ShipHangarState();
}

class _ShipHangarState extends State<ShipHangar> {
  late ShipSpec _shown = kShips[FleetService.preferred] ??
      LevelRegistry.shipFor(LevelRegistry.nextLevelIndex());

  Future<void> _setDefault(String? id) async {
    await FleetService.setPreferred(id);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  void _tap(ShipSpec? ship) {
    if (ship != null) setState(() => _shown = ship);
    if (ship == null) {
      _setDefault(null);
    } else if (FleetService.owns(ship.id)) {
      _setDefault(ship.id);
    } else {
      widget.onOffer(ship);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when a store purchase lands.
    return ValueListenableBuilder<int>(
      valueListenable: MonetizationService.instance.entitlements,
      builder: (context, _, _) => LayoutBuilder(
        builder: (context, box) {
          final preferred = FleetService.preferred;
          final list = ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              _MissionShipRow(
                selected: preferred == null,
                accent: widget.accent,
                onTap: () => _tap(null),
              ),
              for (final s in FleetService.fleet)
                ShipTile(
                  ship: s,
                  accent: widget.accent,
                  isDefault: preferred == s.id,
                  compareTo: kShips[preferred],
                  news: widget.news.contains(s.id),
                  onTap: () => _tap(s),
                ),
            ],
          );
          if (box.maxWidth < 600) return list;
          return Row(
            children: [
              SizedBox(
                width: (box.maxWidth * 0.36).clamp(200.0, 360.0),
                child: _turntable(),
              ),
              Expanded(child: list),
            ],
          );
        },
      ),
    );
  }

  Widget _turntable() {
    final owned = FleetService.owns(_shown.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 0, 6),
      child: Column(
        children: [
          Expanded(
            child: Opacity(
              opacity: owned ? 1 : 0.45,
              child: ShipShowcase(
                key: const ValueKey('ships-turntable'),
                ship: _shown,
                livery: CosmeticsService.getEquippedId(CosmeticsService.catShip),
                plume: CosmeticsService.getEquippedId(CosmeticsService.catPlume),
                accent: widget.accent,
              ),
            ),
          ),
          Text(_shown.name.toUpperCase(), style: hudLabel(13, spacing: 2)),
          Text(
            owned ? shipTrait(_shown) : '🔒 ${shipTrait(_shown)}',
            style: TextStyle(
              color: owned ? Colors.white60 : SpaceColors.gold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Mission ship": no default, each mission flies the ship it's built for.
class _MissionShipRow extends StatelessWidget {
  const _MissionShipRow({
    required this.selected,
    required this.accent,
    required this.onTap,
  });
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: HoloPanel(
          accent: selected ? accent : const Color(0xFF3A5068),
          glow: selected ? 0.6 : 0,
          brackets: selected,
          cut: 12,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Colors.white70, size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mission ship',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'Each mission flies the ship it was built for.',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (selected)
                HoloChip(
                  icon: Icons.check_rounded,
                  label: 'DEFAULT',
                  color: accent,
                  highlight: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One ship in the Garage: trait, blurb, stat bars and how to get it.
class ShipTile extends StatelessWidget {
  const ShipTile({
    super.key,
    required this.ship,
    required this.accent,
    required this.isDefault,
    required this.onTap,
    this.compareTo,
    this.news = false,
  });
  final ShipSpec ship;

  /// Flag it: NEW once rated, AFFORDABLE while locked.
  final bool news;
  final Color accent;
  final bool isDefault;
  final VoidCallback onTap;

  /// The default ship, for ▲▼ deltas (null: none).
  final ShipSpec? compareTo;

  @override
  Widget build(BuildContext context) {
    final source = FleetService.sourceOf(ship.id);
    final owned = source != ShipSource.locked;
    final coins = ProgressService.instance.getCosmeticCurrency();
    final price = FleetService.coinPrice(ship.id);
    final Widget status;
    if (isDefault) {
      status = HoloChip(
        icon: Icons.check_rounded,
        label: 'DEFAULT',
        color: accent,
        highlight: true,
      );
    } else if (owned) {
      status = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const HoloChip(icon: Icons.add_rounded, label: 'FLY', color: SpaceColors.cyan),
          _small(switch (source) {
            ShipSource.rated => 'type-rated',
            ShipSource.coins || ShipSource.iap => 'owned',
            _ => 'stock',
          }, Colors.white54),
        ],
      );
    } else {
      status = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (price != null)
            HoloChip(
              leading: const Text('💰', style: TextStyle(fontSize: 12)),
              label: '$price',
              color: coins >= price ? SpaceColors.green : Colors.white38,
            ),
          _small('or earn: ${kShipEarnedIn[ship.id]}', Colors.white54),
        ],
      );
    }
    final cmp = compareTo == null || compareTo!.id == ship.id ? null : compareTo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: HoloPanel(
          accent: isDefault ? accent : const Color(0xFF3A5068),
          glow: isDefault ? 0.6 : 0,
          brackets: isDefault,
          cut: 12,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                owned ? Icons.rocket_launch_rounded : Icons.lock_outline_rounded,
                size: 22,
                color: owned ? Color(ship.tint ?? 0xFFFFFFFF).withValues(alpha: 1) : Colors.white38,
              ),
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
                          ship.name,
                          style: TextStyle(
                            color: owned ? Colors.white : Colors.white60,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          shipTrait(ship).toUpperCase(),
                          style: hudLabel(9.5, color: SpaceColors.gold),
                        ),
                        if (news && !isDefault)
                          _ribbon(owned ? 'NEW' : 'AFFORDABLE',
                              owned ? SpaceColors.gold : SpaceColors.green),
                      ],
                    ),
                    ShipStatsView(ship: ship, compareTo: cmp),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Flies ${FleetService.missionsFor(ship)} of '
                        '${LevelRegistry.totalLevels} missions',
                        style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                      ),
                    ),
                  ],
                ),
              ),
              status,
            ],
          ),
        ),
      ),
    );
  }

  static Widget _ribbon(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: ShapeDecoration(color: color, shape: ChamferBorder(cut: 4)),
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

  static Widget _small(String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600),
        ),
      );
}

/// A ship's blurb and five bars (▲▼ against [compareTo]).
class ShipStatsView extends StatelessWidget {
  const ShipStatsView({super.key, required this.ship, this.compareTo});
  final ShipSpec ship;
  final ShipSpec? compareTo;

  @override
  Widget build(BuildContext context) {
    final st = ShipStats.of(ship);
    final cmp = compareTo == null ? null : ShipStats.of(compareTo!);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ship.blurb, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 5),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              StatBar(label: 'LIFT', value: st.lift, was: cmp?.lift),
              StatBar(label: 'TURN', value: st.turn, was: cmp?.turn),
              StatBar(label: 'RANGE', value: st.range, was: cmp?.range),
              StatBar(label: 'STEADY', value: st.steady, was: cmp?.steady),
              StatBar(label: 'SMALL', value: st.compact, was: cmp?.compact),
            ],
          ),
        ],
      ),
    );
  }
}

/// How to get a ship that isn't in the hangar: its type rating (free), coins,
/// or the Fleet Pass (every ship). The Fleet Pass row shows only when the
/// store has it (offline: coins and the rating only).
class ShipOfferDialog extends StatelessWidget {
  const ShipOfferDialog({
    super.key,
    required this.ship,
    required this.accent,
    required this.onDone,
  });
  final ShipSpec ship;
  final Color accent;

  /// Closed; [bought] when the ship is now owned.
  final void Function(bool bought) onDone;

  @override
  Widget build(BuildContext context) {
    final m = MonetizationService.instance;
    final coins = ProgressService.instance.getCosmeticCurrency();
    final price = FleetService.coinPrice(ship.id);
    final canCoins = price != null && coins >= price;
    Future<void> store(String id) async {
      final ok = await buyWithFeedback(context, id);
      onDone(ok && FleetService.owns(ship.id));
    }

    return HoloDialog(
      accent: accent,
      maxWidth: 460,
      title: 'Get the ${ship.name}',
      footer: HoloButton(
        label: 'Not now',
        variant: HoloVariant.ghost,
        height: 40,
        onPressed: () => onDone(false),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShipStatsView(ship: ship),
          const SizedBox(height: 8),
          Text(
            'Free: fly its type rating, the first mission of '
            '${kShipEarnedIn[ship.id]}. Or skip ahead now and fly it on every '
            'mission it fits.',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (price != null)
            HoloButton.primary(
              label: canCoins ? 'Buy · $price 💰' : 'Need ${price - coins} more 💰',
              height: 40,
              onPressed: canCoins
                  ? () async {
                      final ok = await FleetService.buyWithCoins(ship.id);
                      onDone(ok);
                    }
                  : null,
            ),
          if (m.canBuy(ProductIds.fleetPass) || kFleetPreview) ...[
            const SizedBox(height: 8),
            HoloButton(
              label: 'Fleet Pass · every ship · ${m.priceOf(ProductIds.fleetPass)}',
              accent: SpaceColors.gold,
              height: 40,
              onPressed: () => store(ProductIds.fleetPass),
            ),
          ],
        ],
      ),
    );
  }
}
