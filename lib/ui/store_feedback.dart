import 'package:flutter/material.dart';

import '../game/services/monetization_service.dart';

/// Buys [productId] and tells the player when it didn't simply go through:
/// pending approval, or the store unavailable. Returns true once delivered.
Future<bool> buyWithFeedback(BuildContext context, String productId) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final outcome = await MonetizationService.instance.purchase(productId);
  final message = switch (outcome) {
    BuyOutcome.purchased || BuyOutcome.failed => null, // the store sheet said it
    BuyOutcome.pending =>
      'Purchase pending: it unlocks as soon as the store approves it.',
    BuyOutcome.unavailable =>
      "The store isn't available right now. Please try again later.",
  };
  if (message != null) _show(messenger, message);
  return outcome == BuyOutcome.purchased;
}

/// Settings → Restore purchases, with a result message.
Future<void> restoreWithFeedback(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final restored = await MonetizationService.instance.restore();
  _show(
    messenger,
    switch (restored) {
      null => "Couldn't reach the store. Please try again later.",
      0 => 'No purchases to restore on this account.',
      _ => 'Purchases restored.',
    },
  );
}

void _show(ScaffoldMessengerState? messenger, String message) {
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}
