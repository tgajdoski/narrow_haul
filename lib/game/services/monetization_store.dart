part of 'monetization_service.dart';

/// Purchases, restores and grants ([MonetizationService]'s store half).
extension MonetizationStore on MonetizationService {
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
    // One store sheet at a time: a double tap must not end the first buy.
    // A buy the store never answered stops blocking after two minutes.
    final open = _pendingBuy;
    if (open != null) {
      if (DateTime.now().difference(_pendingSince) < const Duration(minutes: 2)) {
        return BuyOutcome.failed;
      }
      _clearPending();
      open.complete(BuyOutcome.failed);
    }
    final product = _products[productId];
    Analytics.purchaseAttempt(productId);
    if (!_storeAvailable || product == null) {
      Analytics.purchaseResult(productId, 'unavailable');
      // Usually offline: try the store again for the player's next tap.
      _lastRefreshMs = 0;
      refreshIfNeeded();
      return BuyOutcome.unavailable;
    }
    final pending = _pendingBuy = Completer<BuyOutcome>();
    _pendingProductId = productId;
    _pendingSince = DateTime.now();
    bool started;
    try {
      final param = PurchaseParam(productDetails: product);
      // Consumed by hand after the grant (_consumeIfNeeded): the plugin's
      // auto-consume only works in the session that started the purchase.
      started = ProductIds.consumables.contains(productId)
          ? await InAppPurchase.instance.buyConsumable(
              purchaseParam: param,
              autoConsume: false,
            )
          : await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      // e.g. StoreKit still finishing an earlier transaction for this product.
      _log('MonetizationService: buy $productId failed ($e)');
      started = false;
    }
    if (!started) {
      _clearPending();
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
    _userRestore = true;
    try {
      await InAppPurchase.instance.restorePurchases();
      // Restored purchases arrive on the purchase stream just after.
      await Future<void>.delayed(const Duration(seconds: 2));
      return _restoredCount;
    } catch (e) {
      _log('MonetizationService: restore failed ($e)');
      return null;
    } finally {
      _userRestore = false;
    }
  }

  void _clearPending() {
    _pendingBuy = null;
    _pendingProductId = null;
  }

  /// Ends the open purchase if [productId] is the one it waits for. An
  /// error without a product id (some store failures) ends it too.
  void _settle(String productId, BuyOutcome outcome) {
    final pending = _pendingBuy;
    if (pending == null) return;
    if (productId != _pendingProductId && !(productId.isEmpty && outcome == BuyOutcome.failed)) {
      return;
    }
    _clearPending();
    pending.complete(outcome);
  }

  /// Android: a granted ammo pack is consumed so it can be bought again.
  /// Returns false when consuming failed; the purchase then stays owned and
  /// unfinished, comes back on the next start, and is consumed then (the
  /// grant is once per transaction, so nothing is paid twice).
  Future<bool> _consumeIfNeeded(PurchaseDetails purchase) async {
    if (!Platform.isAndroid || !ProductIds.consumables.contains(purchase.productID)) {
      return false;
    }
    try {
      final android =
          InAppPurchase.instance.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final result = await android.consumePurchase(purchase);
      if (result.responseCode == BillingResponse.ok) return true;
      _log('MonetizationService: consume ${purchase.productID} → ${result.responseCode}');
    } catch (e) {
      _log('MonetizationService: consume ${purchase.productID} failed ($e)');
    }
    return false;
  }


  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final quietRestore = purchase.status == PurchaseStatus.restored && !_userRestore;
      Analytics.purchaseResult(
        purchase.productID,
        quietRestore ? 'restored_startup' : purchase.status.name,
      );
      var consumed = false;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (purchase.status == PurchaseStatus.restored) _restoredCount++;
          await grant(purchase.productID, purchaseId: purchase.purchaseID);
          // Consuming also acknowledges the purchase on Play.
          consumed = await _consumeIfNeeded(purchase);
          _settle(purchase.productID, BuyOutcome.purchased);
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          _settle(purchase.productID, BuyOutcome.failed);
        case PurchaseStatus.pending:
          // Waiting on approval (Ask to Buy, slow card): it's granted when
          // the store later reports it purchased.
          _settle(purchase.productID, BuyOutcome.pending);
      }
      final unconsumedPack = Platform.isAndroid &&
          ProductIds.consumables.contains(purchase.productID) &&
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored);
      if (purchase.pendingCompletePurchase && (consumed || !unconsumedPack)) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  /// Applies a purchase. Idempotent: restores never pay coins twice, and an
  /// ammo pack is paid once per store transaction ([purchaseId]) even if the
  /// store re-delivers it. The Full Game removes interstitials for good; an
  /// ammo pack or the Fleet Pass turns them off for [kAdPurchaseGrace].
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
      await _startAdGrace();
      entitlements.value++;
      return;
    }
    if (productId == ProductIds.fleetPass) {
      // Owned through `iap_granted_<id>` (FleetService.owns). A restore
      // doesn't start the ad-free week again.
      if (!_p.isProductGranted(productId)) {
        Analytics.shipUnlock(productId, 'iap');
        await _startAdGrace();
      }
      await _p.setHasPurchased(true);
      await _p.markProductGranted(productId);
      entitlements.value++;
      return;
    }
    // The Full Game (also inside the Supporter Pack): the Expeditions and no
    // interstitials.
    await _p.setHasPurchased(true);
    await _p.setAdsRemoved(true);
    await _p.markProductGranted(ProductIds.fullGame);
    _dropInterstitial();
    if (productId == ProductIds.supporterPack) {
      await _p.unlockCosmetic(kSupporterSkinId);
      if (!_p.isProductGranted(productId)) {
        await _p.addCosmeticCurrency(ProductIds.supporterCoins);
      }
    }
    await _p.markProductGranted(productId);
    entitlements.value++;
  }

  /// [kAdPurchaseGrace] without interstitials from now (extends, never
  /// shortens a running one).
  Future<void> _startAdGrace() async {
    final until = _nowMs + kAdPurchaseGrace.inMilliseconds;
    if (until > _p.adFreeUntilMs) await _p.setAdFreeUntilMs(until);
    _dropInterstitial();
  }

  void _dropInterstitial() {
    unawaited(_interstitial?.dispose());
    _interstitial = null;
  }
}
