# Narrow Haul — Launch Readiness Report

**Checked:** 2026-10-07, at commit `1af276c` (route guide, demo flight, autopilot difficulty ranking). The working tree was clean.
**Method:** I ran `flutter analyze` and `flutter test` and read the fresh `build/autopilot_report.md`. I audited three areas, platform/store config, code robustness and content/UX, and checked every finding below against the code at this commit.

## Verdict

**Close, but not shippable yet.** The engineering base is solid:
- `flutter analyze` is clean, and **all 128 tests pass**. The autopilot suite is skipped by default.
- The autopilot report (21:40): **all 58 bot-flyable levels reach 3★** with the 1.3 human margin. The labels are 40 *3★ comfortable*, 18 *3★ tight* and 0 *needs help*. Two levels need a human: redoubt_02 and redoubt_04.
- 58 route-guide recordings are bundled in `assets/routes/` (740 KB).
- Release builds use full gravity and have no cheat buttons.
- Real AdMob units are wired, UMP consent is in, and Restore purchases works.
- Store records, IAP products, icons, screenshots, listing texts and the website are done.

What's left:
1. a handful of blockers, mostly cheap ones
2. phone UX: notches, the Android back button, text scaling
3. crash visibility
4. **no human has played** the ships, fields, defences or the route guide yet
5. store paperwork

### Resolved since the first draft
- Committing the autopilot and canister work: done in `54a4dd4` and `1af276c`.
- Tutorial 3★ was out of reach. With the canisters, every tutorial is 3★ for the player estimate: 24–30% fuel against a 30% budget.
- Fuel gaps on alien_02, alien_07, ice_05 and redoubt_05: closed, all pass now.
- Route ghost and demo flight: built. They are still unseen in the real app (see §5).

---

## 1. Blockers (fix before any public release)

| # | Area | Issue | Where |
|---|---|---|---|
| B2 ✅ | iOS | **Done:** `UIRequiresFullScreen = true` added; confirm on the first TestFlight upload. Was: iPad allows landscape only and `UIRequiresFullScreen` isn't set. The upload may be rejected (ITMS-90474), or the iPad window becomes freely resizable. Add `UIRequiresFullScreen = true` and confirm with a TestFlight upload. | `ios/Runner/Info.plist:65-69` |
| B3 ✅ | Gameplay | **Done:** the daily now picks only unlocked levels (`test/daily_challenge_test.dart`). Was: the Daily Challenge picks from **all** 60 levels (`rng.nextInt(totalLevels)`), so a day-one player can get a Redoubt turret level or a zero-g Orbit level. Limit it to unlocked levels. | `lib/game/services/daily_challenge.dart:48` |
| B4 ✅ | Listing | **Done:** "Seven worlds" / "7 WORLDS" and an accurate ads line. Was: the listing says "Six worlds" / "60 HAND-BUILT LEVELS IN 6 WORLDS" but lists 7, and the game has 7. "light, optional ads" isn't true for interstitials. | `art_src/store/listing_en.md:21,32,50` |
| B5 | Naming | "Talon" is still a placeholder (memory note), but it appears in the listing and in "Talon Type Rating". Pick the final name before the listing goes live, researching a real-world term as was done for the ranks. | `ship_spec.dart`, `listing_en.md:42` |
| B6 | Playtest | Ships, gravity/fields, defences and the route guide have **never been played by a human**. A release-build pass is mandatory (see §5). | — |
| B7 ✅ (code) | Ads / COPPA | **Done in code:** `maxAdContentRating: pg`. Still to do in the consoles: audience 13+ and a matching age rating. Was: there's no `RequestConfiguration` and no `maxAdContentRating` anywhere in `lib/`. Set the Play target audience to 13+ and match the iOS age rating. If any under-13 audience is selected, child-directed ad settings become mandatory. | `monetization_service.dart:244,307` |

## 2. Should fix before launch

### Phone UX
- [ ] **The in-game HUD ignores safe areas.** There's no `viewPadding` or `SafeArea` anywhere in `lib/game`.
  - The fuel gauge sits 12 px from the left edge, the minimap 12 px from the right, and THRUST/FIRE 28 px from the edges.
  - In landscape the iPhone notch or Dynamic Island covers 47–59 pt on one side, and the home indicator runs along the bottom.
  - Fix: pass `MediaQuery.viewPaddingOf` insets into the HUD layout (`hud_touch_controls.dart:78-93,584`, `minimap_hud.dart:23,91`).
- [ ] **No `PopScope` / `WillPopScope` anywhere.** The Android back button exits the app from mid-flight or from any overlay. It should go pause → back out of the current overlay → exit only from the menu.
- [ ] **Text scaling isn't clamped** (no `textScaler` anywhere). Clamp it to about 1.0–1.3 in `MaterialApp.builder`.
- [ ] **Android 16 large screens.** targetSdk 36 ignores `sensorLandscape` on screens ≥ 600 dp. Test on tablets and foldables, or add the `PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY` opt-out.

### Stability and observability
- [ ] **No global error handlers** (`FlutterError.onError`, `PlatformDispatcher.onError`) and **no crash reporting**. Add Crashlytics or Sentry; otherwise Dart errors in release builds are invisible. Update the privacy page and Data safety form to match.
- [ ] **`main()` awaits `ProgressService.init()` and `CareerService.migrateIfNeeded()` without try/catch** (`lib/main.dart:29-30`). A corrupt prefs file hangs the splash screen.
- [ ] **`startLevel()` doesn't await `loadCurrentLevel()`**, and nothing catches a failed load.
- [ ] **Saves aren't type-safe on read.** Clamp stars to 0–3 and keep currency and XP ≥ 0. Add an integer `save_version` instead of one-off flags.

### Monetization
- [ ] **A failed interstitial load is never retried** (`monetization_service.dart:250`), unlike rewarded ads (60 s retry). One failure means no interstitials for the session.
- [ ] **`buyNonConsumable` isn't wrapped in try/catch** (`:363`). Also give the player feedback for pending purchases and for "restored / nothing to restore".
- [ ] **The Garage supporter item doesn't check `canBuy` before `buy()`** (`main.dart` ~1770).
- [x] **Done:** the iOS SKAdNetwork list now has all 50 of Google's ids. Was incomplete: `SKAdNetworkItems` has 1 id; Google recommends about 50.
- [x] **Done:** `ITSAppUsesNonExemptEncryption = false` is added. Still optional: an app-level `PrivacyInfo.xcprivacy` (the SDKs ship their own; add it in Xcode only if App Store Connect warns).
- [ ] **Confirm the AdMob IDFA explainer message is published**, so the ATT prompt actually appears. The app never calls ATT itself.

### Legal and settings
- [ ] **No Licenses / Credits screen** (no `showLicensePage` or `LicenseRegistry` in the code). RussoOne is OFL-licensed, so register `assets/fonts/OFL.txt` with `LicenseRegistry`.
- [ ] **No Privacy policy / Support links in Settings** (no `url_launcher`). Add them, plus a **Reset progress** option.

### Release hygiene
- [x] **Done:** `bundleRelease` now fails without `key.properties`, while local release APKs still use the debug key. Was: release builds silently fell back to the debug key when `key.properties` is missing (`android/app/build.gradle.kts:56-60`). Make the build fail instead.
- [ ] **Back up `~/narrowhaul-upload.jks` and `android/key.properties` off this machine.**
- [ ] **Guard `debugPrint` with `kDebugMode`.** The calls in the audio and monetization services also log in release builds.

### Performance (low-end Android)
- [ ] **`CaveTerrain.render` redraws the full rock path every frame**, plus a blurred edge glow. Cache it in a `Picture`, or drop the blur on weak devices.
- [ ] **Caves are built on the UI thread at level load** (the test budget allows up to 250 ms on desktop), and so does the Test Flight validator. Move them to `compute`, or hide them behind the intro.
- [ ] **Profile on a cheap Android phone.**

### Game design
- [ ] **Explain new ship behaviour in flight.** Skate self-levelling and Vector hover assist are only described in the Logbook. Also teach the star rules up front.
- [ ] **No hint explains fuel canisters**, which appear from tut_01. Pickups also reuse `attach.mp3`.
- [ ] **"Perfect Pilot" needs 3★ on redoubt_02 and redoubt_04**, which the bot can't fly. Confirm it's humanly possible during the playtest.
- [ ] **"Fuel Miser" (≥ 90% fuel left) is nearly impossible on normal days.** The bot's lightest run burns 13% (×1.3 ≈ 17% for a player), so it probably needs the "Fuel Rich" daily. That's acceptable, but make sure it's intended. The "≥ 80% fuel" contract is in the same territory.
- [ ] **Coins have nothing to buy after about the Ice world.** The shop has 8 items for 1,180 coins total, and players earn ≥ 2,750 from first stars. Add more items or other coin sinks.

## 3. Store submission — remaining steps

**App Store Connect**
- [ ] Upload the first TestFlight build. It also settles B2.
- [ ] App Preview video: record on the iPhone in release mode, then run `tool/store/make_videos.sh` (needs `brew install ffmpeg`).
- [ ] IAP review screenshots for both products, taken with a sandbox account. Submit the IAPs together with 1.0.
- [ ] App Privacy questionnaire (AdMob: identifiers, usage, diagnostics, third-party ads, tracking), age rating and copyright.

**Play Console**
- [ ] App content: Ads = yes, Data safety, Advertising ID, IARC rating, target audience 13+ (see B7).
- [ ] Upload a new AAB with the build number bumped (currently `1.0.0+2`). It now includes the canisters and the route guide.
- [ ] YouTube promo video URL.
- [ ] Closed testing: personal developer accounts created after Nov 2023 need 12 testers for 14 days before production. Check whether this applies.

**After publishing**
- [ ] Link each store listing in AdMob → App settings. Real ads only serve after that.
- [ ] zafrk.com `deploy.sh`: add `--exclude "narrow-haul"` and `--exclude "narrow-haul/*"`. Without them, a zafrk deploy deletes the privacy and support pages the stores link to.

## 4. Nice to have / post-launch
- **Art and sound.**
  - Themed art: all 7 worlds use the flat fallback, and the `orbit/` and `redoubt/` folders don't exist yet.
  - Final key-art feature graphic.
  - Background music (none exists) and a volume slider.
  - `shot.mp3` and `boom.mp3`: Talon shots are currently silent.
  - Real liveries instead of tints, and check that "Stealth" stays visible on dark caves.
- **Code and data cleanup.**
  - Prune old per-day prefs keys (`daily_*`, `contracts_*`, `replay_xp_*`).
  - Delete the unused `rope_segment_body.dart` and the retired `level_11–20.tmx` (still bundled).
  - Remove the empty theme folders' `.gitkeep`.
- **CLAUDE.md is stale in two places.** The `rot?`/`thrust?` debug warnings no longer exist, and `exhaust.png` is now transparent.
- **Website.** Hard-code the contact details in the HTML instead of setting them from JS. Self-host Google Fonts, or mention them in the privacy policy.
- **Localization** (everything is hard-coded English), a colourblind check of the green markers vs red hazards, and control-size options.
- **If macOS ever ships:** fix its bundle id and add the network entitlement.

## 5. Human playtest plan
Use a **release or profile build**: debug builds run at 0.7× gravity. Alternatively use `--dart-define=STORE_CAPTURE=true`.

1. **Defences.**
   - redoubt_02 and redoubt_04: the bot can't pass them and they have no route.
   - redoubt_05 and redoubt_03 (tightest, meltdown escape).
   - redoubt_01 and rating_talon.
   - The dodge-only turrets in mine_06 and lava_03.
   - Whether FIRE above THRUST works with one thumb.
   - Whether turret fire feels fair.
2. **The tightest levels by difficulty score:**
   - mine_05 (80; only one of four bot profiles passes, 8 s waiting at hazards)
   - alien_07 (67)
   - lava_03, lava_05 and lava_06 (one profile passes)
   - lava_07 and lava_08
   - orbit_01 and orbit_04
   - the tutorials labelled tight: tut_02, tut_07 and tut_09
3. **Ships and fields.**
   - All 5 type ratings.
   - Orbit zero-g levels: stars come down to time.
   - Gravity wells in orbit_02, 03, 05, 06 and 08.
   - Wind in ice_03, 04, 07 and 08, and in lava_02 and 06.
   - Whether the Mule sprite looks wider than its hitbox.
4. **Route guide and demo.**
   - Crash three times to get *Show route*, then check the dotted line and ghost.
   - In *Watch a demo*, check that obstacles stay in sync on a real device, including a Redoubt demo.
   - Check the game-over layout on a short landscape phone.
5. **Devices.**
   - A notched iPhone, an iPad, a cheap Android phone and an Android tablet.
   - On each: background/resume, the back button, ads, and a purchase plus Restore.
6. **Calibrate.** Compare the debug `RUN <id> fuelLeft=… time=…` lines with the bot to set the 1.3 human factor, then re-run the autopilot.

## Suggested order
1. ~~Quick fixes: B2, B3, B4 and B7, the plist keys, and the release-signing guard.~~ Done.
2. Phone UX: safe areas, back button, text scale. Then licenses, privacy/support links and Reset progress.
3. Crash reporting and error handling.
4. Human playtest and tuning (§5). Re-export the routes of any edited level (`LEVELS=<id> EXPORT_ROUTES=true`).
5. Final Talon name.
6. TestFlight and Play closed testing.
7. Video, IAP screenshots and store declarations.
8. Submit.
9. After publishing: AdMob linking and the zafrk `deploy.sh` exclusions.
