// Garage purchases: coins, rank locks, equipping.
import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/rank_service.dart';

import 'helpers/pump.dart';

void main() {
  final tractor = CosmeticsService.byId('rope_tractor')!;
  final longLine = CosmeticsService.byId('rope_braided')!; // rank item
  final supporter = CosmeticsService.byId(kSupporterSkinId)!;
  setUp(CosmeticsService.clearTrials);

  test('every item id is unique and every category has a free default', () async {
    await freshSave();
    final ids = CosmeticsService.all.map((i) => i.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final cat in [
      CosmeticsService.catShip,
      CosmeticsService.catRope,
      CosmeticsService.catPlume,
      CosmeticsService.catKit,
    ]) {
      final item = CosmeticsService.byId(CosmeticsService.getSavedEquippedId(cat));
      expect(item, isNotNull, reason: cat);
      expect(item!.category, cat);
      expect(item.cost, 0, reason: '$cat default must be free');
      expect(item.rankRequired, 0, reason: '$cat default must be open');
    }
  });

  test('buying spends exactly the price, once', () async {
    await freshSave({'cosmetic_currency': tractor.cost + 30});
    final p = ProgressService.instance;
    expect(CosmeticsService.isUnlocked(tractor), isFalse);
    expect(await CosmeticsService.unlock(tractor), isTrue);
    expect(p.getCosmeticCurrency(), 30);
    expect(CosmeticsService.isUnlocked(tractor), isTrue);
    expect(await CosmeticsService.unlock(tractor), isTrue, reason: 'already owned');
    expect(p.getCosmeticCurrency(), 30, reason: 'not charged twice');
  });

  test('one coin short buys nothing', () async {
    await freshSave({'cosmetic_currency': tractor.cost - 1});
    expect(await CosmeticsService.unlock(tractor), isFalse);
    expect(ProgressService.instance.getCosmeticCurrency(), tractor.cost - 1);
    expect(CosmeticsService.isUnlocked(tractor), isFalse);
  });

  test('rank items are locked below the rank and free from it', () async {
    final rank = kRanks[longLine.rankRequired];
    await freshSave({'xp_total': rank.minXp - 1, 'cosmetic_currency': 9999});
    expect(CosmeticsService.isRankLocked(longLine), isTrue);
    expect(await CosmeticsService.unlock(longLine), isFalse);
    expect(ProgressService.instance.getCosmeticCurrency(), 9999);

    await freshSave({'xp_total': rank.minXp});
    expect(CosmeticsService.isUnlocked(longLine), isTrue);
  });

  test('the Supporter livery is never sold for coins', () async {
    await freshSave({'cosmetic_currency': 99999});
    expect(await CosmeticsService.unlock(supporter), isFalse);
    expect(CosmeticsService.isUnlocked(supporter), isFalse);
  });

  test('equip refuses what isn\'t owned', () async {
    await freshSave();
    await CosmeticsService.equip(tractor);
    expect(CosmeticsService.getSavedEquippedId(CosmeticsService.catRope), 'rope_cable');
    await freshSave({'cosmetic_currency': tractor.cost});
    await CosmeticsService.unlock(tractor);
    await CosmeticsService.equip(tractor);
    expect(CosmeticsService.getSavedEquippedId(CosmeticsService.catRope), tractor.id);
  });
}
