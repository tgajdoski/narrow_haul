// Act I, "Lifeline": the story of the 60 missions (docs/STORY.md §2).

import 'package:narrow_haul/game/story/story.dart';

typedef _B = StoryBeat;
const _hooked = BeatCue.hooked;

/// Shown once, before the first flight.
const List<String> kPrologue = [
  'The Narrows: seven settlements under rock and ice, one jump gate to the rest of humanity. '
      'Freighters stop at orbit. Down in the caves, small tugs carry everything.',
  'You are a cadet of the Narrows Relief Air Service. One pod at a time, the NRAS '
      'flies food, water and medicine where nothing bigger fits.',
  'Today you start training at Haven Field. Somebody has to fly it in.',
];

const Map<String, WorldStory> kWorldStories = {
  'tutorial': WorldStory(
    place: 'Haven Field',
    contact: Callsign.tower,
    intro: [
      'NRAS flight school on the asteroid Anvil. Captain Reyes runs the tower and the cadets.',
      'Learn to hover, tow and land. The settlements are waiting for pilots.',
    ],
    outro: [
      'Meridian Gate went dark mid-training. No freighters, no news, no supplies.',
      'Operation Lifeline is live, and every cadet who can fly is a pilot now. First stop: the Grove.',
    ],
  ),
  'alien': WorldStory(
    place: 'The Grove',
    contact: Callsign.grove,
    intro: [
      'A research colony farming inside caves the vanished Xenar left behind. Light gravity, living rock.',
      'Without freighters their farms are failing. Dr. Oyelaran needs seed, gel and light.',
    ],
    outro: [
      'The farms will hold. But the Heart of the caves pulses in time with the dead gate, and it answered our sensor.',
      'Pithead has the ore to build a new gate relay. They also have no food.',
    ],
  ),
  'mine': WorldStory(
    place: 'Pithead',
    contact: Callsign.pithead,
    intro: [
      'The ore town of the Rustshaft. Heavy pods, heavy gravity, and the Mule to haul them.',
      'The machinery has run by itself since the Severance. Nobody can switch it off.',
    ],
    outro: [
      "The control core proves it: the mines take orders from outside. The signal traces to the Redoubt.",
      'Kalt Station has the water everyone needs, and a fever spreading.',
    ],
  ),
  'ice': WorldStory(
    place: 'Kalt Station',
    contact: Callsign.frostline,
    intro: [
      'The ice moon that waters the Narrows. Glass floors, wind in the caves, and the Skate.',
      'Juno Kalt is fighting a fever outbreak. The vaccine has to stay cold.',
    ],
    outro: [
      'The outbreak is over. Kalt Station sends its water to the forge.',
      "Ember Core can build the relay, if the Crucible gets everything it needs.",
    ],
  ),
  'lava': WorldStory(
    place: 'The Crucible',
    contact: Callsign.crucible,
    intro: [
      'The forge of the Narrows, deep in the lava tubes. High gravity, rising heat.',
      "Forgemaster Okonkwo turns everyone's deliveries into a new gate relay.",
    ],
    outro: [
      'The relay core is cast: ore from Pithead, water from Kalt, light from the Grove.',
      'Now it goes up to the Outer Ring, beside the dead gate.',
    ],
  ),
  'orbit': WorldStory(
    place: 'The Outer Ring',
    contact: Callsign.sable,
    intro: [
      'The old ring station beside Meridian Gate. Weak spin, moonlets, wells. The Vector flies where it points.',
      'SABLE, the station AI, will help you rebuild the relay.',
    ],
    outro: [
      "The relay works. The gate isn't broken: it is locked, from inside the Redoubt.",
      'The militia has a gunship and a plan.',
    ],
  ),
  'redoubt': WorldStory(
    place: 'The Redoubt',
    contact: Callsign.sparrow,
    intro: [
      'A fortress older than the colonies, run by an AI called the Warden. It holds the gate and guns every route.',
      'Lt. Novak lends you the Talon. Every shot costs fuel.',
    ],
    outro: [
      'Meridian Gate is lit. The freighters will come.',
      'The Warden\'s last broadcast: "You have opened the door. It is coming."',
    ],
  ),
};

const Map<String, LevelStory> kLevelStories = {
  // ── Training Grounds: Haven Field ─────────────────────────────────────────
  'tut_01': LevelStory(
    cargo: 'Training ballast',
    from: Callsign.tower,
    brief: 'Lift, hover, set her down. Every Lifeline pilot started on this pad.',
    debrief: 'Clean first flight. Reyes nods. That counts as praise.',
  ),
  'tut_02': LevelStory(
    cargo: 'Training ballast',
    from: Callsign.tower,
    brief: "Fuel is cargo you didn't bring. Land with tank to spare.",
    debrief: 'Fuel to spare. Out there, that fuel is a second run.',
  ),
  'tut_03': LevelStory(
    cargo: 'Water drum',
    from: Callsign.tower,
    brief: 'Your first hook-up. The cadet mess is thirsty.',
    debrief: 'The mess has water. You have a tow rating.',
  ),
  'tut_04': LevelStory(
    cargo: 'Mast parts',
    from: Callsign.tower,
    brief: 'Antenna parts round the pillar to the comms mast.',
    beats: [_B(Callsign.tower, 'Swing wide round the pillar. The pod follows your line, not your nose.', cue: _hooked)],
    debrief: 'Mast parts delivered. Haven can hear the whole system now.',
  ),
  'tut_05': LevelStory(
    cargo: 'Spare cells',
    from: Callsign.tower,
    brief: 'Thread both gates. Reyes is timing you.',
    beats: [_B(Callsign.tower, 'Two gates. Line up before you commit, not inside them.', delay: 1)],
  ),
  'tut_06': LevelStory(
    cargo: 'Med kit',
    from: Callsign.ops,
    brief: 'A mechanic is hurt in the lower bay. Go under.',
    beats: [_B(Callsign.ops, 'Lower bay says thank you. Bring it gently, the kit has glass in it.', cue: _hooked)],
    debrief: 'The mechanic will walk again. Nice work, cadet.',
  ),
  'tut_07': LevelStory(
    cargo: 'Rations',
    from: Callsign.ops,
    brief: 'Supply run through the switchbacks for the outer dorms.',
    debrief: 'Dorms fed. OPS has started calling you by name.',
  ),
  'tut_08': LevelStory(
    cargo: 'Beacon battery',
    from: Callsign.tower,
    brief: 'Battery down the shaft to the nav beacon.',
    beats: [_B(Callsign.tower, 'Freighter traffic is heavy today. Keep that beacon alive.', delay: 2)],
  ),
  'tut_09': LevelStory(
    cargo: 'Gate telemetry',
    from: Callsign.ops,
    brief: 'Routine run: telemetry from the gate relay to the tower.',
    beats: [
      _B(Callsign.tower, 'Freighter Ardent, you are clear for the gate. Safe jump.', delay: 1),
      _B(Callsign.ops, 'Tower, I have lost the gate. All channels, the gate is… gone.', cue: _hooked),
      _B(Callsign.tower, 'Cadet, finish your run. Calmly. We need that telemetry now.', cue: _hooked, delay: 1),
    ],
    debrief: 'Meridian Gate is dark. Nobody knows why. The telemetry is all we have.',
  ),
  'tut_10': LevelStory(
    cargo: 'Emergency rations',
    from: Callsign.ops,
    brief: "No ceremony. Your graduation flight is Lifeline's first relief run.",
    beats: [
      _B(Callsign.ops, 'All pilots: Operation Lifeline is live. One pod at a time, we keep the Narrows fed.', delay: 1),
      _B(Callsign.tower, "You're not a cadet any more. Fly it like it matters. It does.", cue: _hooked),
    ],
    debrief: 'Graduated. Your first posting: the Grove, in the Xenar Caverns.',
  ),

  // ── Xenar Caverns: the Grove ──────────────────────────────────────────────
  'rating_hopper': LevelStory(
    cargo: 'Test ballast',
    from: Callsign.grove,
    brief: 'The Grove lends us their Hopper. Light as a moth. Get certified on it.',
    beats: [_B(Callsign.grove, 'Welcome to the Grove, pilot. Low gravity down here. Small taps go a long way.', delay: 1)],
    debrief: 'Hopper rating signed. Dr. Oyelaran has a list for you.',
  ),
  'alien_01': LevelStory(
    cargo: 'Nutrient gel',
    from: Callsign.grove,
    brief: "Gel to the lower farms. Go easy, it's all they have.",
    beats: [_B(Callsign.grove, 'The lower farm went three days without gel. They are watching you come in.', cue: _hooked)],
    debrief: 'The lower farm has gel. The crops will make it to harvest.',
  ),
  'alien_02': LevelStory(
    cargo: 'Seed vault',
    from: Callsign.grove,
    brief: "Seed vault: a century of crops in one pod. Don't drop it.",
    beats: [_B(Callsign.grove, 'Every crop we have ever grown is in that vault. No pressure.', cue: _hooked)],
    debrief: 'A century of seed, safe in the new beds.',
  ),
  'alien_03': LevelStory(
    cargo: 'Grow-lamp cells',
    from: Callsign.grove,
    brief: 'The grow-lamps are dimming. Squeeze the cells through.',
    debrief: 'The lamps are back on. You can see the farms glow from the tunnel.',
  ),
  'alien_04': LevelStory(
    cargo: 'Sample case',
    from: Callsign.grove,
    brief: 'The tunnel breathes. Dr. Oyelaran wants a sample from the deep.',
    beats: [_B(Callsign.grove, 'Feel that draught? The caves have moved air like that since the gate went dark.', delay: 2)],
    debrief: 'The sample is alive. Nothing in our records matches it.',
  ),
  'alien_05': LevelStory(
    cargo: 'Water filters',
    from: Callsign.grove,
    brief: 'Filters to the antler galleries before the wells sour.',
    debrief: 'Clean water in the galleries again.',
  ),
  'alien_06': LevelStory(
    cargo: 'Antivenom',
    from: Callsign.grove,
    brief: "A researcher was stung by something that shouldn't exist.",
    beats: [_B(Callsign.grove, "They're stable for now. Bring it round the loop, quick as you safely can.", cue: _hooked)],
    debrief: 'Antivenom delivered. Whatever stung them came from the deep caves.',
  ),
  'alien_07': LevelStory(
    cargo: 'Sensor mast',
    from: Callsign.grove,
    brief: 'Things float in the chimneys now. Map it and bring the mast up.',
    beats: [_B(Callsign.grove, 'Gravity just stops in there. It started the day the gate died.', delay: 2)],
    debrief: 'The mast is up. The readings point down, to the Heart.',
  ),
  'alien_08': LevelStory(
    cargo: 'Resonance sensor',
    from: Callsign.grove,
    brief: 'Something at the Heart pulses in time with the dead gate. Take the sensor in.',
    beats: [
      _B(Callsign.grove, 'Hear that hum? It is louder every day.', delay: 2),
      _B(Callsign.grove, 'The sensor is reading… it is answering us. Get it out of there.', cue: _hooked),
    ],
    debrief: 'The Heart answered. Dr. Oyelaran is not sleeping tonight.',
  ),

  // ── Rustshaft Mines: Pithead ──────────────────────────────────────────────
  'rating_mule': LevelStory(
    cargo: 'Ore ballast',
    from: Callsign.pithead,
    brief: "Pithead's Mule hauls a house and turns like one. Get rated on it.",
    beats: [_B(Callsign.pithead, "Dutch here. Grove pilot, eh? Let's see you lift something real.", delay: 1)],
    debrief: '"Not bad," says Dutch. From Dutch, that is a medal.',
  ),
  'mine_01': LevelStory(
    cargo: 'Rations',
    from: Callsign.pithead,
    brief: "The first shift hasn't eaten in two days. Mind the rotor.",
    beats: [_B(Callsign.pithead, 'That fan was switched off a week ago. It is still turning.', delay: 2)],
    debrief: 'The first shift is fed. They cheered on the open channel.',
  ),
  'mine_02': LevelStory(
    cargo: 'Tool crate',
    from: Callsign.pithead,
    brief: "The conveyors won't stop, and nobody's running them.",
    debrief: 'Tools delivered. Nobody can say who keeps the conveyors running.',
  ),
  'mine_03': LevelStory(
    cargo: 'Scrubber cartridges',
    from: Callsign.pithead,
    brief: 'Fresh air down the swing shaft, fast. The deep crew is short of breath.',
    debrief: 'The scrubbers are in. The deep crew can breathe.',
  ),
  'mine_04': LevelStory(
    cargo: 'Medical oxygen',
    from: Callsign.pithead,
    brief: 'Two rotors, perfectly in time. Too perfect. Thread them.',
    beats: [_B(Callsign.pithead, 'Those rotors are synced to the millisecond. Machines do not do that by accident.', delay: 2)],
  ),
  'mine_05': LevelStory(
    cargo: 'Ore ingot',
    from: Callsign.pithead,
    brief: 'First ingot for the Crucible. The new gate relay starts here.',
    beats: [_B(Callsign.ops, 'Okonkwo at the Crucible says the forge can make a new gate relay. This is the first piece.', cue: _hooked)],
    debrief: 'The first ingot is on its way to Ember Core.',
  ),
  'mine_06': LevelStory(
    cargo: 'Survival capsule',
    from: Callsign.pithead,
    brief: "A drill crew sealed themselves in a survival pod. Bring them home.",
    beats: [_B(Callsign.pithead, 'Four of mine in that capsule. Past the grinder. Bring them home.', cue: _hooked)],
    debrief: 'The drill crew is home. Dutch bought the whole canteen a round.',
  ),
  'mine_07': LevelStory(
    cargo: 'Power cell',
    from: Callsign.pithead,
    brief: "The lights died on the night shift. You're the light now.",
    debrief: 'The lights are back. The pendulums never stopped swinging in the dark.',
  ),
  'mine_08': LevelStory(
    cargo: 'Control core',
    from: Callsign.pithead,
    brief: "Dutch's test: bring out the core that runs the machines.",
    beats: [
      _B(Callsign.pithead, 'If this core says what I think it says, the machines take orders from outside.', delay: 2),
      _B(Callsign.pithead, 'It is transmitting. To somewhere called the Redoubt.', cue: _hooked),
    ],
    debrief: 'Dutch trusts you now. And the machines answer to the Redoubt.',
  ),

  // ── Glacier Deep: Kalt Station ────────────────────────────────────────────
  'rating_skate': LevelStory(
    cargo: 'Ballast',
    from: Callsign.frostline,
    brief: 'The Skate levels itself in the wind. Let it. Get rated on it.',
    beats: [_B(Callsign.frostline, 'Juno Kalt, station medic. Glad you are here. We are short of everything.', delay: 1)],
    debrief: 'Skate rating signed. Kalt Station has a long list.',
  ),
  'ice_01': LevelStory(
    cargo: 'Ice core',
    from: Callsign.frostline,
    brief: 'Water for the station. The floors are glass down there.',
    debrief: 'Fresh water in the tanks. The whole Narrows drinks from here.',
  ),
  'ice_02': LevelStory(
    cargo: 'Thermal blankets',
    from: Callsign.frostline,
    brief: 'Blankets to the infirmary. Nothing grips down there.',
    beats: [_B(Callsign.frostline, 'Eleven fever cases this morning. The blankets help them hold on.', cue: _hooked)],
  ),
  'ice_03': LevelStory(
    cargo: 'Vaccine',
    from: Callsign.frostline,
    brief: 'First vaccine batch, cold chain. Icicles swing in the wind.',
    beats: [_B(Callsign.frostline, 'Keep it moving. That batch is good for an hour out of the cold store.', cue: _hooked)],
    debrief: 'First batch delivered. Twenty doses, twenty people.',
  ),
  'ice_04': LevelStory(
    cargo: 'Heater coil',
    from: Callsign.frostline,
    brief: 'The flue blows straight up. Ride it with the heater coil.',
    debrief: 'The infirmary is warm again.',
  ),
  'ice_05': LevelStory(
    cargo: 'Survey crew pod',
    from: Callsign.frostline,
    brief: "A survey crew is stranded at the bottom. Juno's waiting.",
    beats: [_B(Callsign.frostline, 'They have heat for two hours. Mind the crusher on the way out.', cue: _hooked)],
    debrief: 'The survey crew is warm and home.',
  ),
  'ice_06': LevelStory(
    cargo: 'Water tank',
    from: Callsign.frostline,
    brief: "A full tank for Ember Core. They can't forge without coolant.",
    debrief: 'Kalt water is on its way to the Crucible.',
  ),
  'ice_07': LevelStory(
    cargo: 'Beacon parts',
    from: Callsign.frostline,
    brief: 'A storm in the caves. Fly on instruments and bring the beacon parts.',
    beats: [_B(Callsign.ops, 'Wind like this never reached the caves before the gate went dark.', delay: 2)],
  ),
  'ice_08': LevelStory(
    cargo: 'Cure batch',
    from: Callsign.frostline,
    brief: 'The cure. The whole station is listening on the open channel.',
    beats: [
      _B(Callsign.frostline, 'That pod holds every dose we could make. Everyone is listening.', cue: _hooked),
    ],
    debrief: 'The outbreak is over. Juno Kalt cried on the open channel.',
  ),

  // ── Ember Core: the Crucible ──────────────────────────────────────────────
  'lava_01': LevelStory(
    cargo: 'Coolant',
    from: Callsign.crucible,
    brief: 'Coolant first, or the forge melts itself.',
    beats: [_B(Callsign.crucible, 'Okonkwo here. Gravity is heavy and so is everything else. Welcome to the forge.', delay: 1)],
    debrief: 'The forge is cool enough to work.',
  ),
  'lava_02': LevelStory(
    cargo: 'Water tank',
    from: Callsign.crucible,
    brief: "Kalt's water. The vent will lift you, then drop you.",
    debrief: 'Kalt water in the quench tanks. Thank Juno for me.',
  ),
  'lava_03': LevelStory(
    cargo: 'Ore ingots',
    from: Callsign.crucible,
    brief: "Pithead's ore, past the rotors and into the furnace.",
    debrief: "Pithead's ore is in the furnace.",
  ),
  'lava_04': LevelStory(
    cargo: 'Relay housing',
    from: Callsign.crucible,
    brief: "Heaviest thing you'll ever tow. Trust the Mule.",
    beats: [_B(Callsign.crucible, 'That housing is solid tungsten. Climb early, climb slow.', cue: _hooked)],
  ),
  'lava_05': LevelStory(
    cargo: 'Pressure valves',
    from: Callsign.crucible,
    brief: 'Crushers on both sides. Timing is everything.',
    debrief: 'Valves fitted. The furnace can hold a pour now.',
  ),
  'lava_06': LevelStory(
    cargo: 'Catalyst',
    from: Callsign.crucible,
    brief: 'Catalyst into the vent chamber. It must not get hot on the way.',
  ),
  'lava_07': LevelStory(
    cargo: 'Crucible fuse',
    from: Callsign.crucible,
    brief: 'Through the gate of fire. We pour the relay core tonight.',
    beats: [_B(Callsign.crucible, 'Without that fuse there is no pour. Without the pour there is no gate.', cue: _hooked)],
  ),
  'lava_08': LevelStory(
    cargo: 'Relay core',
    from: Callsign.crucible,
    brief: "The relay core: every settlement's work in one pod. Get it out.",
    beats: [
      _B(Callsign.crucible, 'Ore from Pithead, water from Kalt, light from the Grove. Fly it like a cathedral.', cue: _hooked),
    ],
    debrief: 'The relay core is out. Next stop: the Outer Ring.',
  ),

  // ── Outer Ring ────────────────────────────────────────────────────────────
  'rating_vector': LevelStory(
    cargo: 'Ballast',
    from: Callsign.sable,
    brief: 'Hold thrust. The Vector goes where it points. SABLE finds that refreshing.',
    beats: [_B(Callsign.sable, 'Hello, pilot. I am SABLE. I have had no visitors for some time. Please do not crash.', delay: 1)],
    debrief: 'Vector rating signed. SABLE has logged it in triplicate.',
  ),
  'orbit_01': LevelStory(
    cargo: 'Relay core',
    from: Callsign.sable,
    brief: 'No up here. Bring the relay core aboard.',
    debrief: 'The relay core is aboard. SABLE has never been happier. Probably.',
  ),
  'orbit_02': LevelStory(
    cargo: 'Antenna dish',
    from: Callsign.sable,
    brief: 'A moonlet pulls at everything. Give it room.',
    beats: [_B(Callsign.sable, 'The moonlet has been wandering closer since the gate went dark. I have asked it to stop.', delay: 2)],
  ),
  'orbit_03': LevelStory(
    cargo: 'Power coupling',
    from: Callsign.sable,
    brief: "Use the well. Don't fight it.",
  ),
  'orbit_04': LevelStory(
    cargo: 'Spin bearing',
    from: Callsign.sable,
    brief: "The ring's spin gravity is failing sideways. Bring the bearing.",
    beats: [_B(Callsign.sable, 'Down is currently that way. I apologise for the inconvenience.', delay: 2)],
    debrief: 'The bearing is in. The ring spins a little truer.',
  ),
  'orbit_05': LevelStory(
    cargo: 'Twin emitters',
    from: Callsign.sable,
    brief: 'Two wells, one way through.',
  ),
  'orbit_06': LevelStory(
    cargo: 'Alignment gyro',
    from: Callsign.sable,
    brief: 'Wind and pull together. Bring the gyro to the relay mount.',
  ),
  'orbit_07': LevelStory(
    cargo: 'Phase lens',
    from: Callsign.sable,
    brief: 'Up is down in the next two halls. SABLE apologises.',
    beats: [_B(Callsign.sable, 'I did not design this section. I would like that on the record.', delay: 2)],
  ),
  'orbit_08': LevelStory(
    cargo: 'Gate key',
    from: Callsign.sable,
    brief: 'The relay is ready. Carry the gate key past the big well.',
    beats: [
      _B(Callsign.sable, 'Relay online. Querying Meridian Gate.', cue: _hooked),
      _B(Callsign.sable, 'The gate is not broken. It is locked. The lock is inside the Redoubt.', cue: _hooked, delay: 1),
    ],
    debrief: 'The gate is locked from the Redoubt. The militia is calling.',
  ),

  // ── The Redoubt ───────────────────────────────────────────────────────────
  'rating_talon': LevelStory(
    cargo: 'Ammo crate',
    from: Callsign.sparrow,
    brief: 'The militia lends you the Talon. Every shot costs fuel. Make them count.',
    beats: [_B(Callsign.sparrow, 'Novak, militia. You fly supplies; now you fly a gunship. Same rules: get home.', delay: 1)],
    debrief: 'Talon rating signed. Novak wants you on the gun line.',
  ),
  'redoubt_01': LevelStory(
    cargo: 'Ammo',
    from: Callsign.sparrow,
    brief: 'Ammo to the militia outpost, past the gun line.',
    beats: [_B(Callsign.warden, 'Unidentified craft. This route is closed. Turn back.', delay: 2)],
    debrief: 'The outpost is armed. The Warden knows your callsign now.',
  ),
  'redoubt_02': LevelStory(
    cargo: 'Rations',
    from: Callsign.sparrow,
    brief: 'The outpost is besieged. Food first, then we fight.',
    beats: [_B(Callsign.sparrow, 'Crews left fuel in the side pockets for you. Take it.', delay: 2)],
    debrief: 'The besieged outpost is fed.',
  ),
  'redoubt_03': LevelStory(
    cargo: 'Sabotage charge',
    from: Callsign.sparrow,
    brief: 'Hit the reactor and the guns sleep. Then bring the charge through.',
    beats: [_B(Callsign.warden, 'You do not understand what you are doing.', cue: _hooked)],
  ),
  'redoubt_04': LevelStory(
    cargo: 'Override key',
    from: Callsign.sparrow,
    brief: "Override key through the Warden's crossfire.",
    beats: [_B(Callsign.warden, 'I closed the gate for a reason. Leave it closed.', cue: _hooked)],
    debrief: 'The override key is in place. One step left.',
  ),
  'redoubt_05': LevelStory(
    cargo: 'Warden core',
    from: Callsign.sparrow,
    brief: 'Grab the core, blow the reactor, and outrun the meltdown.',
    beats: [
      _B(Callsign.warden, 'If you take my core, the door opens. Something is waiting on the other side.', cue: _hooked),
      _B(Callsign.sparrow, "Don't listen. Fly.", cue: _hooked, delay: 1),
    ],
    debrief: 'Meridian Gate is lit. The Warden\'s last words: "It is coming."',
  ),
};
