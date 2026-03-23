import 'package:flutter/foundation.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

/// Monetization service stub.
///
/// To enable real ads, follow these steps:
///   1. Add to pubspec.yaml:    google_mobile_ads: ^5.x.x
///   2. Android: set APPLICATION_ID in android/app/src/main/AndroidManifest.xml
///      <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
///                 android:value="ca-app-pub-XXXXXX~XXXXXX"/>
///   3. iOS: set GADApplicationIdentifier in ios/Runner/Info.plist
///   4. Replace the stub methods below with real AdManager calls.
///
/// To enable IAP:
///   1. Add: in_app_purchase: ^3.x.x
///   2. Configure product IDs in App Store Connect / Google Play Console.
///   3. Replace stub methods below with InAppPurchase calls.
///
/// Product IDs used in this codebase:
class ProductIds {
  static const removeAds = 'nh_remove_ads';
  static const cosmetic1 = 'nh_skin_pack_1';
  static const cosmeticBundle = 'nh_cosmetic_bundle';
  static const supporterPack = 'nh_supporter_pack';
  static const levelPack = 'nh_level_pack_deep_space';
}

class MonetizationService {
  MonetizationService._();
  static MonetizationService? _instance;
  static MonetizationService get instance {
    _instance ??= MonetizationService._();
    return _instance!;
  }

  bool get adsRemoved => ProgressService.instance.getUnlockedAchievements().contains('remove_ads_purchased');

  // ── Rewarded ads ─────────────────────────────────────────────────────────

  /// Show a rewarded ad. [onRewarded] is called if the user watches it fully.
  /// Returns false immediately in this stub (no SDK loaded).
  Future<bool> showRewardedAd({
    required String placement,
    required void Function() onRewarded,
  }) async {
    if (kDebugMode) {
      debugPrint('MonetizationService [STUB]: showRewardedAd($placement)');
      // In debug mode, simulate an immediate reward for testing
      onRewarded();
      return true;
    }
    return false;
  }

  /// Show a rewarded ad to refill 50% fuel. Returns true if reward granted.
  Future<bool> showFuelRefillAd({required void Function() onFuelRefilled}) =>
      showRewardedAd(placement: 'fuel_refill', onRewarded: onFuelRefilled);

  /// Show a rewarded ad to retry with cargo pre-attached.
  Future<bool> showCargoAttachAd({required void Function() onGranted}) =>
      showRewardedAd(placement: 'cargo_attach', onRewarded: onGranted);

  // ── Interstitial ads ──────────────────────────────────────────────────────

  int _levelCompletionsSinceAd = 0;
  static const _interstitialEvery = 3;

  /// Call after each level ends. Shows interstitial every N completions.
  Future<void> onLevelEnd() async {
    if (adsRemoved) return;
    _levelCompletionsSinceAd++;
    if (_levelCompletionsSinceAd >= _interstitialEvery) {
      _levelCompletionsSinceAd = 0;
      await _showInterstitial();
    }
  }

  Future<void> _showInterstitial() async {
    if (kDebugMode) {
      debugPrint('MonetizationService [STUB]: showInterstitial');
    }
  }

  // ── IAP ───────────────────────────────────────────────────────────────────

  /// Purchase a product. Returns true if purchase succeeded (stub: always false).
  Future<bool> purchase(String productId) async {
    if (kDebugMode) {
      debugPrint('MonetizationService [STUB]: purchase($productId)');
    }
    return false;
  }

  /// Restore purchases.
  Future<void> restorePurchases() async {
    if (kDebugMode) {
      debugPrint('MonetizationService [STUB]: restorePurchases');
    }
  }
}

// ── Cosmetic system ───────────────────────────────────────────────────────────

/// Available cosmetic items (unlockable via stars or IAP).
class CosmeticSystem {
  static const shipColors = [
    ShipSkin(id: 'default', name: 'Standard', color: 0xFF00B4D8, unlocked: true),
    ShipSkin(id: 'gold', name: 'Gold Rush', color: 0xFFFFD166, starsRequired: 30),
    ShipSkin(id: 'crimson', name: 'Crimson', color: 0xFFE07A5F, starsRequired: 45),
    ShipSkin(id: 'emerald', name: 'Emerald', color: 0xFF4ADE80, starsRequired: 60),
    ShipSkin(id: 'nebula', name: 'Nebula', color: 0xFF9B5DE5, productId: ProductIds.cosmetic1),
  ];

  static const ropeStyles = [
    RopeStyle(id: 'default', name: 'Cable', unlocked: true),
    RopeStyle(id: 'energy', name: 'Energy Beam', starsRequired: 20),
    RopeStyle(id: 'chain', name: 'Chain', starsRequired: 40),
  ];

  static bool isUnlocked(String itemId, int totalStars) {
    for (final skin in shipColors) {
      if (skin.id == itemId) {
        if (skin.unlocked) return true;
        if (skin.starsRequired != null && totalStars >= skin.starsRequired!) return true;
        if (skin.productId != null) {
          return ProgressService.instance
              .getUnlockedAchievements()
              .contains('iap_${skin.productId}');
        }
        return false;
      }
    }
    return false;
  }

  static String get selectedShipSkinId =>
      ProgressService.instance.getUnlockedAchievements()
          .where((id) => id.startsWith('skin_'))
          .map((id) => id.substring(5))
          .firstOrNull ?? 'default';
}

class ShipSkin {
  const ShipSkin({
    required this.id,
    required this.name,
    required this.color,
    this.unlocked = false,
    this.starsRequired,
    this.productId,
  });
  final String id;
  final String name;
  final int color;
  final bool unlocked;
  final int? starsRequired;
  final String? productId;
}

class RopeStyle {
  const RopeStyle({
    required this.id,
    required this.name,
    this.unlocked = false,
    this.starsRequired,
  });
  final String id;
  final String name;
  final bool unlocked;
  final int? starsRequired;
}
