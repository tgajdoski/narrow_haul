# Camera

How Narrow Haul's flight camera works, why, and how to reuse it in another 2D flyer.

## Shape: a director and an applier

- **Director** (`lib/game/camera/camera_director.dart`, pure Dart, no Flame). Each frame it takes `CameraInputs`: ship position and velocity, launched, towing and pod position, the gap to rock along the velocity, the local "down", and the half-view at the rest zoom. It returns a `CameraShot` (focus x/y, and zoom relative to the rest zoom). All of its smoothing lives here, and it is frame-rate independent.
- **Applier** (`NarrowHaulGame._followCamera`). It feeds the director, multiplies the result by the rest zoom (`_baseZoom × screen scale × mode.zoomMul`), keeps the view inside the world (`_minContainZoom`, `_clampedCameraTarget`), then adds the shake.
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
| Careful zoom-in | After `restDelay` s slow (< 0.3 m/s), on the pad, or creeping (< 0.8 m/s within 2.5 m of rock): zoom in by `restZoomIn` | Precision for landings and tight gaps (Lunar Lander) |
| Tow framing | Focus `podWeight` toward the pod; zoom out just enough to keep it `podMargin` inside the view; plus `towZoomOut` | Multi-target framing (Cinemachine target group) |
| Asymmetric zoom | Out in `outTime` (0.25 s). In over `inTime` (1.2 s), and only after the target has stayed further in for `inHold` (0.6 s) | No "breathing" on every thrust tap; a quick zoom-out when danger appears |
| Log-space zoom | The springs run on `ln(zoom)`, clamped to 0.72–1.10 | A 10% step feels the same at any zoom |
| Springs | Exact critically damped step (`springStep`) | No overshoot, no jump in velocity, the same at 60 and 120 Hz |
| Trauma shake | Events add trauma (crash 1.0, blast 0.55); it decays 1.6/s; offset = 0.45 m × trauma² × smooth noise; the meltdown sets a `floor` | Shake scales with severity and never drifts the camera (Eiserloh, GDC 2016 "Juicing Your Cameras With Math") |
| Reduced motion | System setting: zoom swings halved (√ of the factor) and shake × 0.3 | Accessibility; Centred mode turns all of it off |

## Modes (Settings → camera, `CameraMode` in `flight_tuning.dart`)

| Mode | Lead | Down | Speed out | Impact out | Rest in | Tow out | Pod framing | Base |
|---|---|---|---|---|---|---|---|---|
| Dynamic (default) | 0.4 s | 0.5 m | 22% | 15% | 8% | 12% | yes | 1.0 |
| Look-ahead | 0.4 s | – | – | – | – | 12% | yes | 1.0 |
| Centred | – | – | – | – | – | – | – | 1.0 |
| Wide | 0.3 s | – | 10% | – | – | 8% | yes | 0.85 |

Tests: `test/camera_director_test.dart` (rest zoom-in, quick zoom-out, no pumping around the threshold, wall vs creeping approach, pod in view, range, 60 vs 120 Hz, Centred static, shake bounded). Cost: about 0.015 ms per frame (`camera` lap in the PERF bench), including the 3-ray `probeAhead` every other frame.
