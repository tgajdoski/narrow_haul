/// Watches the tank fall past a level's star fuel marks during a flight, so
/// the HUD and sound can say the moment a star slips away. Pure Dart.
///
/// Each mark fires once per flight. Like the level-info target line, a lost
/// mark stays lost: a canister that lifts the tank back above it doesn't
/// re-arm it, so a pilot never hears the same star go twice.
class StarWatch {
  /// Fuel fractions of the marks, best star first (3★, then 2★).
  List<double> _marks = const [];
  final Set<int> _lost = {};

  /// Starts a flight. [fuel] is the tank now: marks already under it (a
  /// resumed checkpoint, a tiny tank) count as lost and stay quiet.
  void reset(List<double> marks, {double fuel = 1}) {
    _marks = List.of(marks);
    _lost.clear();
    for (var i = 0; i < _marks.length; i++) {
      if (fuel < _marks[i]) _lost.add(i);
    }
  }

  /// Marks lost so far.
  int get lostCount => _lost.length;

  /// The tank is at [fuel] now. Returns the index of the mark it just fell
  /// past (the lowest one, if a big drop passed several), else null.
  int? update(double fuel) {
    int? crossed;
    for (var i = 0; i < _marks.length; i++) {
      if (!_lost.contains(i) && fuel < _marks[i]) {
        _lost.add(i);
        crossed = i;
      }
    }
    return crossed;
  }
}
