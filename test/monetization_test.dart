import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/services/ad_pacing.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/monetization_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/weapons.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _start = 1000000000;
const _s = 1000; // ms per second

/// A seasoned player well past every lifetime gate, due for an ad.
AdPacingInputs _due({
  bool adsRemoved = false,
  int deliveries = 20,
  int playSeconds = 3600,
  int clears = kAdClearsBetween,
  int lastInter = 0,
  int lastRewarded = 0,
}) => AdPacingInputs(
  adsRemoved: adsRemoved,
  lifetimeDeliveries: deliveries,
  lifetimePlaySeconds: playSeconds,
  clearsSinceInterstitial: clears,
  lastInterstitialMs: lastInter,
  lastRewardedMs: lastRewarded,
);

void main() {
  group('AdPacing', () {
    final afterGrace = _start + (kAdSessionGraceSeconds + 1) * _s;

    test('a due player past the session grace gets an interstitial', () {
      expect(
        AdPacing(
          sessionStartMs: _start,
        ).interstitialAllowed(_due(), afterGrace),
        isTrue,
      );
    });

    test('no ads in the first seconds of a session', () {
      final pacing = AdPacing(sessionStartMs: _start);
      expect(pacing.interstitialAllowed(_due(), _start + 10 * _s), isFalse);
    });

    test('new players (tutorial) never see one', () {
      final pacing = AdPacing(sessionStartMs: _start);
      expect(
        pacing.interstitialAllowed(
          _due(deliveries: kAdMinLifetimeDeliveries - 1),
          afterGrace,
        ),
        isFalse,
      );
      expect(
        pacing.interstitialAllowed(
          _due(playSeconds: kAdMinLifetimePlaySeconds - 1),
          afterGrace,
        ),
        isFalse,
      );
    });

    test('needs enough cleared levels since the last one', () {
      final pacing = AdPacing(sessionStartMs: _start);
      expect(
        pacing.interstitialAllowed(
          _due(clears: kAdClearsBetween - 1),
          afterGrace,
        ),
        isFalse,
      );
    });

    test('respects the interstitial and post-rewarded cooldowns', () {
      final pacing = AdPacing(sessionStartMs: _start);
      final now = _start + 3600 * _s;
      expect(
        pacing.interstitialAllowed(
          _due(lastInter: now - (kAdInterCooldownSeconds - 1) * _s),
          now,
        ),
        isFalse,
      );
      expect(
        pacing.interstitialAllowed(
          _due(lastInter: now - (kAdInterCooldownSeconds + 1) * _s),
          now,
        ),
        isTrue,
      );
      expect(
        pacing.interstitialAllowed(
          _due(lastRewarded: now - (kAdAfterRewardedSeconds - 1) * _s),
          now,
        ),
        isFalse,
      );
      expect(
        pacing.interstitialAllowed(
          _due(lastRewarded: now - (kAdAfterRewardedSeconds + 1) * _s),
          now,
        ),
        isTrue,
      );
    });

    test('caps interstitials per session', () {
      final pacing = AdPacing(sessionStartMs: _start)
        ..interstitialsThisSession = kAdMaxPerSession;
      expect(pacing.interstitialAllowed(_due(), afterGrace), isFalse);
    });

    test('remove-ads (or any purchase) turns interstitials off', () {
      expect(
        AdPacing(
          sessionStartMs: _start,
        ).interstitialAllowed(_due(adsRemoved: true), afterGrace),
        isFalse,
      );
    });
  });

  test('failed ad loads back off up to 10 minutes', () {
    expect(
      [for (var i = 1; i <= 6; i++) adRetryDelay(i).inSeconds],
      [60, 120, 240, 480, 600, 600],
    );
  });

  group('Cosmetic trial', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({'save_v3': true});
      await ProgressService.init();
      CosmeticsService.clearTrials();
    });

    test('a trial is rendered without changing the saved choice', () {
      final gold = CosmeticsService.byId('ship_gold')!;
      expect(CosmeticsService.isUnlocked(gold), isFalse);
      CosmeticsService.startTrial(gold);
      expect(
        CosmeticsService.getEquippedId(CosmeticsService.catShip),
        'ship_gold',
      );
      expect(
        CosmeticsService.getSavedEquippedId(CosmeticsService.catShip),
        'ship_standard',
      );
      CosmeticsService.clearTrials();
      expect(
        CosmeticsService.getEquippedId(CosmeticsService.catShip),
        'ship_standard',
      );
    });

    test('the supporter livery is never sold for coins', () async {
      await ProgressService.instance.addCosmeticCurrency(100000);
      final livery = CosmeticsService.byId(kSupporterSkinId)!;
      expect(await CosmeticsService.unlock(livery), isFalse);
      expect(CosmeticsService.isUnlocked(livery), isFalse);
      await ProgressService.instance.unlockCosmetic(kSupporterSkinId);
      expect(CosmeticsService.isUnlocked(livery), isTrue);
    });
  });

  group('Ammo packs', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({'save_v2': true, 'save_v3': true});
      await ProgressService.init();
    });

    test('a pack adds ammo, never removes ads, and pays once per transaction',
        () async {
      final m = MonetizationService.instance;
      final p = ProgressService.instance;
      await m.grant(ProductIds.demolitionKit, purchaseId: 'tx-1');
      expect(p.getAmmo(kDemoCharge.id), 10);
      expect(p.getAmmo(kMiningLaser.id), 60);
      expect(p.adsRemoved, isFalse);
      // The store re-delivers the same transaction: nothing more.
      await m.grant(ProductIds.demolitionKit, purchaseId: 'tx-1');
      expect(p.getAmmo(kDemoCharge.id), 10);
      // A second purchase is a new transaction.
      await m.grant(ProductIds.demolitionKit, purchaseId: 'tx-2');
      expect(p.getAmmo(kDemoCharge.id), 20);
    });

    test('every pack holds only real weapons', () {
      expect(ProductIds.ammoPacks.keys.toSet(), ProductIds.consumables);
      for (final pack in ProductIds.ammoPacks.values) {
        for (final id in pack.keys) {
          expect(weaponById(id), isNotNull, reason: id);
        }
      }
    });

    test('ammo survives a progress reset', () async {
      final p = ProgressService.instance;
      await p.addAmmo(kFlak.id, 4);
      await p.resetProgress();
      expect(p.getAmmo(kFlak.id), 4);
    });
  });
}
