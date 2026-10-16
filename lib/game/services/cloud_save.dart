import 'dart:convert';
import 'dart:math' as math;

/// Cloud save: which save keys travel between devices and how two copies
/// merge. Pure Dart (no plugin, no prefs), so the rules are unit-tested.
///
/// Nothing is ever lost: stars, times, XP and stats keep the best value,
/// owned things are unioned. Coins and carried ammo go up *and* down, so
/// they merge by what changed on each side since the last sync ([base]),
/// which keeps a purchase made on one device from being refunded by the
/// other's older balance.
///
/// Device-only keys never travel: settings (sound, steering, tilt…),
/// purchases (`iap_*`, `ads_*`: the store restores those), ad pacing,
/// reminders, today's contracts and replay-XP cap, the hint counters.
class CloudSave {
  const CloudSave._();

  /// Snapshot format; a newer one from a later app version is ignored.
  static const version = 1;

  /// The saved game's name on Play Games / Game Center.
  static const slot = 'narrow_haul_career';

  /// Keys whose numbers merge by their change since the last sync.
  static bool _isWallet(String key) =>
      key == 'cosmetic_currency' || key.startsWith('ammo_');

  static bool _isMax(String key) =>
      key.startsWith('stars2_') ||
      key.startsWith('fuel2_') ||
      key == 'xp_total' ||
      key == 'total_fuel_spent' ||
      key.startsWith('stat_');

  static bool _isMin(String key) =>
      key.startsWith('time2_') || key.startsWith('daily_time_');

  /// Flags that only ever turn on.
  static bool _isFlag(String key) =>
      key.startsWith('cosmetic_unlocked_') ||
      key.startsWith('ship_owned_') ||
      key.startsWith('route_unlocked_') ||
      key.startsWith('flawless_') ||
      key.startsWith('story_') ||
      key.startsWith('ship_intro_') ||
      key.startsWith('gear_fitted_') ||
      key.startsWith('once_') ||
      key.startsWith('crate_hint_') ||
      key == 'scrape_hint_seen' ||
      key == 'fire_hint_seen' ||
      key == 'controls_hint_seen' ||
      key == 'camera_tip_seen' ||
      key == 'canister_hint_seen' ||
      _isDailyDone(key);

  static final _dailyDone = RegExp(r'^daily_\d{4}-\d{2}-\d{2}$');
  static bool _isDailyDone(String key) => _dailyDone.hasMatch(key);

  static bool _isUnion(String key) =>
      key == 'achievements' || key == 'garage_seen';

  /// Choices: this device's own wins, the other's fills in a missing one.
  static bool _isChoice(String key) =>
      key.startsWith('equipped_cosmetic_') ||
      key.startsWith('ship_choice_') ||
      key == 'ship_preferred';

  /// The daily streak travels as a pair with the day it was last extended.
  static const _streak = 'daily_streak';
  static const _streakDate = 'daily_last_date';

  /// Whether [key] is part of the cloud save.
  static bool isSynced(String key) =>
      _isWallet(key) ||
      _isMax(key) ||
      _isMin(key) ||
      _isFlag(key) ||
      _isUnion(key) ||
      _isChoice(key) ||
      key == _streak ||
      key == _streakDate;

  /// Merges [local] and [cloud] (both already filtered to [isSynced] keys).
  /// [base] is the snapshot both agreed on at the last sync, or null when
  /// this device never synced (then wallets keep the larger balance).
  static Map<String, Object> merge({
    required Map<String, Object> local,
    required Map<String, Object> cloud,
    Map<String, Object>? base,
  }) {
    final out = <String, Object>{};
    for (final key in {...local.keys, ...cloud.keys}) {
      if (key == _streak || key == _streakDate) continue;
      final l = local[key];
      final c = cloud[key];
      final v = _mergeOne(key, l, c, base?[key], hasBase: base != null);
      if (v != null) out[key] = v;
    }
    // Streak: the side that played the daily most recently wins; on the
    // same day, the longer streak.
    final lDate = local[_streakDate] as String? ?? '';
    final cDate = cloud[_streakDate] as String? ?? '';
    final lStreak = _num(local[_streak])?.toInt() ?? 0;
    final cStreak = _num(cloud[_streak])?.toInt() ?? 0;
    final cloudWins =
        cDate.compareTo(lDate) > 0 || (cDate == lDate && cStreak > lStreak);
    final date = cloudWins ? cDate : lDate;
    if (date.isNotEmpty) out[_streakDate] = date;
    if (local.containsKey(_streak) || cloud.containsKey(_streak)) {
      out[_streak] = cloudWins ? cStreak : lStreak;
    }
    return out;
  }

  static Object? _mergeOne(
    String key,
    Object? l,
    Object? c,
    Object? b, {
    required bool hasBase,
  }) {
    if (l == null) return c;
    if (c == null) return l;
    if (_isWallet(key)) {
      final ln = _num(l), cn = _num(c);
      if (ln == null || cn == null) return ln ?? cn;
      final num merged;
      if (!hasBase) {
        merged = math.max(ln, cn);
      } else {
        final bn = _num(b) ?? 0;
        merged = math.max(0, bn + (ln - bn) + (cn - bn));
      }
      return l is int ? merged.round() : merged.toDouble();
    }
    if (_isMax(key) || _isMin(key)) {
      final ln = _num(l), cn = _num(c);
      if (ln == null || cn == null) return ln ?? cn;
      final pick = _isMax(key) ? math.max(ln, cn) : math.min(ln, cn);
      return l is int ? pick.round() : pick.toDouble();
    }
    if (_isFlag(key)) return l == true || c == true;
    if (_isUnion(key)) {
      return {..._strings(l), ..._strings(c)}.toList()..sort();
    }
    return l; // choices: this device's own
  }

  static num? _num(Object? v) => v is num ? v : null;

  static List<String> _strings(Object? v) =>
      v is List ? [for (final e in v) '$e'] : const [];

  /// What [merge] changed against [before] (keys to write back on this
  /// device). Lists compare by content.
  static Map<String, Object> changes(
    Map<String, Object> before,
    Map<String, Object> after,
  ) => {
    for (final e in after.entries)
      if (!_same(before[e.key], e.value)) e.key: e.value,
  };

  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }

  static String encode(Map<String, Object> data, {required int atMs}) =>
      jsonEncode({'v': version, 'at': atMs, 'data': data});

  /// The saved data, or null if [raw] is empty, unreadable or from a newer
  /// format.
  static Map<String, Object>? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['v'] is! int || json['v'] > version) {
        return null;
      }
      final data = json['data'];
      if (data is! Map) return null;
      return {
        for (final e in data.entries)
          if (e.key is String && isSynced(e.key as String) && e.value != null)
            e.key as String: _fromJson(e.value as Object),
      };
    } catch (_) {
      return null;
    }
  }

  static Object _fromJson(Object v) =>
      v is List ? [for (final e in v) '$e'] : v;
}
