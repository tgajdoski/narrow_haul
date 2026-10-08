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
- "7 worlds · 6 ships"
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

## G. Cargo pods per world → `art_src/cargo/<world>[_heavy]_1024_src.png`

In flight the pod is only about 0.27 m across, which is roughly 8 pt, or 24 px
on a phone, so detail disappears. Each pod needs one bold silhouette, one strong
colour that stands out against its world's rock, and a thick dark outline. The
pod rolls, so it must be round (no corners, no spikes or antennae sticking out).

Shared style (append to each prompt below):

> Single game sprite, 2D flat vector with cel shading, thick dark navy
> outline (#14213D), seen straight on, perfectly round overall silhouette,
> centred, filling about 85% of a 1024×1024 square canvas, on a flat plain
> light-grey background (#CCCCCC), no shadow on the ground, no text, no
> lettering. Bold and simple: must still read clearly at 24×24 px. Match the
> style of the attached ship and cargo sprites.

Attach `assets/ship.png` and `assets/cargo.png` as style references.

| File | World (rock colour) | Prompt |
|---|---|---|
| `tutorial` | Training (navy `#1D3461`) | A clean orange (#E07A5F) training cargo sphere with two white hazard stripes and a small top handle. |
| `alien` | Xenar (purple `#3B2166`) | A glowing mint-green (#7EF9D2) alien bio-egg, slightly oval, with a soft inner glow and darker veins. |
| `mine` | Mine (brown `#4A3524`) | A round ore pod: chunky gold-yellow (#FFB74D) ore nuggets inside a dark steel spherical cage. |
| `ice` | Ice (steel blue `#35617F`) | A cryo canister seen end-on: a white-and-cyan (#E0F7FF) round lid with a frosted glass ring and a small blue status light. |
| `lava` | Lava (dark red `#4A1B12`) | A pale steel containment sphere (#D8DEE6) with glowing orange vents showing the magma core inside. |
| `orbit` | Orbit (slate `#2A2F45`) | A satellite core: a white sphere with lavender (#8C9EFF) solar-panel tiles in a band, folded flush, no antennae. |
| `redoubt` | Redoubt (grey `#363C47`) | An armoured munitions sphere, olive-yellow (#FFCA28) with black chevron hazard bands and riveted plates. |
| `mine_heavy`, `ice_heavy`, `lava_heavy` | as above | The same object as its world's pod, but in darker gunmetal with two thick riveted steel bands wrapped around it, so it looks dense and heavy. |

Optional, for a future capsule-shaped cargo (not bundled): `ice_side` is the
same cryo canister seen from the side, a short capsule about 2:1, same style.

Then frame each one into the game:

    python art_src/cargo/fix_cargo.py art_src/cargo/mine_1024_src.png assets/themes/mine/cargo.png
    python art_src/cargo/fix_cargo.py art_src/cargo/mine_heavy_1024_src.png assets/themes/mine/cargo_heavy.png

The script removes the background, centres the pod and scales it so its solid
part fills 80% of a 128 px square (`CargoBody` draws every pod at that framing).
`flutter test test/cargo_art_test.dart` checks the framing.

## Video (not AI — record the real game)

Apple requires App Preview footage to come from the app. Record on your
iPhone in release mode, then run `tool/store/make_videos.sh` (see the header
of that script).
Shot list (~28 s): launch off the pad → hook the pod (rope snaps taut) → thread
an Ice tunnel with wind streaks → swing past a Lava pendulum → slingshot round
an Orbit gravity well → Talon shoots a turret in The Redoubt → land both on the
pad → 3★ result screen.
