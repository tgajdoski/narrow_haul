import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:narrow_haul/game/services/analytics_service.dart';
import 'package:narrow_haul/game/services/progress_service.dart';

/// Lifetime deliveries before the first ask: the pilot has flown enough to
/// have an opinion.
const kReviewMinDeliveries = 8;

/// At most this many asks ever, this far apart. The stores cap it too (iOS
/// shows the sheet at most 3 times a year), so a wasted ask is a lost one.
const kReviewMaxAsks = 3;
const kReviewGap = Duration(days: 60);

/// Whether the result screen may ask for a store rating: only on a happy
/// moment (a 3★ delivery), never over another card (rank-up, story outro),
/// never in a demo.
@visibleForTesting
bool shouldAskForReview({
  required int stars,
  required int lifetimeDeliveries,
  required int asksSoFar,
  required int lastAskMs,
  required int nowMs,
  required bool otherCardShowing,
}) {
  if (stars < 3 || otherCardShowing) return false;
  if (lifetimeDeliveries < kReviewMinDeliveries) return false;
  if (asksSoFar >= kReviewMaxAsks) return false;
  return lastAskMs == 0 || nowMs - lastAskMs >= kReviewGap.inMilliseconds;
}

/// Asks the store for its native rating sheet when [shouldAskForReview]
/// allows. The sheet may not show (the store decides); the ask is counted
/// either way, so the game never nags.
abstract final class ReviewAsk {
  static Future<void> maybeAsk({
    required int stars,
    required bool otherCardShowing,
    required String levelId,
  }) async {
    final p = ProgressService.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!shouldAskForReview(
      stars: stars,
      lifetimeDeliveries: p.getStat(ProgressService.statDeliveries),
      asksSoFar: p.reviewAsks,
      lastAskMs: p.reviewAskMs,
      nowMs: now,
      otherCardShowing: otherCardShowing,
    )) {
      return;
    }
    if (kIsWeb || !(defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android)) {
      return;
    }
    try {
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      await p.setReviewAsks(p.reviewAsks + 1);
      await p.setReviewAskMs(now);
      Analytics.reviewAsked(levelId, p.reviewAsks);
      await review.requestReview();
    } catch (_) {}
  }
}
