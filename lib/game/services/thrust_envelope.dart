/// Volume envelope for the engine loop (pure Dart, tested headless).
///
/// The loop keeps playing muted for the whole flight, so a press only has to
/// raise the volume: starting a media player takes 100–300 ms, which swallowed
/// short taps. A fast attack, a short minimum hold and a soft release make
/// even a one-frame tap audible.
class ThrustEnvelope {
  ThrustEnvelope({
    this.maxVolume = 0.6,
    this.attackSeconds = 0.025,
    this.releaseSeconds = 0.18,
    this.minHoldSeconds = 0.12,
  });

  final double maxVolume;
  final double attackSeconds;
  final double releaseSeconds;
  final double minHoldSeconds;

  /// Smallest volume change worth sending to the platform player.
  static const double sendStep = 0.02;

  double _level = 0;
  double _hold = 0;
  bool _wasThrusting = false;
  double _sent = 0;

  double get volume => _level * maxVolume;

  /// Advances the envelope. Returns the volume to send to the player, or null
  /// when nothing changed enough to be worth a platform call.
  double? step(bool thrusting, double dt) {
    if (thrusting && !_wasThrusting) _hold = minHoldSeconds;
    _wasThrusting = thrusting;
    if (_hold > 0) _hold -= dt;
    final on = thrusting || _hold > 0;
    if (on) {
      _level = (_level + dt / attackSeconds).clamp(0.0, 1.0);
    } else {
      _level = (_level - dt / releaseSeconds).clamp(0.0, 1.0);
    }
    final v = volume;
    final settled = v == 0 || v == maxVolume;
    if ((v - _sent).abs() >= sendStep || (settled && v != _sent)) {
      _sent = v;
      return v;
    }
    return null;
  }

  /// Silences immediately (pause, crash, landing). The next send is forced.
  void reset() {
    _level = 0;
    _hold = 0;
    _wasThrusting = false;
    _sent = -1;
  }
}
