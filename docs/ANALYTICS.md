# Analytics: where each number lives

| Question | Where to look |
|---|---|
| Installs, uninstalls (by day, country, device) | **Play Console** → Statistics / Android vitals. **App Store Connect** → Analytics (first-time downloads, re-downloads, deletions, retention) |
| Revenue, refunds | Play Console → Order management / Financial reports; App Store Connect → Sales and Trends / Payments |
| Ad revenue, eCPM, fill | AdMob → Reports (per ad unit) |
| Active users, retention, sessions, countries, devices, app versions | Firebase → Analytics → Dashboard / Retention (automatic) |
| Uninstalls as an event | Firebase `app_remove` (Android only; iOS never reports uninstalls) |
| Purchases with price | Firebase `in_app_purchase` (automatic, both stores) |
| Hard levels, crash spots, drop-off, purchase funnel | Our events below → BigQuery queries below |
| Crashes and bugs | Firebase → Crashlytics |

## Events the game logs (`lib/game/services/analytics_service.dart`)

All of them are off in debug builds (collection disabled) and in tests (no sink). Debug builds print each one as `Analytics: <name> {…}`.

| Event | When | Params |
|---|---|---|
| `level_start` | Every flight load (not demos) | `level_name` (saveId), `world`, `ship`, `rope`, `mode` (normal / daily / test_flight), `attempt`, `guided` |
| `level_fail` | Ship lost | `level_name`, `cause` (wall / shot / meltdown), `attempt`, `seconds`, `fuel_left_pct`, `towing`, `x`, `y` (whole metres), `mode` |
| `level_end` | Delivered | `level_name`, `success`=1, `stars`, `first_clear`, `new_stars`, `attempt`, `seconds`, `fuel_left_pct`, `guided`, `continued`, `carried_ammo`, `mode` |
| `level_quit` | Restart or menu mid-flight | `level_name`, `reason`, `seconds`, `launched` |
| `route_shown`, `demo_watched` | Route guide / demo from the game-over screen | `level_name` |
| `tutorial_complete` | First clear of tut_10 | – |
| `world_unlocked` | A delivery opened a world | `world` |
| `level_up` | Rank up | `level` (rank index), `character` (rank title) |
| `unlock_achievement` | Achievement earned | `achievement_id` |
| `earn_virtual_currency` / `spend_virtual_currency` | Coins paid / spent (cosmetics, Armory) | `value`, `source` / `item_name` |
| `weapon_used` | First use of a weapon in a flight | `weapon`, `carried` |
| `crate_collected` | Supply crate picked up | `weapon` |
| `salvage_opened` | Mystery salvage cache opened | `effect`, `good` (1 = boon, 0 = curse) |
| `rewarded_ad` | Rewarded ad closed | `placement`, `earned` |
| `interstitial_shown` | Interstitial shown | – |
| `purchase_attempt` / `purchase_result` | Buy tapped / store answered | `product_id`, `status` (purchased / restored / pending / canceled / error / unavailable / not_started) |

`attempt` counts the loads of a level since the player last switched levels or delivered it. A continue is not a new attempt.

User properties (set at launch and after each delivery): `pilot_rank`, `total_stars`, `payer`.

## Setup status (2026-10-08)

| Item | Status |
|---|---|
| Events in the app | ✅ shipped (`analytics_service.dart`) |
| Privacy policy §6 (Firebase Analytics) | ✅ live at zafrk.com/narrow-haul/privacy |
| Custom dimensions / metrics | ✅ all registered (10 event dims, 3 user dims, 4 metrics) |
| BigQuery | ✅ linked, region **EU**, daily export. ⚠ **Sandbox**: tables expire after 60 days until the project is on **Blaze** (do before launch; set a small budget alert) |
| Google Play | ✅ linked (Analytics revenue + Crashlytics on, App Distribution off) |
| iOS stream | ✅ "Tag quality: Excellent", sending data |
| Apple in-app purchase key | ⏭ skipped: a key named "Firebase" exists in App Store Connect (Users and Access → Integrations → In-App Purchase), but neither Firebase nor the GA4 iOS stream offers an upload field for this property. Not needed: `in_app_purchase` and our purchase events arrive anyway; exact revenue is in App Store Connect Sales and Trends. The `.p8` is kept outside the repo |
| AdMob ↔ Firebase | ⏳ link from AdMob → Apps → App settings → Linked services (may need the store listings live) |
| Default consent settings (GA4 stream) | left at defaults: EEA ad signals follow the UMP / TCF consent. Open decision: gate basic analytics on consent too? |
| Device check in DebugView | ✅ 2026-10-09 on iPhone (profile build): `level_start`, `level_fail`, `screen_view` arrive |
| Store privacy forms | ⏳ at submission, see `docs/LAUNCH_READINESS.md` |

## One-time console setup

1. **Firebase → Analytics → Custom definitions.** Add event-scoped custom dimensions: `level_name`, `cause`, `world`, `ship`, `mode`, `placement`, `product_id`, `status`, `reason`, `weapon`. Add custom metrics: `stars`, `attempt`, `seconds`, `fuel_left_pct`. Add user-scoped dimensions: `pilot_rank`, `total_stars`, `payer`. A param that isn't registered never shows in the Firebase reports (BigQuery still has it).
2. **Project settings → Integrations → BigQuery → Link.** Turn on the daily export (free tier: 1 GB/day of events, 10 GB storage). The region can't be changed later (we use `EU`). The export only covers data from the day you link it, so link it before launch.
3. **Integrations → Google Play → Link** (Play purchases and subscriptions). **AdMob** is linked from the AdMob side: the card's Android / Apple links open AdMob → App settings → Linked services → Firebase.
4. **Funnels** (Analytics → Explore → Funnel): `first_open` → `level_start` (tut_01) → `tutorial_complete` → `world_unlocked` → `in_app_purchase`.
5. **DebugView** to check a build: Android `adb shell setprop debug.firebase.analytics.app com.zafrk.narrowhaul`; iOS: `flutter run` can't pass launch arguments, so build with `flutter build ios --profile`, install with `xcrun devicectl device install app --device <id> build/ios/iphoneos/Runner.app`, then launch once with `xcrun devicectl device process launch --terminate-existing --device <id> com.zafrk.narrowhaul -- -FIRDebugEnabled` (the `--` is required; the flag persists until `-- -FIRDebugDisabled`). Collection is on only in release builds: for a DebugView check on a profile build, build it with `--dart-define=FIREBASE_COLLECT=true` (e.g. `flutter build ios --profile --dart-define=FIREBASE_COLLECT=true`). Analytics never collects the advertising ID or IDFV (`google_analytics_adid_collection_enabled` in the Android manifest, `GOOGLE_ANALYTICS_ADID/IDFV_COLLECTION_ENABLED` in `Info.plist`); AdMob still uses the ad ID.

## BigQuery queries

Replace `PROJECT.analytics_XXXX` with the dataset the link creates.

**Level difficulty** (fail rate, attempts and quits per level):

```sql
WITH e AS (
  SELECT user_pseudo_id, event_name,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key='level_name') AS level,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key='attempt') AS attempt,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key='stars') AS stars
  FROM `PROJECT.analytics_XXXX.events_*`
  WHERE event_name IN ('level_start','level_fail','level_end','level_quit')
)
SELECT level,
  COUNTIF(event_name='level_start') AS starts,
  COUNTIF(event_name='level_fail') AS fails,
  COUNTIF(event_name='level_quit') AS quits,
  COUNTIF(event_name='level_end') AS clears,
  SAFE_DIVIDE(COUNTIF(event_name='level_fail'), COUNTIF(event_name='level_start')) AS fail_rate,
  AVG(IF(event_name='level_end', attempt, NULL)) AS avg_attempts_to_clear,
  AVG(IF(event_name='level_end', stars, NULL)) AS avg_stars,
  COUNT(DISTINCT IF(event_name='level_start', user_pseudo_id, NULL)) AS players
FROM e GROUP BY level ORDER BY fail_rate DESC;
```

**Crash hot spots** (where in a level ships are lost):

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key='level_name') AS level,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key='cause') AS cause,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key='x') AS x,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key='y') AS y,
  COUNT(*) AS crashes
FROM `PROJECT.analytics_XXXX.events_*`
WHERE event_name='level_fail'
GROUP BY level, cause, x, y
HAVING crashes >= 3
ORDER BY level, crashes DESC;
```

**Where players stop** (last level started by players not seen for 7+ days):

```sql
WITH last AS (
  SELECT user_pseudo_id,
    ARRAY_AGG((SELECT value.string_value FROM UNNEST(event_params) WHERE key='level_name')
      ORDER BY event_timestamp DESC LIMIT 1)[OFFSET(0)] AS last_level,
    MAX(event_timestamp) AS last_seen
  FROM `PROJECT.analytics_XXXX.events_*`
  WHERE event_name='level_start'
  GROUP BY user_pseudo_id
)
SELECT last_level, COUNT(*) AS players_lost
FROM last
WHERE TIMESTAMP_MICROS(last_seen) < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY last_level ORDER BY players_lost DESC;
```

**Purchase funnel** (taps → outcomes per product):

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key='product_id') AS product,
  event_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key='status') AS status,
  COUNT(*) AS n, COUNT(DISTINCT user_pseudo_id) AS players
FROM `PROJECT.analytics_XXXX.events_*`
WHERE event_name IN ('purchase_attempt','purchase_result','in_app_purchase')
GROUP BY product, event_name, status ORDER BY product, event_name;
```

**Rewarded ads by placement:**

```sql
SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key='placement') AS placement,
  COUNTIF((SELECT value.int_value FROM UNNEST(event_params) WHERE key='earned') = 1) AS earned,
  COUNT(*) AS shown
FROM `PROJECT.analytics_XXXX.events_*`
WHERE event_name='rewarded_ad'
GROUP BY placement;
```
