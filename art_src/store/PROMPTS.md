# Image-generation prompts — Narrow Haul store art

Use ChatGPT (image), Gemini/Imagen or Midjourney. Generate at the largest size
offered, then post-process locally. Keep the raw output here as `*_src.png`.

Game identity to keep consistent: teal delta-wing ship (`assets/ship.png`),
flat vector style with thick dark-navy outlines; orange spherical cargo pod
(`assets/cargo.png`) on a thin rope; cave rock `#1D3461` on space-blue
`#0B132B`; cyan accent `#00B4D8`; mint pad accent `#94D2BD`; title font
RussoOne (`assets/fonts/RussoOne-Regular.ttf`). Attach `assets/ship.png` and
`assets/cargo.png` as reference images when the tool allows it.

---

## A. App icon (master) → `art_src/icon/icon_1024_src.png`

> Mobile game app icon, square 1024×1024, full-bleed (no rounded corners, no
> border, no text). A small teal delta-wing spaceship (flat vector style, thick
> dark navy outline, cel-shaded panels, teal #1FA3C4) diving through a narrow
> glowing cave gap, towing an orange-red spherical cargo pod on a taut thin
> rope below it. Bright cyan-white thruster flame. Dark navy cave rock (#1D3461)
> frames the left and right edges, deep space-blue background (#0B132B) with a
> soft cyan rim light (#00B4D8) along the rock edges. Bold, simple silhouette
> that reads at 60 px, centred composition, high contrast, clean 2D game art,
> no noise, no lettering.

## B. Icon foreground layer → `art_src/icon/icon_fg_src.png`

Same as A, but replace the scene with:

> …the ship, rope and cargo pod only, on a pure flat magenta #FF00FF
> background, nothing else, subject fills the central 60% of the canvas.

Used for the Android adaptive/themed icon, the iOS dark/tinted icon and the
launch screen. The magenta is keyed out in post.

Today's icon is built without AI by `tool/store/make_icon.py` (from the game
sprites). To switch to AI art, save A and B as above, then ask Claude to key
them into the same `art_src/icon/*.png` names and rerun
`dart run flutter_launcher_icons`.

## C. Feature graphic / key art → `art_src/store/feature_src.png`

> Wide cinematic 2D game key art, 2048×1000. A teal delta-wing cargo spaceship
> (flat vector, thick dark outline) threads a winding cave tunnel, towing an
> orange spherical cargo pod on a rope. The cave changes left to right through
> themed zones: purple alien caverns with mint crystals, an amber-lit mine with
> timber, icy blue tunnels, glowing lava rock. Thruster glow, floating dust
> particles, depth through parallax layers, dark navy palette with cyan
> accents. Leave the left third calm and darker for a title. No text.

Then: downscale to 1024×500, overlay "NARROW HAUL" in RussoOne in the left
third, export as JPG or 24-bit PNG with no alpha. Keep the centre free of
important detail, because Play draws a play button there when a promo video
is set.

## D. Screenshot caption backgrounds (optional)

> Seamless dark navy (#0B132B) abstract cave-rock texture with faint cyan edge
> glow, low contrast, suitable as a background behind UI text, 2868×1320, no
> objects, no text.

Suggested captions, one per screenshot:
- "Tow cargo through living caves"
- "6 worlds · 6 ships"
- "Ice, wind and lava"
- "Gravity wells & zero-g"
- "Fight through The Redoubt"
- "Earn your wings: 10 pilot ranks"

## E. Supporter Pack promo image (optional, App Store promoted IAP, 1024×1024)

> Square icon-style art: gold-trimmed variant of the teal delta-wing ship with
> a small heart emblem on the hull, starburst background in navy and gold,
> flat vector, thick dark outline, no text.

## F. YouTube trailer title cards (Play promo video only)

Apple App Previews must show only footage captured from the app, so these
cards go only in `youtube_1080.mp4`. Use C at 1920×1080 with the title as an
intro card, and "Free on iOS & Android" as the outro card.

## Video (not AI — record the real game)

Apple requires App Preview footage to come from the app. Record on your
iPhone in release mode, then run `tool/store/make_videos.sh` (see the header
of that script).
Shot list (~28 s): launch off the pad → hook the pod (rope snaps taut) → thread
an Ice tunnel with wind streaks → swing past a Lava pendulum → slingshot round
an Orbit gravity well → Talon shoots a turret in The Redoubt → land both on the
pad → 3★ result screen.
