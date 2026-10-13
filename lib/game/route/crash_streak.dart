/// Crashes in a row on one level; after [offerAfter] of them the game-over
/// screen offers the route guide ([offerAfterTraining] on the Training
/// Grounds, where help should come sooner). A delivery or another level
/// resets it.
class CrashStreak {
  static const int offerAfter = 3;
  static const int offerAfterTraining = 2;

  String? _levelId;
  int _count = 0;

  int get count => _count;
  String? get levelId => _levelId;

  void onCrash(String levelId) {
    if (levelId != _levelId) {
      _levelId = levelId;
      _count = 0;
    }
    _count++;
  }

  void onDelivered() {
    _levelId = null;
    _count = 0;
  }

  bool shouldOfferFor(String levelId, {bool training = false}) =>
      levelId == _levelId &&
      _count >= (training ? offerAfterTraining : offerAfter);
}
