/// The hangar's "what next" for the career, shown under Missions: the next
/// world's star gate, then the stars still to earn, then flawless runs.
/// Pure: the caller passes the numbers.
String careerGoal({
  required int stars,
  required int missions,
  required int flawless,
  required List<({String name, int starsRequired})> worlds,
}) {
  final locked = [
    for (final w in worlds)
      if (w.starsRequired > stars) w,
  ]..sort((a, b) => a.starsRequired.compareTo(b.starsRequired));
  if (locked.isNotEmpty) {
    final w = locked.first;
    return '${w.starsRequired - stars}★ to ${w.name}';
  }
  final starsLeft = missions * 3 - stars;
  if (starsLeft > 0) return '$starsLeft★ left to earn';
  final notFlawless = missions - flawless;
  if (notFlawless > 0) {
    return notFlawless == 1 ? '1 flawless run to go' : '$notFlawless flawless runs to go';
  }
  return 'Every mission flawless';
}
