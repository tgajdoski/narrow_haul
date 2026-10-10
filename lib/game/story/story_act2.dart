// Act II, "The Long Night": the Expeditions (docs/STORY.md §3).

import 'package:narrow_haul/game/story/story.dart';

typedef _B = StoryBeat;
const _hooked = BeatCue.hooked;
const _landed = BeatCue.landed;

const Map<String, WorldStory> kExpeditionWorldStories = {
  'expeditions': WorldStory(
    place: 'Operation Lifeline',
    contact: Callsign.ops,
    intro: [
      'Expeditions are long hauls: several pods, one cave, staging pads between them.',
      'Land a pod on its pad and the crew there refuels you. Crash later, and you start again from that pad.',
    ],
    outro: [
      'The Narrows are sealed and saved. The Long Night is over.',
    ],
  ),
};

const Map<String, LevelStory> kExpeditionStories = {
  'exp_00': LevelStory(
    cargo: 'Seed vaults',
    from: Callsign.grove,
    brief: 'Three farms, three seed vaults, one long cave. The staging pads refuel you.',
    beats: [
      _B(Callsign.ops, 'Convoy drill, pilot. Every pad you land on refuels you and saves your place.', delay: 1),
      _B(Callsign.grove, 'First farm is right past the dip. They have the beds dug already.', cue: _hooked, leg: 0),
      _B(Callsign.grove, 'Farm one has its vault. The next pod is past the hollow, where nothing falls.',
          cue: _landed, leg: 0),
      _B(Callsign.grove, 'Farm two is planting. Last vault is down under the ledge. Then the long climb.',
          cue: _landed, leg: 1),
      _B(Callsign.ops, 'Last leg. Bring it home and the Grove eats this winter.', cue: _hooked, leg: 2),
    ],
    debrief: 'Three farms planted. The Grove will eat this winter.',
  ),
  'exp_01': LevelStory(
    cargo: 'Survivor capsules',
    from: Callsign.pithead,
    brief: 'A tremor brought the east shaft down. Four capsules, four trips. Go.',
    beats: [
      _B(Callsign.pithead, "Dutch here. The Tide's first tremor. My people sealed themselves in capsules.", delay: 1),
      _B(Callsign.pithead, "Got the first crew. Easy past the rotor, they're shaken enough.", cue: _hooked, leg: 0),
      _B(Callsign.ops, 'Capsule one is out. The pad crew has your tanks full.', cue: _landed, leg: 0),
      _B(Callsign.pithead, 'Two out. The rock is still moving down there. Keep going.', cue: _landed, leg: 1),
      _B(Callsign.pithead, "Three. One more crew, the deepest. They've stopped answering.", cue: _landed, leg: 2),
      _B(Callsign.pithead, "They're knocking on the hull! They're alive. Bring them up.", cue: _hooked, leg: 3),
    ],
    debrief: 'Every miner is out. Dutch stood the whole shift a round. Twice.',
  ),
  'exp_02': LevelStory(
    cargo: 'Vaccine',
    from: Callsign.frostline,
    brief: 'Three outposts, one vaccine batch, a warming clock. Fly fast, fly clean.',
    beats: [
      _B(Callsign.frostline, 'The Tide is pulling the heat out of everything. The outposts have hours, not days.',
          delay: 1),
      _B(Callsign.frostline, 'Batch one. Keep it moving, it warms in the wind.', cue: _hooked, leg: 0),
      _B(Callsign.frostline, 'Outpost one dosed. The next batch is waiting on the cold shelf.', cue: _landed, leg: 0),
      _B(Callsign.frostline, 'Two outposts safe. The last one is the farthest out.', cue: _landed, leg: 1),
      _B(Callsign.ops, 'Last batch aboard. The whole station is counting with you.', cue: _hooked, leg: 2),
    ],
    debrief: 'All three outposts dosed. Juno Kalt finally slept.',
  ),
  'exp_03': LevelStory(
    cargo: 'Evacuation pods',
    from: Callsign.crucible,
    brief: 'The Crucible is erupting. Four evacuation pods. Get the forge crew out.',
    beats: [
      _B(Callsign.crucible, 'Okonkwo. The core is waking up under us. Every pod carries three of my people.', delay: 1),
      _B(Callsign.crucible, 'First crew clear. The vents are getting stronger, mind the updrafts.', cue: _landed, leg: 0),
      _B(Callsign.crucible, "Two out. I'm staying until the last pod leaves.", cue: _landed, leg: 1),
      _B(Callsign.ops, 'Three out. Okonkwo, that last pod is you. Get in it.', cue: _landed, leg: 2),
      _B(Callsign.crucible, "I'm in. Fly, pilot. Don't look back at the forge.", cue: _hooked, leg: 3),
    ],
    debrief: 'The forge is lost. Every one of its people is not.',
  ),
  'exp_04': LevelStory(
    cargo: 'Shield emitters',
    from: Callsign.sable,
    brief: 'Four shield emitters round the Ring before the Tide arrives.',
    beats: [
      _B(Callsign.sable, 'The Tide is eleven days out. My estimate. I would prefer to be wrong.', delay: 1),
      _B(Callsign.sable, 'Emitter one. It is heavier than it looks. So am I, in a sense.', cue: _hooked, leg: 0),
      _B(Callsign.sable, 'Segment one live. Three to go. Please do not touch the wells.', cue: _landed, leg: 0),
      _B(Callsign.sable, 'Two segments. I can feel the shield. It feels like a coat.', cue: _landed, leg: 1),
      _B(Callsign.sable, 'Three. One more and the Ring is wrapped.', cue: _landed, leg: 2),
      _B(Callsign.sable, 'Last emitter. Thank you for coming back, pilot.', cue: _hooked, leg: 3),
    ],
    debrief: "The Ring's shield is up. SABLE logged it as 'a good day'.",
  ),
  'exp_05': LevelStory(
    cargo: 'Turret ammunition',
    from: Callsign.warden,
    brief: "The Warden asks for help holding the gate. Its guns don't know yet.",
    beats: [
      _B(Callsign.warden, 'Pilot. I was wrong to seal the gate alone. Bring my guns their ammunition.', delay: 1),
      _B(Callsign.sparrow, 'Its old defences still fire on anything. Shoot what you must.', delay: 6),
      _B(Callsign.warden, 'One battery armed. The others still see you as a threat. I am sorry.', cue: _landed, leg: 0),
      _B(Callsign.sparrow, 'Two batteries. The Warden is actually helping. Strange days.', cue: _landed, leg: 1),
      _B(Callsign.warden, 'The last battery guards the gate itself. Hurry. It is close now.', cue: _hooked, leg: 2),
    ],
    debrief: "The Warden's guns face outward now. The gate is held.",
  ),
  'exp_06': LevelStory(
    cargo: 'Xenar relics',
    from: Callsign.grove,
    brief: 'The Heart wants its relics back. Four of them, deep in the caves.',
    beats: [
      _B(Callsign.grove, 'The relics you found are Xenar shield keys. The Heart is calling them home.', delay: 1),
      _B(Callsign.grove, "The first relic is warm. That's new.", cue: _hooked, leg: 0),
      _B(Callsign.grove, 'The Heart brightened when that one landed. Three more.', cue: _landed, leg: 0),
      _B(Callsign.grove, 'Two keys home. The hum is a chord now.', cue: _landed, leg: 1),
      _B(Callsign.grove, 'Three. The gravity down there is unsettled. Careful.', cue: _landed, leg: 2),
    ],
    debrief: 'Four keys in the Heart. The old shield is waking.',
  ),
  'exp_07': LevelStory(
    cargo: "The Warden's core",
    from: Callsign.ops,
    brief: "The Tide is here. Carry the Warden's core to the Heart, piece by piece.",
    beats: [
      _B(Callsign.ops, 'All pilots. This is it. Lifeline flies tonight, all of us.', delay: 1),
      _B(Callsign.warden, 'My core is yours. Five pieces. Carry them to the Heart.', delay: 6),
      _B(Callsign.sable, 'The Tide reached the Ring. Shield holding. Keep flying.', cue: _landed, leg: 0),
      _B(Callsign.grove, 'The Heart is taking the core. Two pieces in.', cue: _landed, leg: 1),
      _B(Callsign.pithead, 'Pithead is dark but holding. Go, kid.', cue: _landed, leg: 2),
      _B(Callsign.frostline, 'Kalt is cold but alive. One more, pilot.', cue: _landed, leg: 3),
      _B(Callsign.warden, 'Last piece. When it lands, the Narrows close. Thank you.', cue: _hooked, leg: 4),
    ],
    debrief: 'The Narrows are sealed and saved. Somebody had to fly it in.',
  ),
};
