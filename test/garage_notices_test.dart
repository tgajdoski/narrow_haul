import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/garage_notices.dart';
import 'package:narrow_haul/game/services/rank_service.dart';

CosmeticItem _item(String id) => CosmeticsService.byId(id)!;

const _defaults = {'ship_standard', 'rope_cable', 'kit_none', 'plume_blue'};

GarageSnapshot _snap({
  int coins = 0,
  int rank = 0,
  int? xp,
  Set<String> bought = const {},
  Set<String> seen = const {},
  Set<String> fitted = const {},
  Map<String, String> equipped = const {},
}) {
  const items = CosmeticsService.all;
  return GarageSnapshot(
    items: items,
    owned: {
      ..._defaults,
      ...bought,
      for (final i in items)
        if (i.rankRequired > 0 && rank >= i.rankRequired) i.id,
    },
    rankIndex: rank,
    xp: xp ?? kRanks[rank].minXp,
    coins: coins,
    seen: seen,
    fitted: fitted,
    equipped: {
      'ship': 'ship_standard',
      'rope': 'rope_cable',
      'kit': 'kit_none',
      'plume': 'plume_blue',
      ...equipped,
    },
  );
}

void main() {
  test('a fresh pilot has nothing flagged, and saves for the Tow Chain', () {
    final s = _snap();
    expect(s.fresh, isEmpty);
    expect(s.unusedGear, isEmpty);
    expect(s.nextGoal!.item.id, 'rope_chain');
    expect(s.nextGoal!.coinsToGo, 80);
    expect(s.nextGoal!.label, contains('80 💰 to go'));
  });

  test('coins make items fresh until seen', () {
    final s = _snap(coins: 90);
    final ids = {for (final i in s.fresh) i.id};
    expect(ids, containsAll(['rope_chain', 'plume_green', 'plume_red']));
    expect(s.markFor(_item('rope_chain')), GarageMark.affordable);
    expect(s.tabHasNews('rope'), isTrue);

    final seen = _snap(coins: 90, seen: {for (final i in s.fresh) s.stateKey(i)!});
    expect(seen.fresh, isEmpty);
    expect(seen.markFor(_item('rope_chain')), GarageMark.none);
  });

  test('reaching a rank flags its item again, even if seen as affordable', () {
    final before = _snap(rank: 2);
    expect(before.stateKey(_item('rope_braided')), isNull); // rank-locked
    final s = _snap(rank: 3, seen: {'rope_chain:afford'});
    expect(s.markFor(_item('rope_braided')), GarageMark.newUnlock);
    // Seen the rank-up card, but never fitted: the gear nags softly.
    final seen = _snap(rank: 3, seen: {'rope_braided:rank'});
    expect(seen.markFor(_item('rope_braided')), GarageMark.notFitted);
    expect(seen.unusedGear.map((i) => i.id), ['rope_braided']);
    // Once fitted it's quiet, even after switching back to stock.
    final fitted = _snap(rank: 3, seen: {'rope_braided:rank'}, fitted: {'rope_braided'});
    expect(fitted.markFor(_item('rope_braided')), GarageMark.none);
  });

  test('bought looks are not nagged about; bought gear is until flown', () {
    final s = _snap(coins: 0, bought: {'ship_neon', 'kit_gyro'});
    expect(s.markFor(_item('ship_neon')), GarageMark.none);
    expect(s.markFor(_item('kit_gyro')), GarageMark.notFitted);
    final equipped = _snap(bought: {'kit_gyro'}, equipped: {'kit': 'kit_gyro'});
    expect(equipped.markFor(_item('kit_gyro')), GarageMark.none);
  });

  test('next goal: gear first, then the nearest rank unlock, then looks', () {
    const allGear = {
      'rope_chain', 'rope_energy', 'rope_neon', 'rope_tractor',
      'kit_gyro', 'kit_verniers', 'kit_dampers',
    };
    final s = _snap(rank: 1, xp: 1000, bought: allGear);
    final g = s.nextGoal!;
    expect(g.item.id, 'rope_braided');
    expect(g.byRank, isTrue);
    expect(g.xpToGo, kRanks[3].minXp - 1000);
    expect(g.label, contains('Second Officer'));

    final top = _snap(rank: 9, bought: allGear);
    expect(top.nextGoal!.item.category, isNot('rope'));
    expect(top.nextGoal!.byRank, isFalse);
  });

  test('a payout lists what it made affordable, gear first', () {
    final list = newlyAffordable(
      CosmeticsService.all,
      before: 40,
      after: 120,
      owned: _defaults,
      rankIndex: 0,
    );
    expect(list.first.id, 'rope_chain');
    expect({for (final i in list) i.id}, {'rope_chain', 'plume_green', 'plume_red', 'ship_neon'});
  });

  test('every rank perk names the Garage items it unlocks', () {
    for (final r in kRanks) {
      for (final i in unlocksAtRank(CosmeticsService.all, r.index)) {
        expect(r.perk, contains(i.name), reason: '${r.title} → ${i.id}');
      }
    }
  });
}
