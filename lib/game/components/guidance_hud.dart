/// In-flight guidance drawn into the cockpit HUD (see `flight_guidance.dart`
/// for what is shown when):
///
/// * [CoachMarkHud]: a ring on the control itself (THRUST, the steering
///   dial, FIRE) with a callout plate beside it. It collapses into the
///   control with a tick once the pilot has used it.
/// * [WorldMarkerHud]: target brackets on turrets, the pod's HOOK / LOWER
///   tag, the pad beacon with its ship + pod slots, a canister ring, the
///   flight drill ring, the nose-up cue on the ship, and edge chevrons for
///   whatever is off-screen.
/// * [CommsHud]: the radio line (TOWER / OPS) in the free band between the
///   thumbs, typed on and gone after its reading time.
library;

import 'package:narrow_haul/game/components/coach_mark_hud.dart';
import 'package:narrow_haul/game/components/comms_hud.dart';
import 'package:narrow_haul/game/components/world_marker_hud.dart';

export 'package:narrow_haul/game/components/coach_mark_hud.dart';
export 'package:narrow_haul/game/components/comms_hud.dart';
export 'package:narrow_haul/game/components/hud_holo.dart' show placeAvoiding;
export 'package:narrow_haul/game/components/world_marker_hud.dart';
