import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:narrow_haul/game/services/ad_pacing.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

/// Store product ids (create the same ids in App Store Connect / Play Console,
/// both as non-consumables).
class ProductIds {
  /// Removes interstitials. Rewarded ads stay available (opt-in).
  static const removeAds = 'nh_remove_ads';

  /// Remove-ads + exclusive [kSupporterSkinId] livery + [supporterCoins].
  static const supporterPack = 'nh_supporter_pack';

  static const all = {removeAds, supporterPack};
  static const supporterCoins = 500;
}

/// AdMob ad-unit ids. Debug builds always use Google's public test units so
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

  static String get interstitial => kDebugMode
      ? (Platform.isIOS ? _testInterIos : _testInterAndroid)
      : (Platform.isIOS ? _releaseInterIos : _releaseInterAndroid);

  static String get rewarded => kDebugMode
      ? (Platform.isIOS ? _testRewardedIos : _testRewardedAndroid)
      : (Platform.isIOS ? _releaseRewardedIos : _releaseRewardedAndroid);
}

/// Rewarded-ad placements (analytics labels + intent).
class AdPlacement {
  static const continueAfterCrash = 'continue';
  static const doubleCoins = 'double_coins';
  static const cosmeticTrial = 'cosmetic_trial';
}

/// Ads (AdMob + UMP consent) and purchases (in_app_purchase).
///
/// Every call fails safe: no SDK, no consent, no network or no loaded ad means
/// the game just carries on. On platforms without the ad SDK (macOS, tests)
/// debug builds grant rewarded placements instantly so flows stay testable.
class MonetizationService {
  MonetizationService._();
  static final MonetizationService instance = MonetizationService._();

  /// Mobile ad SDK exists only on Android / iOS.
  static bool get _adPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  final AdPacing _pacing = AdPacing(
    sessionStartMs: DateTime.now().millisecondsSinceEpoch,
  );

  bool _adsReady = false;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _showingFullScreen = false;

  /// True when a rewarded ad can be shown right now — gate reward buttons on
  /// it so a player never taps "watch ad" and gets nothing.
  final ValueNotifier<bool> rewardedReady = ValueNotifier(
    kDebugMode && !_adPlatform,
  );

  /// UMP says this user must be offered a "Privacy options" entry point.
  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier(false);

  /// Bumped whenever an entitlement changes (purchase / restore).
  final ValueNotifier<int> entitlements = ValueNotifier(0);

  final Map<String, ProductDetails> _products = {};
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _storeAvailable = false;
  Completer<bool>? _pendingBuy;

  ProgressService get _p => ProgressService.instance;

  bool get adsRemoved => _p.adsRemoved;
  bool get storeAvailable => _storeAvailable;

  /// The store returned this product, so it can actually be bought.
  bool canBuy(String productId) => _products.containsKey(productId);

  /// Localized store price, or a fallback before the store answers.
  String priceOf(String productId) =>
      _products[productId]?.price ??
      (productId == ProductIds.supporterPack ? r'$4.99' : r'$2.99');

  // ── Startup ──────────────────────────────────────────────────────────────

  /// Call once after `runApp` (the consent form needs a live UI). Never
  /// throws; ads stay off if consent or the SDK isn't available.
  Future<void> init() async {
    await _initStore();
    if (!_adPlatform) return;
    try {
      await _gatherConsent();
      if (!await ConsentInformation.instance.canRequestAds()) {
        debugPrint('MonetizationService: consent does not allow ads yet');
        return;
      }
      // Keep ad content in line with the store age rating (9+ / Everyone 10+):
      // no mature ads. Not child-directed — the store audience is 13+.
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.pg),
      );
      await MobileAds.instance.initialize();
      _adsReady = true;
      debugPrint('MonetizationService: ads SDK ready');
      _loadInterstitial();
      _loadRewarded();
    } catch (e) {
      debugPrint('MonetizationService: ads unavailable ($e)');
    }
  }

  /// UMP: refresh consent status every launch and show the form when the
  /// user is in a regulated region (GDPR first; the IDFA explainer + ATT
  /// prompt on iOS come from the "IDFA message" configured in AdMob).
  Future<void> _gatherConsent() async {
    final updated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      updated.complete,
      (error) {
        debugPrint(
          'MonetizationService: consent update failed ${error.message}',
        );
        updated.complete();
      },
    );
    await updated.future;
    final shown = Completer<void>();
    await ConsentForm.loadAndShowConsentFormIfRequired((_) => shown.complete());
    await shown.future;
    await _refreshPrivacyOptions();
  }

  Future<void> _refreshPrivacyOptions() async {
    final status = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    privacyOptionsRequired.value =
        status == PrivacyOptionsRequirementStatus.required;
  }

  /// Settings → "Privacy options": lets the user change or withdraw consent.
  Future<void> showPrivacyOptions() async {
    if (!_adPlatform) return;
    final done = Completer<void>();
    await ConsentForm.showPrivacyOptionsForm((_) => done.complete());
    await done.future;
    await _refreshPrivacyOptions();
  }

  // ── Interstitials ────────────────────────────────────────────────────────

  /// A level was cleared (crashes and retries never count).
  Future<void> recordLevelClear() async =>
      _p.setAdClearsSinceInterstitial(_p.adClearsSinceInterstitial + 1);

  bool get _interstitialAllowed => _pacing.interstitialAllowed(
    AdPacingInputs(
      adsRemoved: _p.adsRemoved || _p.hasPurchased,
      lifetimeDeliveries: _p.getStat(ProgressService.statDeliveries),
      lifetimePlaySeconds: _p.getStat(ProgressService.statPlaytimeSeconds),
      clearsSinceInterstitial: _p.adClearsSinceInterstitial,
      lastInterstitialMs: _p.lastInterstitialMs,
      lastRewardedMs: _p.lastRewardedMs,
    ),
    DateTime.now().millisecondsSinceEpoch,
  );

  /// Shows an interstitial if pacing allows and one is loaded; completes when
  /// it is dismissed (or immediately). Only call from the result screen.
  /// Returns whether an ad was shown.
  Future<bool> maybeShowInterstitial() async {
    final ad = _interstitial;
    if (kDebugMode) _logPacing(loaded: ad != null);
    if (ad == null || _showingFullScreen || !_interstitialAllowed) return false;
    _interstitial = null;
    final done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        _pacing.interstitialsThisSession++;
        _p.setLastInterstitialMs(DateTime.now().millisecondsSinceEpoch);
        _p.setAdClearsSinceInterstitial(0);
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!done.isCompleted) done.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!done.isCompleted) done.complete(false);
      },
    );
    _showingFullScreen = true;
    try {
      await ad.show();
      return await done.future;
    } finally {
      _showingFullScreen = false;
      _loadInterstitial();
    }
  }

  /// Debug only: why the result screen did or didn't show an interstitial.
  void _logPacing({required bool loaded}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    String ago(int ms) => ms == 0 ? 'never' : '${(now - ms) ~/ 1000}s ago';
    debugPrint(
      'MonetizationService: interstitial check → '
      'allowed=$_interstitialAllowed loaded=$loaded | '
      'deliveries=${_p.getStat(ProgressService.statDeliveries)}/$kAdMinLifetimeDeliveries '
      'flown=${_p.getStat(ProgressService.statPlaytimeSeconds)}s/${kAdMinLifetimePlaySeconds}s '
      'session=${(now - _pacing.sessionStartMs) ~/ 1000}s/${kAdSessionGraceSeconds}s '
      'clears=${_p.adClearsSinceInterstitial}/$kAdClearsBetween '
      'lastInter=${ago(_p.lastInterstitialMs)} lastRewarded=${ago(_p.lastRewardedMs)} '
      'shown=${_pacing.interstitialsThisSession}/$kAdMaxPerSession '
      'adsRemoved=${_p.adsRemoved}',
    );
  }

  void _loadInterstitial() {
    if (!_adsReady || adsRemoved || AdIds.interstitial.isEmpty) return;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('MonetizationService: interstitial loaded');
          _interstitial = ad;
        },
        onAdFailedToLoad: (e) =>
            debugPrint('MonetizationService: interstitial load failed $e'),
      ),
    );
  }

  // ── Rewarded ─────────────────────────────────────────────────────────────

  /// Shows a rewarded ad; calls [onReward] only if the user earned it.
  /// Returns whether the reward was granted.
  Future<bool> showRewarded(
    String placement, {
    required VoidCallback onReward,
  }) async {
    if (!_adPlatform) {
      // Desktop / tests: debug grants instantly, release has no ads.
      if (!kDebugMode) return false;
      debugPrint('MonetizationService [debug]: rewarded "$placement" granted');
      await _p.setLastRewardedMs(DateTime.now().millisecondsSinceEpoch);
      onReward();
      return true;
    }
    final ad = _rewarded;
    if (ad == null || _showingFullScreen) return false;
    _rewarded = null;
    rewardedReady.value = false;
    var earned = false;
    final done = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!done.isCompleted) done.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!done.isCompleted) done.complete();
      },
    );
    _showingFullScreen = true;
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
      await done.future;
    } finally {
      _showingFullScreen = false;
      _loadRewarded();
    }
    if (earned) {
      await _p.setLastRewardedMs(DateTime.now().millisecondsSinceEpoch);
      onReward();
    }
    return earned;
  }

  void _loadRewarded() {
    if (!_adsReady || AdIds.rewarded.isEmpty) return;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('MonetizationService: rewarded loaded');
          _rewarded = ad;
          rewardedReady.value = true;
        },
        onAdFailedToLoad: (e) {
          debugPrint('MonetizationService: rewarded load failed $e');
          // Retry later rather than hammering a no-fill network.
          Future.delayed(const Duration(seconds: 60), _loadRewarded);
        },
      ),
    );
  }

  // ── Purchases ────────────────────────────────────────────────────────────

  Future<void> _initStore() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return;
    }
    try {
      final iap = InAppPurchase.instance;
      _storeAvailable = await iap.isAvailable();
      if (!_storeAvailable) {
        debugPrint('MonetizationService: store not available');
        return;
      }
      _purchaseSub = iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) => debugPrint('MonetizationService: store $e'),
      );
      final resp = await iap.queryProductDetails(ProductIds.all);
      for (final p in resp.productDetails) {
        _products[p.id] = p;
      }
      debugPrint(
        'MonetizationService: store products ${_products.keys.toList()} '
        'missing ${resp.notFoundIDs}${resp.error == null ? '' : ' error ${resp.error}'}',
      );
      // Android restores silently; on iOS a restore can prompt for the Apple
      // ID, so there it stays behind the Settings button.
      if (Platform.isAndroid) await iap.restorePurchases();
    } catch (e) {
      debugPrint('MonetizationService: store unavailable ($e)');
      _storeAvailable = false;
    }
  }

  /// Starts a purchase; completes true once it is delivered.
  Future<bool> buy(String productId) async {
    final product = _products[productId];
    if (!_storeAvailable || product == null) return false;
    _pendingBuy?.complete(false);
    final pending = _pendingBuy = Completer<bool>();
    final started = await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    if (!started) {
      _pendingBuy = null;
      return false;
    }
    return pending.future;
  }

  /// Settings → "Restore purchases" (required by Apple).
  Future<void> restore() async {
    if (!_storeAvailable) return;
    await InAppPurchase.instance.restorePurchases();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _grant(purchase.productID);
          _pendingBuy?.complete(true);
          _pendingBuy = null;
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          _pendingBuy?.complete(false);
          _pendingBuy = null;
        case PurchaseStatus.pending:
          break;
      }
      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  /// Applies an entitlement. Idempotent: restores never pay coins twice.
  Future<void> _grant(String productId) async {
    if (!ProductIds.all.contains(productId)) return;
    await _p.setHasPurchased(true);
    await _p.setAdsRemoved(true);
    _interstitial?.dispose();
    _interstitial = null;
    if (productId == ProductIds.supporterPack) {
      await _p.unlockCosmetic(kSupporterSkinId);
      if (!_p.isProductGranted(productId)) {
        await _p.addCosmeticCurrency(ProductIds.supporterCoins);
      }
    }
    await _p.markProductGranted(productId);
    entitlements.value++;
  }

  void dispose() => _purchaseSub?.cancel();
}
