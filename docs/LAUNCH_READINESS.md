# Narrow Haul — Launch Readiness

**Third check:** 2026-10-09, after 53 commits since the second check (`59b9532`): weapons, loadout, flight feel, the holo UI, the bigger ship and pod, the launch intro, the guidance HUD, offline recovery, the perf pass, and the fixes under *Done in this pass*.

## Verdict

**The code is ready for a TestFlight / Play closed-testing build.** What's left is a device playtest of everything new since 2026-10-08, new store screenshots, and store paperwork.

- `flutter analyze` is clean. **387 tests pass**; the autopilot and perf benches are skipped by default.
- Autopilot: **60/60 levels deliver 3★** with the 1.3 human margin. `mine_08` (bar chamber widened to 3.5 m for the bigger Mule), `lava_05` and `lava_08` are "3★ tight". All 60 route-guide recordings are bundled.
- Performance (`docs/PERF_BASELINE.md`):
  - Headless, every level updates in ≤ 0.9 ms p95.
  - On the iPhone, raster p95 is ≤ 4.2 ms on the 7 heaviest levels, with no late frames.
  - Sound pools now warm up after the game shows.
- This pass found **two release-only bugs that tests couldn't see** and fixed both:
  - Rock carving never worked on a device.
  - Android ammo packs could get stuck as "already owned".
- Release builds:
  - full gravity, no debug buttons
  - real ad units; test units in debug/profile
  - Firebase collects only in release, and Analytics never takes the advertising ID

---

## Open — your actions

### Before the first test build
- [ ] **Create the `nh_full_game` IAP** ($4.99, non-consumable) in both stores, and re-price the Supporter Pack to $7.99 with its new text: copy-ready in `art_src/store/README.md` → *Full Game*. Don't create `nh_remove_ads`; it's gone.
- [ ] **Playtest the story and the Expeditions** (added 2026-10-10):
  - the prologue and chapter cards, and the radio lines (tut_09 Severance, alien_08, redoubt_05 outro)
  - `exp_00` Lifeline Convoy: refuel and checkpoint pads, *Resume · pad N*
  - one long generated Expedition (e.g. `exp_01` Cave-in), for length and fun
  - a sandbox Full Game buy: gold beacons open, interstitials stop
- [ ] **Playtest the profile build** on the iPhone (plan below). No human has flown these yet: weapons, kits, steering presets, the Dynamic camera, forgiving rock and the shield glow, the guidance HUD, the briefing, the intro, the mystery salvage caches and the fleet (pick another ship in a briefing and in the Garage Ships tab, buy one with coins, check its stars feel fair and that *With route* hides off par).
- [ ] **Recapture the store screenshots and feature graphic** (`tool/store/capture_screenshots.sh`, plus `ipad`).
  - The current ones are from 2026-10-07, before the holo hangar, drawn flight controls and the bigger ship/pod.
  - Consider adding a weapons shot, the Armory and the briefing. See `art_src/store/README.md`.
- [ ] **Deploy the website** (`website/deploy.sh`). The privacy policy now covers the ammo packs, every analytics event (including `salvage_opened`), and that Analytics doesn't collect the ad ID.
- [ ] **Back up** `~/narrowhaul-upload.jks` and `android/key.properties` off this machine. If they're lost, you can't ship updates on Play.
- [ ] **AdMob:** confirm the IDFA explainer message is published. The ATT prompt comes from it.
- [ ] Bump the build number in `pubspec.yaml`. It's `1.0.0+3`; use +4 unless 3 was never uploaded.

### Test builds
- [ ] **TestFlight upload.** If App Store Connect warns about ITMS-91053 (privacy manifest), add `ios/Runner/PrivacyInfo.xcprivacy`. The plugins ship their own, so a warning is unlikely.
- [ ] **Play closed testing.** Personal developer accounts created after Nov 2023 need 12 testers for 14 days.
- [ ] **Profile on a cheap Android phone**, and try an Android tablet or foldable (Android 16 ignores `sensorLandscape` on screens ≥ 600 dp).
- [ ] On each device:
  - background/resume (music silent in the background) and the back button
  - an interstitial and a rewarded ad (music pauses)
  - a sandbox purchase and Restore
- [ ] **Android only: buy an ammo pack twice.** The second buy must go through, which proves the pack is consumed. Also kill the app while the Play sheet is open, relaunch, and check the pack arrives once and can be bought again.
- [ ] **Offline:** start in airplane mode (no ads, no buy rows, the game plays), then go online and open the Garage. Ads and the store should come back.
- [ ] DebugView check now needs `--dart-define=FIREBASE_COLLECT=true` on a profile build (`docs/ANALYTICS.md`).

### Store paperwork
- [ ] **App Store Connect:**
  - **App Privacy:**
    - AdMob: identifiers, usage, diagnostics, third-party ads, tracking.
    - Crashlytics: Diagnostics → Crash data; app functionality, not linked, no tracking.
    - Firebase Analytics: Usage Data → Product Interaction, Diagnostics → Other; Analytics, not linked, no tracking. The device ID is now AdMob's only; Analytics uses its own app-instance ID.
  - Age rating and copyright.
- [ ] **Play Console:**
  - Ads = yes, Advertising ID (AdMob), IARC rating, **target audience 13+**.
  - **Data safety:**
    - Crash logs and diagnostics (Crashlytics).
    - App interactions and purchase history (Analytics).
    - Device or other IDs (AdMob).
    - All collected, not shared, encrypted in transit.
- [ ] App Preview video from a release build (`tool/store/make_videos.sh`). Use Goose Ninja tracks for the YouTube promo: some Pixabay tracks are in Content ID.
- [ ] IAP review screenshots (sandbox account): Settings buy rows, Garage → Armory → AMMO PACKS, and Garage → Ships → a locked ship's offer. Submit the 5 IAPs with 1.0: the ammo packs as **consumables**; `nh_full_game` ($4.99), `nh_supporter_pack` ($7.99) and `nh_fleet_pass` ($3.99) as **non-consumables**, in both stores.

### After publishing
- [ ] Firebase: upgrade to **Blaze** (BigQuery sandbox tables expire after 60 days); link AdMob ↔ Firebase.
- [ ] Link each store listing in AdMob → App settings. Real ads only serve after that.
- [ ] zafrk.com `deploy.sh`: add `--exclude "narrow-haul"` and `--exclude "narrow-haul/*"`, or a zafrk deploy deletes the privacy and support pages.

## Playtest plan
Use a **profile or release build**: debug flies at 0.7× gravity. Install with `flutter build ios --profile`, then `xcrun devicectl device install app …` (CLAUDE.md → Debug Mode). Debug builds print `RUN <id> fuelLeft=… time=…` per delivery; use those to calibrate the 1.3 human factor.

1. **Start and onboarding:**
   - Cold start on iOS and Android 12+: does the splash ship line up with the intro, with no colour flash?
   - Credits on first launch.
   - Mission briefing on LAUNCH: does the extra tap feel slow? Does the mission's ship on its small stand (wide phones only, never on a Test Flight day) look right?
   - Countdown 3·2·1·GO.
   - tut_01–03 coach marks.
2. **Guidance HUD:**
   - Does the comms plate ever cover the pod at the bottom of a cave?
   - Are the callouts too chatty?
   - The LAND BOTH beacon on a real landing.
   - The crate weapon icon flying into FIRE.
   - All of it in left-handed mode.
3. **Flight feel:**
   - Try each steering preset (Two-speed, Smooth, Agile, **Point**, Classic) and each camera preset.
   - **Dynamic camera** (new default; retuned closer after the first test): does it close in once you let go of the controls? Does a fast dive still zoom out early enough to see the wall? Land on a pad at the world's floor and fly into a bottom corner: is the ship always clear of THRUST and the dial (both hands)? Pick up two crates of the same weapon: the plate the first time only, never over the ship? Does a slow pad landing tighten gently? Does the level-start close-up on the ship (eases out over 3 · 2 · 1) look good and never get in the way, does tapping during it hand over at once, and does the delivery push-in read well? Is a pod on a long line or the tractor beam still on screen? Does the view ever pump in and out? Do the crash, blast and meltdown shakes feel right? Is Centred still? Tuning: `CameraMode` in `flight_tuning.dart`, rationale in `docs/CAMERA.md`.
   - Scrape a wall and touch down hard-ish on rock. Does the shield flare and glow feel fair?
   - Is the glow red near bars and turrets?
4. **Loadout:** tow gear (Chain, Long Line, Magnetic Grapple, Shock Cord, Tractor Beam) and the Handling kits (Gyro, Vernier, Dampers). Does each feel like a real trade-off?
   - **Hook-up (new):** on tut_01, does the stock cable catch the pod from a comfortable hover (~0.8 m of air under the tail), and does the pod hang visibly below the ship (≥ 1.0 m tow)? Tuning: `kStockHookReach` / `minTowLength` in `loadout.dart`, then re-run the autopilot (mine_04 is the canary).
   - **Garage turntable (new):** on Liveries and Plumes, the ship turns on a tilted holo pad beside the list. Does it read as 3D (hull thickness, shadow, the light sweeping as it turns)? Is the 14 s spin right, and does dragging spin it nicely? Tap a livery or plume you don't own: is it previewed on the ship, marked "preview"? Do the arrows switch between your next mission's ship and your type-rated ships? Does the screen stay smooth (it redraws every frame)? Code: `lib/ui/ship_showcase.dart`.
   - **Garage notices (new):** earn coins until something is affordable. Do you see the result-screen note, the hangar "N NEW" badge and the tab dot, and do they clear once seen? At a promotion, does **Fit now** work? Does owned gear you never fitted show "FIT" in the hangar and "not fitted" in the briefing? Does every paid item ask *Buy & fit* first?
5. **Weapons:**
   - Supply crates: are the 35% odds right?
   - Charge, bomb, laser, seeker and flak.
   - **Does a blast carve the rock** (fixed this pass: carving never worked on a device before)?
   - Ammo-rail thumb reach. The −★ badge on carried ammo.
   - The Armory, and the rewarded charge after 2 crashes.
6. **The Redoubt** (Talon):
   - redoubt_04 and 02 (snipe from cover)
   - 05 and 03 (meltdown escape, 35/40 s)
   - 01 and rating_talon
   - FIRE above THRUST with one thumb, turret fairness, shells shot down, demos firing back
7. **The tightest levels:** mine_08 (widened bar chamber), lava_05, lava_08, mine_05, alien_07, lava_06, orbit_04, lava_07, orbit_01, and tut_02/07/09.
8. **Ships and fields:**
   - All 5 type ratings.
   - Zero-g in Orbit (are the star times fair?).
   - Gravity wells in orbit_02/03/05/06/08, and their strength.
   - Wind in ice_03/04/07/08 and lava_02/06.
9. **Route guide and demo:**
   - Crash 3×, then *Show route*: the dotted line and the ghost.
   - *Watch a demo*: obstacles stay in sync.
   - The game-over layout on a short phone.
10. **Audio:**
    - Thrust taps.
    - Music against the engine and UI sounds.
    - The Sound and Music switches.
    - The iPhone silent switch.
11. **Achievements:**
    - "Fuel Miser" (≥ 85%) on mine_03 or rating_mule.
    - "Perfect Pilot" feels achievable.
12. **Mystery salvage (new, 2026-10-10):**
    - Force each effect with `flutter run --profile --dart-define=SALVAGE=<effect>`. `SALVAGE=always` gives a cache every flight with the normal odds.
      - Effects: overshield, topOff, afterburner, fuelSaver, stealth, compactor, chrono, antiGrav, lucky, ammoCache, swarmSting, fuelLeak, sporeTrip, crossedWires, sputter, blackout, hiccups, heavyHeart, flareBeacon.
      - Try stealth / flareBeacon on a Redoubt level, and heavyHeart with the pod in tow.
    - Feel and readability:
      - Does the roulette read well, and is the badge clear of the fuel gauge, the level info and the minimap?
      - Are the radio quips funny, not chatty?
    - Fairness:
      - Does a curse ever feel like it caused a crash?
      - The swell growing next to rock, and the Compactor growing back in a tight tunnel.
      - Crossed Wires resting near the pad.
      - Is Hiccups too strong? Is Blackout too dark?
    - Spore Trip: does the shader look right on iOS (Impeller), and what is the frame time while it runs (`--dart-define=PERF=true`)? It redraws the whole world each frame for 8 s.
    - Chrono: is slow motion fun, and does the music or engine sound odd?
    - Odds: is 40% per attempt the right amount? Are durations of 5–15 s right? Tuning: `kSalvage` / `kSalvageChance`.
    - Meta: the Salvage log in the Pilot Logbook, the achievement toasts, the Grit line on the result screen, the salvage contracts, and a Salvage Chaos daily (three caches).

## Post-launch / nice to have
- **Art:** themed backdrops (`far/mid/near`) and decor for the 7 worlds. Every world has rock and pod art, but the parallax uses the shared tinted fallback. Key-art feature graphic. Real liveries instead of tints; check that "Stealth" stays visible on dark caves.
- **Loadout:** Engine and Tank kits, winch in/out, release & re-hook, beam sounds.
- **Audio:** volume sliders, pro SFX, and confirm the source of `attach.mp3` / `crash.mp3`.
- **Tests:** layout checks for the `rankUp` and `demo` overlays and the contracts popover; a drawn-HUD check (coach marks, comms) at 568×320 left-handed.
- **IAP:** an ammo pack's grant writes each weapon before marking the transaction. A crash in between re-grants the whole pack once, which errs toward the player.
- **Cleanup:** prune old per-day prefs keys (`daily_*`, `contracts_*`, `replay_xp_*`). Point `ShipBody._skinTints` and `ThrustPlume`'s plume colours at `lib/game/ship/livery.dart` (`kLiveryTints`, `plumePalette`), the copy the Garage turntable uses, so the two can't drift apart.
- **Ship close-ups still to try:** a "meet your ship" orbit on a new ship's type-rating level, a short punch-in on a crash, and the ship turning behind the pause menu (`ShipShowcase` can do the last).
- **Website:** self-host Google Fonts or mention them in the privacy policy; hard-code the contact details instead of setting them from JS.
- **Reach:** localization, a colourblind check (green markers vs red hazards), control-size options.
- **macOS**, if it ever ships: bundle id and network entitlement.

---

## Done

### In this pass (2026-10-09)
- **Rock carving works on devices.**
  - The carve isolate's closure captured the game, so every background re-extract failed with "object is unsendable". On a phone, blasts never opened rock.
  - Tests only took the synchronous path; a new test carves through the real isolate.
  - The Test Flight ship options got the same fix.
- **Android ammo packs:**
  - They're consumed after the grant (`autoConsume: false`), so a pack bought in a session that died, or approved later, no longer blocks every future buy.
  - Buys settle only on their own product, so the startup restore can't "deliver" a pack early. A double tap can't end the first buy.
  - Startup restores log as `restored_startup`.
- **Intro and credits** leave even if the game load fails or hangs (15 s at most); the error is reported.
- **Shield glow** is always red near machinery, turrets, reactors and well cores. Those crash at any speed; before, a slow drift glowed a safe cyan.
- **Firebase** collects only in release builds, so profile playtests no longer skew the dashboards. Analytics never collects the advertising ID or IDFV.
- **Garage:** every tab is layout-tested. The Armory overflowed on an iPhone SE at 1.3× text; fixed.
- **Store texts:**
  - The listing no longer says "every wall is deadly".
  - It now covers weapons, carving, the shield, steering presets, tow gear, handling kits and the Armory, and says bought ammo caps a flight at 2★.
  - The screenshots are flagged for recapture.
- **Privacy policy:** ammo packs, every analytics event and user property, and no ad ID.
- Same day, from the parallel perf pass (`cdef346`, `ff4536c`):
  - frame probe and benches
  - cancel-safe level loads, and a delivery whose booking throws still shows results
  - sound pools built after the game shows
  - mine_08's bar chamber widened

### Since the second check (2026-10-08 → 09)
- **Gameplay:**
  - Weapons (5 specials + cannon), destructible machinery, rock carving, supply crates, Armory and ammo packs.
  - Tow gear with real stats, plus the tractor beam.
  - Handling kits.
- **Flight feel:**
  - forgiving rock (scrape/touchdown), deflector shield flare and proximity glow
  - two-speed steering with five presets; camera presets with look-ahead and tow zoom
  - Dynamic camera (default): speed and wall-ahead zoom-out, careful zoom-in, pod framing, trauma shake (`docs/CAMERA.md`); retuned closer, zooms in once you let go, keeps the ship clear of the controls and help text
  - ship close-ups: the level opens close on the ship and eases out over 3 · 2 · 1; a delivery pushes in on ship and pod
  - hull traced from the art; ship 1.6× and pod 3× real size; camera scaled to the screen
  - flat pad shelves, so landings are reliable
  - player fire shoots down turret shells
- **UI:**
  - holo hangar, drawn flight controls, mission and daily briefings, world tabs
  - Garage ship turntable with a 3D look (tilted pad, hull thickness, shadow, sweeping light; preview any livery or plume) and the mission's ship on the briefing
  - FIRE pad with ammo ring and the ammo rail
  - guidance HUD (coach marks, world markers, comms) instead of the hint pill
  - animated launch intro and "Delivered by" credits
  - desktop keyboard controls
- **Art:** per-world pod sprites (plus heavy pods), rock textures from the tile sheet.
- **Services:**
  - Firebase Analytics events (DebugView verified on the iPhone)
  - purchase confirmations
  - test ad units and logs in profile builds
  - offline recovery of ads and the store
- Shop total 5,280 coins.

### Earlier (first and second checks, `1af276c` → `59b9532`)
- **Blockers:**
  - daily only from unlocked levels
  - iPad `UIRequiresFullScreen`
  - honest listing
  - ads capped at PG
- **Phone UX:** safe areas, Android back, text-scale cap.
- **Stability:**
  - Crashlytics, guarded migrations and level loads, type-safe saves
  - pooled one-shot audio; music silent in the background and under ads
- **Monetization:**
  - ad and IAP retries
  - purchase/restore feedback
  - 50 SKAdNetwork ids
  - `ITSAppUsesNonExemptEncryption`
  - signing guard
- **Legal:** licences, privacy and support links, Reset progress.
- **Levels:** turrets only for armed ships; redoubt_02/04 reworked; Fuel Miser at 85%.
