import 'package:flutter/material.dart';

import '../game/services/monetization_service.dart';
import '../game/services/progress_service.dart';
import '../game/ship/weapons.dart';
import 'store_feedback.dart';
import 'tap_sound.dart';

/// Units a rewarded ad adds (laser: seconds).
double rewardedAmmoUnits(WeaponSpec w) => w.continuous ? 5 : 1;

String ammoText(WeaponSpec w, double units) =>
    w.continuous ? '${units.round()} s' : '×${units.round()}';

String _weaponIcon(WeaponSpec w) => switch (w.kind) {
      WeaponKind.charge => '💥',
      WeaponKind.bomb => '💣',
      WeaponKind.laser => '🔦',
      WeaponKind.seeker => '🚀',
      WeaponKind.flak => '🎆',
      WeaponKind.cannon => '🔫',
    };

/// Garage → Armory: the special weapons, the ammo the pilot carries, and
/// ways to get more (coins, a rewarded ad, ammo packs from the store).
/// Ammo found in supply crates mid-level is free and keeps 3★ possible;
/// carried ammo caps the run it's used in at 2★.
class ArmoryList extends StatefulWidget {
  const ArmoryList({super.key, required this.onCoinsChanged});

  /// The Garage header shows the coin balance.
  final VoidCallback onCoinsChanged;

  @override
  State<ArmoryList> createState() => _ArmoryListState();
}

class _ArmoryListState extends State<ArmoryList> {
  final _p = ProgressService.instance;

  Future<void> _buyWithCoins(WeaponSpec w) async {
    if (_p.getCosmeticCurrency() < w.coinCost) return;
    await _p.spendCosmeticCurrency(w.coinCost);
    await _p.addAmmo(w.id, w.coinPack.toDouble());
    widget.onCoinsChanged();
    if (mounted) setState(() {});
  }

  Future<void> _watchForAmmo(WeaponSpec w) async {
    await MonetizationService.instance.showRewarded(
      AdPlacement.ammo,
      onReward: () async {
        await _p.addAmmo(w.id, rewardedAmmoUnits(w));
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = MonetizationService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: m.entitlements,
      builder: (context, _, _) {
        final coins = _p.getCosmeticCurrency();
        final packs = [
          for (final id in ProductIds.consumables)
            if (m.canBuy(id)) id,
        ];
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text(
                'Supply crates turn up on some levels: their ammo is free and '
                'keeps 3★ possible. Ammo you carry from here works on any '
                'level (not in the daily), but caps that run at 2★.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            for (final w in kWeapons)
              _WeaponTile(
                weapon: w,
                carried: _p.getAmmo(w.id),
                canAfford: coins >= w.coinCost,
                onBuy: () => _buyWithCoins(w),
                onWatch: () => _watchForAmmo(w),
              ),
            if (packs.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  'AMMO PACKS',
                  style: TextStyle(
                    color: Color(0xFFFFC857),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),
              for (final id in packs)
                _PackTile(
                  productId: id,
                  onBuy: () async {
                    await buyWithFeedback(context, id);
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ],
        );
      },
    );
  }
}

class _WeaponTile extends StatelessWidget {
  const _WeaponTile({
    required this.weapon,
    required this.carried,
    required this.canAfford,
    required this.onBuy,
    required this.onWatch,
  });

  final WeaponSpec weapon;
  final double carried;
  final bool canAfford;
  final VoidCallback onBuy;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final st = WeaponStats.of(weapon);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x151B263B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_weaponIcon(weapon), style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      weapon.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      carried > 0 ? ammoText(weapon, carried) : 'none',
                      style: TextStyle(
                        color: carried > 0 ? const Color(0xFFFFC857) : Colors.white30,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  weapon.blurb,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _Bar(label: 'POWER', value: st.power),
                    _Bar(label: 'REACH', value: st.reach),
                    _Bar(label: 'MINING', value: st.mining),
                    _Bar(label: 'AIM', value: st.precision),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextButton(
                onPressed: canAfford ? withTapSound(onBuy) : null,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4ADE80),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  '+${ammoText(weapon, weapon.coinPack.toDouble())}  💰 ${weapon.coinCost}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: MonetizationService.instance.rewardedReady,
                builder: (context, ready, _) => !ready
                    ? const SizedBox.shrink()
                    : TextButton.icon(
                        onPressed: withTapSound(onWatch),
                        icon: const Icon(Icons.ondemand_video_rounded, size: 16),
                        label: Text(
                          '+${ammoText(weapon, rewardedAmmoUnits(weapon))}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFFD166),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({required this.productId, required this.onBuy});

  final String productId;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final contents = ProductIds.ammoPacks[productId]!;
    final line = [
      for (final e in contents.entries)
        if (weaponById(e.key) case final w?) '${ammoText(w, e.value)} ${w.name}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1A12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x55FFC857)),
      ),
      child: Row(
        children: [
          const Text('📦', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ProductIds.names[productId] ?? productId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(line, style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ],
            ),
          ),
          FilledButton(
            onPressed: withTapSound(onBuy),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFC857),
              foregroundColor: const Color(0xFF1B1A12),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(MonetizationService.instance.priceOf(productId)),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value});
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
        Container(
          width: 52,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0x22FFFFFF),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFC857),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
