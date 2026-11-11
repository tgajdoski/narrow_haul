import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show BillingResponse;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:narrow_haul/game/physics_constants.dart' show kStoreCapture;
import 'package:narrow_haul/game/services/ad_pacing.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/game/services/cosmetics_service.dart';
import 'package:narrow_haul/game/services/music_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';
import 'package:narrow_haul/game/services/monetization_ids.dart';

export 'package:narrow_haul/game/services/monetization_ids.dart';

part 'monetization_ads.dart';
part 'monetization_store.dart';

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

  /// The product [_pendingBuy] waits for: other products' events (a
  /// restore on start, a stale cancel) never settle it.
  String? _pendingProductId;
  DateTime _pendingSince = DateTime.fromMillisecondsSinceEpoch(0);

  /// The player tapped Restore; restores outside it (Android checks owned
  /// items on every start) are logged as `restored_startup`.
  bool _userRestore = false;

  int _restoredCount = 0;

  ProgressService get _p => ProgressService.instance;

  bool get adsRemoved => _p.adsRemoved;

  /// No interstitials right now: the Full Game, or a purchase's
  /// [kAdPurchaseGrace] still running.
  bool get interstitialsOff => _p.adsRemoved || _nowMs < _p.adFreeUntilMs;

  /// When a purchase's ad-free week ends, while it runs (else null). The
  /// Full Game shows as [adsRemoved] instead.
  DateTime? get adFreeUntil => !_p.adsRemoved && _nowMs < _p.adFreeUntilMs
      ? DateTime.fromMillisecondsSinceEpoch(_p.adFreeUntilMs)
      : null;

  int get _nowMs => ProgressService.clock().millisecondsSinceEpoch;
  bool get storeAvailable => _storeAvailable;

  /// The store returned this product, so it can actually be bought.
  /// Store screenshot builds (`STORE_CAPTURE`) show every product's buy
  /// row with its fallback price, for the IAP review screenshots.
  bool canBuy(String productId) =>
      _products.containsKey(productId) ||
      (kStoreCapture && ProductIds.all.contains(productId));

  /// Localized store price, or a fallback before the store answers.
  String priceOf(String productId) =>
      _products[productId]?.price ??
      switch (productId) {
        ProductIds.supporterPack => r'$6.99',
        ProductIds.fullGame => r'$4.99',
        ProductIds.fleetPass || ProductIds.arsenalCrate => r'$2.99',
        ProductIds.demolitionKit => r'$0.99',
        _ => r'$2.99',
      };

  // ── Startup ──────────────────────────────────────────────────────────────

  /// Call once after `runApp` (the consent form needs a live UI). Never
  /// throws; ads stay off if consent or the SDK isn't available. Store and
  /// ads set up in parallel, so a slow store never delays the first ad.
  bool _initStarted = false;

  Future<void> init() async {
    _initStarted = true;
    _lastRefreshMs = DateTime.now().millisecondsSinceEpoch;
    if (!_adPlatform) _settlePrivacyPrompts();
    await Future.wait([_initStore(), _initAds()]);
  }

  /// Completes once the first launch's consent form and iOS tracking prompt
  /// are over (or were never needed). Game Center waits for it: its sign-in
  /// sheet on screen makes iOS drop the tracking request without showing it
  /// (App Review rejected 1.0.1 under 2.1 for a missing ATT prompt).
  Future<void> get privacyPromptsDone => _privacyPrompts.future;
  final Completer<void> _privacyPrompts = Completer<void>();

  void _settlePrivacyPrompts() {
    if (!_privacyPrompts.isCompleted) _privacyPrompts.complete();
  }

  /// Picks up whatever failed while offline: ads that never set up, store
  /// products that never arrived, ads waiting out a retry backoff. Called on
  /// app resume and when the hangar or a shop screen opens. Throttled and
  /// fail-safe; offline it does nothing visible.
  void refreshIfNeeded() {
    // Nothing before init (the first launch holds it until the credits end).
    if (!_initStarted) return;
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
      await _requestTracking();
      _settlePrivacyPrompts();
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
      _settlePrivacyPrompts();
    }
  }

  /// iOS: asks for tracking (ATT) ourselves when UMP's IDFA message didn't,
  /// before the ads SDK starts. Only while the status is undetermined, so
  /// it's asked once ever. iOS ignores the request unless the app is active
  /// and no other sheet is still on screen, hence the wait and the beat.
  Future<void> _requestTracking() async {
    if (!Platform.isIOS) return;
    try {
      if (await AppTrackingTransparency.trackingAuthorizationStatus !=
          TrackingStatus.notDetermined) {
        return;
      }
      await _whenAppActive();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final status =
          await AppTrackingTransparency.requestTrackingAuthorization();
      _log('MonetizationService: tracking $status');
    } catch (e) {
      _log('MonetizationService: tracking request failed ($e)');
    }
  }

  Future<void> _whenAppActive() async {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    final active = Completer<void>();
    final listener = AppLifecycleListener(
      onResume: () {
        if (!active.isCompleted) active.complete();
      },
    );
    await active.future;
    listener.dispose();
  }

  /// UMP: refresh consent status every launch and show the form when the
  /// user is in a regulated region (GDPR first; on iOS the "IDFA message"
  /// configured in AdMob may show the ATT prompt, else [_requestTracking]).
  Future<void> _gatherConsent() async {
    final updated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      updated.complete,
      (error) {
        _log('MonetizationService: consent update failed ${error.message}');
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

  void dispose() => _purchaseSub?.cancel();
}

/// Ad / purchase decisions are logged in debug and profile builds (see
/// CLAUDE.md, "Debugging ads"); release builds stay quiet.
void _log(String message) {
  if (!kReleaseMode) debugPrint(message);
}
