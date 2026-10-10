// The story behind every mission (see docs/STORY.md). Pure Dart: the game
// reads it for the briefing, the radio and the result screen; tests check
// every level has one.

import 'package:narrow_haul/game/story/story_act1.dart';

/// Radio callsigns of the cast (docs/STORY.md, "Cast").
abstract final class Callsign {
  static const tower = 'TOWER';
  static const ops = 'OPS';
  static const grove = 'GROVE';
  static const pithead = 'PITHEAD';
  static const frostline = 'FROSTLINE';
  static const crucible = 'CRUCIBLE';
  static const sable = 'SABLE';
  static const sparrow = 'SPARROW';
  static const warden = 'WARDEN';

  static const all = {tower, ops, grove, pithead, frostline, crucible, sable, sparrow, warden};
}

/// When a story beat goes on air.
enum BeatCue {
  /// After the level card, [StoryBeat.delay] seconds later.
  start,

  /// The moment the pod is hooked.
  hooked,
}

/// One radio line of a mission's story.
class StoryBeat {
  const StoryBeat(this.callsign, this.text, {this.cue = BeatCue.start, this.delay = 0});
  final String callsign;
  final String text;
  final BeatCue cue;

  /// Extra seconds after the cue.
  final double delay;
}

/// A mission's story: what the pod carries, the dispatcher's one-line
/// brief, its radio beats and the line on the result screen.
class LevelStory {
  const LevelStory({
    required this.cargo,
    required this.brief,
    this.from = Callsign.ops,
    this.beats = const [],
    this.debrief,
  });

  /// What's in the pod ("Rations", "Seed vault").
  final String cargo;

  /// The briefing's one line, said by [from].
  final String brief;
  final String from;
  final List<StoryBeat> beats;

  /// Said on the result screen after a delivery.
  final String? debrief;
}

/// A world's chapter: shown as a card on first entering it ([intro]) and
/// after its last mission is first cleared ([outro]).
class WorldStory {
  const WorldStory({
    required this.place,
    required this.contact,
    required this.intro,
    required this.outro,
  });

  /// The settlement ("The Grove").
  final String place;

  /// The world's radio contact (a [Callsign]).
  final String contact;
  final List<String> intro;
  final List<String> outro;
}

/// The story of the level saved as [saveId], if it has one.
LevelStory? storyFor(String saveId) => kLevelStories[saveId];

/// The chapter of the world [worldId].
WorldStory? worldStoryFor(String worldId) => kWorldStories[worldId];

/// Longest radio line: it has to fit the comms band on a small phone.
const int kMaxBeatChars = 110;

/// Longest briefing line (one line in the dialog on a landscape phone).
const int kMaxBriefChars = 80;

/// Longest result-screen debrief.
const int kMaxDebriefChars = 72;
