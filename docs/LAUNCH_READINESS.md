# Narrow Haul — Launch Readiness

**Second check:** 2026-10-08, after `feef73e` (music, SFX, countdown) and the fixes listed under *Done in this pass*. The first check (`1af276c`) is summarised under *Done*.

## Verdict

**The code is ready for a TestFlight / Play closed-testing build. What's left is mostly playtesting and store paperwork.**
- `flutter analyze` is clean, and **150 tests pass** (the autopilot is skipped by default).
- Autopilot: a full re-run at the current code was in progress at commit time, with **42/42 levels passing 3★ so far** (Tutorial to lava_05). The last committed full run (`659c4ae`) passed all 60. If the remaining levels change anything, it will be noted here.
- All 60 levels have a bundled route-guide recording. Turrets only appear in The Redoubt, where the Talon can shoot back.
- Release builds run at full gravity with no debug buttons.
- In place:
  - Crashlytics
  - real AdMob units, UMP consent, IAP with Restore
  - safe areas, the Android back button, a text-scale cap
  - licences, privacy and support links, Reset progress
- The one real unknown is **no human has played** the ships, fields, defences, route guide, countdown or audio in a release build yet.

---

## Open — your actions

### Before the first test build
- [ ] **Playtest the profile build** on the iPhone (see the plan below).
- [ ] **Back up** `~/narrowhaul-upload.jks` and `android/key.properties` off this machine. If they're lost, you can't ship updates on Play.
- [ ] **AdMob:** confirm the IDFA explainer message is published. The ATT prompt comes from it; the app never calls ATT itself.
- [ ] Bump the build number in `pubspec.yaml` (it's currently `1.0.0+2`).

### Test builds
- [ ] **TestFlight upload.** It confirms `UIRequiresFullScreen`. If App Store Connect warns about ITMS-91053 (privacy manifest), add an app-level `ios/Runner/PrivacyInfo.xcprivacy`. Every plugin already ships its own, so a warning is unlikely.
- [ ] **Play closed testing.** Personal developer accounts created after Nov 2023 need 12 testers for 14 days before production.
- [ ] **Profile on a cheap Android phone** and try an **Android tablet or foldable**. Android 16 ignores `sensorLandscape` on screens ≥ 600 dp.
- [ ] On each device, check:
  - background and resume (the music must stay silent in the background)
  - the back button
  - an interstitial and a rewarded ad (the music pauses under them)
  - a sandbox purchase, plus Restore (you should see the "Purchases restored" or "No purchases to restore" message)

### Store paperwork
- [ ] **App Store Connect:**
  - App Privacy questionnaire. Include AdMob (identifiers, usage, diagnostics, third-party ads, tracking) and Crashlytics (**Diagnostics → Crash data**: app functionality, not linked to the user, no tracking).
  - Age rating and copyright.
- [ ] **Play Console:**
  - Ads = yes, Advertising ID, IARC rating, **target audience 13+**. Ads are already capped at `MaxAdContentRating.pg`.
  - Data safety. Crashlytics goes under **App info and performance → Crash logs + Diagnostics**: collected, not shared, encrypted in transit.
- [ ] App Preview video: record a release build on the iPhone, then run `tool/store/make_videos.sh` (needs ffmpeg). For the **YouTube promo**, use Goose Ninja tracks: some Pixabay tracks are registered with YouTube Content ID and may get claimed.
- [ ] IAP review screenshots for every product, taken with a sandbox account. Submit the IAPs together with 1.0. The ammo packs `nh_demo_kit` / `nh_arsenal_crate` are **consumables** (Armory tab in the Garage; the rows show only once the store returns them).

### After publishing
- [ ] Link each store listing in AdMob → App settings. Real ads only serve after that.
- [ ] zafrk.com `deploy.sh`: add `--exclude "narrow-haul"` and `--exclude "narrow-haul/*"`. Without them, a zafrk deploy deletes the privacy and support pages the stores link to.

## Playtest plan
Use a **profile or release build**: debug builds fly at 0.7× gravity. To install on a device: `flutter build ios --profile`, then `xcrun devicectl device install app …` (see CLAUDE.md → Debug Mode). Debug builds print `RUN <id> fuelLeft=… time=…` on every delivery. Use those lines to calibrate the 1.3 human factor.

1. **The Redoubt** (Talon):
   - redoubt_04 and redoubt_02, both reworked on 2026-10-08 so every gun can be sniped from cover
   - redoubt_05 and redoubt_03 (the meltdown escape)
   - redoubt_01 and rating_talon

   Check that FIRE above THRUST works with one thumb, that turret fire feels fair, and that Redoubt demos fire back.
2. **The tightest levels:** mine_05, alien_07, lava_06, orbit_04, lava_08, lava_05, lava_07, orbit_01, and the tight tutorials tut_02, tut_07 and tut_09.
3. **Ships and fields:**
   - all 5 type ratings
   - zero-g in Orbit (stars come down to time)
   - gravity wells in orbit_02, 03, 05, 06 and 08
   - wind in ice_03, 04, 07 and 08, and lava_02 and 06
   - whether the Mule sprite looks wider than its hitbox
4. **Start and audio:**
   - Does the 3·2·1·GO countdown feel right, or launch too early?
   - Thrust taps are audible, and music is balanced against the engine.
   - The Sound and Music switches work.
   - Silent switch on iPhone (ambient: the game should be silent).
5. **Route guide and demo:**
   - Crash 3× and choose *Show route*: check the dotted line and the ghost.
   - In *Watch a demo*, obstacles should stay in sync.
   - Check the game-over layout on a short landscape phone.
6. **Achievements:** "Fuel Miser" is now ≥ 85% fuel left, so check it can be earned on mine_03 or rating_mule. Check that "Perfect Pilot" (all 3★) feels achievable.

## Post-launch / nice to have
- **Art:** themed art for the 7 worlds (all use the flat fallback, and the `orbit/` and `redoubt/` folders don't exist yet). Key-art feature graphic. Real liveries instead of tints, and check that "Stealth" stays visible on dark caves.
- **Audio:** volume sliders (Sound and Music are on/off). Pro sound effects to replace the synthesized ones. The source of `attach.mp3` and `crash.mp3` isn't recorded: confirm it or regenerate them. Optionally mute the music when other audio is already playing.
- **Cleanup:** prune old per-day prefs keys (`daily_*`, `contracts_*`, `replay_xp_*`). Delete the unused `rope_segment_body.dart`.
- **Website:** hard-code the contact details instead of setting them from JS. Self-host Google Fonts, or mention them in the privacy policy.
- **Reach:** localization, a colourblind check (green markers vs red hazards), control-size options.
- **macOS**, if it ever ships: bundle id and network entitlement.

---

## Done

### In this pass (2026-10-08)
- **Audio:**
  - Every one-shot sound now plays from a preloaded pool. Android's low-latency one-off players never reported completion, so they kept piling up.
  - Each sound file loads on its own, so a bad file only mutes itself instead of all audio and music.
- **Music:**
  - It can no longer start playing in the background, when the app was backgrounded while a track was starting or fading out.
  - It pauses under full-screen ads, and the engine loop and alarm stop.
- **Purchase feedback:**
  - Messages for a purchase pending approval, an unavailable store, and "restored" / "nothing to restore".
  - The Garage Supporter tile no longer does nothing when the store has no product.
- **Fuel Miser** is now ≥ 85% fuel left. 90% was only reachable on a Fuel Rich daily.
- Smaller fixes:
  - The countdown digit is cleared when you leave to the menu.
  - Switch taps play after the switch, so turning Sound off is silent.
- The retired `level_11–20.tmx` files are no longer bundled.
- The store listing now mentions the soundtrack.
- A full autopilot re-run at the current code was started (see the verdict).

### Earlier (first check, `1af276c` → `feef73e`)
- **Blockers:**
  - Daily from unlocked levels only
  - iPad `UIRequiresFullScreen`
  - Listing fixed to 7 worlds, with an honest ads line
  - "Talon" kept as the ship name
  - Ads capped at PG
- **Phone UX:**
  - HUD safe areas
  - Android back steps back one screen
  - Text scale capped at 1.3
- **Stability:**
  - `ErrorReporter` and Firebase Crashlytics (website privacy section deployed)
  - Guarded save migrations and level loads
  - Type-safe, clamped saves
- **Monetization:**
  - Interstitial retry
  - IAP errors caught
  - 50 SKAdNetwork ids
  - `ITSAppUsesNonExemptEncryption`
  - A signing guard on `bundleRelease`
  - Release logs silenced
- **Legal and settings:** Licenses (RussoOne and music credits), Privacy and Support links, Reset progress.
- **Performance:**
  - Pre-rendered cave glow
  - Cached HUD text
  - Cave builds and Test Flight validation on background isolates
- **Design:**
  - Hints for unfamiliar ships, fuel canisters and the star rules
  - A premium Garage tier (shop total 4,180 coins)
- **Levels:**
  - Turrets only for armed ships
  - redoubt_02 and redoubt_04 reworked
  - All 60 routes bundled
- **Audio:** music (Space Music Pack + Pixabay), synthesized SFX, the thrust-tap fix, and the start countdown.
