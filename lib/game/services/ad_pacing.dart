/// Interstitial pacing rules — pure Dart, no SDK, injectable clock.
///
/// An interstitial may only follow a *cleared* level (the player taps Next /
/// Menu on the result screen), never a crash, retry, level start or resume.
/// Every rule below must pass; the numbers follow Unity/AdMob guidance for
/// skill-based level games (late first ad, level + time spacing, session cap).
library;

/// Lifetime deliveries before the first interstitial (tutorial stays clean).
const int kAdMinLifetimeDeliveries = 4;

/// Lifetime flight seconds before the first interstitial.
const int kAdMinLifetimePlaySeconds = 300;

/// Seconds after app launch before an interstitial may show.
const int kAdSessionGraceSeconds = 90;

/// Cleared levels between interstitials.
const int kAdClearsBetween = 3;

/// Seconds between interstitials.
const int kAdInterCooldownSeconds = 180;

/// Seconds after a rewarded ad before an interstitial may show.
const int kAdAfterRewardedSeconds = 240;

/// Interstitials per app session.
const int kAdMaxPerSession = 4;

/// Persisted inputs the rules read (see `ProgressService` ad keys).
class AdPacingInputs {
  const AdPacingInputs({
    required this.adsRemoved,
    required this.lifetimeDeliveries,
    required this.lifetimePlaySeconds,
    required this.clearsSinceInterstitial,
    required this.lastInterstitialMs,
    required this.lastRewardedMs,
  });

  final bool adsRemoved;
  final int lifetimeDeliveries;
  final int lifetimePlaySeconds;
  final int clearsSinceInterstitial;

  /// Epoch ms, 0 = never.
  final int lastInterstitialMs;
  final int lastRewardedMs;
}

/// Session-scoped pacing (one instance per app launch).
class AdPacing {
  AdPacing({required this.sessionStartMs});

  final int sessionStartMs;
  int interstitialsThisSession = 0;

  bool interstitialAllowed(AdPacingInputs s, int nowMs) {
    if (s.adsRemoved) return false;
    if (s.lifetimeDeliveries < kAdMinLifetimeDeliveries) return false;
    if (s.lifetimePlaySeconds < kAdMinLifetimePlaySeconds) return false;
    if (nowMs - sessionStartMs < kAdSessionGraceSeconds * 1000) return false;
    if (s.clearsSinceInterstitial < kAdClearsBetween) return false;
    if (s.lastInterstitialMs > 0 &&
        nowMs - s.lastInterstitialMs < kAdInterCooldownSeconds * 1000) {
      return false;
    }
    if (s.lastRewardedMs > 0 &&
        nowMs - s.lastRewardedMs < kAdAfterRewardedSeconds * 1000) {
      return false;
    }
    return interstitialsThisSession < kAdMaxPerSession;
  }
}

/// First wait before reloading an ad that failed to load (seconds).
const int kAdRetryBaseSeconds = 60;

/// Longest wait between reload attempts, so a phone that stays offline
/// doesn't keep waking the radio.
const int kAdRetryMaxSeconds = 600;

/// Wait before the next load after [failures] failed loads in a row (≥ 1):
/// 60 s, 120 s, 240 s, … capped at [kAdRetryMaxSeconds].
Duration adRetryDelay(int failures) {
  final doublings = (failures - 1).clamp(0, 10);
  final seconds = kAdRetryBaseSeconds << doublings;
  return Duration(seconds: seconds.clamp(0, kAdRetryMaxSeconds));
}
