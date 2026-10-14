part of 'progress_service.dart';

/// Ads, purchases and carried weapon ammo (see MonetizationService /
/// AdPacing). `iap_*`, `ads_*` and `ammo_*` keys survive a progress reset.
extension ProgressAds on ProgressService {
  /// No interstitials for good: the Full Game (on its own or in the
  /// Supporter Pack).
  bool get adsRemoved => _read(_adsRemoved);
  Future<void> setAdsRemoved(bool v) => _write(_adsRemoved, v);

  /// Epoch ms until which interstitials stay off after any other purchase
  /// (ammo pack, Fleet Pass; `kAdPurchaseGrace`). 0 = none.
  int get adFreeUntilMs => _read(_adFreeUntil);
  Future<void> setAdFreeUntilMs(int v) => _write(_adFreeUntil, v);

  /// Any IAP ever made (ad pacing reads [adsRemoved] / [adFreeUntilMs]).
  bool get hasPurchased => _read(_anyPurchase);
  Future<void> setHasPurchased(bool v) => _write(_anyPurchase, v);

  /// Non-consumable product ids already granted (supporter pack payout once).
  bool isProductGranted(String id) => _bool('iap_granted_$id') ?? false;
  Future<void> markProductGranted(String id) async =>
      _prefs.setBool('iap_granted_$id', true);

  /// The Full Game is owned (on its own or in the Supporter Pack): every
  /// Expedition opens.
  bool get hasFullGame => isProductGranted(ProductIds.fullGame);

  /// A consumable purchase (store transaction id) was already paid out.
  bool isTransactionGranted(String purchaseId) =>
      _bool('iap_tx_$purchaseId') ?? false;
  Future<void> markTransactionGranted(String purchaseId) async =>
      _prefs.setBool('iap_tx_$purchaseId', true);

  /// Dev only: forgets every purchase on this device (sandbox test buys), so
  /// ads show again. A store restore grants them back.
  Future<void> debugClearPurchases() async {
    for (final key in _prefs.getKeys().toList()) {
      if (key == _adsRemoved.key ||
          key == _adFreeUntil.key ||
          key.startsWith('iap_')) {
        await _prefs.remove(key);
      }
    }
  }

  int get adClearsSinceInterstitial => _read(_clearsSinceInter);
  Future<void> setAdClearsSinceInterstitial(int v) =>
      _write(_clearsSinceInter, v);

  /// Epoch ms of the last interstitial / rewarded ad (0 = never).
  int get lastInterstitialMs => _read(_lastInterMs);
  Future<void> setLastInterstitialMs(int v) => _write(_lastInterMs, v);

  int get lastRewardedMs => _read(_lastRewardedMs);
  Future<void> setLastRewardedMs(int v) => _write(_lastRewardedMs, v);

  /// Epoch ms the remove-ads offer was last shown on the result screen.
  int get removeAdsOfferMs => _read(_removeAdsOfferMs);
  Future<void> setRemoveAdsOfferMs(int v) => _write(_removeAdsOfferMs, v);

  /// Carried units of a special weapon (charges, bombs, laser seconds).
  /// Kept across a progress reset: most of it was paid for.
  double getAmmo(String weaponId) =>
      math.max(0, _double('ammo_$weaponId') ?? 0);

  Future<void> addAmmo(String weaponId, double units) async {
    final next = math.max(0.0, getAmmo(weaponId) + units);
    await _prefs.setDouble('ammo_$weaponId', next);
  }
}
