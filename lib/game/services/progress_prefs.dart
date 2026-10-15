part of 'progress_service.dart';

/// A value stored under [key]; reads [fallback] when it's missing or of the
/// wrong type (see [ProgressService._read]).
final class _Pref<T extends Object> {
  const _Pref(this.key, this.fallback);
  final String key;
  final T fallback;
}

/// Keys whose pref is read with no default (null = never set).
abstract final class _Keys {
  static const tiltSteer = 'tilt_steer';
  static const steerMode = 'steer_mode';
  static const cameraMode = 'camera_mode';
  static const cameraZoom = 'camera_zoom';
  static const tiltSensitivity = 'tilt_sensitivity';
  static const tiltMode = 'tilt_mode';
  static const remindersEnabled = 'reminders_enabled';
  static const reminderHours = 'reminder_hours';
  static const reminderLastTried = 'reminder_last_tried';
  static const shipPreferred = 'ship_preferred';
  static const achievements = 'achievements';
  static const garageSeen = 'garage_seen';
  static const dailyLastDate = 'daily_last_date';
  static const dailyStreak = 'daily_streak';
  static const saveV2 = 'save_v2';
}

// Settings and flags with a default.
const _soundEnabled = _Pref('sound_enabled', true);
const _musicEnabled = _Pref('music_enabled', true);
const _hapticsEnabled = _Pref('haptics_enabled', true);
const _leftHanded = _Pref('left_handed', false);
const _minimapEnabled = _Pref('minimap_enabled', true);
const _creditsSeen = _Pref('credits_seen', false);
const _scrapeHintSeen = _Pref('scrape_hint_seen', false);
const _fireHintSeen = _Pref('fire_hint_seen', false);
const _controlsHintSeen = _Pref('controls_hint_seen', false);
const _cameraTipSeen = _Pref('camera_tip_seen', false);
const _canisterHintSeen = _Pref('canister_hint_seen', false);
const _noseDownClean = _Pref('nose_down_clean', 0);
const _reminderAsks = _Pref('reminder_asks', 0);
const _reminderAskMs = _Pref('reminder_ask_ms', 0);
const _xpMigrated = _Pref('save_v3', false);

// Ads & purchases.
const _adsRemoved = _Pref('ads_removed', false);
const _adFreeUntil = _Pref('ads_free_until', 0);
const _anyPurchase = _Pref('iap_any_purchase', false);
const _clearsSinceInter = _Pref('ads_clears_since_inter', 0);
const _lastInterMs = _Pref('ads_last_inter_ms', 0);
const _lastRewardedMs = _Pref('ads_last_rewarded_ms', 0);
const _removeAdsOfferMs = _Pref('ads_offer_ms', 0);

// Career totals.
const _noRetryStreak = _Pref('no_retry_streak', 0);
const _totalFuelSpent = _Pref('total_fuel_spent', 0.0);
const _currency = _Pref('cosmetic_currency', 0);
const _xpTotal = _Pref('xp_total', 0);
