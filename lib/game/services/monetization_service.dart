import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:narrow_haul/game/services/ad_pacing.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/music_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/ship/weapons.dart';

/// Store product ids (create the same ids in App Store Connect / Play Console:
/// [removeAds] and [supporterPack] as non-consumables, the [ammoPacks] as
/// consumables).
class ProductIds {
  /// Removes interstitials. Rewarded ads stay available (opt-in).
  static const removeAds = 'nh_remove_ads';

  /// Remove-ads + exclusive [kSupporterSkinId] livery + [supporterCoins].
  static const supporterPack = 'nh_supporter_pack';

  /// Weapon ammo, bought again and again (consumables).
  static const demolitionKit = 'nh_demo_kit';
  static const arsenalCrate = 'nh_arsenal_crate';

  static const nonConsumables = {removeAds, supporterPack};
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
  bool _adsInitInFlight = false;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _showingFullScreen = false;

  // Loads in flight and failures in a row (for the retry backoff).
  bool _interstitialLoading = false;
  bool _rewardedLoading = false;
  int _interstitialFailures = 0;
  int _rewardedFailures = 0;
  Timer? _interstitialRetry;
  Timer? _rewardedRetry;

  /// Last [refreshIfNeeded] run, so screen changes don't spam the SDKs.
  int _lastRefreshMs = 0;

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
  bool _storeInitInFlight = false;
  bool _restoredAtStartup = false;
  Completer<BuyOutcome>? _pendingBuy;

  ProgressService get _p => ProgressService.instance;

  bool get adsRemoved => _p.adsRemoved;
  bool get storeAvailable => _storeAvailable;

  /// The store returned this product, so it can actually be bought.
  bool canBuy(String productId) => _products.containsKey(productId);

  /// Localized store price, or a fallback before the store answers.
  String priceOf(String productId) =>
      _products[productId]?.price ??
      switch (productId) {
        ProductIds.supporterPack || ProductIds.arsenalCrate => r'$4.99',
        ProductIds.demolitionKit => r'$1.99',
        _ => r'$2.99',
      };

  // ── Startup ──────────────────────────────────────────────────────────────

  /// Call once after `runApp` (the consent form needs a live UI). Never
  /// throws; ads stay off if consent or the SDK isn't available. Store and
  /// ads set up in parallel, so a slow store never delays the first ad.
  Future<void> init() async {
    _lastRefreshMs = DateTime.now().millisecondsSinceEpoch;
    await Future.wait([_initStore(), _initAds()]);
  }

  /// Picks up whatever failed while offline: ads that never set up, store
  /// products that never arrived, ads waiting out a retry backoff. Called on
  /// app resume and when the hangar or a shop screen opens. Throttled and
  /// fail-safe; offline it does nothing visible.
  void refreshIfNeeded() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRefreshMs < 30000) return;
    _lastRefreshMs = now;
    if (_adPlatform && !_adsReady) {
      _initAds();
    } else if (_adsReady) {
      if (_interstitial == null && !_interstitialLoading) _loadInterstitial();
      if (_rewarded == null && !_rewardedLoading) _loadRewarded();
    }
    if (!_storeAvailable || _products.isEmpty) _initStore();
  }

  Future<void> _initAds() async {
    if (!_adPlatform || _adsReady || _adsInitInFlight) return;
    _adsInitInFlight = true;
    try {
      await _gatherConsent();
      if (!await ConsentInformation.instance.canRequestAds()) {
        _log('MonetizationService: consent does not allow ads yet');
        return;
      }
      // Keep ad content in line with the store age rating (9+ / Everyone 10+):
      // no mature ads. Not child-directed — the store audience is 13+.
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.pg),
      );
      await MobileAds.instance.initialize();
      _adsReady = true;
      _log('MonetizationService: ads SDK ready');
      _loadInterstitial();
      _loadRewarded();
    } catch (e) {
      _log('MonetizationService: ads unavailable ($e)');
    } finally {
      _adsInitInFlight = false;
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
        _log(
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
    if (!kReleaseMode) _logPacing(loaded: ad != null);
    if (ad == null || _showingFullScreen || !_interstitialAllowed) return false;
    _interstitial = null;
    final done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        _pacing.interstitialsThisSession++;
        Analytics.interstitialShown();
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
    _setShowingFullScreen(true);
    try {
      await ad.show();
      return await done.future;
    } finally {
      _setShowingFullScreen(false);
      _loadInterstitial();
    }
  }

  /// Full-screen ads play their own audio: the music pauses and the engine
  /// loop and alarm stop while one is up.
  void _setShowingFullScreen(bool showing) {
    _showingFullScreen = showing;
    if (showing) {
      AudioService.stopEngine();
      AudioService.setAlarm(false);
    }
    MusicService.setAdShowing(showing);
  }

  /// Debug only: why the result screen did or didn't show an interstitial.
  void _logPacing({required bool loaded}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    String ago(int ms) => ms == 0 ? 'never' : '${(now - ms) ~/ 1000}s ago';
    _log(
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
    if (_interstitialLoading) return;
    _interstitialRetry?.cancel();
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _log('MonetizationService: interstitial loaded');
          _interstitialLoading = false;
          _interstitialFailures = 0;
          _interstitial = ad;
        },
        onAdFailedToLoad: (e) {
          _interstitialLoading = false;
          final wait = adRetryDelay(++_interstitialFailures);
          _log(
            'MonetizationService: interstitial load failed $e, '
            'retry in ${wait.inSeconds}s',
          );
          // Retry with backoff (offline, no fill); refreshIfNeeded cuts the
          // wait short once the player is back online.
          _interstitialRetry = Timer(wait, _loadInterstitial);
        },
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
      _log('MonetizationService [debug]: rewarded "$placement" granted');
      await _p.setLastRewardedMs(DateTime.now().millisecondsSinceEpoch);
      Analytics.rewardedAd(placement, earned: true);
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
    _setShowingFullScreen(true);
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
      await done.future;
    } finally {
      _setShowingFullScreen(false);
      _loadRewarded();
    }
    Analytics.rewardedAd(placement, earned: earned);
    if (earned) {
      await _p.setLastRewardedMs(DateTime.now().millisecondsSinceEpoch);
      onReward();
    }
    return earned;
  }

  void _loadRewarded() {
    if (!_adsReady || AdIds.rewarded.isEmpty) return;
    if (_rewardedLoading) return;
    _rewardedRetry?.cancel();
    _rewardedLoading = true;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _log('MonetizationService: rewarded loaded');
          _rewardedLoading = false;
          _rewardedFailures = 0;
          _rewarded = ad;
          rewardedReady.value = true;
        },
        onAdFailedToLoad: (e) {
          _rewardedLoading = false;
          final wait = adRetryDelay(++_rewardedFailures);
          _log(
            'MonetizationService: rewarded load failed $e, '
            'retry in ${wait.inSeconds}s',
          );
          _rewardedRetry = Timer(wait, _loadRewarded);
        },
      ),
    );
  }

  // ── Purchases ────────────────────────────────────────────────────────────

  Future<void> _initStore() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return;
    }
    if (_storeInitInFlight) return;
    _storeInitInFlight = true;
    try {
      final iap = InAppPurchase.instance;
      _storeAvailable = await iap.isAvailable();
      if (!_storeAvailable) {
        _log('MonetizationService: store not available');
        return;
      }
      _purchaseSub ??= iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) => _log('MonetizationService: store $e'),
      );
      final resp = await iap.queryProductDetails(ProductIds.all);
      for (final p in resp.productDetails) {
        _products[p.id] = p;
      }
      _log(
        'MonetizationService: store products ${_products.keys.toList()} '
        'missing ${resp.notFoundIDs}${resp.error == null ? '' : ' error ${resp.error}'}',
      );
      // Android restores silently; on iOS a restore can prompt for the Apple
      // ID, so there it stays behind the Settings button.
      if (Platform.isAndroid && !_restoredAtStartup) {
        _restoredAtStartup = true;
        await iap.restorePurchases();
      }
    } catch (e) {
      _log('MonetizationService: store unavailable ($e)');
      _storeAvailable = false;
    } finally {
      _storeInitInFlight = false;
    }
  }

  /// Starts a purchase and reports how it ended, so the UI can explain a
  /// pending (e.g. Ask to Buy) or unavailable purchase.
  Future<BuyOutcome> purchase(String productId) async {
    final product = _products[productId];
    Analytics.purchaseAttempt(productId);
    if (!_storeAvailable || product == null) {
      Analytics.purchaseResult(productId, 'unavailable');
      // Usually offline: try the store again for the player's next tap.
      _lastRefreshMs = 0;
      refreshIfNeeded();
      return BuyOutcome.unavailable;
    }
    _pendingBuy?.complete(BuyOutcome.failed);
    final pending = _pendingBuy = Completer<BuyOutcome>();
    bool started;
    try {
      final param = PurchaseParam(productDetails: product);
      started = ProductIds.consumables.contains(productId)
          ? await InAppPurchase.instance.buyConsumable(purchaseParam: param)
          : await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      // e.g. StoreKit still finishing an earlier transaction for this product.
      _log('MonetizationService: buy $productId failed ($e)');
      started = false;
    }
    if (!started) {
      _pendingBuy = null;
      Analytics.purchaseResult(productId, 'not_started');
      return BuyOutcome.failed;
    }
    return pending.future;
  }

  /// Settings → "Restore purchases" (required by Apple). Returns how many
  /// purchases came back, or null if the store couldn't be reached.
  Future<int?> restore() async {
    if (!_storeAvailable) {
      _lastRefreshMs = 0;
      refreshIfNeeded();
      return null;
    }
    _restoredCount = 0;
    try {
      await InAppPurchase.instance.restorePurchases();
      // Restored purchases arrive on the purchase stream just after.
      await Future<void>.delayed(const Duration(seconds: 2));
      return _restoredCount;
    } catch (e) {
      _log('MonetizationService: restore failed ($e)');
      return null;
    }
  }

  int _restoredCount = 0;

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      Analytics.purchaseResult(purchase.productID, purchase.status.name);
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (purchase.status == PurchaseStatus.restored) _restoredCount++;
          await grant(purchase.productID, purchaseId: purchase.purchaseID);
          _pendingBuy?.complete(BuyOutcome.purchased);
          _pendingBuy = null;
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          _pendingBuy?.complete(BuyOutcome.failed);
          _pendingBuy = null;
        case PurchaseStatus.pending:
          // Waiting on approval (Ask to Buy, slow card): it's granted when
          // the store later reports it purchased.
          _pendingBuy?.complete(BuyOutcome.pending);
          _pendingBuy = null;
      }
      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  /// Applies a purchase. Idempotent: restores never pay coins twice, and an
  /// ammo pack is paid once per store transaction ([purchaseId]) even if the
  /// store re-delivers it. Ammo packs never remove ads.
  @visibleForTesting
  Future<void> grant(String productId, {String? purchaseId}) async {
    if (!ProductIds.all.contains(productId)) return;
    final pack = ProductIds.ammoPacks[productId];
    if (pack != null) {
      if (purchaseId != null && _p.isTransactionGranted(purchaseId)) return;
      for (final e in pack.entries) {
        await _p.addAmmo(e.key, e.value);
      }
      if (purchaseId != null) await _p.markTransactionGranted(purchaseId);
      await _p.setHasPurchased(true);
      entitlements.value++;
      return;
    }
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

/// Ad / purchase decisions are logged in debug and profile builds (see
/// CLAUDE.md, "Debugging ads"); release builds stay quiet.
void _log(String message) {
  if (!kReleaseMode) debugPrint(message);
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
