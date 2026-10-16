/// Play Games / Game Center ids for the achievements and the leaderboard.
///
/// Game Center ids are ours (`nh.<local id>`, entered in App Store
/// Connect). Play Games generates its own ids when the achievements are
/// imported in Play Console (Play Games Services → Achievements, from
/// `tool/store/make_achievements.py`'s zip); they're copied into
/// [kPlayAchievementIds]. An achievement without a Play id is simply not
/// mirrored on Android (`test/cloud_save_test.dart` checks all are there).
library;

String gameCenterAchievementId(String localId) => 'nh.$localId';

/// Local achievement id → Play Games id (`CgkI…`).
const Map<String, String> kPlayAchievementIds = {
  'first_haul': 'CgkI-LT6hcYGEAIQGA',
  'fuel_miser': 'CgkI-LT6hcYGEAIQBA',
  'speed_hauler': 'CgkI-LT6hcYGEAIQGQ',
  'no_scratch': 'CgkI-LT6hcYGEAIQEg',
  'perfect_pilot': 'CgkI-LT6hcYGEAIQDg',
  'level_10': 'CgkI-LT6hcYGEAIQEw',
  'level_20': 'CgkI-LT6hcYGEAIQCQ',
  'daily_pilot': 'CgkI-LT6hcYGEAIQDw',
  'cargo_swinger': 'CgkI-LT6hcYGEAIQBQ',
  'rank_commercial': 'CgkI-LT6hcYGEAIQGw',
  'rank_captain': 'CgkI-LT6hcYGEAIQAg',
  'rank_chief': 'CgkI-LT6hcYGEAIQDA',
  'full_manifest': 'CgkI-LT6hcYGEAIQBw',
  'week_on_duty': 'CgkI-LT6hcYGEAIQHA',
  'century_hauler': 'CgkI-LT6hcYGEAIQCw',
  'fleet_qualified': 'CgkI-LT6hcYGEAIQIg',
  'off_type': 'CgkI-LT6hcYGEAIQHw',
  'storm_rider': 'CgkI-LT6hcYGEAIQHQ',
  'orbital_mechanic': 'CgkI-LT6hcYGEAIQIA',
  'heavy_lifter': 'CgkI-LT6hcYGEAIQEA',
  'test_pilot': 'CgkI-LT6hcYGEAIQFw',
  'weapons_hot': 'CgkI-LT6hcYGEAIQDQ',
  'meltdown_escape': 'CgkI-LT6hcYGEAIQCg',
  'hold_fire': 'CgkI-LT6hcYGEAIQIQ',
  'hot_refuel': 'CgkI-LT6hcYGEAIQCA',
  'opened_the_box': 'CgkI-LT6hcYGEAIQBg',
  'gambler': 'CgkI-LT6hcYGEAIQFQ',
  'ghost_protocol': 'CgkI-LT6hcYGEAIQGg',
  'bee_lieve_it': 'CgkI-LT6hcYGEAIQFA',
  'bad_trip': 'CgkI-LT6hcYGEAIQEQ',
  'shake_it_off': 'CgkI-LT6hcYGEAIQFg',
  'clover': 'CgkI-LT6hcYGEAIQAw',
  'salvage_collector': 'CgkI-LT6hcYGEAIQHg',
  'flawless_world': 'CgkI-LT6hcYGEAIQJA',
};

/// Career stars (the "Total stars" leaderboard).
const kStarsLeaderboardGameCenter = 'nh.total_stars';
const kStarsLeaderboardPlay = 'CgkI-LT6hcYGEAIQIw';
