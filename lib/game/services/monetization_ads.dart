part of 'monetization_service.dart';

/// Interstitials and rewarded ads ([MonetizationService]'s ad half).
extension MonetizationAds on MonetizationService {
  // ── Interstitials ────────────────────────────────────────────────────────

  /// A level was cleared (crashes and retries never count).
  Future<void> recordLevelClear() async =>
      _p.setAdClearsSinceInterstitial(_p.adClearsSinceInterstitial + 1);

  bool get _interstitialAllowed => _pacing.interstitialAllowed(
    AdPacingInputs(
      adsRemoved: _p.adsRemoved,
      adFreeUntilMs: _p.adFreeUntilMs,
      lifetimeDeliveries: _p.getStat(ProgressService.statDeliveries),
      lifetimePlaySeconds: _p.getStat(ProgressService.statPlaytimeSeconds),
      clearsSinceInterstitial: _p.adClearsSinceInterstitial,
      lastInterstitialMs: _p.lastInterstitialMs,
      lastRewardedMs: _p.lastRewardedMs,
    ),
    _nowMs,
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
      AudioService.setBuzz(false);
      AudioService.setSpores(false);
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
      'adsRemoved=${_p.adsRemoved} '
      'adFreeUntil=${adFreeUntil?.toIso8601String() ?? 'none'}',
    );
  }

  void _loadInterstitial() {
    if (!_adsReady || interstitialsOff || AdIds.interstitial.isEmpty) return;
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
    if (!MonetizationService._adPlatform) {
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
}
