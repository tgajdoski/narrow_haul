part of 'progress_service.dart';

/// Settings, one-time hints, story flags and return reminders.
extension ProgressSettings on ProgressService {
  /// The "Delivered by" credits play on the first launch only.
  bool get creditsSeen => _read(_creditsSeen);
  Future<void> markCreditsSeen() => _write(_creditsSeen, true);

  /// "Slow touches are safe" shows on the first scrape only.
  bool get scrapeHintSeen => _read(_scrapeHintSeen);
  Future<void> markScrapeHintSeen() => _write(_scrapeHintSeen, true);

  /// The FIRE coach mark: once ever, until the first shot or its timeout.
  bool get fireHintSeen => _read(_fireHintSeen);
  Future<void> markFireHintSeen() => _write(_fireHintSeen, true);

  /// THRUST / STEER coach marks: until both are learned once.
  bool get controlsHintSeen => _read(_controlsHintSeen);
  Future<void> markControlsHintSeen() => _write(_controlsHintSeen, true);

  /// TOWER's camera tip airs once ever.
  bool get cameraTipSeen => _read(_cameraTipSeen);
  Future<void> markCameraTipSeen() => _write(_cameraTipSeen, true);

  /// OPS's fuel canister line airs once ever.
  bool get canisterHintSeen => _read(_canisterHintSeen);
  Future<void> markCanisterHintSeen() => _write(_canisterHintSeen, true);

  /// Deliveries in a row without a nose-down warning; the in-flight lesson
  /// runs until it reaches `kNoseDownCleanFlights`.
  int get noseDownCleanFlights => _read(_noseDownClean);
  Future<void> setNoseDownCleanFlights(int n) => _write(_noseDownClean, n);

  /// A crate's "loaded, tap FIRE" plate shows the first time each weapon
  /// is picked up; after that the icon flying into FIRE says it.
  bool crateHintSeen(String weaponId) => _bool('crate_hint_$weaponId') ?? false;
  Future<void> markCrateHintSeen(String weaponId) async =>
      _prefs.setBool('crate_hint_$weaponId', true);

  /// OPS's "You're flying the X" line plays on a ship's first flight only.
  bool shipIntroSeen(String shipId) => _bool('ship_intro_$shipId') ?? false;
  Future<void> markShipIntroSeen(String shipId) async =>
      _prefs.setBool('ship_intro_$shipId', true);

  /// Story chapter cards seen (`intro_<world>` / `outro_<world>`); a reset
  /// tells the story again.
  bool storySeen(String key) => _bool('story_$key') ?? false;
  Future<void> markStorySeen(String key) async =>
      _prefs.setBool('story_$key', true);

  /// Return reminders (local notifications): null until the player answers
  /// the in-game question, then their choice (Settings can change it).
  bool? get remindersEnabled => _bool(_Keys.remindersEnabled);
  Future<void> setRemindersEnabled(bool v) async =>
      _prefs.setBool(_Keys.remindersEnabled, v);

  /// How often, and when last (ms), the reminder question was shown.
  int get reminderAsks => _read(_reminderAsks);
  int get reminderAskMs => _read(_reminderAskMs);
  Future<void> recordReminderAsk(int nowMs) async {
    await _write(_reminderAsks, reminderAsks + 1);
    await _write(_reminderAskMs, nowMs);
  }

  /// The career mission last launched: a reminder picks it up if it's
  /// still unflown.
  String? get reminderLastTried => _string(_Keys.reminderLastTried);
  Future<void> setReminderLastTried(String saveId) async =>
      _prefs.setString(_Keys.reminderLastTried, saveId);

  /// Hours (0–23) of the last 8 session starts: reminders go out at the
  /// player's usual time.
  List<int> get reminderHours => [
    for (final h in _stringList(_Keys.reminderHours) ?? const <String>[])
      ?int.tryParse(h),
  ];
  Future<void> recordSessionHour(int hour) async {
    final hours = [...reminderHours, hour];
    final last = hours.length > 8 ? hours.sublist(hours.length - 8) : hours;
    await _prefs.setStringList(_Keys.reminderHours, [
      for (final h in last) '$h',
    ]);
  }

  bool get minimapEnabled => _read(_minimapEnabled);
  Future<void> setMinimapEnabled(bool v) => _write(_minimapEnabled, v);

  bool get soundEnabled => _read(_soundEnabled);
  Future<void> setSoundEnabled(bool v) => _write(_soundEnabled, v);

  bool get musicEnabled => _read(_musicEnabled);
  Future<void> setMusicEnabled(bool v) => _write(_musicEnabled, v);

  bool get hapticsEnabled => _read(_hapticsEnabled);
  Future<void> setHapticsEnabled(bool v) => _write(_hapticsEnabled, v);

  /// Mirrors the touch controls: thrust on the left, joystick on the right.
  bool get leftHanded => _read(_leftHanded);
  Future<void> setLeftHanded(bool v) => _write(_leftHanded, v);

  /// Steering and camera presets (`SteerMode` / `CameraMode` names).
  String? get steerMode => _string(_Keys.steerMode);
  Future<void> setSteerMode(String v) async =>
      _prefs.setString(_Keys.steerMode, v);
  String? get cameraMode => _string(_Keys.cameraMode);
  Future<void> setCameraMode(String v) async =>
      _prefs.setString(_Keys.cameraMode, v);

  /// Tilt steering on/off (null = never chosen: on wherever the phone has
  /// the sensor) and its `TiltSensitivity` name.
  bool? get tiltSteer => _bool(_Keys.tiltSteer);
  Future<void> setTiltSteer(bool v) async =>
      _prefs.setBool(_Keys.tiltSteer, v);
  String? get tiltSensitivity => _string(_Keys.tiltSensitivity);
  Future<void> setTiltSensitivity(String v) async =>
      _prefs.setString(_Keys.tiltSensitivity, v);
  String? get tiltMode => _string(_Keys.tiltMode);
  Future<void> setTiltMode(String v) async =>
      _prefs.setString(_Keys.tiltMode, v);
}
