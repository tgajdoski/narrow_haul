import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/narrow_haul_game.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/fleet_service.dart';
import 'package:narrow_haul/game/services/garage_notices.dart';
import 'package:narrow_haul/game/services/rank_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/loadout.dart';
import 'package:narrow_haul/game/ship/ship_spec.dart';
import 'package:narrow_haul/ui/armory.dart';
import 'package:narrow_haul/ui/garage_ships.dart';
import 'package:narrow_haul/ui/ship_showcase.dart';
import 'package:narrow_haul/ui/space_ui.dart';
import 'package:narrow_haul/ui/store_feedback.dart';
import 'package:narrow_haul/game/overlay_ids.dart';

const _garageAccent = SpaceColors.coral;

/// 'cosmetics' overlay — the Garage: ships, liveries, tow gear, plumes and
/// the Armory, behind a segmented cockpit tab bar.
class GarageOverlay extends StatefulWidget {
  const GarageOverlay({super.key, required this.game, this.initialTab});

  final NarrowHaulGame game;

  /// Tab to open on (null: what's new). [GarageOverlay.shipsTab] opens the
  /// fleet, e.g. from a briefing's "Get it".
  final String? initialTab;

  static const shipsTab = 'ships';

  @override
  State<GarageOverlay> createState() => _GarageOverlayState();
}

class _GarageOverlayState extends State<GarageOverlay> {
  /// The weapons tab (not a cosmetics category).
  static const _armory = 'armory';

  /// The fleet tab (not a cosmetics category either).
  static const _ships = GarageOverlay.shipsTab;

  /// A locked ship waiting on [ShipOfferDialog].
  ShipSpec? _shipOffer;
  late String _selectedCategory;

  /// Items that were news when their tab was opened this visit: they keep
  /// their ribbon until the Garage closes, though they're marked seen.
  final Map<String, GarageMark> _shownMarks = {};

  /// A paid item waiting for "Buy & fit".
  CosmeticItem? _confirm;

  /// The livery / plume last tapped (owned or not), shown on the turntable.
  final Map<String, String> _preview = {};

  /// The ships on the turntable: the next mission's, then every ship the
  /// player is type-rated on. [_shipAt] picks one.
  late final List<ShipSpec> _fleet = garageFleet();
  int _shipAt = 0;

  static const _tabs = [
    (_ships, 'Ships', Icons.flight_rounded),
    (CosmeticsService.catShip, 'Liveries', Icons.rocket_rounded),
    (CosmeticsService.catRope, 'Tow gear', Icons.link_rounded),
    (CosmeticsService.catKit, 'Handling', Icons.tune_rounded),
    (CosmeticsService.catPlume, 'Plumes', Icons.local_fire_department_outlined),
    (_armory, 'Armory', Icons.gps_fixed_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialTab ?? _firstTab(GarageNotices.current());
    _view(_selectedCategory);
  }

  /// Open on what's new; else on gear the player owns but never flew.
  static String _firstTab(GarageSnapshot snap) {
    if (FleetService.fresh.isNotEmpty) return _ships;
    for (final (id, _, _) in _tabs) {
      if (snap.fresh.any((i) => i.category == id)) return id;
    }
    final unused = snap.unusedGear;
    if (unused.isNotEmpty) return unused.first.category;
    return CosmeticsService.catShip;
  }

  /// Ships with news when the Ships tab opened: ribbons until the Garage
  /// closes, though they're marked seen.
  Set<String> _shipNews = const {};

  void _view(String category) {
    if (category == _ships) {
      _shipNews = {..._shipNews, ...FleetService.fresh};
      unawaited(FleetService.markSeen());
      return;
    }
    if (category == _armory) return;
    final snap = GarageNotices.current();
    final fresh = [for (final i in snap.fresh) if (i.category == category) i];
    for (final i in fresh) {
      _shownMarks[i.id] = snap.markFor(i);
    }
    if (fresh.isNotEmpty) unawaited(GarageNotices.markSeen(fresh));
  }

  void _select(String category) {
    setState(() {
      _selectedCategory = category;
      _view(category);
    });
  }

  Future<void> _onItemTap(
    CosmeticItem item,
    bool unlocked,
    bool equipped,
  ) async {
    _showOnTurntable(item);
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
      // Coins are spent only after a confirm that shows what they buy.
      setState(() => _confirm = item);
    }
  }

  Future<void> _buy(CosmeticItem item) async {
    setState(() => _confirm = null);
    final success = await CosmeticsService.unlock(item);
    if (success) {
      await CosmeticsService.equip(item);
      if (mounted) setState(() {});
    }
  }

  /// Liveries and plumes go on the turntable when tapped, even before
  /// they're bought.
  void _showOnTurntable(CosmeticItem item) {
    if (!_hasTurntable(item.category)) return;
    setState(() => _preview[item.category] = item.id);
  }

  static bool _hasTurntable(String category) =>
      category == CosmeticsService.catShip || category == CosmeticsService.catPlume;

  /// Why a locked tile can't be had yet, as a SnackBar.
  void _explainLocked(CosmeticItem item, int coins) {
    _showOnTurntable(item);
    final String message;
    if (CosmeticsService.isRankLocked(item)) {
      final xp = (item.requiredRank.minXp - CareerService.xp).clamp(0, 1 << 30);
      message =
          '${item.name} is free at ${item.requiredRank.title} — $xp XP to go. '
          'Fly missions to earn XP.';
    } else {
      message =
          'Need ${item.cost - coins} more 💰 for ${item.name}. '
          'Stars and promotions pay coins.';
    }
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  /// Sort: stock first, then owned, then for sale by price, then rank items.
  static int _order(CosmeticItem i) {
    if (i.cost == 0 && i.rankRequired == 0 && !i.supporterOnly) return 0;
    if (CosmeticsService.isUnlocked(i)) return 1;
    if (CosmeticsService.isRankLocked(i)) return 3;
    return 2;
  }

  static String? _caption(String category) => switch (category) {
    _ships =>
      'Each ship flies differently · fly any you own where it fits · '
          'stars stay fair (fuel scaled by range)',
    CosmeticsService.catShip ||
    CosmeticsService.catPlume => 'Looks only · no effect on flight',
    CosmeticsService.catRope =>
      'Sidegrades: each line trades one strength for a weakness · '
          '▲▼ compare with the one you fly now',
    CosmeticsService.catKit =>
      'Sidegrades: easier handling, paid in fuel or tank · '
          '▲▼ compare with the one you fly now',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final currency = ProgressService.instance.getCosmeticCurrency();
    final snap = GarageNotices.current();
    final items =
        CosmeticsService.all
            .where((e) => e.category == _selectedCategory)
            .toList()
          ..sort((a, b) {
            final o = _order(a).compareTo(_order(b));
            if (o != 0) return o;
            final r = a.rankRequired.compareTo(b.rankRequired);
            return r != 0 ? r : a.cost.compareTo(b.cost);
          });
    final caption = _caption(_selectedCategory);
    final confirm = _confirm;

    return Stack(
      children: [
        Positioned.fill(
          child: SpaceScreen(
            title: 'Garage',
            accent: _garageAccent,
            onBack: () => widget.game.closeScreen(OverlayIds.cosmetics),
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
                            dot: id != _selectedCategory &&
                                id != _armory &&
                                (id == _ships
                                    ? FleetService.fresh.isNotEmpty
                                    : snap.tabHasNews(id)),
                            onTap: () => _select(id),
                          ),
                        ),
                        if (id != _armory) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                if (caption != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                    child: Text(
                      caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                Expanded(
                  child: _selectedCategory == _armory
                      ? ArmoryList(onCoinsChanged: () => setState(() {}))
                      : _selectedCategory == _ships
                      ? ShipHangar(
                          accent: _garageAccent,
                          news: _shipNews,
                          onOffer: (s) => setState(() => _shipOffer = s),
                          onChanged: () => setState(() {}),
                        )
                      : LayoutBuilder(
                          builder: (context, box) {
                            final list = ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              itemCount: items.length,
                              itemBuilder: (context, i) =>
                                  _tile(items[i], snap, currency),
                            );
                            // Looks tabs: the ship on its stand beside the
                            // list, where the screen is wide enough.
                            if (!_hasTurntable(_selectedCategory) || box.maxWidth < 600) {
                              return list;
                            }
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
                ),
              ],
            ),
          ),
        ),
        if (_shipOffer case final offer?)
          Positioned.fill(
            child: ShipOfferDialog(
              ship: offer,
              accent: _garageAccent,
              onDone: (bought) {
                if (!mounted) return;
                setState(() => _shipOffer = null);
                if (bought) unawaited(FleetService.setPreferred(offer.id));
              },
            ),
          ),
        if (confirm != null)
          Positioned.fill(
            child: _BuyConfirm(
              item: confirm,
              coins: currency,
              onBuy: () => _buy(confirm),
              onCancel: () => setState(() => _confirm = null),
            ),
          ),
      ],
    );
  }

  Widget _turntable() {
    final ship = _fleet[_shipAt % _fleet.length];
    String look(String cat) =>
        _preview[cat] ?? CosmeticsService.getEquippedId(cat);
    final livery = look(CosmeticsService.catShip);
    final plume = look(CosmeticsService.catPlume);
    final shown = CosmeticsService.all.where(
      (i) => i.id == (_selectedCategory == CosmeticsService.catPlume ? plume : livery),
    );
    final item = shown.isEmpty ? null : shown.first;
    final owned = item == null || CosmeticsService.isUnlocked(item);
    Widget arrow(IconData icon, int step) => _fleet.length < 2
        ? const SizedBox(width: 28)
        : IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            color: Colors.white70,
            icon: Icon(icon),
            onPressed: () => setState(() => _shipAt = (_shipAt + step) % _fleet.length),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 0, 6),
      child: Column(
        children: [
          Expanded(
            child: ShipShowcase(
              key: const ValueKey('garage-turntable'),
              ship: ship,
              livery: livery,
              plume: plume,
              accent: _garageAccent,
            ),
          ),
          Row(
            children: [
              arrow(Icons.chevron_left_rounded, _fleet.length - 1),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      ship.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: hudLabel(13, spacing: 2),
                    ),
                    if (item != null)
                      Text(
                        owned ? item.name : '${item.name} · preview',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: owned ? Colors.white60 : SpaceColors.gold,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              arrow(Icons.chevron_right_rounded, 1),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(CosmeticItem item, GarageSnapshot snap, int currency) {
    final unlocked = CosmeticsService.isUnlocked(item);
    final equipped =
        CosmeticsService.getSavedEquippedId(item.category) == item.id;
    final trying = CosmeticsService.trialOverride[item.category] == item.id;
    final rankLocked = CosmeticsService.isRankLocked(item);
    final affordable = item.cost <= currency;
    // Coin items can be test-flown for one level via an ad.
    final canTry = !unlocked && !trying && !item.supporterOnly && !rankLocked;
    final locked = !unlocked && !item.supporterOnly && (rankLocked || !affordable);
    var mark = _shownMarks[item.id] ?? snap.markFor(item);
    // Bought or fitted since the tab opened: the news is spent.
    if (mark == GarageMark.affordable && unlocked) mark = GarageMark.none;
    if (equipped) mark = GarageMark.none;
    return CosmeticTile(
      item: item,
      unlocked: unlocked,
      equipped: equipped,
      trying: trying,
      locked: locked,
      mark: mark,
      coins: currency,
      compareTo: equipped
          ? null
          : CosmeticsService.getSavedEquippedId(item.category),
      tryButton: canTry
          ? _TryButton(
              onReward: () =>
                  setState(() => CosmeticsService.startTrial(item)),
            )
          : null,
      onLocked: () => _explainLocked(item, currency),
      onTap: () => _onItemTap(item, unlocked, equipped),
    );
  }
}

/// The Garage turntable's ships: the next mission's first, then each ship
/// the player holds a type rating on.
List<ShipSpec> garageFleet() {
  final next = LevelRegistry.shipFor(LevelRegistry.nextLevelIndex());
  return [
    next,
    for (final s in kShips.values)
      if (s.id != next.id && LevelRegistry.hasTypeRating(s.id)) s,
  ];
}

/// "Buy & fit" confirm: what the coins buy and what's left after.
class _BuyConfirm extends StatelessWidget {
  const _BuyConfirm({
    required this.item,
    required this.coins,
    required this.onBuy,
    required this.onCancel,
  });
  final CosmeticItem item;
  final int coins;
  final VoidCallback onBuy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final equippedId = CosmeticsService.getSavedEquippedId(item.category);
    final gear = isGear(item);
    return HoloDialog(
      accent: _garageAccent,
      maxWidth: 440,
      title: gear ? 'Buy & fit' : 'Buy & wear',
      footer: Row(
        children: [
          Expanded(
            child: HoloButton(
              label: 'Cancel',
              variant: HoloVariant.ghost,
              height: 40,
              onPressed: onCancel,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: HoloButton.primary(
              label: 'Buy · ${item.cost} 💰',
              height: 40,
              onPressed: onBuy,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(item.icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (item.category == CosmeticsService.catRope)
            RopeStatsView(rope: ropeById(item.id), compareTo: ropeById(equippedId)),
          if (item.category == CosmeticsService.catKit)
            KitStatsView(kit: kitById(item.id), compareTo: kitById(equippedId)),
          if (!gear)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'A new look. It does not change how the ship flies.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'You have $coins 💰 · ${coins - item.cost} 💰 left after. '
            '${gear ? 'You can switch back to any gear you own at any time.' : 'Switch looks any time.'}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
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
    this.dot = false,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  /// Something new in this tab.
  final bool dot;

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
                if (dot) ...[
                  const SizedBox(width: 5),
                  Container(
                    key: const ValueKey('tab-dot'),
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: SpaceColors.gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
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
          widget.onLocked?.call();
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
