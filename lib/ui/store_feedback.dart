import 'package:flutter/material.dart';

import '../game/services/monetization_service.dart';
import '../game/ship/ship_spec.dart';
import '../game/ship/weapons.dart';
import 'armory.dart' show ammoText;

/// Buys [productId] and tells the player how it went: what was delivered,
/// pending approval, or the store unavailable. Returns true once delivered.
Future<bool> buyWithFeedback(BuildContext context, String productId) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final outcome = await MonetizationService.instance.purchase(productId);
  final message = switch (outcome) {
    BuyOutcome.purchased => _deliveredMessage(productId),
    BuyOutcome.failed => null, // the store sheet said it (or it was cancelled)
    BuyOutcome.pending =>
      'Purchase pending: it unlocks as soon as the store approves it.',
    BuyOutcome.unavailable =>
      "Purchases need an internet connection. Check it and try again.",
  };
  if (message != null) _show(messenger, message);
  return outcome == BuyOutcome.purchased;
}

/// What a successful purchase put in the player's hands.
String _deliveredMessage(String productId) {
  final pack = ProductIds.ammoPacks[productId];
  if (pack != null) {
    final items = [
      for (final e in pack.entries)
        if (weaponById(e.key) case final w?) '${ammoText(w, e.value)} ${w.name}',
    ].join(' · ');
    return '${ProductIds.names[productId] ?? 'Ammo'} delivered to your Armory: '
        '$items';
  }
  if (productId == ProductIds.fleetPass) {
    return 'Fleet Pass active: every ship is in your hangar. Thanks!';
  }
  if (ProductIds.ships.contains(productId)) {
    final ship = shipById(productId.substring('nh_ship_'.length));
    return '${ship.name} delivered to your hangar. Pick it in the Garage or a briefing.';
  }
  if (productId == ProductIds.supporterPack) {
    return 'Thanks for your support! Ads removed, Supporter Livery and '
        '${ProductIds.supporterCoins} 💰 added.';
  }
  return 'Ads removed. Thanks for supporting Narrow Haul!';
}

/// Settings → Restore purchases, with a result message.
Future<void> restoreWithFeedback(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final restored = await MonetizationService.instance.restore();
  _show(
    messenger,
    switch (restored) {
      null => "Couldn't reach the store. Check your connection and try again.",
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
