import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/level_registry.dart';
import 'package:narrow_haul/game/story/story.dart';
import 'package:narrow_haul/game/story/story_act1.dart';

void main() {
  test('every mission has a story, and every world a chapter', () {
    for (final def in LevelRegistry.flat) {
      expect(storyFor(def.saveId), isNotNull, reason: def.saveId);
    }
    for (final w in LevelRegistry.worlds) {
      final s = worldStoryFor(w.id);
      expect(s, isNotNull, reason: w.id);
      expect(s!.intro, isNotEmpty, reason: w.id);
      expect(s.outro, isNotEmpty, reason: w.id);
      expect(Callsign.all, contains(s.contact), reason: w.id);
    }
  });

  test('no story for a level that does not exist', () {
    final ids = {for (final d in LevelRegistry.flat) d.saveId};
    expect(kLevelStories.keys.where((k) => !ids.contains(k)), isEmpty);
  });

  test('every line fits: known callsigns, short enough for the radio band', () {
    for (final e in kLevelStories.entries) {
      final s = e.value;
      expect(Callsign.all, contains(s.from), reason: e.key);
      expect(s.cargo, isNotEmpty, reason: e.key);
      expect(s.brief.length, lessThanOrEqualTo(kMaxBriefChars), reason: '${e.key}: ${s.brief}');
      expect(s.debrief?.length ?? 0, lessThanOrEqualTo(kMaxDebriefChars), reason: '${e.key}: ${s.debrief}');
      expect(s.beats.length, lessThanOrEqualTo(3), reason: e.key);
      for (final b in s.beats) {
        expect(Callsign.all, contains(b.callsign), reason: e.key);
        expect(b.text.length, lessThanOrEqualTo(kMaxBeatChars), reason: '${e.key}: ${b.text}');
      }
    }
  });
}
