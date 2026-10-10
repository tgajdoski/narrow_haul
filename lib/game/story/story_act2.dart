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
};
