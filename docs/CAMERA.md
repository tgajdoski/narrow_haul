# Camera

How Narrow Haul's flight camera works, why, and how to reuse it in another 2D flyer.

## Shape: a director and an applier

- **Director** (`lib/game/camera/camera_director.dart`, pure Dart, no Flame). Each frame it takes `CameraInputs`: ship position and velocity, launched, towing and pod position, the gap to rock along the velocity, the local "down", and the half-view at the rest zoom. It returns a `CameraShot` (focus x/y, and zoom relative to the rest zoom). All of its smoothing lives here, and it is frame-rate independent.
- **Applier** (`NarrowHaulGame._followCamera`). It feeds the director, multiplies the result by the rest zoom (`_baseZoom × screen scale × mode.zoomMul`), keeps the view inside the world (`_minContainZoom`, `_clampedCameraTarget`), shifts it so the ship isn't under a control (the safe frame, below), then adds the shake.
- **Shake** (`TraumaShake`) is an offset added *after* the follow (`_applyShake`) and removed before the next frame (`_removeShake`), so the follow never sees it.

To port it, copy `camera_director.dart`, build `CameraInputs` from your physics body, and apply the shot to your engine camera. Only the profiles and the inputs are game-specific.

## Behaviours and the reasoning behind them

| Behaviour | Rule | Why |
|---|---|---|
| Look-ahead | Focus leads `velocity × lead` (cap `leadMax`), eased by a spring over `leadTime` | Show where you're going, not where you've been |
| Down bias | Focus sits `downBias` m toward local gravity (fields included; none in zero-g) | Pads and pods are below; gravity pulls you there |
| Dead zone | The ship can wander `deadZone` m before the camera follows | Hover jitter doesn't shake the world |
| Speed zoom | Zoom out by `speedZoomOut × smoothstep(speedLo, speedHi, speed)` | More reaction distance at speed (Thrust, Gravitar, Solar Jetman) |
| Impact zoom | Extra zoom-out by `impactZoomOut` once time to impact (gap ahead ÷ speed) drops under `impactSeconds`, full at 0.5 s | Based on closing speed, not proximity: a fast approach needs room |
| Careful zoom-in | After `restDelay` (0.8 s) slow (< 0.3 m/s), on the pad, or creeping (< 0.8 m/s within 2.5 m of rock): zoom in by `restZoomIn` | Precision for landings and tight gaps (Lunar Lander) |
| Hands-off zoom-in | Once no thrust, turn or fire for `restDelay`: the speed zoom-out lets go and the view closes in, even while falling (impact and pod framing still apply) | Not touching the controls means watching, not flying: show the ship big |
| Tow framing | Focus `podWeight` toward the pod; zoom out just enough to keep it `podMargin` inside the view; plus `towZoomOut` | Multi-target framing (Cinemachine target group) |
| Asymmetric zoom | Out in `outTime` (0.25 s). In over `inTime` (1.2 s), and only after the target has stayed further in for `inHold` (0.6 s) | No "breathing" on every thrust tap; a quick zoom-out when danger appears |
| Log-space zoom | The springs run on `ln(zoom)`, clamped to 0.85–1.15 | A 10% step feels the same at any zoom; the floor keeps the ship from getting small |
| Safe frame | `safeFrameNudge`: if the ship's screen point (plus its radius) is inside a control zone (`HudTouchControls.controlZones`: the dial at rest and while held, the THRUST/FIRE/rail cluster, plus the top-left gauges), shift the view the shorter way out, up or toward the centre, never toward an edge. Eased in 0.3 s, out 0.8 s. The view may look up to `kCameraOverscroll` (6 m; 3 m at the top) past the world, where the rock is drawn (`CaveTerrain.buildRockPath`, `WorldFrame` on tutorial levels) | Touch controls cover the bottom corners of a phone; near the floor the world clamp would park the ship under a thumb |
| Text stays off the ship | The coach plate and the comms line try their other spots (`placeAvoiding`) when they'd cover the ship or pod, and fade to a ghost (25–30%) if every spot does. A crate's "loaded" plate is see-through and shows once per weapon | Help must never hide the thing it's helping you fly |
| Close-ups | `CloseUp` multiplies the zoom on top of the follow. Level start: 2.2× on the ship (2.6× on a new ship's first flight, 1.5× on a retry), held through the level card, eased out over 3 · 2 · 1 to the flight view at GO; any input releases it in 0.45 s; without a countdown (onboarding) it holds until the first input. The ship is framed at 72% of the screen height, below the level card and the countdown digits. Delivery: a 1.5× push-in on ship and pod during the 1.1 s before the result screen. Off in Centred mode, demos and store captures; reduced motion keeps 40% of it | Show off the lit, animated ship when nothing else is happening, without ever costing the player control |
| Springs | Exact critically damped step (`springStep`) | No overshoot, no jump in velocity, the same at 60 and 120 Hz |
| Trauma shake | Events add trauma (crash 1.0, blast 0.55); it decays 1.6/s; offset = 0.45 m × trauma² × smooth noise; the meltdown sets a `floor` | Shake scales with severity and never drifts the camera (Eiserloh, GDC 2016 "Juicing Your Cameras With Math") |
| Reduced motion | System setting: zoom swings halved (√ of the factor) and shake × 0.3 | Accessibility; Centred mode turns all of it off |

## Modes (Settings → camera, `CameraMode` in `flight_tuning.dart`)

| Mode | Lead | Down | Speed out | Impact out | Rest in | Tow out | Pod framing | Base |
|---|---|---|---|---|---|---|---|---|
| Dynamic (default) | 0.4 s | 0.5 m | 10% | 8% | 12% (also hands-off) | 8% | yes | 1.0 |
| Look-ahead | 0.4 s | – | – | – | – | 12% | yes | 1.0 |
| Centred | – | – | – | – | – | – | – | 1.0 |
| Wide | 0.3 s | – | 6% | – | – | 8% | yes | 0.85 |

Tuned from the first iPhone test (2026-10-09): the first Dynamic numbers (22% / 15% out, 0.72 floor) felt too far out.

Tests: `test/camera_close_up_test.dart` (in the real game: close on load, back by GO, released by input, none in Centred, delivery push-in), `test/camera_director_test.dart` (close-up timeline, rest and hands-off zoom-in, quick zoom-out, no pumping around the threshold, wall vs creeping approach, pod in view, range, 60 vs 120 Hz, Centred static, shake bounded, safe-frame pushes), `test/camera_safe_frame_test.dart` (in the real game, both hands: a ship in the floor corners ends up clear of the controls), `test/flight_guidance_test.dart` (`placeAvoiding`). Cost: about 0.025 ms per frame (`camera` lap in the PERF bench), including the 3-ray `probeAhead` every other frame.
