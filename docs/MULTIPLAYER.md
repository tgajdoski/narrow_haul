# Multiplayer (future versions)

Status: brainstorm, 2026-10-14. Nothing built. Revisit after 1.1 (Game Center / Play Games sign-in, achievements, leaderboard, cloud save).

## Context
Game Center / Play Games is going in now (`games_services` 5.3: sign-in, achievements, a stars leaderboard, cloud save). The question: could we add a head-to-head mode? Portrait arena, the opponent's base at the top and ours at the bottom, cover to hide behind, both pilots hauling pods home while shooting with the same ammo. Should we plan for it in the next versions?

## 1. Can Game Center / Play Games be the backend?
| Option | Real-time action? | Cross-platform? | Verdict |
|---|---|---|---|
| **Game Center GKMatch** (real-time) | Yes: matchmaking, invites, peer-to-peer or Apple relay, voice | **iOS only** | Free and good, but it splits the player base. `games_services` doesn't cover it, so we'd need our own Swift platform channel. |
| **Game Center GKTurnBasedMatch** | No (turns, async) | iOS only | Fine for async duels. |
| **Play Games Services** | **No.** Google removed real-time and turn-based multiplayer in 2020. Only sign-in, saves, achievements and leaderboards are left. | – | Can't do it on Android. |
| **Own backend** | Yes | Yes | Needed for any Android ↔ iOS play. |

**Conclusion:** for real-time play that works on Android too, we need our own backend. Game Center and Play Games still help, because their signed-in player id gives us identity and friends (no account system needed).

Own-backend options, from least to most work:
- **Nakama** (Heroic Labs, open source; self-hosted on a small VM or Heroic Cloud). Matchmaker, relayed or authoritative matches, leaderboards, and a community Dart client. Probably the best fit.
- **Small WebSocket relay of our own** (Dart or Go on Cloud Run or Fly.io) plus Firebase Auth or a Game Center/PGS token check. Most control, but we'd build matchmaking ourselves.
- Photon and Colyseus have no official Dart SDK. Firebase Realtime DB / Firestore is too slow for shooting, but fine for async modes.

Cost: a relay for 2-player rooms is cheap (a few €/month at launch scale). The real cost is regions/latency and keeping it running.

## 2. Does the game's design fit? Mostly yes, and some existing systems are a big help
- **Same gravity for both? Use gravity zones.** Gravity points down for everyone, so the top player would have to haul *up*, which isn't fair. Fix: `GravityZoneSpec` already does sideways and reversed gravity. The top half pulls up, the bottom half pulls down, and a zero-g or weak band in the middle is where the pods float. Each client draws the world rotated 180° for the top player, so **both players see themselves at the bottom** and fly normally. Local-up logic (NOSE UP, Skate levelling, the touchdown rule) already follows local gravity.
- **Fair arenas:** build them point-symmetric (rotated 180°) from `LevelSpec`. The Expedition generator (`lib/game/level/gen/`) and `validateCaveSpec` can produce and prove one half, then mirror it. Cover = rock pillars and bowls. Weapon carving (`TerrainCarver`) makes cover destructible, which is a great PvP feature.
- **Shooting:** `Shell` is already analytic, not a physics body, and a shot is just muzzle + velocity (`FlightRoute.shotRays`). That's ideal for networking: send "fired at t, from p, with v" and both sides simulate the same shell. Interception (`combat/intercept.dart`) works the same way. Same ammo for both: the Talon cannon plus one loadout (e.g. 2 charges + 2 seekers).
- **Input is already abstract:** `rotateAxis / thrustHeld / fireHeld`. The autopilot already drives the real game through it at a fixed 1/60 s step.
- **AI opponent for free-ish:** the autopilot already plans routes, tows, snipes and assaults turrets and dodges shells. A "bot pilot" opponent could ship before any networking.

## 3. The hard parts (honest)
1. **Physics over the network.** Forge2D is too sensitive for full lockstep (FMA and platform float differences, rope joints, chain contacts). Recommended model: **each client owns its own ship and the pod it's towing.** It simulates them locally and sends state at 15–20 Hz. The other side shows them interpolated ~100 ms behind. Shells are deterministic events. Hits are decided by the victim's client (or the server), with a small favour-the-shooter window.
2. **Contested pods** (both going for the same pod, or stealing a towed one) need an ownership handoff. That's the trickiest code. v1: each player has their own pods, but they're in the open middle band, exposed to fire.
3. **Portrait mode:** the app is landscape-only (manifest `sensorLandscape`, iPad `UIRequiresFullScreen`). The HUD (`HudButtonLayout`, joystick dial, THRUST/FIRE, minimap, ammo rail), the camera's `_screenScale` and safe frame, and every overlay assume landscape. Options: (a) let only the PvP screen go portrait, which means a portrait HUD layout and camera profile, roughly 2–3 weeks of UI work; (b) **keep landscape** and still put the opponent at the top, because the arena just scrolls vertically. (b) is far cheaper, and the "up = them, down = me" idea still works.
4. **Player liquidity:** with a small player base, random matchmaking finds nobody. This is the #1 reason indie real-time PvP dies. Plan around friend invites (Game Center/PGS friends, share links) plus a bot fallback after ~10 s.
5. **Fairness and cheating:** with client authority, a modded client can lie. For casual friend matches that's acceptable. Ranked play would need server-side checks.
6. **Monetization and ads** in PvP: no interstitials mid-session. It's a natural fit for the Full Game or Fleet Pass.

## 4. Cheaper steps that test demand first (recommended order)
1. **Ghost Duel (async)**: race a friend's recorded flight on the same level. `FlightRecorder`, `FlightRoute` and the demo ghost (`RouteGhost`) already exist. Store routes in Firestore (or GKTurnBasedMatch on iOS) and challenge through a share link or friends list. Days to ~2 weeks of work, no real-time networking.
2. **Bot Duel (offline PvP)**: the symmetric arena + split gravity + an autopilot-driven opponent with the same ammo. This proves the mode is fun before any server cost, and later becomes the matchmaking fallback.
3. **Couch duel on iPad** (optional): one device, top player's controls rotated 180°. Also no networking.
4. **Real-time 1v1** on Nakama or our own relay, friends-first, landscape. Only if 1–2 show players want it. Rough size: 6–10 weeks for a solid first version (netcode, lobby, arena set, HUD, testing on bad networks).

## 5. Should we consider it for next versions?
Yes as a direction, no for the next release. The core game is precision flying, which reads as a single-player game, and PvP only pays off with enough players. Things worth doing now so we don't close the door (all cheap):
- Keep the sim driven only by the input triple + fixed step. Don't add flight logic that reads the UI directly.
- Keep weapons event-like: shells analytic, shots as (t, p, v).
- Keep the Game Center/PGS player id handy in `GamesService` (identity for future invites).
- Build new HUD layout code against `HudButtonLayout` sizes rather than hard landscape constants.

Suggested 1.x roadmap: 1.1 Ghost Duel (also good for retention and reminders), 1.2 Bot Duel arena, then decide on real-time from the analytics (`duel_*` events).

## How to check it, if we build it
- Prototype the split-gravity mirrored arena as a `LevelSpec`. Run `dart run tool/preview_levels.dart` and the validator on both halves.
- Fly the autopilot against the autopilot in `GameHarness` (headless) to tune arena fairness.
- Netcode: a test harness with 100–250 ms simulated latency and 2% packet loss.
