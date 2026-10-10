# Store assets: what's ready and where it goes

How each asset is made: see "Store assets" in `CLAUDE.md`. Prompts for AI art are in
`PROMPTS.md`, and all listing texts are in `listing_en.md`.

## Status

| Asset | File | Status |
|---|---|---|
| App icon (iOS / Android / macOS, in the build) | `art_src/icon/icon_1024.png` → generated into the platform folders | ✅ built from the game sprites (AI version optional: prompts A/B) |
| Play listing icon 512×512 | `art_src/icon/play_icon_512.png` | ✅ |
| Launch screen (dark, ship mark) | in the build | ✅ |
| iPhone 6.9" screenshots 2868×1320 | `screenshots/ios_69/` | ⚠ **recapture**: taken 2026-10-07, before the holo hangar UI, drawn flight controls and the bigger ship/pod (2026-10-08/09) |
| iPad 13" screenshots 2752×2064 | `screenshots/ios_ipad13/` | ⚠ **recapture**: taken 2026-10-07, before the holo hangar UI, drawn flight controls and the bigger ship/pod (2026-10-08/09) (iPad simulator) |
| Play phone + tablet screenshots 1920×1080 | `screenshots/play_1080/` | ⚠ **recapture**: taken 2026-10-07, before the holo hangar UI, drawn flight controls and the bigger ship/pod (2026-10-08/09) |
| Play feature graphic 1024×500 | `feature_graphic_1024x500.png` | ⚠ **regenerate** after the screenshots (old ship/pod size); AI key art optional: prompt C |
| Store texts | `listing_en.md` | ✅ checked against the character limits |
| App Preview videos + YouTube promo | `video/` | ⏳ record on the iPhone, then run `tool/store/make_videos.sh` (needs `brew install ffmpeg`) |
| IAP review screenshot (both products) | — | ⏳ Settings on the iPhone with a sandbox account: the buy rows only show when the store returns products |
| Promoted IAP image 1024 (optional) | — | ⏳ prompt E |
| IAP images (`nh_demo_kit`, `nh_arsenal_crate`, `nh_fleet_pass`, `nh_full_game`, `nh_supporter_pack`) | `iap/<id>_1024.png`, `iap/<id>_512.png` | ✅ `tool/store/make_pack_images.py` (needs Pillow) |

Worth adding to the set: a weapons shot (a charge carving rock), Garage → Armory, and the mission briefing.

Suggested screenshot order (store pages show the first 3 most): `01_alien_05`, `04_lava_03`,
`05_orbit_02`, `06_redoubt_02`, `03_ice_03`, `10_level_complete`, `02_mine_03`, `08_missions`,
`11_garage`, `12_logbook`. Skip `13_settings_iap` on the listing.

## App Store Connect → Narrow Haul → iOS App → 1.0 Prepare for Submission

1. **Previews and Screenshots**
   - iPhone 6.9" Display: `screenshots/ios_69/` (up to 10) + `video/preview_iphone.mp4`
   - iPad 13" Display: `screenshots/ios_ipad13/` (up to 10) + `video/preview_ipad.mp4`
   - Smaller devices reuse these automatically.
2. **Promotional Text, Description, Keywords, Support URL, Marketing URL** from `listing_en.md`.
3. **Build:** upload from Xcode/Transporter. The icon comes from the binary; you don't upload it separately.
4. **App Information:** subtitle, category Games → Arcade (secondary Action), age rating questionnaire, copyright.
5. **App Privacy:** AdMob data (identifiers, usage data, diagnostics, used for third-party advertising), Firebase Analytics (product interaction, device ID, diagnostics: Analytics, not linked, no tracking), Crashlytics (crash data) and the privacy URL.
6. **In-App Purchases:** for each of `nh_full_game` (Full Game, $4.99: every Expedition + no ads) and `nh_supporter_pack` (Supporter Pack, $7.99: the Full Game + livery + 500 coins) (**non-consumable**), plus `nh_demo_kit` (Demolition Kit, $1.99: 10 Demolition Charges, 10 Gravity Bombs, 60 s Mining Laser) and `nh_arsenal_crate` (Arsenal Crate, $4.99: 30 of each weapon, 180 s laser) as **consumables**, and `nh_fleet_pass` (Fleet Pass, $3.99: every ship, now and later) as a **non-consumable**. For each: display name, description, review screenshot (Garage → Armory, or Garage → Ships → a locked ship). Submit them together with the first version. In Play Console, create the two packs as one-time products too (the app consumes them itself).

### IAP review screenshots and notes, per product

Screenshots are in `art_src/store/iap_review/` at 2868×1320 (iPhone 6.9", landscape), the size App Store Connect's *Review Information → Screenshot* accepts. Re-render them with `tool/store/capture_screenshots.sh macos` (shots `13`–`16`, copied there by hand). Don't use the 1024×1024 images here: those go in the optional *Promotional Image* field.

**Google Play** has no review notes or review screenshot on one-time products: just the product ID, name, description and price. Nothing below is needed there.

| Product | App Store review screenshot | App Store review notes |
|---|---|---|
| `nh_full_game` | `iap_review/nh_full_game.png` (a paid Expedition's briefing with the Full Game button) | Non-consumable, bought once. Unlocks every Expedition after the first (the first one, "Lifeline Convoy", is free to play) and turns off the interstitial ads shown between missions. Optional rewarded ads stay available. Where to find it: Settings → Full Game (available right away), or Missions → "The Long Night" tab → tap a mission with a gold FULL GAME lock → the briefing's Full Game button (that tab opens after 8 stars, i.e. the Training Grounds). Restore: Settings → Restore purchases. |
| `nh_supporter_pack` | `iap_review/nh_supporter_pack.png` (Settings with the purchase rows) | Non-consumable, bought once. Includes everything in the Full Game (every Expedition, no interstitial ads), plus the exclusive Supporter ship livery (Garage → Liveries) and 500 in-game coins, credited once. Where to find it: Settings → Supporter Pack, or Garage → Liveries → Supporter Livery. Restore: Settings → Restore purchases (the coins are never credited twice). |
| `nh_fleet_pass` | `iap_review/nh_fleet_pass.png` (a locked ship's offer in Garage → Ships) | Non-consumable, bought once. Unlocks every ship in the hangar now and every ship added later. Each ship can also be earned for free by completing its type-rating mission, or bought with in-game coins. Does not remove ads. Where to find it: Garage → Ships → tap a locked ship, or Settings → Fleet Pass. Restore: Settings → Restore purchases. |
| `nh_demo_kit` | `iap_review/nh_ammo_packs.png` (Garage → Armory → AMMO PACKS) | Consumable. Adds 10 Demolition Charges, 10 Gravity Bombs and 60 seconds of Mining Laser to the player's weapon stock. Ammo is used up in flight, so the pack can be bought again. It is not restorable, by design (consumable). Where to find it: Garage → Armory → AMMO PACKS. A flight that uses bought ammo earns at most 2 of 3 stars, and every weapon can also be found free in supply crates during play. |
| `nh_arsenal_crate` | `iap_review/nh_ammo_packs.png` (same screen) | Consumable. Adds 30 Demolition Charges, 30 Gravity Bombs, 30 Seeker Missiles, 30 Flak Bursts and 3 minutes of Mining Laser to the player's weapon stock. Ammo is used up in flight, so the pack can be bought again. It is not restorable, by design (consumable). Where to find it: Garage → Armory → AMMO PACKS. A flight that uses bought ammo earns at most 2 of 3 stars, and every weapon can also be found free in supply crates during play. |

### Full Game (`nh_full_game`): copy-ready

Bought once, kept for life (non-consumable, restorable). The product id must match exactly (`ProductIds.fullGame`). It replaces the earlier `nh_remove_ads`: don't create that one. If it already exists, leave it unused; product ids can't be reused or renamed.

| Field | Value |
|---|---|
| Type | Non-consumable (App Store) · One-time product (Play) |
| Product ID | `nh_full_game` |
| Reference name (App Store only) | Full Game |
| Price | $4.99 (USD 4.99; let the stores convert other countries) |
| Display name (≤ 30) | Full Game |
| Description (App Store ≤ 45) | Every Expedition, and no ads between missions. |
| Description (Play ≤ 200) | Unlock every Expedition (Act II: long multi-leg hauls with staging pads, the first one is free to try) and turn off the ads between missions for good. Optional rewarded ads stay available. |
| Promotional image (App Store, optional) | `art_src/store/iap/nh_full_game_1024.png` (1024×1024) |
| Review screenshot | `art_src/store/iap_review/nh_full_game.png` (2868×1320; see *IAP review screenshots and notes* above). Not the 1024×1024 image |
| Review notes | See *IAP review screenshots and notes* above |

The **Supporter Pack** (`nh_supporter_pack`) now includes the Full Game. Set its price to **$7.99**, with description (≤ 45) "Full Game, Supporter Livery and 500 coins." Play (≤ 200): "Everything in the Full Game (every Expedition, no ads between missions), plus the exclusive Supporter ship livery and 500 coins."

**App Store Connect:** My Apps → Narrow Haul → Monetization → **In-App Purchases** → **+** → *Non-Consumable* → Reference name `Full Game`, Product ID `nh_full_game` → Availability: all countries → Price Schedule: $4.99 → Localization (English U.S.): display name and description from the table → Review information: the screenshot and notes → Save. Then on the 1.0 version page, **In-App Purchases and Subscriptions** → **+** → select Full Game (and the other IAPs) so they're reviewed with the build.

**Play Console:** Narrow Haul → Monetize with Play → Products → **One-time products** → **Create one-time product** → Product ID `nh_full_game`, name and description from the table → **Add a purchase option** (buy, non-rentable) → price $4.99 → **Activate**. The app sees it only in a build uploaded after the BILLING permission is in (any internal-testing build of this app).

**Test it:** sandbox / licence-tester account:
1. Settings shows a *Full Game* row, and the briefing of a locked Expedition shows the button.
2. Buy it. The beacons open, the *Full Game* row turns into "Full Game · Thanks", and no interstitials show.
3. Settings → *Reset purchases (dev)* → *Restore purchases* brings it back.

### Fleet Pass (`nh_fleet_pass`): copy-ready

The product id must match exactly; the app finds the product by it (`ProductIds.fleetPass`).

| Field | Value |
|---|---|
| Type | Non-consumable (App Store) · One-time product (Play) |
| Product ID | `nh_fleet_pass` |
| Reference name (App Store only) | Fleet Pass |
| Price | $3.99 (USD 3.99; let the stores convert other countries) |
| Display name (≤ 30) | Fleet Pass |
| Description (App Store ≤ 45) | Every ship in the hangar, now and later. |
| Description (Play ≤ 200) | Unlock every ship in the hangar right away, plus every ship added in future updates. Each ship can also be earned for free by playing. Does not remove ads. |
| Promotional image (App Store, optional) | `art_src/store/iap/nh_fleet_pass_1024.png` (1024×1024). Play one-time products take no image |
| Review screenshot | Garage → Ships → tap a locked ship (the offer dialog with the Fleet Pass button). If every ship is already yours, run with `--dart-define=FLEET_PREVIEW=true`: all ships but the Kestrel show locked and the button shows before the store loads (save untouched) |
| Review notes | Non-consumable. Grants all ships (Garage → Ships). Restorable via Settings → Restore purchases. Ships can also be earned in game by completing each world's first mission. |

**App Store Connect:** My Apps → Narrow Haul → Monetization → **In-App Purchases** → **+** → *Non-Consumable* → fill the table → Availability: all countries → Price Schedule → add the English (U.S.) localization → upload the review screenshot → Save. Then in the 1.0 version page, **In-App Purchases and Subscriptions** → **+** → select Fleet Pass so it's reviewed with the build (the first IAPs must ship with a version).

**Play Console:** Narrow Haul → Monetize with Play → Products → **One-time products** → **Create one-time product** → Product ID `nh_fleet_pass`, name and description from the table → **Add a purchase option** (buy, non-rentable) → set price $3.99 → Activate. Play only shows products to builds uploaded *after* the app has the BILLING permission (the `in_app_purchase` plugin adds it), so an internal-testing build must be live first.

**Test it:** sandbox / licence-tester account → Settings shows a *Fleet Pass* row and a locked ship's offer shows the button → buy → every ship turns owned, ads still show → Settings → *Reset purchases (dev)* → *Restore purchases* brings it back.

## Play Console → Narrow Haul → Grow users → Store presence → Main store listing

1. **App icon:** `art_src/icon/play_icon_512.png`
2. **Feature graphic:** `feature_graphic_1024x500.png`
3. **Video:** upload `video/youtube_1080.mp4` to YouTube (public or unlisted, ads off) and paste the URL.
4. **Phone screenshots:** `screenshots/play_1080/` (up to 8). **7" and 10" tablet:** the same files, or `ios_ipad13/` for 4:3.
5. **App name, short description, full description** from `listing_en.md`.
6. **Policy → App content:** Ads = yes, Data safety (AdMob, Crashlytics, Firebase Analytics: app interactions, device IDs, purchase history), Advertising ID, content rating (IARC), target audience.
7. Upload a new AAB with the next build number (`pubspec.yaml` `1.0.0+N`) so the new icon and splash ship.

## Regenerate

```bash
python tool/store/make_icon.py && dart run flutter_launcher_icons
dart run flutter_native_splash:create        # then restore AndroidManifest.xml (see CLAUDE.md)
tool/store/capture_screenshots.sh            # macOS sets; add "ipad" for the iPad set
python tool/store/make_feature.py
tool/store/make_videos.sh art_src/store/video/raw/<file>.mov 0 28
```
