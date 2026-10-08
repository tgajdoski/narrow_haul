# Store assets: what's ready and where it goes

How each asset is made: see "Store assets" in `CLAUDE.md`. Prompts for AI art are in
`PROMPTS.md`, and all listing texts are in `listing_en.md`.

## Status

| Asset | File | Status |
|---|---|---|
| App icon (iOS / Android / macOS, in the build) | `art_src/icon/icon_1024.png` → generated into the platform folders | ✅ built from the game sprites (AI version optional: prompts A/B) |
| Play listing icon 512×512 | `art_src/icon/play_icon_512.png` | ✅ |
| Launch screen (dark, ship mark) | in the build | ✅ |
| iPhone 6.9" screenshots 2868×1320 | `screenshots/ios_69/` | ✅ 13 shots |
| iPad 13" screenshots 2752×2064 | `screenshots/ios_ipad13/` | ✅ 13 shots (captured on the simulator) |
| Play phone + tablet screenshots 1920×1080 | `screenshots/play_1080/` | ✅ 13 shots |
| Play feature graphic 1024×500 | `feature_graphic_1024x500.png` | ✅ placeholder from gameplay (AI key art optional: prompt C) |
| Store texts | `listing_en.md` | ✅ checked against the character limits |
| App Preview videos + YouTube promo | `video/` | ⏳ record on the iPhone, then run `tool/store/make_videos.sh` (needs `brew install ffmpeg`) |
| IAP review screenshot (both products) | — | ⏳ Settings on the iPhone with a sandbox account: the buy rows only show when the store returns products |
| Promoted IAP image 1024 (optional) | — | ⏳ prompt E |
| Ammo pack images (`nh_demo_kit`, `nh_arsenal_crate`) | `iap/<id>_1024.png`, `iap/<id>_512.png` | ✅ `tool/store/make_pack_images.py` (needs Pillow) |

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
6. **In-App Purchases:** for each of `nh_remove_ads` and `nh_supporter_pack` (**non-consumable**), plus `nh_demo_kit` (Demolition Kit, $1.99: 10 Demolition Charges, 10 Gravity Bombs, 60 s Mining Laser) and `nh_arsenal_crate` (Arsenal Crate, $4.99: 30 of each weapon, 180 s laser) as **consumables**: display name, description, review screenshot (Garage → Armory). Submit them together with the first version. In Play Console, create the two packs as one-time products too (the app consumes them itself).

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
