import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:narrow_haul/game/services/ad_pacing.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

/// Store product ids (create the same ids in App Store Connect / Play Console:
/// [fullGame], [supporterPack] and [fleetPass] as non-consumables, the
/// [ammoPacks] as consumables).
class ProductIds {
  /// The Full Game, bought once and kept for life: every Expedition (Act II,
  /// docs/STORY.md) and no interstitials. Rewarded ads stay available
  /// (opt-in). Replaces the earlier Remove Ads product.
  static const fullGame = 'nh_full_game';

  /// The Full Game + exclusive [kSupporterSkinId] livery + [supporterCoins].
  static const supporterPack = 'nh_supporter_pack';

  /// Weapon ammo, bought again and again (consumables).
  static const demolitionKit = 'nh_demo_kit';
  static const arsenalCrate = 'nh_arsenal_crate';

  /// Every ship, now and later (non-consumable). The one store route to
  /// ships: single ships are bought with coins, and every ship is also
  /// earned by play, so it only turns interstitials off for
  /// [kAdPurchaseGrace].
  static const fleetPass = 'nh_fleet_pass';

  static const nonConsumables = {fullGame, supporterPack, fleetPass};
  static const consumables = {demolitionKit, arsenalCrate};
  static const all = {...nonConsumables, ...consumables};
  static const supporterCoins = 500;

  /// What each ammo pack adds to the carried stock (weapon id → units;
  /// laser units are seconds).
  static final Map<String, Map<String, double>> ammoPacks = {
    demolitionKit: {
      kDemoCharge.id: 10,
      kGravityBomb.id: 10,
      kMiningLaser.id: 60,
    },
    arsenalCrate: {
      kDemoCharge.id: 30,
      kGravityBomb.id: 30,
      kMiningLaser.id: 180,
      kSeeker.id: 30,
      kFlak.id: 30,
    },
  };

  /// Store-facing names (Settings / Armory rows).
  static const names = {
    demolitionKit: 'Demolition Kit',
    arsenalCrate: 'Arsenal Crate',
    fleetPass: 'Fleet Pass',
    fullGame: 'Full Game',
    supporterPack: 'Supporter Pack',
  };
}

/// AdMob ad-unit ids. Debug and profile builds always use Google's public test units so
/// tapping our own ads can never get the account flagged.
///
/// Release units belong to the "Narrow_Haul" apps in the AdMob account (app
/// ids in AndroidManifest.xml / Info.plist). They serve real ads only once
/// each app is linked to its published store listing.
class AdIds {
  static const _releaseInterAndroid = 'ca-app-pub-7248828164794524/6883176886';
  static const _releaseRewardedAndroid =
      'ca-app-pub-7248828164794524/2398146128';
  static const _releaseInterIos = 'ca-app-pub-7248828164794524/8370237117';
  static const _releaseRewardedIos = 'ca-app-pub-7248828164794524/4430992101';

  static const _testInterAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testInterIos = 'ca-app-pub-3940256099942544/4411468910';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

  static String get interstitial => !kReleaseMode
      ? (Platform.isIOS ? _testInterIos : _testInterAndroid)
      : (Platform.isIOS ? _releaseInterIos : _releaseInterAndroid);

  static String get rewarded => !kReleaseMode
      ? (Platform.isIOS ? _testRewardedIos : _testRewardedAndroid)
      : (Platform.isIOS ? _releaseRewardedIos : _releaseRewardedAndroid);
}

/// Rewarded-ad placements (analytics labels + intent).
class AdPlacement {
  static const continueAfterCrash = 'continue';
  static const doubleCoins = 'double_coins';
  static const cosmeticTrial = 'cosmetic_trial';

  /// Armory / game-over: a free charge or two of a special weapon.
  static const ammo = 'ammo';
}

/// How a [MonetizationService.purchase] ended.
enum BuyOutcome {
  purchased,

  /// Started but waiting on approval; delivered later.
  pending,

  /// Cancelled or failed.
  failed,

  /// The store or the product isn't available right now.
  unavailable,
}
