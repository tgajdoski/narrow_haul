# In-App Events (App Store) and Promotional Content (Google Play)

Ready-to-paste texts. Limits are in brackets, then the measured count.
Checked 2026-11-09 against Apple's *In-App Events* page and Google's
*Promotional content* help page (sources at the bottom).

## Read first: what each event needs from the game

| Event | Works with today's game? |
|---|---|
| 1. Daily Dispatch Boards | **Needs 1.0.1.** The shared daily and its per-stage leaderboards are on `main`, not in live build 4. Schedule it for the week 1.0.1 goes live. |
| 2. Salvage Chaos Weekend | **Ships in 1.0.1:** the first weekend of every month (the Saturday in days 1–7 and the Sunday after it, dispatch days) is always Salvage Chaos (`DailyChallengeConfig.isChaosWeekend`); schedule the event for one of those weekends once 1.0.1 is live. Cadet-tier pilots (Training Grounds only) still get a standard run that weekend. Before:  Salvage Chaos is one of 7 daily modifiers, drawn from the date (`DailyChallengeConfig._modifiers`). It comes up about one day in seven, and only when the day's mission is a cave level; on a Training Grounds mission (the Cadet tier) it falls back to a standard run. You can't schedule a weekend of it today. Either ship a date override (e.g. a `kChaosDays` list that forces `chaos: true` on cave dailies, in a release before the event), or use the honest reframe below (*Relic Hunt*). |
| 3. The Long Night | **Works now.** E0 is free and E1–E7 need the Full Game. The catch: it shipped in 1.0, so on iOS it's only "new" in the first weeks after the 2026-11-08 launch. Run it now as a *Premiere* while that's still true, or save it for an update that adds something to the Expeditions (the per-leg timers on the roadmap). |

Apple's rules that matter here:
- An event lasts at most **31 days**, can be promoted up to **14 days** before
  it starts, up to **10** can be live at once, and App Review checks each one.
- **No prices** anywhere in event text, or it's rejected. Whether an IAP is
  needed is set with the separate *Purchase requirement* setting.
- The name is the event's real name, not a tagline. Don't repeat the badge type
  in it ("Challenge", "Event").
- Media: a card image 1920×1080 (16:9) and a details image 1080×1920 (9:16),
  JPG/PNG, or looping videos at the same sizes. No borders or gradients.
- A deep link is optional. Without one, the event opens the app, which lands in
  the hangar. That's fine for all three events.

## App Store Connect → Narrow Haul → In-App Events → +

### Event 1: Daily Dispatch Boards

- **Reference name** (internal): `daily-dispatch-boards-1.0.1`
- **Badge:** Competition
- **Event purpose:** Keep active users informed
- **Priority:** High
- **Duration:** 7 days, starting the day 1.0.1 is live (start 08:00 UTC, when the dispatch turns over)
- **Promotion start:** at the event start (an update can't be promoted before it's live)
- **Purchase requirement:** None
- **Media:** card = a mission with the HUD visible (`01_alien_05`); details = a portrait crop of the result screen showing *Today's board*

#### Event name [30] (21)
Daily Dispatch Boards

#### Short description [50] (48)
One mission for everyone. Fastest delivery wins.

#### Long description [120] (119)
Every day at 08:00 UTC, pilots at your career stage fly the same run. Deliver fast and climb today's Game Center board.

### Event 2: Salvage Chaos Weekend (first weekend of the month, from 1.0.1)

- **Reference name:** `salvage-chaos-weekend-1`
- **Badge:** Special Event
- **Event purpose:** Bring back lapsed users
- **Priority:** Normal
- **Duration:** Saturday 08:00 UTC to Monday 08:00 UTC (the 2 dispatch days of the month's first weekend, e.g. 2026-12-05 → 2026-12-07)
- **Promotion start:** 7 days before
- **Purchase requirement:** None
- **Media:** card = a ship inside a glowing "?" cache; details = the Spore Trip or Swarm Sting effect in flight

#### Event name [30] (21)
Salvage Chaos Weekend

#### Short description [50] (40)
Three mystery relics on every daily run.

#### Long description [120] (118)
All weekend the Daily Dispatch has three "?" caches. Each relic is a boon or a curse: a shield or a bee in the engine.

### Event 2, alternative (not needed since 1.0.1): Relic Hunt

Honest without any new code: caches already turn up on about 40% of cave
flights. Still, Apple may see an event with nothing time-limited about it as
evergreen content and reject it. Run it only alongside something real, such as
a release.

- **Badge:** Challenge · **Purpose:** Appropriate for all users · **Priority:** Normal · **Duration:** 14 days · **Purchase requirement:** None

#### Event name [30] (16)
Xenar Relic Hunt

#### Short description [50] (38)
Find all 19 alien relics in the caves.

#### Long description [120] (105)
Fly through glowing "?" caches to open Xenar relics. Some help, some misbehave. Fill the relic catalogue.

### Event 3: The Long Night

- **Reference name:** `the-long-night-premiere`
- **Badge:** Premiere (now, in the launch window) or Major Update (with an update that adds Expedition content)
- **Event purpose:** Attract new users
- **Priority:** High
- **Duration:** 14 days
- **Promotion start:** 7 days before, or at the start if it's already running
- **Purchase requirement:** **In-App Purchase required.** Seven of the eight Expeditions need the Full Game. The long description says the first is free.
- **Media:** card = a wide Expedition cave with the staging pads (`19_briefing` or a key-art frame); details = a portrait crop of a ship towing a pod in a big cave

#### Event name [30] (14)
The Long Night

#### Short description [50] (49)
Act II: eight long convoy hauls through the dark.

#### Long description [120] (119)
Haul pods pad to pad through giant caves, refuel and fly on. Crash and resume from the last pad. The first one is free.

## Google Play Console → Grow users → Promotional content → Create

Google's rules (2026-11-09):
- Content must be **new and noteworthy**, not routine. Events must apply to all
  users, and **one item can be submitted at a time**.
- **Tagline:** 80 characters (48 for the Spotlight format). It says what the
  event is, starting with the key detail. No line breaks, no calls to action,
  no generic promotional text. It should stress the limited time and usually
  name the event.
- **Description:** 500 characters, ≥ 100 recommended. Explain the benefit and
  how to take part, in short paragraphs (no bullets). Don't repeat the tagline
  and don't describe the app in general. Use em dashes, not hyphens; at most
  one "!" or "?" in a row; no ALL CAPS.
- **Image:** 1920×1080 JPG/24-bit PNG with **no text or logos**, not a plain
  screenshot. Keep the safe zone clear: 15% top, 10% sides, 20% bottom. No
  frames or rounded corners.
- The event has to be live in the game at the same time, and the start date
  must be more than 24 hours away.
- Content must be localised for each locale it targets. Target English only
  unless you translate these too.
- The promotion's internal name isn't shown to players, and Google documents no
  limit for it.

### Card 1: Daily Dispatch Boards (type: Major update, with 1.0.1)

- **Internal name:** Daily Dispatch Boards 1.0.1
- **Duration:** 7–14 days from the 1.0.1 rollout

#### Tagline [80] (73)
Daily Dispatch Boards — race every pilot at your stage on today's mission

#### Description [500] (371)
Every day at 08:00 UTC, every pilot at your career stage gets the same mission and the same twist. Deliver the pod as fast as you can and see where you land on today's Play Games leaderboard.

Each stage has its own board, so new pilots race new pilots. Sign in to Play Games from Settings to post your times. Your achievements and career now sync through cloud save too.

### Card 2: Salvage Chaos Weekend (type: Time-limited event; from 1.0.1, first weekend of the month)

- **Internal name:** Salvage Chaos Weekend 1
- **Duration:** Saturday 08:00 UTC to Monday 08:00 UTC (the month's first weekend)

#### Tagline [80] (63)
Salvage Chaos Weekend — three mystery relics on every daily run

#### Description [500] (334)
All weekend the Daily Dispatch carries three glowing "?" caches. Fly through a cache to open an alien relic: an overshield, an afterburner or slow time — or a bee in the engine, a fuel leak or crossed wires. It's 50/50 boon or curse.

Open the Daily from the hangar to take part. Deliver after a curse to earn bonus Grit XP and coins.

### Card 3 (optional, a dev decision): Full Game offer (type: Offer)

Only if you run a real temporary price cut on `nh_full_game` in Play Console
(at least 10% off, redeemable in the game, not limited in quantity). Offers must
state their value in the first 40 characters. Skip this card if you don't want
a sale.

- **Internal name:** Full Game sale
- **Duration:** the sale's dates

#### Tagline [80] (58)
40% off the Full Game — every Expedition of The Long Night

#### Description [500] (366)
For a limited time the Full Game costs 40% less. It unlocks all seven paid Expeditions of Act II, The Long Night: long convoy hauls through giant caves with staging pads, refuels and checkpoints. It also removes the ads between missions for good.

Open Missions, then The Long Night, and tap any mission with the gold FULL GAME lock. You can also buy it in Settings.

(Change "40%" to the discount you actually set.)

## Sources
- Apple, In-App Events: https://developer.apple.com/app-store/in-app-events/
- Google Play, Promotional content: https://support.google.com/googleplay/android-developer/answer/12929944
